-- LeaderboardService: three GLOBAL leaderboards (Top Cash, Top Income/sec, Rarest Collection)
-- backed by OrderedDataStore, written on a THROTTLED cadence (and on leave), read into a small
-- cache the in-world billboards render from. Every DataStore call is pcall-wrapped with backoff
-- so a failed board call NEVER errors the server or blocks gameplay.
--
-- VALUE SAFETY: OrderedDataStore values must be NON-NEGATIVE INTEGERS in a safe range. Cash and
-- income can grow past 2^53 (double integer safety), so every written value is floor()ed and
-- clamped to [0, MaxValue] (see Shared/Monetization.Leaderboard.MaxValue, ~just under 2^53).
--
-- MOCK FALLBACK: in unpublished Studio the DataStore API is unavailable, so we keep an in-memory
-- board of the players currently in the server -- the billboards still populate for testing.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Monetization)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local UnitIncome = require(ReplicatedStorage.Shared.UnitIncome)

local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local TextFilter = require(script.Parent.TextFilter)

local LeaderboardService = {}

local LB = Monetization.Leaderboard
local DS_RETRIES = 3

local usingMock = false
local mockScores = {} -- [boardKey] = { [userId] = value }
local topCache = {} -- [boardKey] = { { Rank, Name, Value }, ... }
local nameCache = {} -- [userId] = displayName

-- Effective income = base owned income * the player's income multiplier (the 2x Cash gamepass
-- counts on the board too). A briefly carried unit is not excluded -- negligible over a 60s tick.
-- Effective income = Σ effective per-unit income (mutation-aware, via the canonical helper) *
-- global multiplier * prestige. Mutation factor is per-unit (uncapped); the global multiplier is
-- capped; prestige is the separate axis -- matching the income loop exactly.
local function incomeValue(player, profile)
    local sum = 0
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        sum += UnitIncome.effective(brainrot)
    end
    return sum * Benefits.GetIncomeMultiplier(player) * (profile.Data.PrestigeMultiplier or 1)
end

-- Rarest-collection metric: a single positive integer = SUM over Discovered Ids of that Id's
-- rarity weight (config). Bigger = a rarer/deeper collection.
local function collectionScore(profile)
    local score = 0
    for id in pairs(profile.Data.Discovered) do
        local item = Catalog.Get(id)
        if item ~= nil then
            score += LB.RarityWeights[item.Rarity] or 0
        end
    end
    return score
end

-- The three boards. Compute(player, profile) -> raw number (clamped on write).
local boardList = {
    {
        Key = "Cash",
        Title = "Top Cash",
        Compute = function(_player, profile)
            return profile.Data.Cash
        end,
    },
    {
        Key = "Income",
        Title = "Top Income / sec",
        Compute = function(player, profile)
            return incomeValue(player, profile)
        end,
    },
    {
        Key = "Collection",
        Title = "Rarest Collection",
        Compute = function(_player, profile)
            return collectionScore(profile)
        end,
    },
}

-- OrderedDataStore values must be non-negative integers within a safe range.
local function clampValue(value)
    value = math.floor(value)
    if value < 0 then
        value = 0
    elseif value > LB.MaxValue then
        value = LB.MaxValue
    end
    return value
end

-- Runs a DataStore call with pcall + exponential backoff. Returns ok, result.
local function withRetry(fn)
    for attempt = 1, DS_RETRIES do
        local ok, result = pcall(fn)
        if ok then
            return true, result
        end
        if attempt < DS_RETRIES then
            task.wait(0.5 * 2 ^ attempt)
        end
    end
    return false, nil
end

-- Cached UserId -> name. Uses an in-server player when present, else a pcall'd web lookup.
local function resolveName(userId)
    if userId == nil then
        return "?"
    end
    local cached = nameCache[userId]
    if cached ~= nil then
        return cached
    end
    -- In-server: reuse the already-filtered SafeName (M13.4); falls back to the pre-moderated name.
    local player = Players:GetPlayerByUserId(userId)
    if player ~= nil then
        local safe = player:GetAttribute("SafeName") or player.Name
        nameCache[userId] = safe
        return safe
    end
    -- Offline: look the name up, then filter it once. Names are pre-moderated by Roblox, so on a
    -- filter-API blip we keep the raw name rather than hiding the leaderboard row.
    local ok, name = pcall(function()
        return Players:GetNameFromUserIdAsync(userId)
    end)
    local resolved = (ok and name) or ("User" .. tostring(userId))
    local filtered, safe = TextFilter.FilterForBroadcast(resolved, userId)
    if filtered then
        resolved = safe
    end
    nameCache[userId] = resolved
    return resolved
end

local function writeValue(board, userId, rawValue)
    local value = clampValue(rawValue)
    if usingMock then
        mockScores[board.Key][userId] = value
        return
    end
    withRetry(function()
        board.Store:SetAsync(tostring(userId), value)
    end)
