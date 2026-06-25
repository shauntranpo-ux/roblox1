-- Bootstrap: wires the server-authoritative economy + M2 shop plumbing. Each service
-- is a plain module with an Init/Start function -- no framework. This script owns the
-- join ordering so the profile loads before anything reads it, and creates the Remotes
-- folder before clients connect.

local Players = game:GetService("Players")

local ProfileManager = require(script.Parent.ProfileManager)
local Remotes = require(script.Parent.Remotes)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local IncomeService = require(script.Parent.IncomeService)
local Leaderstats = require(script.Parent.Leaderstats)
local PlayerStats = require(script.Parent.PlayerStats)
local PurchaseService = require(script.Parent.PurchaseService)
local InventoryService = require(script.Parent.InventoryService)

print("[BRAINROT] M3 starting -- rarity roster + scaling economy")

-- Data layer, network surface, world, income loop, then the client-facing handlers.
ProfileManager.Init()
Remotes.Init()
PlotService.Init()
IncomeService.Start()
PurchaseService.Init()
InventoryService.Init()

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

    -- 3) Cash readout + brainrot visuals (grants the starter for brand-new players),
    --    then publish the replicated HUD attributes (after the starter is granted so
    --    the initial IncomePerSec is correct).
    Leaderstats.Setup(player, profile)
    BrainrotService.SetupPlayer(player, profile, plot)
    PlayerStats.Setup(player, profile)

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
    BrainrotService.ClearPlayer(player)
    PlotService.FreePlot(player)
    ProfileManager.ReleaseProfile(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle anyone who joined before this script ran (common in Studio Play Solo).
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end
