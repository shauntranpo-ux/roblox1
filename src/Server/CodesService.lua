-- CodesService: server-authoritative, idempotent, data-driven CODE redemption. The client sends
-- ONLY the string it typed (RedeemCode RemoteFunction); the server normalizes + validates it,
-- grants the reward through EXISTING guarded systems, and records it in a profile-persisted
-- RedeemedCodes set -- the grant and the record commit in the SAME mutation, so a code grants
-- EXACTLY once even across crashes / restarts / servers. Returns a precise result enum for the UI.
--
-- ============================  SELF-AUDIT (codes path)  =====================================
-- * DOUBLE-REDEEM: blocked by the persisted RedeemedCodes[normalized] check; the grant + the
--   record are written together with NO yields between, so a crash can't grant-without-recording
--   or record-without-granting.
-- * DUPE/LOSS: rewards reuse the guarded systems -- AddCash (clamped), the M5 income-multiplier
--   source (boost), and a free-pad placement (brainrot). A brainrot with NO free pad is REFUSED
--   and is NOT recorded, so the player can redeem it later -- no dupe, no loss.
-- * BRUTE FORCE: per-player rate limit on every attempt; invalid attempts are cheap + harmless.
-- * INPUT: type + length checked; trimmed + UPPER-normalized; never corrupts state.
-- * GLOBAL LIMIT: opt-in MaxGlobalUses via a pcall+backoff DataStore counter; on Studio mock it
--   falls back to per-player-once (logged). On live API failure it DENIES (never over-grants).
-- ===========================================================================================

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)

local CodesConfig = require(script.Parent.CodesConfig)
local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local PlayerStats = require(script.Parent.PlayerStats)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local ProtectionService = require(script.Parent.ProtectionService)
local Leaderstats = require(script.Parent.Leaderstats)
local Remotes = require(script.Parent.Remotes)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local EventService = require(script.Parent.EventService)

local CodesService = {}

local BOOST_SOURCE = "boost" -- keyed income-multiplier source -> can't double-stack with itself
local BOOST_SWEEP = 5 -- s between boost-expiry checks
local MAX_INPUT = 64 -- reject oversized input at the boundary
local USES_STORE = "BrainrotCodeUses"

local globalFallbackLogged = false

-- ===========================================================================================
-- Timed boost (reuses the M5 income-multiplier path)
-- ===========================================================================================
local function applyBoost(player, profile)
    Benefits.SetIncomeSource(player, BOOST_SOURCE, profile.Data.BoostMultiplier - 1)
    PlayerStats.UpdateIncome(player, profile)
end

local function clearBoost(player, profile)
    profile.Data.BoostMultiplier = 1
    profile.Data.BoostExpiry = 0
    Benefits.SetIncomeSource(player, BOOST_SOURCE, 0)
    PlayerStats.UpdateIncome(player, profile)
end

-- On join: re-apply a still-valid boost, or clean up an expired one. Idempotent.
function CodesService.SetupPlayer(player, profile)
    if profile.Data.BoostExpiry > os.time() then
        applyBoost(player, profile)
    elseif profile.Data.BoostExpiry ~= 0 or profile.Data.BoostMultiplier ~= 1 then
        clearBoost(player, profile)
    end
end

-- ===========================================================================================
-- Reward registry: prepare WITHOUT mutating; return (applyFn, successMessage) or (nil, reason).
-- Splitting "can we?" from "do it" keeps the commit free of any failure surface.
-- ===========================================================================================
local function prepareReward(player, profile, reward)
    local t = reward.Type
    if t == "Cash" then
        local amount = reward.Amount
        return function()
            ProfileManager.AddCash(player, amount)
        end,
            "Redeemed! +$" .. tostring(amount)
    elseif t == "Boost" then
        local mult = reward.Multiplier
        local duration = reward.DurationSeconds
        return function()
            profile.Data.BoostMultiplier = mult
            profile.Data.BoostExpiry = os.time() + duration
            applyBoost(player, profile)
        end,
            string.format("Redeemed! %gx cash for %d min!", mult, math.floor(duration / 60))
    elseif t == "Brainrot" then
        local def = Catalog.Get(reward.BrainrotId)
        if def == nil then
            return nil, "That reward is unavailable."
        end
        local plot = PlotService.GetPlot(player)
        if plot == nil then
            return nil, "Your base isn't ready yet."
        end
        local padIndex = PlotService.FindFreePad(player, profile)
        if padIndex == nil then
            return nil, "Free a pad first, then redeem again."
        end
        return function()
            local brainrot =
                BrainrotFactory.create(player, def, padIndex, BrainrotFactory.RollFor.Code)
            table.insert(profile.Data.OwnedBrainrots, brainrot)
            profile.Data.Discovered[def.Id] = true
            BrainrotService.SpawnBrainrot(player, plot, brainrot)
            ProtectionService.RefreshPrompts(player)
        end,
            "Redeemed! Got " .. def.DisplayName .. "!"
    end
    return nil, "That reward is unavailable."
