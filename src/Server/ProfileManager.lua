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
    -- M3/M5: how many pads this player may use. This is now a DERIVED cache that
    -- MonetizationService recomputes on join from DefaultUnlockedPads + PadProducts + any
    -- gamepass pad bonus, written via ProfileManager.SetUnlockedPads. Start at the default.
    UnlockedPads = Config.Plots.DefaultUnlockedPads,
    -- M5: permanently unlocked pads bought via DEVELOPER PRODUCTS (additive, receipt-deduped).
    -- The gamepass "Extra Pads" is session-derived from ownership and is NOT stored here.
    PadProducts = 0,
    -- M3: set of roster Ids the player has ever owned (Id -> true). Cheap foundation for a
    -- later Index/collection UI; updated on every acquire.
    Discovered = {},
    -- M5: idempotency ledger for developer-product receipts (PurchaseId -> true). The grant
    -- and this record are written in the SAME mutation so a purchase grants EXACTLY once, even
    -- across retries and server restarts. Never pruned (PurchaseIds are unique forever).
    PurchaseHistory = {},
    -- M6: one-time onboarding flag. Reconciles onto existing saves as false, so returning
    -- players never re-see the tutorial; brand-new players run it once (skippable).
    TutorialDone = false,
    -- M6: persisted client preferences (booleans only; SettingsService validates the shape).
    Settings = { Music = false, SFX = true, Shake = true },
    -- M7: set of NORMALIZED (trimmed+UPPER) code strings this player has redeemed (code -> true).
    -- A code's grant and its entry here are written in the SAME mutation, so a code grants
    -- EXACTLY once even across crashes/restarts/servers. Reconciles onto old saves as empty.
    RedeemedCodes = {},
    -- M7: a timed income BOOST from a code -- a multiplier active until an expiry timestamp.
    -- Re-applied on join only if still valid, expired cleanly server-side, never double-applied.
    BoostMultiplier = 1,
    BoostExpiry = 0, -- os.time() the boost ends (0 = none)
    -- M7: last GameInfo.Version this player saw the "What's New" card for (drives show-once).
    LastSeenVersion = "",
    -- M8.1 REBIRTH: how many times the player has prestiged, and the resulting PERMANENT prestige
    -- income multiplier (a SEPARATE multiplicative axis, outside the global cap; re-derived from
    -- the count on join). Reconcile onto old saves as 0 / 1.
    RebirthCount = 0,
    PrestigeMultiplier = 1,
    -- M8.1 INDEX: set of completion-milestone Ids already claimed (Id -> true). The grant + this
    -- record commit together so a completion reward is granted EXACTLY once. Reconciles as empty.
    ClaimedIndexRewards = {},
    -- M8.2 TRADING: capped per-player history of completed trades (partner + what was given/received
    -- + when), for support/disputes. Trimmed to TradeConfig.MaxHistory. Reconciles as empty.
    TradeHistory = {},
    -- M8.3 MUTATIONS: set of mutation Keys this player has ever owned (key -> true). Per-unit
    -- Mutation lives on each OwnedBrainrots record (legacy units reconcile as nil = Normal); this
    -- set reconciles as empty and is updated by the factory + on receiving a mutated unit.
    MutationsDiscovered = {},
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

-- ===========================================================================================
-- GUARDED CASH MUTATION -- the ONLY two functions that ever write Cash. Every cash change in
-- the game (income accrual, purchases, product grants) flows through these, so cash can never
-- go negative, never become NaN/inf, and never exceed a safe display range. Nothing here is
-- reachable by the client; deltas always originate from server-side sources (roster/config).
-- ===========================================================================================
local MAX_CASH = 1e15 -- below 2^53; keeps Cash in a safe, displayable, OrderedDataStore-safe range

-- Adds `delta` (income, grants; may be negative defensively) and clamps to [0, MAX_CASH].
-- Rejects non-finite deltas. Returns the new balance.
function ProfileManager.AddCash(player, delta)
    local profile = Profiles[player]
    if profile == nil then
        return 0
    end
    if type(delta) ~= "number" or delta ~= delta or delta == math.huge or delta == -math.huge then
        return profile.Data.Cash -- NaN / inf / non-number -> no-op
    end
    profile.Data.Cash = math.clamp(profile.Data.Cash + delta, 0, MAX_CASH)
    return profile.Data.Cash
end

-- Atomic spend: deducts `amount` ONLY if the player can afford it; never goes negative. No
-- yields between the check and the deduct, so it can't be raced. Returns true on success.
function ProfileManager.TrySpend(player, amount)
    local profile = Profiles[player]
    if profile == nil then
        return false
    end
    if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
        return false
    end
    if profile.Data.Cash < amount then
        return false
    end
    profile.Data.Cash -= amount
    return true
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

-- Requests an immediate save of the player's profile (best-effort, pcall-wrapped). Used after a
-- trade's in-memory swap so both profiles persist as close together as possible.
function ProfileManager.ForceSave(player)
    local profile = Profiles[player]
    if profile ~= nil then
        pcall(function()
            profile:Save()
        end)
    end
end

return ProfileManager
