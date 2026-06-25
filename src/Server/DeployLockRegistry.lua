-- DeployLockRegistry: a tiny, decoupled set of brainrot Ids currently LOCKED because they are
-- DEPLOYED to a role slot. Decoupled (requires nothing) so SellService / FusionService / StealService
-- / TradeService can READ it to refuse acting on a deployed unit, without a require cycle back into
-- DeployService (same pattern as TransitRegistry / TradeLockRegistry).
--   * DeployService WRITES it (lock on assign, unlock on unassign / leave).
--   * Sell / Fusion / Steal / Trade READ it (a deployed unit can't be sold/fused/stolen/traded).

local DeployLockRegistry = {}

local locked = {} -- [brainrotId] = true

function DeployLockRegistry.Set(brainrotId, value)
    if value then
        locked[brainrotId] = true
    else
        locked[brainrotId] = nil
    end
end

function DeployLockRegistry.Has(brainrotId)
    return locked[brainrotId] == true
end

-- Read-only shallow copy (for the dev invariant validator).
function DeployLockRegistry.All()
    local copy = {}
    for id in pairs(locked) do
        copy[id] = true
    end
    return copy
end

return DeployLockRegistry
