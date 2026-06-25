-- Bootstrap: wires the M1 server-authoritative economy loop. Each service is a plain
-- module with an Init/Start function -- no heavy framework. This script owns the join
-- ordering so the profile is loaded before anything reads it.

local Players = game:GetService("Players")

local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local IncomeService = require(script.Parent.IncomeService)
local Leaderstats = require(script.Parent.Leaderstats)

print("[BRAINROT] M1 starting -- server-authoritative economy loop")

-- Start the data layer, build the world, and begin the income loop.
ProfileManager.Init()
PlotService.Init()
IncomeService.Start()

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

    -- 3) Cash readout + brainrot visuals (grants the starter for brand-new players).
    Leaderstats.Setup(player, profile)
    BrainrotService.SetupPlayer(player, profile, plot)

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
