-- SettingsService: persists + serves the tiny client preference table (Music / SFX / Shake).
--
-- TRUST BOUNDARY (GetSettings / SaveSettings): the client may only READ its own prefs and SAVE a
-- table of KNOWN boolean keys. The server validates the shape (anything else is dropped), stores
-- nothing but the three booleans, and rate-limits saves. Settings are purely presentational --
-- they grant zero gameplay advantage, so there is no economy/ownership surface here.

local Remotes = require(script.Parent.Remotes)
local ProfileManager = require(script.Parent.ProfileManager)
local RateLimiter = require(script.Parent.RateLimiter)

local SettingsService = {}

-- The only keys ever stored, with their defaults (music defaults OFF -- no audio asset shipped).
local DEFAULTS = { Music = false, SFX = true, Shake = true }

-- Coerces arbitrary client input into exactly the known boolean keys (defaults fill the rest).
local function sanitize(data)
    local out = {}
    for key, default in pairs(DEFAULTS) do
        local value = type(data) == "table" and data[key]
        if type(value) == "boolean" then
            out[key] = value
        else
            out[key] = default
        end
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
        return
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    profile.Data.Settings = sanitize(data) -- only validated booleans are ever persisted
end

function SettingsService.Init()
    Remotes.GetSettings.OnServerInvoke = getSettings
    Remotes.SaveSettings.OnServerEvent:Connect(onSave)
end

return SettingsService
