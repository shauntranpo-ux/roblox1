-- Bootstrap: wires the server-authoritative economy + M2 shop plumbing. Each service
-- is a plain module with an Init/Start function -- no framework. This script owns the
-- join ordering so the profile loads before anything reads it, and creates the Remotes
-- folder before clients connect.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameInfo = require(ReplicatedStorage.Shared.GameInfo)

local ProfileManager = require(script.Parent.ProfileManager)
local Remotes = require(script.Parent.Remotes)
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

print("[BRAINROT] M8.5 starting -- leaderboard seasons (the final milestone)")

-- Data layer, network surface, world, defense, income loop, then the client-facing handlers.
ProfileManager.Init()
Remotes.Init()
PlotService.Init()
ProtectionService.Init()
IncomeService.Start()
PurchaseService.Init()
InventoryService.Init()
StealService.Init()
-- M5: the Robux money path (single ProcessReceipt + gamepass ownership) and the global boards.
MonetizationService.Init()
LeaderboardService.Init()
LeaderboardBillboards.Init()
-- M6: client-preference persistence + the one-time onboarding handshake.
SettingsService.Init()
TutorialService.Init()
-- M7: redeemable codes (binds RedeemCode + starts the boost-expiry sweep).
CodesService.Init()
-- M8.1: rebirth/prestige + collection-index completion rewards.
RebirthService.Init()
IndexService.Init()
-- M8.2: same-server player-to-player trading.
TradeService.Init()
-- M8.4: the limited-time events scheduler/transition engine.
EventService.Init()
-- M8.5: competitive seasons + pull-based end-of-season reward claims.
SeasonService.Init()
SeasonRewardService.Init()

local handled = {} -- [Player] = true, guards against double-joins (Studio Play Solo)

local function onCharacterAdded(player)
    PlotService.MovePlayerToPlot(player)
end

local function onPlayerAdded(player)
    if handled[player] then
        return
    end
    handled[player] = true

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
    -- M8.4: apply any currently-active event modifiers (idempotent) + prune stale event data.
    EventService.SetupPlayer(player, profile)
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
