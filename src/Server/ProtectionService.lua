-- ProtectionService: the simple, timer-based defense layer (v1). A plot is "protected" for
-- a window of time; while protected, its brainrots' steal prompts are disabled and the
-- server rejects steals against it. Two windows grant protection automatically -- a
-- new-player grace on first spawn and a post-robbery window after a player is robbed -- and
-- ExtendProtection is a public hook M5's gamepass can call for a longer/stronger lock.
--
-- Defense is intentionally NOT a destructible-HP wall this milestone; that ("lock HP" you
-- grind down) is a possible later option, not built here. Everything is data/timer-driven so
-- windows can be retuned in StealConfig without touching steal logic.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StealConfig = require(ReplicatedStorage.Shared.StealConfig)

local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)

local ProtectionService = {}

local protection = {} -- [Player] = { Until = clock, Dome = Part, Label = TextLabel }
local UPDATE_INTERVAL = 0.25
local accum = 0

-- True while the player's plot is protected (steals must be rejected).
function ProtectionService.IsProtected(player)
    local state = protection[player]
    return state ~= nil and os.clock() < state.Until
end

-- Re-applies prompt enable/disable for a player's units based on current protection. Called
-- by ProtectionService itself on every change, and by spawners after they place a new unit.
function ProtectionService.RefreshPrompts(player)
    BrainrotService.SetPromptsEnabled(player, not ProtectionService.IsProtected(player))
end

-- Builds (once) the translucent dome + countdown billboard over a player's plot.
local function ensureVisuals(player)
    local state = protection[player]
    if state == nil or state.Dome ~= nil then
        return
    end
    local plot = PlotService.GetPlot(player)
    if plot == nil then
        return
    end

    local dome = Instance.new("Part")
    dome.Name = "ProtectionDome"
    dome.Shape = Enum.PartType.Ball
    dome.Anchored = true
    dome.CanCollide = false
    dome.CanQuery = false
    dome.CastShadow = false
    dome.Material = Enum.Material.ForceField
    dome.Color = Color3.fromRGB(95, 170, 255)
    dome.Transparency = 0.55
    dome.Size = Vector3.new(46, 46, 46)
    dome.CFrame = plot.Origin * CFrame.new(0, 6, 0)
    dome.Parent = plot.Model

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Countdown"
    billboard.Size = UDim2.fromScale(6, 1.4)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 16, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = dome
    billboard.Parent = dome

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(170, 210, 255)
    label.TextStrokeTransparency = 0.3
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Text = "Protected"
    label.Parent = billboard

    state.Dome = dome
    state.Label = label
end

-- Removes a player's protection visuals and re-enables their steal prompts.
local function expire(player)
    local state = protection[player]
    if state == nil then
        return
    end
    if state.Dome ~= nil then
        state.Dome:Destroy()
    end
    protection[player] = nil
    ProtectionService.RefreshPrompts(player)
end

-- Core grant: raises a player's protection to AT LEAST untilClock (never shortens it).
local function grantUntil(player, untilClock)
    local state = protection[player]
    if state == nil then
        state = { Until = untilClock }
        protection[player] = state
    else
        state.Until = math.max(state.Until, untilClock)
    end
    ensureVisuals(player)
    ProtectionService.RefreshPrompts(player)
end

-- New-player grace, granted when a player first spawns in this session.
function ProtectionService.GrantGrace(player)
    grantUntil(player, os.clock() + StealConfig.NewPlayerGrace)
end

-- Post-robbery window, granted to a victim right after they're successfully robbed.
function ProtectionService.GrantPostRobbery(player)
    grantUntil(player, os.clock() + StealConfig.PostRobberyProtection)
end

-- PUBLIC HOOK for M5: extend (stack onto) a plot's protection by `seconds`. A gamepass
-- "stronger lock" / "longer shield" will call this. Adds to whatever time remains.
function ProtectionService.ExtendProtection(player, seconds)
    local base = math.max(os.clock(), protection[player] and protection[player].Until or 0)
    grantUntil(player, base + seconds)
end

-- PUBLIC HOOK for M5: ensure protection lasts AT LEAST `seconds` from now (never shortens it).
-- Unlike ExtendProtection this does not accumulate, so the "Reinforced Lock" gamepass can keep
-- a steady shield on a renew tick without the timer creeping ever upward.
function ProtectionService.MaintainAtLeast(player, seconds)
    grantUntil(player, os.clock() + seconds)
end

-- Clears protection + visuals for a leaving player (called from Bootstrap before release).
function ProtectionService.ClearPlayer(player)
    local state = protection[player]
    if state ~= nil then
        if state.Dome ~= nil then
            state.Dome:Destroy()
        end
        protection[player] = nil
    end
end

function ProtectionService.Init()
    RunService.Heartbeat:Connect(function(deltaTime)
        accum += deltaTime
        if accum < UPDATE_INTERVAL then
            return
        end
        accum = 0

        local now = os.clock()
        for player, state in pairs(protection) do
            if player.Parent ~= Players or now >= state.Until then
                expire(player)
            elseif state.Label ~= nil then
                state.Label.Text = "Protected " .. tostring(math.ceil(state.Until - now)) .. "s"
            end
        end
    end)
end

return ProtectionService
