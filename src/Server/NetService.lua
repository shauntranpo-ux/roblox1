-- NetService (M10.4): the NET tool -- server-authoritative catch-parameter bonuses + the upgrade cash
-- sink. The server holds each player's net TIER (persisted) + the Pro Net gamepass flag, and computes
-- the EFFECTIVE catch params (hold mult, range add, auto-catch, flee-resist) by SUMMING net + HUNT
-- perks + the gamepass UNDER THE NetConfig CAPS. WildSpawnService (instanced) + SharedEventService
-- (shared) read these. The net adjusts PARAMETERS ONLY -- it never touches catch atomicity / dupe-
-- safety / the no-catch-rng rule.
--
-- ============================  SELF-AUDIT (net)  =============================================
-- (a) SERVER-AUTHORITATIVE: EffectiveCatch reads the persisted NetTier + the ProNet attribute +
--     PerkEffects on the server; the client only sends equip/upgrade intent + renders. A client
--     claiming a higher tier is ignored.
-- (b) STACKS UNDER CAPS, NO BLOWUP: net + gamepass + HUNT are SUMMED then clamped (MaxHoldReduce /
--     MaxRangeAdd / MaxAutoCatch / MaxFleeResist) -- no double-apply, no multiplicative runaway.
-- (c) UPGRADE IDEMPOTENT + PRICED: each upgrade advances ONE tier + TrySpends that tier's cost
--     (guarded accessor) + records NetTier; rate-limited; persists; you can never get a tier without
--     paying its cost. The second cash sink alongside M10.2 gate unlocks.
-- (d) NON-RANDOM ROBUX: the Pro Net gamepass + every tier is a fixed, named, disclosed effect.
-- (e) CATCH UNCHANGED: parameters only; M10.1/M10.3 atomicity + no-catch-rng intact.
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetConfig = require(ReplicatedStorage.Shared.NetConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local PerkEffects = require(script.Parent.PerkEffects)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local Analytics = require(script.Parent.Analytics)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)

local NetService = {}

local function tierOf(player)
    local profile = ProfileManager.GetProfile(player)
    return (profile ~= nil and profile.Data.NetTier) or NetConfig.BaseTier
end

-- THE single combine site: effective catch params from net tier + Pro Net gamepass + HUNT perks,
-- summed then clamped to the caps. Read by WildSpawnService + SharedEventService.
function NetService.EffectiveCatch(player)
    local tier = NetConfig.Get(tierOf(player))
    local hunt = PerkEffects.GetHunt(player)
    local huntSpeed = (hunt ~= nil and type(hunt.CatchSpeed) == "number") and hunt.CatchSpeed or 0
    local huntRange = (hunt ~= nil and type(hunt.CatchRange) == "number") and hunt.CatchRange or 0
    local huntAuto = (hunt ~= nil and type(hunt.AutoCatch) == "number") and hunt.AutoCatch or 0
    local hasGp = player:GetAttribute("ProNet") == true
    local gpHold = hasGp and NetConfig.Gamepass.HoldReduce or 0
    local gpRange = hasGp and NetConfig.Gamepass.RangeAdd or 0

    local holdReduce = math.clamp(tier.HoldReduce + gpHold + huntSpeed, 0, NetConfig.MaxHoldReduce)
    local rangeAdd = math.clamp(tier.RangeAdd + gpRange + huntRange, 0, NetConfig.MaxRangeAdd)
    local autoCatch = math.clamp((tier.AutoCatch or 0) + huntAuto, 0, NetConfig.MaxAutoCatch)
    local fleeResist = math.clamp(tier.FleeResist or 0, 0, NetConfig.MaxFleeResist)
    return {
        HoldMult = 1 - holdReduce, -- multiply the base hold by this
        RangeAdd = rangeAdd, -- + catch distance (studs)
        AutoCatch = autoCatch, -- combined passive auto-catch chance (commons)
        FleeResist = fleeResist, -- fraction the creature's flee distance is cut by
    }
end

local function buildState(player)
    local tierId = tierOf(player)
    local tier = NetConfig.Get(tierId)
    local nextTier = NetConfig.Tiers[tierId + 1]
    return {
        Tier = tierId,
        TierName = tier.Name,
        MaxTier = NetConfig.MaxTier,
        HasProNet = player:GetAttribute("ProNet") == true,
        Bonuses = {
            HoldReduce = tier.HoldReduce,
            RangeAdd = tier.RangeAdd,
            FleeResist = tier.FleeResist,
            AutoCatch = tier.AutoCatch,
        },
        Next = nextTier ~= nil and {
            Name = nextTier.Name,
            Cost = nextTier.Cost,
            HoldReduce = nextTier.HoldReduce,
            RangeAdd = nextTier.RangeAdd,
            FleeResist = nextTier.FleeResist,
            AutoCatch = nextTier.AutoCatch,
        } or nil,
        ProNetBonus = NetConfig.Gamepass,
    }
end

local function handleUpgrade(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    local current = profile.Data.NetTier or NetConfig.BaseTier
    if current >= NetConfig.MaxTier then
        return { Result = "Error", Message = "Your net is already max tier." }
    end
    local cost = NetConfig.UpgradeCost(current) or 0
    -- ===== COMMIT: spend (guarded) + advance one tier + record, no yields. =====
    if cost > 0 and not ProfileManager.TrySpend(player, cost) then
        return { Result = "Error", Message = "You can't afford it ($" .. cost .. ")." }
    end
    profile.Data.NetTier = current + 1
    -- ==========================================================================
    ProfileManager.ForceSave(player)
    PlayerStats.PushCash(player, profile)
    Leaderstats.Update(player, profile)
    Analytics.custom(player, Analytics.Events.NetUpgrade, profile.Data.NetTier)
    Remotes.NotifyPlayer(
        player,
        "success",
        "Upgraded to the " .. NetConfig.Get(profile.Data.NetTier).Name .. "!",
        "buy"
    )
    return { Result = "Success", State = buildState(player) }
end

function NetService.SetupPlayer(_player, profile)
    if type(profile.Data.NetTier) ~= "number" then
        profile.Data.NetTier = NetConfig.BaseTier
    end
    profile.Data.NetTier = math.clamp(math.floor(profile.Data.NetTier), 1, NetConfig.MaxTier)
end

function NetService.Init()
    Remotes.NetAction.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return { Result = "Error", Message = "Invalid request." }
        end
        if not RateLimiter.check(player, "net", 0.5) then
            return { Result = "Error", Message = "Slow down." }
        end
        if payload.Action == "get" then
            return { Result = "Success", State = buildState(player) }
        elseif payload.Action == "upgrade" then
            return handleUpgrade(player)
        end
        return { Result = "Error", Message = "Unknown action." }
    end
end

return NetService
