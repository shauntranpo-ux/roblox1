-- EventsConfig: data-driven LIMITED-TIME EVENTS. Each event is a time window (absolute UTC
-- os.time() timestamps) the server activates/deactivates by wall-clock -- identical on every
-- server, no coordination needed. An event is an ORCHESTRATOR: it toggles EXISTING levers
-- (income/luck multiplier sources, the per-roster/per-mutation Available flags) and offers quests
-- + an optional currency/shop. No parallel economy, no new monetization.
--
-- TIMESTAMPS ARE UTC os.time(). Set StartTimestamp/EndTimestamp to real epoch seconds to schedule.
-- Leaving them 0 means "never naturally active" -- use the guarded DEV/TEST force-event hook to
-- exercise an event in Studio without waiting for real dates. (Seasons (8.5) reuse this scheduler.)

local EventsConfig = {}

EventsConfig.TickInterval = 3 -- s between active-set recomputes (cheap)
EventsConfig.GraceWindow = 86400 -- s after an event ends that earned-but-unclaimed rewards remain claimable

-- OPTIONAL future cross-server community-goal counter. DEFAULT OFF; the engine does not depend on
-- it. (A real implementation would use MessagingService + a shared DataStore -- left as a hardening
-- item; see the comment in EventService.)
EventsConfig.CommunityCounterEnabled = false

-- Objective Types map to signals the existing services already emit (see EventService.Signal):
--   EARN_CASH, BUY_BRAINROTS, STEAL_BRAINROTS, COMPLETE_TRADES, ROLL_MUTATION, REDEEM_CODE
EventsConfig.Events = {
    {
        Key = "double_weekend",
        DisplayName = "2x Income Weekend",
        Description = "Double income + double mutation luck! Complete quests for Tickets.",
        StartTimestamp = 0, -- <<< set real UTC epoch seconds to schedule (0 = dev-force only)
        EndTimestamp = 0,
        Active = true,
        Modifiers = { IncomeMultiplier = 2, LuckMultiplier = 2 },
        UnlockedRosterIds = {}, -- event-only brainrot Ids made available during the window
        UnlockedMutationKeys = {}, -- event-only mutation keys made available
        EventCurrency = { Id = "tickets", Name = "Tickets" },
        Quests = {
            {
                Id = "buy5",
                Description = "Buy 5 brainrots",
                Type = "BUY_BRAINROTS",
                Target = 5,
                Reward = { Type = "Cash", Amount = 50000 },
            },
            {
                Id = "steal3",
                Description = "Steal 3 brainrots",
                Type = "STEAL_BRAINROTS",
                Target = 3,
                Reward = { Type = "EventCurrency", Amount = 15 },
            },
            {
                Id = "earn1m",
                Description = "Earn $1M",
                Type = "EARN_CASH",
                Target = 1000000,
                Reward = { Type = "EventCurrency", Amount = 10 },
            },
        },
        ShopEntries = {
            {
                Id = "lucky",
                Name = "Event Brainrot",
                Price = 20,
                Grant = { Type = "Brainrot", BrainrotId = "chimpanzini" },
            },
            { Id = "cash", Name = "$250K", Price = 5, Grant = { Type = "Cash", Amount = 250000 } },
        },
    },
}

EventsConfig.ByKey = {}
for _, event in ipairs(EventsConfig.Events) do
    EventsConfig.ByKey[event.Key] = event
end

-- Defensive validity check: skip malformed / disabled events (zero-length or inverted windows are
-- still valid for dev-force since both are 0; a real window must have End > Start).
function EventsConfig.IsConfigValid(event)
    if event == nil or event.Active == false then
        return false
    end
    if
        event.StartTimestamp ~= 0
        and event.EndTimestamp ~= 0
        and event.EndTimestamp <= event.StartTimestamp
    then
        return false
    end
    return true
end

return EventsConfig
