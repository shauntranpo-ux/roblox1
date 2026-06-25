-- GameSignals (M12.1): a tiny DECOUPLED server-side event BUS so OBSERVER systems (quests, future
-- achievements) can SUBSCRIBE to real gameplay events WITHOUT the gameplay systems depending on them.
-- A gameplay site fires a clean metric ("catch_count", "evolutions", ...) as a pure OBSERVATION hook --
-- one line, NO behavior change, NO return value read. Subscribers run in a pcall so an observer error
-- can NEVER break the gameplay path. Requires nothing (no require cycles); one writer many readers.
--
-- This is the "emit/observe" seam: the catch/steal/evolution/boss/fusion/economy logic is UNCHANGED;
-- it just announces that a thing happened. QuestService.Init subscribes; metrics whose source system
-- never fires stay dormant with no error (forward-compat).

local GameSignals = {}

local subscribers = {} -- array of fn(player, metric, amount)

function GameSignals.subscribe(fn)
    if type(fn) == "function" then
        table.insert(subscribers, fn)
    end
end

-- Announce a gameplay event for `player`. `amount` defaults to 1. Never errors out to the caller.
function GameSignals.fire(player, metric, amount)
    if player == nil or type(metric) ~= "string" then
        return
    end
    amount = tonumber(amount) or 1
    if amount <= 0 then
        return
    end
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, player, metric, amount)
        if not ok then
            warn("[GameSignals] subscriber error on '" .. metric .. "': " .. tostring(err))
        end
    end
end

return GameSignals