end

-- Reads the current top-N for one board (real GetSortedAsync, or the in-memory mock), resolving
-- names and ranks. Never errors -- on failure it returns whatever it has.
local function readTop(board)
    local rows = {}
    if usingMock then
        for userId, value in pairs(mockScores[board.Key]) do
            table.insert(rows, { UserId = userId, Value = value })
        end
        table.sort(rows, function(a, b)
            return a.Value > b.Value
        end)
    else
        local ok, pages = withRetry(function()
            return board.Store:GetSortedAsync(false, LB.TopN)
        end)
        if ok and pages ~= nil then
            for _, entry in ipairs(pages:GetCurrentPage()) do
                table.insert(rows, { UserId = tonumber(entry.key), Value = entry.value })
            end
        end
    end

    local top = {}
    for rank, row in ipairs(rows) do
        if rank > LB.TopN then
            break
        end
        table.insert(top, { Rank = rank, Name = resolveName(row.UserId), Value = row.Value })
    end
    return top
end

local function refreshCache()
    for _, board in ipairs(boardList) do
        topCache[board.Key] = readTop(board)
    end
end

-- ===========================================================================================
-- Public API
-- ===========================================================================================

-- Writes a player's current values to every board. In MOCK mode it also refreshes the cache
-- immediately (cheap, in-memory) so billboards update the moment a player joins. In REAL mode
-- the throttled loop owns cache refreshes to respect the DataStore budget.
function LeaderboardService.UpdatePlayer(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    for _, board in ipairs(boardList) do
        writeValue(board, player.UserId, board.Compute(player, profile))
    end
    if usingMock then
        refreshCache()
    end
end

-- Final write on leave. Captures values synchronously (the profile may be released right after),
-- then writes off-thread so it never blocks the player's profile release.
function LeaderboardService.OnPlayerRemoving(player)
    if usingMock then
        for _, board in ipairs(boardList) do
            mockScores[board.Key][player.UserId] = nil -- mock board = players currently present
        end
        refreshCache()
        return
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    local userId = player.UserId
    local captured = {}
    for _, board in ipairs(boardList) do
        captured[board.Key] = board.Compute(player, profile)
    end
    task.spawn(function()
        for _, board in ipairs(boardList) do
            writeValue(board, userId, captured[board.Key])
        end
    end)
end

-- Best-effort SYNCHRONOUS flush of every in-server player's values. Used by BindToClose on
-- shutdown so a restart doesn't lose the latest board state. No-op in mock mode; each write is
-- pcall'd + retried inside writeValue, so it can never error the shutdown path.
function LeaderboardService.FlushAll()
    if usingMock then
        return
    end
    for _, player in ipairs(Players:GetPlayers()) do
        local profile = ProfileManager.GetProfile(player)
        if profile ~= nil then
            for _, board in ipairs(boardList) do
                writeValue(board, player.UserId, board.Compute(player, profile))
            end
        end
    end
end

-- For the billboards: the board metadata (ordered) and the cached top-N rows.
function LeaderboardService.GetBoardList()
    local list = {}
    for _, board in ipairs(boardList) do
        table.insert(list, { Key = board.Key, Title = board.Title })
    end
    return list
end

function LeaderboardService.GetBoard(boardKey)
    return topCache[boardKey] or {}
end

function LeaderboardService.IsUsingMock()
    return usingMock
end

-- Detects whether the OrderedDataStore API is usable; live servers always have it, Studio only
-- with "Enable Studio Access to API Services". Falls back to the in-memory mock otherwise.
local function apiAvailable()
    if not RunService:IsStudio() then
        return true
    end
    local ok = pcall(function()
        DataStoreService:GetOrderedDataStore("__lb_probe"):GetSortedAsync(false, 1)
    end)
    return ok
end

function LeaderboardService.Init()
    usingMock = not apiAvailable()

    for _, board in ipairs(boardList) do
        if usingMock then
            mockScores[board.Key] = {}
        else
            board.Store = DataStoreService:GetOrderedDataStore("Leaderboard_" .. board.Key)
        end
        topCache[board.Key] = {}
    end

    if usingMock then
        print(
            "[Leaderboard] DataStore API unavailable -> MOCK boards (players in this server only)."
        )
    else
        print("[Leaderboard] Using REAL OrderedDataStore -> global boards.")
    end

    -- Throttled write/read loop. First pass runs immediately so boards populate at startup.
    task.spawn(function()
        while true do
            for _, player in ipairs(Players:GetPlayers()) do
                LeaderboardService.UpdatePlayer(player)
            end
            refreshCache()
            task.wait(LB.RefreshInterval)
        end
    end)
end

return LeaderboardService
