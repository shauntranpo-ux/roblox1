-- RebirthService: the prestige/rebirth long-tail loop. ONE atomic, guarded, debounced operation.
--
-- ============================  SELF-AUDIT (rebirth path)  ===================================
-- ATOMIC: the destructive profile change (Cash->0, non-premium OwnedBrainrots cleared, RebirthCount++,
--   PrestigeMultiplier set) happens in ONE synchronous block with NO yields, so a crash leaves the
--   profile fully PRE-rebirth or fully POST-rebirth -- never half-reset (ProfileStore persists Data
--   atomically). The model despawns before it are pure visuals; only the profile mutation matters.
-- NEVER STRIPS PAID VALUE: premium/limited units (Catalog Premium=true) are KEPT on their pads;
--   unlocked pads (incl. gamepass/product pads) persist; gamepasses + their benefit sources are
--   untouched (rebirth never clears them) and re-derive on join as always; a still-valid timed code
--   boost persists. Discovered / PurchaseHistory / RedeemedCodes / ClaimedIndexRewards / settings
--   all persist.
-- STEAL-SAFE: refuses to run while the player is mid-steal (thief OR victim, via StealService.IsBusy)
--   so no unit can be duped or stranded mid-carry.
-- NO DOUBLE-REBIRTH: a rate limit + an in-flight guard mean a spammed/raced request performs at most
--   once; the prestige multiplier is RE-DERIVED from the count (idempotent), never accumulated.
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthConfig = require(ReplicatedStorage.Shared.RebirthConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local ProtectionService = require(script.Parent.ProtectionService)
local StealService = require(script.Parent.StealService)
local TradeService = require(script.Parent.TradeService)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)
local SeasonService = require(script.Parent.SeasonService)

local RebirthService = {}

local inFlight = {} -- [Player] = true while a rebirth is committing (guards the race)

-- Publishes rebirth count + prestige multiplier as attributes (for the HUD/panel) and re-derives
-- the multiplier from the count (idempotent). Call on join + after a rebirth.
function RebirthService.SetupPlayer(player, profile)
    profile.Data.PrestigeMultiplier = RebirthConfig.MultiplierFor(profile.Data.RebirthCount)
    player:SetAttribute("RebirthCount", profile.Data.RebirthCount)
    player:SetAttribute("PrestigeMultiplier", profile.Data.PrestigeMultiplier)
    PlayerStats.UpdateIncome(player, profile)
end

-- The single guarded mutation. No yields between the first profile write and the last.
local function commitRebirth(player, profile)
    local cashSunk = profile.Data.Cash
    local newCount = profile.Data.RebirthCount + 1

    -- Partition owned units: premium SURVIVE, others are cleared.
    local kept = {}
    local cleared = {}
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        local def = Catalog.Get(brainrot.Type)
        if def ~= nil and def.Premium then
            table.insert(kept, brainrot)
        else
            table.insert(cleared, brainrot)
        end
    end
    -- Despawn cleared models (visual only; janitor-equivalent RemoveModel destroys each instance).
    for _, brainrot in ipairs(cleared) do
        BrainrotService.RemoveModel(player, brainrot.Id)
    end

    -- ===== ATOMIC: profile mutation, no yields =====
    profile.Data.OwnedBrainrots = kept
    ProfileManager.AddCash(player, -cashSunk) -- guarded accessor -> clamps to 0
    profile.Data.RebirthCount = newCount
    profile.Data.PrestigeMultiplier = RebirthConfig.MultiplierFor(newCount)
    -- ===============================================

    -- Re-grant the fresh starter on a free pad (premium units may occupy some pads).
    if RebirthConfig.RegrantStarter then
        local padIndex = PlotService.FindFreePad(player, profile)
        local plot = PlotService.GetPlot(player)
        if padIndex ~= nil and plot ~= nil then
            local starter = Catalog.GetStarter()
            local unit =
                BrainrotFactory.create(player, starter, padIndex, BrainrotFactory.RollFor.Starter)
            table.insert(profile.Data.OwnedBrainrots, unit)
            profile.Data.Discovered[starter.Id] = true
            BrainrotService.SpawnBrainrot(player, plot, unit)
        end
    end

    RebirthService.SetupPlayer(player, profile)
    PlayerStats.PushCash(player, profile)
    Leaderstats.Update(player, profile)
    ProtectionService.RefreshPrompts(player)

    Analytics.custom(player, Analytics.Events.Rebirth, newCount)
    Analytics.economySink(player, cashSunk, 0, Analytics.Tx.Gameplay, "rebirth")
    SeasonService.Signal(player, "REBIRTH", 1)
end

-- Request handler (RemoteFunction). TRUST BOUNDARY: the client sends NOTHING but the request; the
-- server reads Cash + count from the profile and the requirement from config. Returns a result enum.
function RebirthService.Request(player)
    if not RateLimiter.check(player, "rebirth", 1) then
        return { Result = "Error", Message = "Slow down." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    if inFlight[player] then
        return { Result = "Error", Message = "Rebirth already in progress." }
    end
    if StealService.IsBusy(player) then
        return { Result = "Busy", Message = "Finish your steal before rebirthing." }
    end
    if TradeService.IsTrading(player) then
        return { Result = "Busy", Message = "Finish your trade before rebirthing." }
    end
    local requirement = RebirthConfig.RequirementFor(profile.Data.RebirthCount)
    if profile.Data.Cash < requirement then
        return { Result = "Ineligible", Message = "You don't have enough cash to rebirth yet." }
    end

    inFlight[player] = true
    local ok = pcall(commitRebirth, player, profile)
    inFlight[player] = nil
    if not ok then
        return { Result = "Error", Message = "Rebirth failed -- nothing changed." }
    end
    return {
        Result = "Success",
        Message = string.format("REBIRTH! Prestige x%.2g", profile.Data.PrestigeMultiplier),
    }
end

function RebirthService.ClearPlayer(player)
    inFlight[player] = nil
end

function RebirthService.Init()
    Remotes.RequestRebirth.OnServerInvoke = function(player)
        return RebirthService.Request(player)
    end
end

return RebirthService
