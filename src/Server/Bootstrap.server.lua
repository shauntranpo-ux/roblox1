-- Bootstrap: wires the server-authoritative economy + M2 shop plumbing. Each service
-- is a plain module with an Init/Start function -- no framework. This script owns the
-- join ordering so the profile loads before anything reads it, and creates the Remotes
-- folder before clients connect.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameInfo = require(ReplicatedStorage.Shared.GameInfo)

local ProfileManager = require(script.Parent.ProfileManager)
local Remotes = require(script.Parent.Remotes)
-- VM6: procedurally generates + tags the world (runs FIRST so PlotService clones the plot template).
local WorldBuilder = require(script.Parent.WorldBuilder)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local IncomeService = require(script.Parent.IncomeService)
local Leaderstats = require(script.Parent.Leaderstats)
local PlayerStats = require(script.Parent.PlayerStats)
local PurchaseService = require(script.Parent.PurchaseService)
local InventoryService = require(script.Parent.InventoryService)
local ProtectionService = require(script.Parent.ProtectionService)
local StealService = require(script.Parent.StealService)
local MonetizationService = require(script.Parent.MonetizationService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local LeaderboardBillboards = require(script.Parent.LeaderboardBillboards)
local SettingsService = require(script.Parent.SettingsService)
local TutorialService = require(script.Parent.TutorialService)
local RateLimiter = require(script.Parent.RateLimiter)
local CodesService = require(script.Parent.CodesService)
local Analytics = require(script.Parent.Analytics)
local RebirthService = require(script.Parent.RebirthService)
local IndexService = require(script.Parent.IndexService)
local TradeService = require(script.Parent.TradeService)
local EventService = require(script.Parent.EventService)
local SeasonService = require(script.Parent.SeasonService)
local SeasonRewardService = require(script.Parent.SeasonRewardService)
-- M11.4: seasonal exclusives (gating + grants atop the seasons/claim systems).
local ExclusivesService = require(script.Parent.ExclusivesService)
-- M10.4: net tool -- catch-param bonuses + upgrade cash sink (required before the catch services).
local NetService = require(script.Parent.NetService)
-- M10.2: biome zones + per-biome rarity routing + unlock gates (required before WildSpawnService).
local BiomeService = require(script.Parent.BiomeService)
-- M10.1: wild-catch spawn engine + catch mechanic (the acquisition pivot).
local WildSpawnService = require(script.Parent.WildSpawnService)
-- M10.3: shared server-wide rare-event spawns (the hype layer).
local SharedEventService = require(script.Parent.SharedEventService)
-- M12.1: tutorial + quests (observes gameplay signals; binds GetQuests/ClaimQuest).
local QuestService = require(script.Parent.QuestService)
-- M12.2: free rewards (daily chest / gift / spin / mystery block; server-time-gated).
local FreeRewardService = require(script.Parent.FreeRewardService)
-- M13.1: referral / invite system (server-authoritative attribution + milestone-gated rewards).
local ReferralService = require(script.Parent.ReferralService)
-- M13.3: friends & social play (gifting via the trade transfer + VIP/private-server perks).
local SocialService = require(script.Parent.SocialService)
-- M9.1: selling (the economy floor sink).
local SellService = require(script.Parent.SellService)
-- M9.2: fusion + stars (turn duplicates into fuel).
local FusionService = require(script.Parent.FusionService)
-- M11.1: signature perks + loadout (units become an equippable arsenal; replaces M9.3 roles).
local LoadoutService = require(script.Parent.LoadoutService)
-- M11.2: per-unit XP + evolution (raise units through stages).
local EvolutionService = require(script.Parent.EvolutionService)
-- M11.3: world-boss co-op hunts (ephemeral server-wide scramble + dupe-safe per-player rewards).
local BossService = require(script.Parent.BossService)
-- M9.4: set perks (themed Index sets -> permanent passive perks).
local SetService = require(script.Parent.SetService)
-- VM0: boot/join health check + the dev-only sacred-invariant validator.
local Diagnostics = require(script.Parent.Diagnostics)
local InvariantValidator = require(script.Parent.InvariantValidator)
-- M13.4: admin + moderation. BanStore is the persistent global ban list; AdminService is the ONE
-- server-authoritative command system (allowlist-gated) + the report flow + ban enforcement + the
-- filtered-name publisher. DevCommands (below) now delegates its authority to the same AdminConfig.
local BanStore = require(script.Parent.BanStore)
local AdminService = require(script.Parent.AdminService)
-- M13.6: the Roblox group hook (idempotent member reward / capped live perk) + the re-engagement
-- notification trigger layer (opt-in is a persisted setting; delivery is backend).
local GroupRewardService = require(script.Parent.GroupRewardService)
local NotificationService = require(script.Parent.NotificationService)
local SlingshotService = require(script.Parent.SlingshotService)
-- Admin/troubleshooting: in-chat commands (allowlisted) + Studio command-bar API.
local DevCommands = require(script.Parent.DevCommands)

print("[BRAINROT] starting up...")

-- VM0 RESILIENCE: start each service inside a pcall so ONE service that throws on Init can't halt
-- the whole boot (which would leave later remotes unbound + PlayerAdded never connected). Every
-- result is recorded; Diagnostics.bootReport prints exactly which started and which failed.
local serviceResults = {}
local function start(name, fn)
    local ok, err = pcall(fn)
    table.insert(serviceResults, { Name = name, Ok = ok, Err = err })
    if not ok then
        warn(string.format("[Bootstrap] %s failed to start: %s", name, tostring(err)))
    end
end

-- Data layer, network surface, world, defense, income loop, then the client-facing handlers.
start("ProfileManager", ProfileManager.Init)
start("Remotes", Remotes.Init)
-- M13.4: open the global ban DataStore (or its MOCK) before anyone can join + be checked.
start("BanStore", BanStore.Init)
-- VM6: generate the voxel world + the plot template BEFORE PlotService builds/assigns plots.
start("WorldBuilder", WorldBuilder.Init)
start("PlotService", PlotService.Init)
start("ProtectionService", ProtectionService.Init)
start("IncomeService", IncomeService.Start)
start("PurchaseService", PurchaseService.Init)
start("InventoryService", InventoryService.Init)
start("StealService", StealService.Init)
-- M5: the Robux money path (single ProcessReceipt + gamepass ownership) and the global boards.
start("MonetizationService", MonetizationService.Init)
start("LeaderboardService", LeaderboardService.Init)
start("LeaderboardBillboards", LeaderboardBillboards.Init)
-- M6: client-preference persistence + the one-time onboarding handshake.
start("SettingsService", SettingsService.Init)
start("TutorialService", TutorialService.Init)
-- M7: redeemable codes (binds RedeemCode + starts the boost-expiry sweep).
start("CodesService", CodesService.Init)
-- M8.1: rebirth/prestige + collection-index completion rewards.
start("RebirthService", RebirthService.Init)
start("IndexService", IndexService.Init)
-- M8.2: same-server player-to-player trading.
start("TradeService", TradeService.Init)
-- M8.4: the limited-time events scheduler/transition engine.
start("EventService", EventService.Init)
-- M8.5: competitive seasons + pull-based end-of-season reward claims.
start("SeasonService", SeasonService.Init)
start("SeasonRewardService", SeasonRewardService.Init)
-- M11.4: bind the exclusives remote + the season-change announce watcher.
start("ExclusivesService", ExclusivesService.Init)
-- M10.4: bind the net upgrade remote.
start("NetService", NetService.Init)
-- M10.2: biome detection loop + unlock handler (server-authoritative zones; before spawning).
start("BiomeService", BiomeService.Init)
-- M10.1: wild-catch spawn loop + catch handler (server-authoritative registry).
start("WildSpawnService", WildSpawnService.Init)
-- M10.3: shared rare-event spawn loop + first-to-catch resolution.
start("SharedEventService", SharedEventService.Init)
-- M12.1: subscribe quests to GameSignals + bind the quest remotes.
start("QuestService", QuestService.Init)
-- M12.2: bind the free-reward remotes + the mystery-block prompts.
start("FreeRewardService", FreeRewardService.Init)
-- M13.1: init the referral mailbox + bind the milestone check loop + the referral remote.
start("ReferralService", ReferralService.Init)
-- M13.3: detect a private/VIP server + bind the social (gift) remote.
start("SocialService", SocialService.Init)
-- M9.1: the sell sink (binds SellRequest).
start("SellService", SellService.Init)
-- M9.2: fusion + stars (binds FuseRequest).
start("FusionService", FusionService.Init)
-- M11.1: signature perks + loadout (binds LoadoutRequest).
start("LoadoutService", LoadoutService.Init)
-- M11.2: XP accrual loop + evolve handler (binds EvolveRequest).
start("EvolutionService", EvolutionService.Init)
-- M11.3: world-boss spawn loop + validated catch handler (server-authoritative).
start("BossService", BossService.Init)
-- M9.4: set perks (binds ClaimSetPerk).
start("SetService", SetService.Init)
-- M13.4: bind the admin panel + report remotes + the server-side chat-mute gate.
start("AdminService", AdminService.Init)
-- M13.6: bind the group-reward remote (membership check + idempotent claim).
start("GroupRewardService", GroupRewardService.Init)
start("SlingshotService", SlingshotService.Init)
-- Admin: register the allowlisted in-chat commands (hidden from chat).
start("DevCommands", DevCommands.Init)

-- VM0: print the boot health report (services started/failed, remote surface, REAL vs MOCK stores,
-- SIM flag) and arm the dev-only invariant validator.
Diagnostics.bootReport(serviceResults)
InvariantValidator.Init()

local handled = {} -- [Player] = true, guards against double-joins (Studio Play Solo)

local function onCharacterAdded(player)
    PlotService.MovePlayerToPlot(player)
end

local function onPlayerAdded(player)
    if handled[player] then
        return
    end
    handled[player] = true

    -- M13.4: enforce BANS here, BEFORE any plot claim or profile load. A banned user is kicked with the
    -- reason and we return -- their save is never opened, so a ban can never corrupt their data. The ban
    -- store is global, so this enforces across every server; timed bans auto-expire (BanStore.GetBan).
    if AdminService.EnforceBan(player) then
        handled[player] = nil
        return
    end

    -- 1) Claim a base first (no yield) so the character has somewhere to spawn.
    local plot = PlotService.AssignPlot(player)
    if plot == nil then
        player:Kick("All bases are currently full. Please try again shortly.")
        handled[player] = nil
        return
    end

    -- 2) Load saved data (yields). On failure the player is already kicked.
    local profile = ProfileManager.LoadProfile(player)
    if profile == nil then
        PlotService.FreePlot(player)
        return
    end

    -- VM0: log this join's health (profile loaded? every template field present? store mode?).
    Diagnostics.playerReport(player, profile)

    -- M7 analytics: session start + the onboarding funnel's first step (new players only).
    Analytics.custom(player, Analytics.Events.SessionStart)
    if not profile.Data.TutorialDone then
        Analytics.funnelStepOnce(player, Analytics.Funnel.Spawn)
    end

    -- 3) Cash readout + brainrot visuals (grants the starter for brand-new players),
    --    then publish the replicated HUD attributes (after the starter is granted so
    --    the initial IncomePerSec is correct).
    Leaderstats.Setup(player, profile)
    BrainrotService.SetupPlayer(player, profile, plot)
    PlayerStats.Setup(player, profile)
    if not profile.Data.TutorialDone then
        Analytics.funnelStepOnce(player, Analytics.Funnel.SawStarter)
    end

    -- New-player grace: protect the base on spawn (raises the dome + disables the steal
    -- prompts on their units until the grace window expires).
    ProtectionService.GrantGrace(player)

    -- M5: verify gamepass ownership (yields) + apply owned benefits + recompute pads, then
    -- seed this player's leaderboard entries. Runs after the roster exists so income/pads are
    -- correct. Benefit application is idempotent (safe on every join).
    MonetizationService.SetupPlayer(player, profile)
    LeaderboardService.UpdatePlayer(player)

    -- M7: re-apply a still-valid timed code boost (or clean up an expired one), then show the
    -- "What's New" card once per version bump (drives return visits + announces new codes).
    CodesService.SetupPlayer(player, profile)
    -- M8.1: re-derive prestige multiplier + attributes, and re-apply claimed completion
    -- multiplier sources (both idempotent) so income reflects them on join.
    RebirthService.SetupPlayer(player, profile)
    IndexService.SetupPlayer(player, profile)
    -- M9.4: re-apply permanent set perks (income/luck sources) from claimed sets (idempotent; keyed).
    SetService.SetupPlayer(player, profile)
    -- M10.2: ensure the starter biome is unlocked (idempotent) before wild spawns route by biome.
    BiomeService.SetupPlayer(player, profile)
    -- M10.4: reconcile the player's net tier to the base tier (existing saves default cleanly).
    NetService.SetupPlayer(player, profile)
    -- M12.1: reset stale daily/weekly periods, sync reached-quests, publish the objective banner.
    QuestService.SetupPlayer(player, profile)
    -- M12.2: seed starter spins on first contact + accrue banked spins from server time.
    FreeRewardService.SetupPlayer(player, profile)
    -- M13.1: attribute the referrer (new accounts only, once ever) + welcome bonus + apply the capped
    -- invite boost from the credited set + drain the inviter mailbox (off-thread). Runs after PlayerStats
    -- + Benefits exist so the boost feeds income correctly on join.
    ReferralService.SetupPlayer(player, profile)
    -- M13.3: reset the daily gift cap + apply the capped VIP perk if this is a private/VIP server.
    SocialService.SetupPlayer(player, profile)
    -- M13.4: publish this player's filtered SafeName (every name display reads it) + their OWN admin
    -- tier attribute (so the client knows whether to surface the admin panel; the allowlist stays server-only).
    AdminService.SetupPlayer(player)
    -- M13.6: check group membership (server-side) -> apply the capped live perk + auto-grant the
    -- one-time member reward if eligible + unclaimed (idempotent). Yields on IsInGroup; safe here.
    GroupRewardService.SetupPlayer(player, profile)
    -- M8.4: apply any currently-active event modifiers (idempotent) + prune stale event data.
    EventService.SetupPlayer(player, profile)
    -- M11.1: re-derive equipped perks + re-lock equipped units from the saved loadout (idempotent;
    -- runs after units + Benefits exist so income/luck reflect perk sources on join). Also grants any
    -- Cold Storage offline earnings.
    LoadoutService.SetupPlayer(player, profile)
    -- M8.5: ensure the season-score record is for the current season, then (off-thread, since it
    -- reads DataStores) grant any unclaimed end-of-season rewards from frozen seasons.
    SeasonService.SetupPlayer(player, profile)
    task.spawn(SeasonRewardService.CheckPlayer, player)
    if profile.Data.LastSeenVersion ~= GameInfo.Version then
        profile.Data.LastSeenVersion = GameInfo.Version
        Remotes.FireWhatsNew(player)
    end

    -- 4) Place the character on the base now and on every respawn.
    player.CharacterAdded:Connect(function()
        onCharacterAdded(player)
    end)
    if player.Character ~= nil then
        task.spawn(onCharacterAdded, player)
    end
