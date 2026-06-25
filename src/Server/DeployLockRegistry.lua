-- DeployLockRegistry: a tiny, decoupled set of brainrot Ids currently LOCKED because they are
-- EQUIPPED to a perk slot (M11.1). This is the SAME item-lock the M9.3 deploy system used -- REUSED,
-- not forked. Decoupled (requires nothing) so SellService / FusionService / StealService /
-- TradeService can READ it to refuse acting on an equipped unit, without a require cycle.
--   * LoadoutService WRITES it (lock on equip, unlock on unequip / leave).
--   * Sell / Fusion / Steal / Trade READ it (an equipped unit can't be sold/fused/stolen/traded).

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
