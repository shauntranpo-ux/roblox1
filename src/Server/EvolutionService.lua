-- EvolutionService (M11.2): per-unit XP accrual + the server-validated, atomic EVOLVE action. A unit
-- banks XP while it earns (and when it survives a steal); at a threshold it can EVOLVE -- a bigger
-- income multiplier (via the canonical helper), a stronger M11.1 perk, and a placeholder evolved look.
--
-- ============================  SELF-AUDIT (evolution path)  ==================================
-- (a) STAGE + XP ARE INTRINSIC + TRAVEL UNCHANGED: they live on the per-unit record; the ONLY place
--     stage changes is handleEvolve (server-validated). Steal/trade move the WHOLE record (Mutation,
--     Star, EvolutionStage, XP) by reference -- never reset/re-rolled/duplicated (proven in
--     StealService.transferOwnership + TradeService).
-- (b) THE EVOLUTION MULTIPLIER APPLIES EXACTLY ONCE: only Shared/UnitIncome multiplies it, from the
--     stage field; stored IncomePerSec stays the species base. Per-unit factors uncapped; the global
--     multiplier stays capped (IncomeService) -- formula intact, no double-count.
-- (c) EVOLVING AN EQUIPPED UNIT RECOMPUTES ITS PERK IDEMPOTENTLY: PerksConfig.Scale now reads the
--     stage, and we call LoadoutService.RecomputePlayer (full recompute-from-scratch) -> the perk
--     magnitude updates exactly once, under the cap, with no residue.
-- (d) EVOLVE IS ATOMIC + SERVER-VALIDATED: TrySpend (guarded accessor) + stage increment + XP reset
--     run with NO yields, so a crash leaves the unit EITHER evolved (+cost paid) OR untouched.
-- (e) FORWARD-COMPAT: AwardUnitXP / AwardAllXP are dormant hooks for M10 wild-catch + M11.3 bosses;
--     they no-op safely until those systems call them.
-- ===========================================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EvolutionConfig = require(ReplicatedStorage.Shared.EvolutionConfig)
local UnitIncome = require(ReplicatedStorage.Shared.UnitIncome)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local ProfileManager = require(script.Parent.ProfileManager)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local TransitRegistry = require(script.Parent.TransitRegistry)
local TradeLockRegistry = require(script.Parent.TradeLockRegistry)
local BrainrotService = require(script.Parent.BrainrotService)
local PlotService = require(script.Parent.PlotService)
local LoadoutService = require(script.Parent.LoadoutService)
local Analytics = require(script.Parent.Analytics)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)

local EvolutionService = {}

local XP_INTERVAL = 8 -- s: how often placed units bank earning-XP (a sane cadence, NOT per frame)
local accum = 0

local function findEntry(profile, unitId)
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        if unit.Id == unitId then
            return unit
        end
    end
    return nil
end

