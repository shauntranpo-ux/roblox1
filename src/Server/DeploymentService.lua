-- DeploymentService (M10): moves an owned unit between the BAG (PadIndex == nil -- storage, earns no
-- income) and the player's PADS (PadIndex set -- on-pad, earns income). Server-authoritative INTENT
-- handlers exposed through the existing InventoryAction RemoteFunction (deploy / undeploy / swap).
--
-- DUPE-SAFE: these only flip PadIndex on an existing unit record -- never mint or destroy a unit -- so
-- there is no duplication surface. The free-pad lookup + the PadIndex write + the on-pad visual
-- spawn/remove run with NO yields between them (the only yield is the trailing ForceSave, after state is
-- already consistent), so two concurrent invokes can't hand out the same pad. A unit that is perk-locked,
-- in a steal transit, or in a trade is BUSY and refuses to move (its pad state is owned elsewhere).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitIncome = require(ReplicatedStorage.Shared.UnitIncome)

local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local ProtectionService = require(script.Parent.ProtectionService)
local RateLimiter = require(script.Parent.RateLimiter)
local DeployLockRegistry = require(script.Parent.DeployLockRegistry)
local TransitRegistry = require(script.Parent.TransitRegistry)
local TradeLockRegistry = require(script.Parent.TradeLockRegistry)

local DeploymentService = {}

local function findUnit(profile, unitId)
    if type(unitId) ~= "string" or #unitId == 0 or #unitId > 100 then
        return nil
    end
    for _, u in ipairs(profile.Data.OwnedBrainrots) do
        if u.Id == unitId then
            return u
        end
    end
    return nil
end

-- A unit busy in another system can't be re-padded here (its pad/transit state is owned elsewhere).
local function isBusy(unitId)
    return DeployLockRegistry.Has(unitId)
        or TransitRegistry.Has(unitId)
        or TradeLockRegistry.Has(unitId)
end

-- The weakest currently-placed, movable unit (lowest effective income) -> the default swap candidate.
local function weakestPlaced(profile, excludeId)
    local best, bestRate = nil, nil
    for _, u in ipairs(profile.Data.OwnedBrainrots) do
        if u.PadIndex ~= nil and u.Id ~= excludeId and not isBusy(u.Id) then
            local rate = UnitIncome.effective(u)
            if bestRate == nil or rate < bestRate then
                best, bestRate = u, rate
            end
        end
    end
    return best
end

-- Recompute income + refresh prompts/stats + persist (the only yield is the trailing save).
local function commit(player, profile)
    ProtectionService.RefreshPrompts(player)
    PlayerStats.UpdateIncome(player, profile)
    PlayerStats.PushCash(player, profile)
    Leaderstats.Update(player, profile)
    ProfileManager.ForceSave(player)
end

-- DEPLOY: move a BAG unit onto a free pad + spawn its on-pad visual. If the base is full, returns
-- Result="Full" + the suggested swap candidate (the weakest placed unit) so the client can offer a swap.
function DeploymentService.Deploy(player, unitId)
    if not RateLimiter.check(player, "deploy", 0.2) then
        return { Result = "Error", Message = "Slow down." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    local plot = PlotService.GetPlot(player)
    if plot == nil then
        return { Result = "Error", Message = "Your base isn't ready." }
    end
    local unit = findUnit(profile, unitId)
    if unit == nil then
        return { Result = "Error", Message = "You don't own that unit." }
    end
    if unit.PadIndex ~= nil then
        return { Result = "Error", Message = "That unit is already deployed." }
    end
    if isBusy(unit.Id) then
        return { Result = "Error", Message = "That unit is busy right now." }
    end

    local padIndex = PlotService.FindFreePad(player, profile)
    if padIndex == nil then
        local cand = weakestPlaced(profile, unitId)
        return {
            Result = "Full",
            Message = "Your base is full.",
            SwapId = cand ~= nil and cand.Id or nil,
        }
    end

    -- ===== no-yield commit: claim the pad + spawn the visual =====
    unit.PadIndex = padIndex
    BrainrotService.SpawnBrainrot(player, plot, unit)
    -- =============================================================
    commit(player, profile)
    return { Result = "Success" }
end

-- UNDEPLOY: pull a placed unit OFF its pad back into the bag (removes its visual; it stops earning).
function DeploymentService.Undeploy(player, unitId)
    if not RateLimiter.check(player, "deploy", 0.2) then
        return { Result = "Error", Message = "Slow down." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    local unit = findUnit(profile, unitId)
    if unit == nil then
        return { Result = "Error", Message = "You don't own that unit." }
    end
    if unit.PadIndex == nil then
        return { Result = "Error", Message = "That unit is already in your bag." }
    end
    if isBusy(unit.Id) then
        return { Result = "Error", Message = "That unit is busy right now." }
    end

    -- ===== no-yield commit: remove the visual + free the pad =====
    BrainrotService.RemoveModel(player, unit.Id)
    unit.PadIndex = nil
    -- ============================================================
    commit(player, profile)
    return { Result = "Success" }
end

-- SWAP: send a placed unit to the bag and deploy a bag unit onto the pad it just freed (one tap).
function DeploymentService.Swap(player, bagUnitId, padUnitId)
    if not RateLimiter.check(player, "deploy", 0.2) then
        return { Result = "Error", Message = "Slow down." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    local plot = PlotService.GetPlot(player)
    if plot == nil then
        return { Result = "Error", Message = "Your base isn't ready." }
    end
    local bagUnit = findUnit(profile, bagUnitId)
    local padUnit = findUnit(profile, padUnitId)
    if bagUnit == nil or padUnit == nil or bagUnit == padUnit then
        return { Result = "Error", Message = "Those units can't be swapped." }
    end
    if bagUnit.PadIndex ~= nil then
        return { Result = "Error", Message = "The first unit is already deployed." }
    end
    if padUnit.PadIndex == nil then
        return { Result = "Error", Message = "The unit to swap out isn't deployed." }
    end
    if isBusy(bagUnit.Id) or isBusy(padUnit.Id) then
        return { Result = "Error", Message = "One of those units is busy right now." }
    end

    -- ===== no-yield commit: free padUnit's pad, then deploy bagUnit onto it =====
    local padIndex = padUnit.PadIndex
    BrainrotService.RemoveModel(player, padUnit.Id)
    padUnit.PadIndex = nil
    bagUnit.PadIndex = padIndex
    BrainrotService.SpawnBrainrot(player, plot, bagUnit)
    -- ===========================================================================
    commit(player, profile)
    return { Result = "Success" }
end

return DeploymentService
