-- SettingsService: persists + serves the tiny client preference table (Music / SFX / Shake).
--
-- TRUST BOUNDARY (GetSettings / SaveSettings): the client may only READ its own prefs and SAVE a
-- table of KNOWN boolean keys. The server validates the shape (anything else is dropped), stores
-- nothing but the three booleans, and rate-limits saves. Settings are purely presentational --
-- they grant zero gameplay advantage, so there is no economy/ownership surface here.

local Remotes = require(script.Parent.Remotes)
local ProfileManager = require(script.Parent.ProfileManager)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)

local SettingsService = {}

-- The only keys ever stored. BOOL mutes/toggles + M12.4 VOLUME numbers (0..1). Anything else from the
-- client is DROPPED. These are presentational PREFERENCES only -- they grant ZERO gameplay advantage,
-- so there is no economy/ownership surface here. (M13.6 added the graphics/HUD/notify toggles.)
local BOOL_DEFAULTS = {
    Music = false,
    SFX = true,
    Shake = true,
    ReduceEffects = false, -- graphics: skip particle/flash juice
    ShowKillFeed = true, -- HUD: show steal banners
    NotifyOptIn = false, -- re-engagement notifications opt-in (a preference; delivery is backend)
}
local NUM_DEFAULTS = { MusicVolume = 0.5, SfxVolume = 0.7, AmbienceVolume = 0.5 }

-- Coerces arbitrary client input into exactly the known keys (validated bools + clamped 0..1 numbers).
local function sanitize(data)
    local out = {}
    local t = type(data) == "table" and data or {}
    for key, default in pairs(BOOL_DEFAULTS) do
        out[key] = type(t[key]) == "boolean" and t[key] or default
    end
    for key, default in pairs(NUM_DEFAULTS) do
        local n = tonumber(t[key])
        out[key] = (n ~= nil) and math.clamp(n, 0, 1) or default
    end
    return out
end

local function getSettings(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return sanitize(nil) -- defaults
    end
    return sanitize(profile.Data.Settings)
end

local function onSave(player, data)
    if not RateLimiter.check(player, "settings", 0.3) then
        return -- rate-limited: spoofed/spammed persist intents are bounded
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    local prev = type(profile.Data.Settings) == "table" and profile.Data.Settings or {}
    local sanitized = sanitize(data) -- only validated keys are ever persisted; everything else dropped
    profile.Data.Settings = sanitized
    -- Analytics only (pcall-wrapped inside Analytics) -- NEVER affects gameplay. Settings grant nothing.
    Analytics.custom(player, Analytics.Events.SettingsChange, 1)
    if sanitized.NotifyOptIn and not prev.NotifyOptIn then
        Analytics.custom(player, Analytics.Events.NotifyOptIn, 1) -- false -> true opt-in
    end
end

function SettingsService.Init()
    Remotes.GetSettings.OnServerInvoke = getSettings
    Remotes.SaveSettings.OnServerEvent:Connect(onSave)
end

return SettingsService
