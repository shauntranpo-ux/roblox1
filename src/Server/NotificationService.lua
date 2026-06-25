-- NotificationService (M13.6): the in-engine half of RE-ENGAGEMENT notifications. The opt-in is a
-- persisted PREFERENCE (Settings.NotifyOptIn); ACTUAL delivery to an offline player is sent from a
-- BACKEND via Roblox Open Cloud against that opt-in (you can't ping an absent player from Luau). So
-- this module is the trigger + frequency-cap + analytics layer: gameplay/scheduler hooks call
-- notify(player, key) when something notify-worthy happens; we gate it on the player's opt-in + a
-- per-trigger cap and emit the analytics signal a backend consumes. Everything degrades gracefully:
-- it touches NO gameplay/economy state and never errors the caller.
--
-- ============================  SELF-AUDIT (notifications)  ==================================
-- (a) OPT-IN RESPECTED: notify() no-ops unless the player has Settings.NotifyOptIn = true. Nothing is
--     forced; no reward is tied to opting in (platform-rule safe).
-- (b) CAPPED: a per-player, per-trigger minimum interval (NotifyConfig.MinSecondsBetween) -> no spam.
-- (c) GRACEFUL: master switch + all reads guarded; no platform API is hard-required in-engine, so an
--     unavailable piece simply means no signal -- never an error.
-- ===========================================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NotifyConfig = require(ReplicatedStorage.Shared.NotifyConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local Analytics = require(script.Parent.Analytics)

local NotificationService = {}

-- [Player] = { [triggerKey] = lastSentOsTime } -- in-memory frequency-cap bookkeeping (session-scoped).
local lastSent = {}

local function optedIn(player)
    local profile = ProfileManager.GetProfile(player)
    return profile ~= nil
        and type(profile.Data.Settings) == "table"
        and profile.Data.Settings.NotifyOptIn == true
end

-- Records a notify-worthy event for `player`. No-ops unless the feature is on, the player opted in, and
-- the per-trigger cap has elapsed. Emits the analytics signal a backend reads to send the actual ping.
-- Returns true if a signal was emitted (for tests/logging); never errors the caller.
function NotificationService.notify(player, triggerKey)
    if not NotifyConfig.Enabled or type(triggerKey) ~= "string" then
        return false
    end
    if player == nil or player.Parent ~= Players then
        return false
    end
    if not optedIn(player) then
        return false -- opt-in is respected: no opt-in, no ping
    end
    local perPlayer = lastSent[player]
    if perPlayer == nil then
        perPlayer = {}
        lastSent[player] = perPlayer
    end
    local now = os.time()
    local last = perPlayer[triggerKey]
    if last ~= nil and (now - last) < NotifyConfig.MinSecondsBetween then
        return false -- frequency cap: don't spam
    end
    perPlayer[triggerKey] = now
    -- The signal a backend (Open Cloud) consumes to deliver the re-engagement notification.
    Analytics.custom(player, Analytics.Events.NotifyTrigger, 1)
    return true
end

-- Scheduler hook: a limited-time event just went live -> signal every opted-in player in this server.
-- Called (guarded) from EventService.onEventStart. Demonstrates trigger-via-the-existing-scheduler.
function NotificationService.onEventStart()
    if not NotifyConfig.Enabled then
        return
    end
    for _, player in ipairs(Players:GetPlayers()) do
        NotificationService.notify(player, NotifyConfig.Triggers.EventStart)
    end
end

function NotificationService.ClearPlayer(player)
    lastSent[player] = nil
end

return NotificationService
