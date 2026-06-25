-- SeasonService: recurring competitive SEASONS. The CURRENT SEASON ID is derived purely from
-- server time + config (identical on every server). Each season writes to its OWN per-season
-- OrderedDataStore ("Season_<id>"); "reset" = a NEW per-season store -- the prior board is FROZEN
-- (no longer written) and readable for the claim window. NON-DESTRUCTIVE rollover, no coordination.
--
-- SELF-AUDIT: scores are server-authoritative (computed from weighted signals), only the CURRENT
-- season's store is ever written, values are floored/clamped/non-negative, every store call is
-- pcall'd + retried. Mock fallback in unpublished Studio. SeasonRewardService reads the FROZEN
-- store to grant end-of-season rewards (pull-based; see that module).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonsConfig = require(ReplicatedStorage.Shared.SeasonsConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local DevConfig = require(script.Parent.DevConfig)
local Remotes = require(script.Parent.Remotes)

local SeasonService = {}

local WRITE_INTERVAL = 60 -- s between throttled score writes + board reads
local MAX_VALUE = 9000000000000000 -- < 2^53
local DS_RETRIES = 3

local usingMock = false
local mockStores = {} -- [seasonId] = { [userId] = points }
local nameCache = {}
local topCache = {} -- top-N rows for the current season
local currentId = nil
local forcedOffset = 0 -- SIM-only: advances the effective season id for dev rollover testing

-- Set by SeasonRewardService.Init so a rollover can trigger live end-of-season claims (no cycle:
-- SeasonService never requires SeasonRewardService).
SeasonService.RolloverCallback = nil

local function effectiveId()
    return SeasonsConfig.CurrentId(os.time()) + forcedOffset
end

function SeasonService.CurrentId()
    return effectiveId()
end

function SeasonService.IsMock()
    return usingMock
end

local function clampValue(v)
    v = math.floor(v)
    if v < 0 then
        v = 0
    elseif v > MAX_VALUE then
        v = MAX_VALUE
    end
    return v
end

local function withRetry(fn)
    for attempt = 1, DS_RETRIES do
        local ok, res = pcall(fn)
        if ok then
            return true, res
        end
        if attempt < DS_RETRIES then
            task.wait(0.5 * 2 ^ attempt)
        end
    end
    return false, nil
end

local function realStore(seasonId)
    return DataStoreService:GetOrderedDataStore("Season_" .. seasonId)
end

local function resolveName(userId)
    if userId == nil then
        return "?"
    end
    local cached = nameCache[userId]
    if cached ~= nil then
        return cached
    end
    local p = Players:GetPlayerByUserId(userId)
    if p ~= nil then
        nameCache[userId] = p.Name
        return p.Name
    end
    local ok, name = pcall(function()
        return Players:GetNameFromUserIdAsync(userId)
    end)
    local resolved = (ok and name) or ("User" .. tostring(userId))
    nameCache[userId] = resolved
    return resolved
end

-- Writes a player's CURRENT-season points to `seasonId`'s store -- but ONLY if their score record
-- belongs to that season (never writes to a frozen/past season's store).
local function writeScoreTo(seasonId, player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil or profile.Data.SeasonScore.Id ~= seasonId then
        return
    end
    local value = clampValue(profile.Data.SeasonScore.Points)
    if usingMock then
        mockStores[seasonId] = mockStores[seasonId] or {}
        mockStores[seasonId][player.UserId] = value
        return
    end
    withRetry(function()
        realStore(seasonId):SetAsync(tostring(player.UserId), value)
    end)
end

-- ===========================================================================================
-- Reads used by the UI + SeasonRewardService
-- ===========================================================================================
function SeasonService.GetScore(seasonId, userId)
    if usingMock then
        return (mockStores[seasonId] or {})[userId] or 0
    end
    local ok, value = withRetry(function()
        return realStore(seasonId):GetAsync(tostring(userId))
    end)
    return (ok and value) or 0
end

-- Reads the top-N rows for a season (rank/name/score). Used for display + the ranked-reward scan.
local function readTop(seasonId)
    local rows = {}
    if usingMock then
        for userId, value in pairs(mockStores[seasonId] or {}) do
            table.insert(rows, { UserId = userId, Value = value })
        end
        table.sort(rows, function(a, b)
            return a.Value > b.Value
        end)
    else
        local ok, pages = withRetry(function()
            return realStore(seasonId):GetSortedAsync(false, SeasonsConfig.TopN)
        end)
        if ok and pages ~= nil then
            for _, entry in ipairs(pages:GetCurrentPage()) do
                table.insert(rows, { UserId = tonumber(entry.key), Value = entry.value })
            end
        end
    end
    local top = {}
    for rank, row in ipairs(rows) do
        if rank > SeasonsConfig.TopN then
            break
        end
        table.insert(top, { Rank = rank, Name = resolveName(row.UserId), Value = row.Value })
    end
    return top
end

-- The player's rank within the top-N of a season (nil if not in the top-N). Exact self-rank at
-- scale is impractical via OrderedDataStore, so we resolve it within the top-N (which covers all
-- ranked reward tiers) and otherwise report "unranked". Documented approximation.
function SeasonService.GetRankInTop(seasonId, userId)
    for _, row in ipairs(readTop(seasonId)) do
        if row.UserId == userId then
            return row.Rank
        end
    end
    return nil
end

-- ===========================================================================================
-- Scoring (server-authoritative; only the current season accrues)
-- ===========================================================================================
function SeasonService.Signal(player, signalType, amount)
    local weight = SeasonsConfig.ScoreWeights[signalType]
    if weight == nil then
        return
    end
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    local id = effectiveId()
    if profile.Data.SeasonScore.Id ~= id then
        profile.Data.SeasonScore = { Id = id, Points = 0 } -- fresh season -> clean reset
    end
    profile.Data.SeasonScore.Points += weight * amount
end

-- On join: ensure the player's score record is for the current season (reset if stale).
function SeasonService.SetupPlayer(_player, profile)
    local id = effectiveId()
    if profile.Data.SeasonScore.Id ~= id then
        profile.Data.SeasonScore = { Id = id, Points = 0 }
    end
end

function SeasonService.OnPlayerRemoving(player)
    writeScoreTo(effectiveId(), player) -- final write (best-effort; pcall'd inside)
end

-- ===========================================================================================
-- Rollover detection (reuses the scheduler concept; the engine's seasons extension point)
-- ===========================================================================================
local function tick()
    local id = effectiveId()
    if currentId == nil then
        currentId = id
    end
    if id ~= currentId then
        local oldId = currentId
        -- Flush final old-season scores, THEN reset online players to the new season.
        for _, player in ipairs(Players:GetPlayers()) do
            writeScoreTo(oldId, player)
        end
        for _, player in ipairs(Players:GetPlayers()) do
            local profile = ProfileManager.GetProfile(player)
            if profile ~= nil and profile.Data.SeasonScore.Id == oldId then
                profile.Data.SeasonScore = { Id = id, Points = 0 }
            end
        end
        currentId = id
        if SeasonService.RolloverCallback ~= nil then
            SeasonService.RolloverCallback(oldId) -- frozen season is now claimable
        end
        if Remotes.SeasonsUpdate ~= nil then
            Remotes.SeasonsUpdate:FireAllClients()
        end
    end
    -- Normal throttled write + board refresh for the current season.
    for _, player in ipairs(Players:GetPlayers()) do
        writeScoreTo(id, player)
    end
    topCache = readTop(id)
end

-- Flushes all current-season scores (BindToClose).
function SeasonService.FlushAll()
    local id = effectiveId()
    for _, player in ipairs(Players:GetPlayers()) do
        writeScoreTo(id, player)
    end
end

-- DEV/TEST (SIM only): force a rollover to the next season NOW, routing through the real
-- freeze + reset + claim transition. require(...SeasonService).ForceRollover()
function SeasonService.ForceRollover()
    if not DevConfig.SimMode then
        warn("[Seasons] ForceRollover ignored -- SIM mode is OFF.")
        return
    end
    forcedOffset += 1
    tick()
end

-- The cached current-season top-N (for the in-world season billboard).
function SeasonService.GetTop()
    return topCache
end

-- State the Seasons UI renders from.
function SeasonService.GetState(player)
    local id = effectiveId()
    local _, windowEnd = SeasonsConfig.WindowFor(id - forcedOffset) -- real wall-clock window end
    local profile = ProfileManager.GetProfile(player)
    local myScore = 0
    if profile ~= nil and profile.Data.SeasonScore.Id == id then
        myScore = profile.Data.SeasonScore.Points
    end
    return {
        SeasonId = id,
        EndsAt = forcedOffset > 0 and 0 or windowEnd,
        Now = os.time(),
        Top = topCache,
        MyScore = math.floor(myScore),
        MyRank = SeasonService.GetRankInTop(id, player.UserId),
        Track = SeasonsConfig.TrackRewards,
        Ranked = SeasonsConfig.RankedRewards,
    }
end

local function apiAvailable()
    if not RunService:IsStudio() then
        return true
    end
    local ok = pcall(function()
        DataStoreService:GetOrderedDataStore("__season_probe"):GetSortedAsync(false, 1)
    end)
    return ok
end

function SeasonService.Init()
    usingMock = not apiAvailable()
    currentId = effectiveId()
    print(
        usingMock and "[Seasons] DataStore API unavailable -> MOCK season boards."
            or "[Seasons] Using REAL per-season OrderedDataStores."
    )

    Remotes.GetSeasons.OnServerInvoke = function(player)
        return SeasonService.GetState(player)
    end

    task.spawn(function()
        while true do
            tick()
            task.wait(WRITE_INTERVAL)
        end
    end)
end

return SeasonService
