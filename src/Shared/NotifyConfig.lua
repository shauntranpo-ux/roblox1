-- NotifyConfig (M13.6): tunables for RE-ENGAGEMENT notifications (the "notify me to come back" pings
-- when a daily chest is ready / an event starts / offline earnings cap out).
--
-- ============================  HOW THIS WORKS (platform boundary)  ==========================
-- The OPT-IN is captured in-experience as a persisted PREFERENCE (Settings.NotifyOptIn) -- the player
-- chooses to receive pings; nothing is forced and no reward is tied to enabling it. ACTUAL DELIVERY of
-- a re-engagement notification to an OFFLINE player is sent from a BACKEND via Roblox Open Cloud
-- (POST .../notifications) against this opt-in -- it cannot be sent from in-engine Luau (you can't ping
-- a player who isn't here). So in-engine we: (1) store the opt-in, (2) define the TRIGGERS + frequency
-- CAP here, (3) log analytics at each trigger point so the backend has the signal. Everything degrades
-- gracefully if a platform/API piece is unavailable.
-- ===========================================================================================

local NotifyConfig = {}

NotifyConfig.Enabled = true -- master switch for the whole re-engagement layer
NotifyConfig.OptInDefault = false -- players are OPTED OUT until they choose in (respect permissions)

-- Frequency cap: the minimum seconds between pings of the SAME trigger to one player (anti-spam). The
-- backend is the source of truth for real delivery caps; this also gates the in-engine analytics signal.
NotifyConfig.MinSecondsBetween = 6 * 3600 -- 6h

-- The trigger keys a backend would notify on. Wire points fire NotificationService.notify(player, key).
NotifyConfig.Triggers = {
    DailyChestReady = "daily_chest_ready", -- the daily streak chest is claimable again
    EventStart = "event_start", -- a limited-time event just went live
    OfflineCap = "offline_cap", -- offline earnings have hit their cap (come collect)
}

-- Shown in the settings toggle subtitle so the player knows what they're opting into.
NotifyConfig.Blurb =
    "Get a ping when your daily chest is ready or an event starts. Opt out anytime."

return NotifyConfig