end

local function onPlayerRemoving(player)
    handled[player] = nil
    -- ORDERING IS CRITICAL: settle every steal this player is in (as thief OR victim) FIRST,
    -- while their profile is still loaded, so the save captures correct, un-duped ownership.
    StealService.ResolvePlayer(player)
    -- M8.2: cancel any in-flight trade (no-op, unlock items) BEFORE the profile is released, so a
    -- leave mid-trade can never persist a half-swap.
    TradeService.ResolvePlayer(player)
    -- M11.1: release equip locks + perk effects while the profile is still loaded, and stamp
    -- LastLeaveTime (Cold Storage). The saved loadout persists; perks re-derive on rejoin. Benefits
    -- perk sources are wiped below.
    LoadoutService.ClearPlayer(player)
    -- M11.3: drop this player from any live boss's contribution map (no stale ref; they won't be
    -- granted a reward they can't receive). The boss is ephemeral + server-memory only.
    BossService.ClearPlayer(player)
    -- M10.1: drop this player's wild spawns from the registry (ephemeral, server-memory only).
    WildSpawnService.ClearPlayer(player)
    -- M10.2: drop the player's cached current-biome (state persists in the profile).
    BiomeService.ClearPlayer(player)
    -- M13.1: drop the player's session join-time (referral state persists in the profile/mailbox).
    ReferralService.ClearPlayer(player)
    -- Final leaderboard write while the profile is STILL loaded (captures values synchronously,
    -- then writes off-thread) -- must precede MonetizationService.ClearPlayer, which drops the
    -- income multiplier this read depends on, and ProfileManager.ReleaseProfile.
    LeaderboardService.OnPlayerRemoving(player)
    -- M8.5: final season-score write while the profile is still loaded.
    SeasonService.OnPlayerRemoving(player)
    SeasonRewardService.ClearPlayer(player)
    -- M7: flush this player's aggregated income as a final economy-source event while the
    -- profile is still loaded, then drop their analytics session guards.
    IncomeService.FlushAnalytics(player)
    Analytics.clearPlayer(player)
    ProtectionService.ClearPlayer(player)
    MonetizationService.ClearPlayer(player)
    BrainrotService.ClearPlayer(player)
    -- M6 cleanup: drop the cached income rate + per-player rate-limit timestamps so nothing
    -- lingers after leave (verified leak-free across repeated join/leave cycles).
    PlayerStats.ClearPlayer(player)
    RebirthService.ClearPlayer(player)
    TradeService.ClearPlayer(player)
    PlotService.FreePlot(player)
    RateLimiter.clear(player)
    -- M13.4: drop the player's session mute + report counter (a BAN is what persists, in the store).
    AdminService.ClearPlayer(player)
    -- M13.6: drop the player's notification frequency-cap bookkeeping (the group perk is in Benefits,
    -- already wiped by MonetizationService.ClearPlayer above).
    NotificationService.ClearPlayer(player)
    ProfileManager.ReleaseProfile(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle anyone who joined before this script ran (common in Studio Play Solo).
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

-- Graceful shutdown (server restart / BindToClose): settle every in-flight steal so no unit is
-- duped/lost, flush the latest leaderboard values, then release every profile so ProfileStore
-- saves cleanly. All best-effort + pcall-wrapped so one failure can't block the shutdown.
game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        pcall(StealService.ResolvePlayer, player)
    end
    pcall(LeaderboardService.FlushAll)
    pcall(SeasonService.FlushAll)
    for _, player in ipairs(Players:GetPlayers()) do
        pcall(ProfileManager.ReleaseProfile, player)
    end
end)