-- ===========================================================================================
-- Evolve handler (INTENT ONLY: a unit Id). Server-validated + atomic.
-- ===========================================================================================
local function handleEvolve(player, unitId)
    if type(unitId) ~= "string" or #unitId == 0 or #unitId > 100 then
        return { Result = "Error", Message = "Invalid unit." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    local unit = findEntry(profile, unitId)
    if unit == nil then
        return { Result = "Error", Message = "You don't own that unit." }
    end
    -- Can't evolve a unit that's mid-steal or locked in a trade (equipped is fine).
    if TransitRegistry.Has(unitId) then
        return { Result = "Error", Message = "That unit is being stolen right now." }
    end
    if TradeLockRegistry.Has(unitId) then
        return { Result = "Error", Message = "That unit is locked in a trade." }
    end

    local stage = EvolutionConfig.StageOf(unit)
    if stage >= EvolutionConfig.MaxStage then
        return { Result = "Error", Message = "Already at max stage." }
    end
    if not EvolutionConfig.CanEvolve(unit) then
        return { Result = "Error", Message = "Needs more XP to evolve." }
    end
    local cost = EvolutionConfig.EvolveCost(stage)

    -- ===== COMMIT: pay (guarded accessor) + increment stage + settle XP, NO yields between. =====
    if cost > 0 then
        if not ProfileManager.TrySpend(player, cost) then
            return {
                Result = "Error",
                Message = "You can't afford the evolve cost ($" .. cost .. ").",
            }
        end
    end
    local threshold = EvolutionConfig.Threshold(stage) or 0
    unit.EvolutionStage = stage + 1
    if EvolutionConfig.CarryOverXP then
        unit.XP = math.max(0, (unit.XP or 0) - threshold) -- carry the overflow toward the next stage
    else
        unit.XP = 0
    end
    -- ===========================================================================================

    -- Refresh the on-pad visual (new size/aura/label) -- only if its model is currently spawned.
    local plot = PlotService.GetPlot(player)
    if plot ~= nil then
        BrainrotService.RemoveModel(player, unitId)
        BrainrotService.SpawnBrainrot(player, plot, unit)
    end
    -- Recompute income AND (idempotently) every equipped perk -- the evolved unit's perk magnitude
    -- now reflects its new stage, applied exactly once, under the cap.
    LoadoutService.RecomputePlayer(player, profile)
    PlayerStats.PushCash(player, profile)
    Leaderstats.Update(player, profile)

    local def = Catalog.Get(unit.Type)
    Analytics.custom(player, Analytics.Events.Evolve, unit.EvolutionStage)
    ProfileManager.ForceSave(player)
    return {
        Result = "Success",
        Stage = unit.EvolutionStage,
        Message = (def ~= nil and def.DisplayName or "Unit")
            .. " evolved to Stage "
            .. unit.EvolutionStage
            .. "!",
    }
end

-- ===========================================================================================
-- XP accrual + forward-compat hooks
-- ===========================================================================================

-- FORWARD-COMPAT (M10 wild-catch / M11.3 bosses): award XP to ONE owned unit. Dormant until those
-- systems call it; no-ops safely if the unit isn't owned. AddXP caps gracefully at max stage.
function EvolutionService.AwardUnitXP(player, unitId, amount)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    local unit = findEntry(profile, unitId)
    if unit ~= nil then
        EvolutionConfig.AddXP(unit, amount)
    end
end

-- FORWARD-COMPAT (M11.3 boss participation): award XP to ALL of a player's placed (non-in-transit)
-- units. Dormant until bosses land.
function EvolutionService.AwardAllXP(player, amount)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        if not TransitRegistry.Has(unit.Id) then
            EvolutionConfig.AddXP(unit, amount)
        end
    end
end

function EvolutionService.Init()
    Remotes.EvolveRequest.OnServerInvoke = function(player, unitId)
        if not RateLimiter.check(player, "evolve", 0.5) then
            return { Result = "Error", Message = "Slow down." }
        end
        return handleEvolve(player, unitId)
    end

    -- LIVE XP source: a placed/earning unit banks XP proportional to its effective income + a flat
    -- trickle, on a throttled cadence. In-transit units don't accrue (they earn for no one).
    RunService.Heartbeat:Connect(function(deltaTime)
        accum += deltaTime
        if accum < XP_INTERVAL then
            return
        end
        local elapsed = accum
        accum = 0
        for _, player in ipairs(Players:GetPlayers()) do
            local profile = ProfileManager.GetProfile(player)
            if profile ~= nil then
                for _, unit in ipairs(profile.Data.OwnedBrainrots) do
                    if not TransitRegistry.Has(unit.Id) then
                        local xp = UnitIncome.effective(unit) * elapsed * EvolutionConfig.XPPerCash
                            + EvolutionConfig.FlatXPPerSec * elapsed
                        EvolutionConfig.AddXP(unit, xp)
                    end
                end
            end
        end
    end)
end

return EvolutionService
