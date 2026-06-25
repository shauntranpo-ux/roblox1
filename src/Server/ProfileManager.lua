-- ProfileManager: server-only wrapper around ProfileStore (loleris' ProfileService
-- successor). Owns every player's session-locked saved data. The client is never
-- trusted and never sees this module.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(script.Parent.Lib.ProfileStore)
local Config = require(ReplicatedStorage.Shared.Config)

local ProfileManager = {}

-- Persisted fields. Plot assignment is session state and intentionally NOT saved. Cash is
-- a number and may hold fractions internally; only the display is floored.
-- Profile:Reconcile() (called on load) adds any new field to existing M1/M2 saves, so
-- UnlockedPads and Discovered appear on old profiles with these defaults -- no migration.
local PROFILE_TEMPLATE = {
    Cash = 0,
    OwnedBrainrots = {}, -- array of { Id, Type, IncomePerSec, PadIndex } (Type = Catalog Id)
    -- M3: how many pads this player may use. Defaults to the starting pad count so existing
    -- saves are unaffected. M5's pad gamepass raises this via ProfileManager.SetUnlockedPads.
    UnlockedPads = Config.Plots.PadsPerPlot,
    -- M3: set of roster Ids the player has ever owned (Id -> true). Cheap foundation for a
    -- later Index/collection UI; updated on every acquire.
    Discovered = {},
}

local Profiles = {} -- [Player] = Profile

local PlayerStore = nil
local usingMock = false

-- Detect whether real DataStores are usable. A live server always has access; in
-- Studio they only work when "Enable Studio Access to API Services" is on, so we
-- probe with a harmless read and fall back to ProfileStore's mock store if it throws.
local function dataStoresAvailable()
    if not RunService:IsStudio() then
        return true
    end
    local ok = pcall(function()
        DataStoreService:GetDataStore("__brainrot_probe"):GetAsync("__probe")
    end)
    return ok
end

function ProfileManager.Init()
    if PlayerStore ~= nil then
        return
    end

    PlayerStore = ProfileStore.New("PlayerData", PROFILE_TEMPLATE)

    usingMock = not dataStoresAvailable()
    if usingMock then
        PlayerStore = PlayerStore.Mock
        print(
            "[ProfileManager] DataStore API unavailable -> using MOCK store. Cash RESETS when you stop Play."
        )
    else
        print("[ProfileManager] Using REAL DataStore -> data will persist.")
    end
end

-- Loads a session-locked profile. Yields. Returns the Profile, or nil if the load
-- failed (player is kicked) or the player left mid-load.
function ProfileManager.LoadProfile(player)
    local profile = PlayerStore:StartSessionAsync("Player_" .. player.UserId, {
        Cancel = function()
            return player.Parent ~= Players
        end,
    })

    if profile == nil then
        -- Lock held by another session or the store is unreachable. Never let two
        -- servers write the same key -- kick instead.
        player:Kick("Could not load your saved data. Please rejoin.")
        return nil
    end

    profile:AddUserId(player.UserId) -- GDPR association
    profile:Reconcile() -- add any new template fields to old saves

    profile.OnSessionEnd:Connect(function()
        Profiles[player] = nil
        player:Kick("Your data session ended. Please rejoin.")
    end)

    if player.Parent ~= Players then
        -- Player left while we were loading; release the lock immediately.
        profile:EndSession()
        return nil
    end

    Profiles[player] = profile
    return profile
end

-- Releases the session lock so the player can safely rejoin elsewhere. Safe to call twice.
function ProfileManager.ReleaseProfile(player)
    local profile = Profiles[player]
    if profile ~= nil then
        profile:EndSession()
        Profiles[player] = nil
    end
end

function ProfileManager.GetProfile(player)
    return Profiles[player]
end

function ProfileManager.GetCash(player)
    local profile = Profiles[player]
    if profile ~= nil then
        return profile.Data.Cash
    end
    return 0
end

function ProfileManager.SetCash(player, amount)
    local profile = Profiles[player]
    if profile ~= nil then
        profile.Data.Cash = amount
    end
end

-- Returns the player's unlocked-pad count (saved). Falls back to the default when the
-- profile isn't loaded yet.
function ProfileManager.GetUnlockedPads(player)
    local profile = Profiles[player]
    if profile ~= nil then
        return profile.Data.UnlockedPads
    end
    return Config.Plots.PadsPerPlot
end

-- Sets the player's unlocked-pad count. THIS is the clean hook M5's pad gamepass will call.
-- Stores the raw value (>=1); the actual placement cap is min(this, physical pads) in the
-- free-pad check, so raising it beyond the current pad layout is harmless until more pads
-- physically exist. Returns the stored value, or nil if the profile isn't loaded.
function ProfileManager.SetUnlockedPads(player, count)
    local profile = Profiles[player]
    if profile == nil then
        return nil
    end
    profile.Data.UnlockedPads = math.max(1, math.floor(count))
    return profile.Data.UnlockedPads
end

function ProfileManager.IsUsingMock()
    return usingMock
end

return ProfileManager
