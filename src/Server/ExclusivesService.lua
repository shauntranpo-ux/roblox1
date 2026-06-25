-- ExclusivesService (M11.4): grants + gates SEASONAL EXCLUSIVES. Extends the seasons + idempotent-
-- claim systems; it does NOT fork them. deliverExclusive is the SOLE authorized path that mints an
-- exclusive (passing allowExclusive=true to the factory after eligibility is validated); the factory
-- default-denies every other path.
--
-- ============================  SELF-AUDIT (exclusives path)  =================================
-- (a) EXCLUSIVITY SERVER-ENFORCED + PERMANENT-PER-WINDOW: availability derives PURELY from server
--     time (SeasonService.CurrentId(), identical on every server). In-window sources (shop/boss/catch)
--     check IsObtainable (currentSeasonId == the exclusive's SeasonId); track/ranked are gated by the
--     per-season FROZEN eligibility (score/rank from the frozen store) + the per-key claim set. The
--     BRAINROT FACTORY default-denies any ExclusiveSeason species unless deliverExclusive authorizes
--     it -> NO path (shop/catch/hatch/fusion/boss/trade-as-new-grant) can mint an expired exclusive.
-- (b) OWNERSHIP PERMANENT: an exclusive is a normal owned unit / a profile cosmetic flag -> kept
--     forever after the season ends; nothing confiscates it.
-- (c) IDEMPOTENT + ATOMIC: deliverExclusive dedupes via profile.Data.ClaimedExclusives[Key]; the grant
--     + the record commit with NO yields between (factory mint / cosmetic flag, then the record), so a
--     reward is granted EXACTLY once across servers/restarts/logins. NO-PAD: a unit reward with no free
--     pad is NOT recorded -> retries next join; never duped/lost. The client sends INTENT only.
-- (d) TIME SERVER-AUTHORITATIVE: windows are server-time, cross-server-consistent; a SIM-only dev
--     force window exists for testing and is refused in production (DevConfig.SimMode).
-- (e) FORWARD-COMPAT: boss/catch sources gate on IsObtainable when those systems exist; absent, the
--     exclusive simply isn't grantable that way -- no error.
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ExclusivesConfig = require(ReplicatedStorage.Shared.ExclusivesConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local ProfileManager = require(script.Parent.ProfileManager)
local SeasonService = require(script.Parent.SeasonService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local BrainrotService = require(script.Parent.BrainrotService)
local PlotService = require(script.Parent.PlotService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local DevConfig = require(script.Parent.DevConfig)
local Analytics = require(script.Parent.Analytics)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)

local ExclusivesService = {}

local forcedSeasonId = nil -- SIM-only override (dev testing); nil in production
local lastSeenSeason = nil

local function currentSeasonId()
    return forcedSeasonId or SeasonService.CurrentId()
end

-- True if an in-window exclusive (shop/boss/catch) is currently obtainable (its season window is open
-- by server time). Track/ranked exclusives are NOT obtained this way -- they are earned + claimed.
function ExclusivesService.IsObtainable(ex)
    if ex == nil or not ExclusivesConfig.IsInWindowSource(ex.Source) then
        return false
    end
    return currentSeasonId() == ex.SeasonId
end

-- THE sole authorized exclusive-minting path. Idempotent (per-Key claim set) + no-pad-safe. Returns
-- true if owned/granted, false if it couldn't be delivered (no free pad -> not recorded; retries).
local function deliverExclusive(player, profile, ex)
    if profile.Data.ClaimedExclusives[ex.Key] then
        return true -- already owned (idempotent)
    end

    if ex.Kind == "Cosmetic" then
        -- ===== COMMIT: grant + record, no yields. Cosmetics need no pad -> always deliverable. =====
        profile.Data.OwnedCosmetics[ex.CosmeticId] = true
        profile.Data.ClaimedExclusives[ex.Key] = true
        -- ==========================================================================================
        Remotes.NotifyPlayer(
            player,
            "success",
            "Unlocked exclusive cosmetic: " .. ex.DisplayName .. "!",
            "buy"
        )
    else
        local species = ex.Kind == "Mutation" and ex.CarrierSpecies or ex.Species
        local def = Catalog.Get(species)
        if def == nil then
            return false
        end
        local plot = PlotService.GetPlot(player)
        if plot == nil then
            return false
        end
        local pad = PlotService.FindFreePad(player, profile)
        if pad == nil then
            return false -- NO-PAD: not recorded -> retries next join (never duped/lost)
        end
        -- Authorized exclusive mint (allowExclusive=true; the caller validated eligibility/window).
        local unit = BrainrotFactory.create(player, def, pad, false, true)
        if unit == nil then
            return false -- defensive (factory refused) -> not recorded
        end
        if ex.Kind == "Mutation" then
            unit.Mutation = ex.Mutation -- exclusive mutation granted directly (never rolled)
        end
        -- ===== COMMIT: insert + record, no yields. =====
        table.insert(profile.Data.OwnedBrainrots, unit)
        profile.Data.Discovered[def.Id] = true
        if unit.Mutation ~= nil then
            profile.Data.MutationsDiscovered[unit.Mutation] = true
        end
        profile.Data.ClaimedExclusives[ex.Key] = true
        -- ===============================================
        BrainrotService.SpawnBrainrot(player, plot, unit)
        PlayerStats.UpdateIncome(player, profile)
        Remotes.NotifyPlayer(
            player,
            "success",
            "Unlocked SEASON EXCLUSIVE: " .. ex.DisplayName .. "!",
            "buy"
        )
    end

    PlayerStats.PushCash(player, profile)
    Leaderstats.Update(player, profile)
    Analytics.custom(player, Analytics.Events.ExclusiveGrant, 1)
    ProfileManager.ForceSave(player)
    return true
end

-- Called by SeasonRewardService at season-claim time: grant any track/ranked exclusive the player
-- EARNED in a frozen season (score/rank read from the frozen store), deduped per Key.
function ExclusivesService.GrantSeasonExclusives(player, profile, seasonId, score, rank)
    for _, ex in ipairs(ExclusivesConfig.ForSeason(seasonId)) do
        if
            (ex.Source == "track" or ex.Source == "ranked")
            and not profile.Data.ClaimedExclusives[ex.Key]
        then
            local trackOk = ex.Source == "track"
                and type(ex.TrackScore) == "number"
                and score >= ex.TrackScore
            local rankedOk = ex.Source == "ranked"
                and rank ~= nil
                and type(ex.RankMax) == "number"
                and rank <= ex.RankMax
            if trackOk or rankedOk then
                deliverExclusive(player, profile, ex)
            end
        end
    end
end

-- Cheap pre-check so SeasonRewardService only does the (yielding) frozen-store read when there's
-- actually an unclaimed track/ranked exclusive for that season.
function ExclusivesService.HasUnclaimedFor(profile, seasonId)
    for _, ex in ipairs(ExclusivesConfig.ForSeason(seasonId)) do
        if
            (ex.Source == "track" or ex.Source == "ranked")
            and not profile.Data.ClaimedExclusives[ex.Key]
        then
            return true
        end
    end
    return false
end

-- In-window SHOP purchase with EARNED cash (server-validated). No Robux, no randomness.
function ExclusivesService.Buy(player, key)
    if not RateLimiter.check(player, "exclbuy", 0.5) then
        return { Result = "Error", Message = "Slow down." }
    end
    if type(key) ~= "string" or #key == 0 or #key > 80 then
        return { Result = "Error", Message = "Invalid request." }
    end
    local ex = ExclusivesConfig.Get(key)
    if ex == nil or ex.Source ~= "shop" then
        return { Result = "Error", Message = "Not a shop exclusive." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    if profile.Data.ClaimedExclusives[key] then
        return { Result = "Error", Message = "You already own that." }
    end
    if not ExclusivesService.IsObtainable(ex) then
        return { Result = "Error", Message = "That exclusive isn't available this season." }
    end
    -- Pre-check a free pad for unit exclusives so TrySpend can't take cash then fail to deliver.
    if ex.Kind ~= "Cosmetic" and PlotService.FindFreePad(player, profile) == nil then
        return { Result = "Error", Message = "Free a pad first, then buy." }
    end
    local price = ex.Price or 0
    if price > 0 and not ProfileManager.TrySpend(player, price) then
        return { Result = "Error", Message = "You can't afford it ($" .. price .. ")." }
    end
    deliverExclusive(player, profile, ex)
    return { Result = "Success", Message = "Unlocked " .. ex.DisplayName .. "!" }
end

-- State the Exclusives UI renders from (current-season exclusives + the full owned/missed list).
function ExclusivesService.GetState(player)
    local profile = ProfileManager.GetProfile(player)
    local owned = {}
    local cosmetics = {}
    if profile ~= nil then
        for k in pairs(profile.Data.ClaimedExclusives) do
            owned[k] = true
        end
        for c in pairs(profile.Data.OwnedCosmetics) do
            cosmetics[c] = true
        end
    end
    local seasonId = currentSeasonId()
    local current = {}
    for _, ex in ipairs(ExclusivesConfig.ForSeason(seasonId)) do
        table.insert(current, {
            Key = ex.Key,
            Kind = ex.Kind,
            Source = ex.Source,
            DisplayName = ex.DisplayName,
            Price = ex.Price,
            TrackScore = ex.TrackScore,
            RankMax = ex.RankMax,
            Owned = owned[ex.Key] == true,
            Obtainable = ExclusivesService.IsObtainable(ex),
        })
    end
    local all = {}
    for _, ex in ipairs(ExclusivesConfig.Exclusives) do
        table.insert(all, {
            Key = ex.Key,
            Kind = ex.Kind,
            SeasonId = ex.SeasonId,
            DisplayName = ex.DisplayName,
            Owned = owned[ex.Key] == true,
        })
    end
    return { SeasonId = seasonId, Current = current, All = all, OwnedCosmetics = cosmetics }
end

function ExclusivesService.Init()
    Remotes.ExclusiveAction.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return { Result = "Error", Message = "Invalid request." }
        end
        if payload.Action == "get" then
            return { Result = "Success", State = ExclusivesService.GetState(player) }
        elseif payload.Action == "buy" then
            return ExclusivesService.Buy(player, payload.Key)
        end
        return { Result = "Error", Message = "Unknown action." }
    end

    -- Announce watcher: on a season change, ping clients + announce the live exclusives (reuses the
    -- existing toast/banner). Availability is derived live, so this is purely the FOMO heads-up.
    lastSeenSeason = SeasonService.CurrentId()
    task.spawn(function()
        while true do
            task.wait(30)
            local id = currentSeasonId()
            if id ~= lastSeenSeason then
                lastSeenSeason = id
                if #ExclusivesConfig.ForSeason(id) > 0 then
                    for _, p in ipairs(Players:GetPlayers()) do
                        Remotes.NotifyPlayer(
                            p,
                            "info",
                            "Season "
                                .. id
                                .. " exclusives are LIVE -- grab them before they're gone!"
                        )
                    end
                end
                if Remotes.SeasonsUpdate ~= nil then
                    Remotes.SeasonsUpdate:FireAllClients()
                end
            end
        end
    end)
end

-- ===========================================================================================
-- DEV/TEST hooks (SIM-only; refused in production so a live admin can't open windows / mint).
-- ===========================================================================================
function ExclusivesService.DevForceWindow(key)
    if not DevConfig.SimMode then
        return false, "SIM-only (force window is OFF in production)."
    end
    local ex = ExclusivesConfig.Get(key)
    if ex == nil then
        return false, "unknown exclusive key."
    end
    forcedSeasonId = ex.SeasonId
    return true,
        "forced window OPEN: season " .. ex.SeasonId .. " (in-window exclusives obtainable)."
end

function ExclusivesService.DevClearWindow()
    if not DevConfig.SimMode then
        return false, "SIM-only."
    end
    forcedSeasonId = nil
    return true, "forced window cleared (back to real server-time seasons)."
end

function ExclusivesService.DevGrant(player, key)
    if not DevConfig.SimMode then
        return false, "SIM-only."
    end
    local ex = ExclusivesConfig.Get(key)
    if ex == nil then
        return false, "unknown exclusive key."
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return false, "not ready."
    end
    local ok = deliverExclusive(player, profile, ex)
    return ok, ok and ("granted " .. ex.DisplayName .. ".") or "couldn't deliver (free a pad?)."
end

function ExclusivesService.ListKeys()
    local out = {}
    for _, ex in ipairs(ExclusivesConfig.Exclusives) do
        table.insert(
            out,
            ex.Key
                .. " ("
                .. ex.Kind
                .. "/"
                .. ex.Source
                .. "/S"
                .. ex.SeasonId
                .. (ExclusivesService.IsObtainable(ex) and "/OPEN" or "")
                .. ")"
        )
    end
    return out
end

return ExclusivesService
