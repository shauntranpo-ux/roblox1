-- TradeConfig: THE single source of truth for player-to-player trading tunables. Retune here.
--
-- Trading is SAME-SERVER ONLY (both profiles session-locked on this server) so the swap is one
-- synchronous in-memory mutation -- see TradeService for the dupe-proof atomic two-party swap.

local TradeConfig = {}

TradeConfig.RequestTimeout = 30 -- s a trade request waits for the target to accept
TradeConfig.SessionTimeout = 180 -- s of inactivity before an open trade auto-cancels
TradeConfig.SettleDelay = 1 -- s after ANY offer edit before "Ready" can be clicked (anti-switcheroo)
TradeConfig.MaxItemsPerSide = 6 -- max brainrots one side can offer
TradeConfig.CashTradingEnabled = true -- allow cash in trades?
TradeConfig.MaxCashPerTrade = 1000000000 -- per-side cash offer cap
TradeConfig.TradeCooldown = 5 -- s between a player's completed trades
TradeConfig.MaxHistory = 20 -- capped per-player trade-history entries persisted

-- Are premium/limited units tradeable? Default FALSE to protect their paid value. Flip to true
-- to allow it. (A roster entry can also set Tradeable = false explicitly to lock any unit.)
TradeConfig.PremiumTradeable = false

-- The single tradeable rule, used by the server on offer-add AND at COMMIT, and by the client UI
-- to grey out untradeable units. `item` is a Catalog roster entry.
function TradeConfig.IsTradeable(item)
    if item == nil then
        return false
    end
    if item.Tradeable == false then
        return false -- explicitly locked in the roster
    end
    if item.Premium == true and not TradeConfig.PremiumTradeable then
        return false -- premium units protected by default
    end
    return true
end

return TradeConfig
