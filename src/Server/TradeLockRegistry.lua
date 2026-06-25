-- TradeLockRegistry: a tiny, decoupled set of brainrot Ids currently LOCKED in a trade offer.
-- Decoupled (requires nothing) so StealService can READ it to refuse stealing a locked unit
-- without a require cycle back into TradeService (same pattern as TransitRegistry).
--   * TradeService WRITES it (lock on offer-add, unlock on remove/cancel/complete).
--   * StealService READS it (a locked unit can't be stolen / become IN_TRANSIT).

local TradeLockRegistry = {}

local locked = {} -- [brainrotId] = true

function TradeLockRegistry.Set(brainrotId, value)
    if value then
        locked[brainrotId] = true
    else
        locked[brainrotId] = nil
    end
end

function TradeLockRegistry.Has(brainrotId)
    return locked[brainrotId] == true
end

return TradeLockRegistry