end

-- Cross-server global cap (opt-in). Returns true if a use was consumed (allowed).
local function tryConsumeGlobal(entry)
    if ProfileManager.IsUsingMock() then
        if not globalFallbackLogged then
            globalFallbackLogged = true
            print(
                "[Codes] DataStore API unavailable -> global code limits fall back to per-player-once."
            )
        end
        return true -- per-player dedupe still applies
    end
    local store = DataStoreService:GetDataStore(USES_STORE)
    for attempt = 1, 3 do
        local ok, result = pcall(function()
            return store:UpdateAsync(entry.Normalized, function(current)
                current = current or 0
                if current >= entry.MaxGlobalUses then
                    return nil -- limit reached -> cancel the write
                end
                return current + 1
            end)
        end)
        if ok then
            return result ~= nil -- nil => transform cancelled => limit reached
        end
        if attempt < 3 then
            task.wait(0.5 * 2 ^ attempt)
        end
    end
    return false -- persistent API failure -> deny (never over-grant)
end

local function logRewardAnalytics(player, profile, entry, reward)
    Analytics.custom(player, Analytics.Events.CodeRedeemed, 1)
    if reward.Type == "Cash" then
        Analytics.economySource(
            player,
            reward.Amount,
            profile.Data.Cash,
            Analytics.Tx.TimedReward,
            "code:" .. entry.Normalized
        )
    end
end

-- ===========================================================================================
-- Redeem (RemoteFunction handler). TRUST BOUNDARY: the client sends ONLY the typed string.
-- ===========================================================================================
local function redeem(player, rawInput)
    -- Rate limit FIRST so brute-forcing random strings is cheap + harmless.
    if not RateLimiter.check(player, "redeem", 1) then
        return { Result = "Error", Message = "Too many tries -- wait a moment." }
    end
    if type(rawInput) ~= "string" or #rawInput > MAX_INPUT then
        return { Result = "Invalid", Message = "Enter a valid code." }
    end

    local normalized = CodesConfig.normalize(rawInput)
    if normalized == nil then
        return { Result = "Invalid", Message = "Enter a code." }
    end
    local entry = CodesConfig.ByNormalized[normalized]
    if entry == nil then
        return { Result = "Invalid", Message = "That code doesn't exist." }
    end
    if entry.Active == false then
        return { Result = "Inactive", Message = "That code is no longer active." }
    end
    if entry.Expiry ~= nil and os.time() > entry.Expiry then
        return { Result = "Expired", Message = "That code has expired." }
    end

    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet -- try again." }
    end
    if profile.Data.RedeemedCodes[normalized] then
        return { Result = "AlreadyRedeemed", Message = "You already redeemed that code." }
    end

    -- Validate the reward WITHOUT mutating (e.g. brainrot needs a free pad). If it can't be
    -- granted, we do NOT record the code, so the player can try again later.
    local apply, message = prepareReward(player, profile, entry.Reward)
    if apply == nil then
        return { Result = "Error", Message = message }
    end

    -- Opt-in cross-server limit, consumed right before commit.
    if entry.MaxGlobalUses ~= nil then
        if not tryConsumeGlobal(entry) then
            return { Result = "Expired", Message = "This code has reached its limit." }
        end
    end

    -- ===== COMMIT: grant + record in the SAME mutation, no yields between. =====
    apply()
    profile.Data.RedeemedCodes[normalized] = true
    -- ==========================================================================

    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
    logRewardAnalytics(player, profile, entry, entry.Reward)
    EventService.Signal(player, "REDEEM_CODE", 1)

    return { Result = "Success", Message = message }
end

function CodesService.Init()
    Remotes.RedeemCode.OnServerInvoke = function(player, rawInput)
        return redeem(player, rawInput)
    end

    -- Boost expiry sweep: clears boosts cleanly server-side when their timer runs out.
    task.spawn(function()
        while true do
            task.wait(BOOST_SWEEP)
            local now = os.time()
            for _, player in ipairs(Players:GetPlayers()) do
                local profile = ProfileManager.GetProfile(player)
                if
                    profile ~= nil
                    and profile.Data.BoostExpiry > 0
                    and now >= profile.Data.BoostExpiry
                then
                    clearBoost(player, profile)
                end
            end
        end
    end)
end

return CodesService
