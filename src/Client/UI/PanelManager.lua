-- PanelManager: the SINGLE client-side authority over which primary panel is open. Every primary
-- panel (Shop, Inventory, Menu, Seasons, Events, Trade, Rebirth, Index, Codes, Settings) registers
-- here. INVARIANT: at most ONE primary panel is open at any moment.
--
-- HOW IT ENFORCES THAT: each panel is still a ScreenGui that flips its own `.Enabled` (its existing
-- open/refresh/close logic is untouched). The manager OBSERVES every registered panel's `.Enabled`
-- and reacts: the instant one becomes enabled it disables whatever else was open, raises a single
-- shared scrim, and animates the panel in; when the open one disables, it drops the scrim. So even
-- a panel that opens itself (Trade auto-opening on an incoming request) is coordinated -- two panels
-- can never coexist, and there is only ever one close (X).
--
-- toggle(name) is what the HUD/Menu nav buttons call: open it if closed, close it if it's the open
-- one. The scrim (tap-off) and the Escape key both close the open panel. Rapid toggles are debounced
-- and in-flight open tweens are cancelled so spamming can't leave a panel half-open.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local UIStyle = require(script.Parent.UIStyle)

local PanelManager = {}

local SCRIM_ORDER = 5 -- scrim sits below panels (and below the HUD, which is raised above it)
local PANEL_ORDER = 10 -- every primary panel renders above the scrim
local DEBOUNCE = 0.12 -- s between accepted toggles
local OPEN_TIME = 0.2 -- s open animation

local panels = {} -- [name] = { gui, toggle, frame }
local listeners = {} -- active-panel-change subscribers (e.g. HUD highlight)
local current = nil -- name of the open panel, or nil
local lastToggle = 0
local scrimGui = nil
local scrim = nil
local openTween = nil

local function notify(activeName)
    for _, fn in ipairs(listeners) do
        task.spawn(fn, activeName)
    end
end

-- Subscribe to "which panel is open" changes (passed the panel name, or nil when nothing is open).
function PanelManager.onChange(fn)
    table.insert(listeners, fn)
end

local function showScrim()
    if scrimGui == nil then
        return
    end
    scrimGui.Enabled = true
    scrim.BackgroundTransparency = 1
    TweenService:Create(scrim, TweenInfo.new(0.18), {
        BackgroundTransparency = UIStyle.ScrimTransparency,
    }):Play()
end

local function hideScrim()
    if scrimGui == nil then
        return
    end
    local tween = TweenService:Create(scrim, TweenInfo.new(0.14), { BackgroundTransparency = 1 })
    tween:Play()
    tween.Completed:Once(function()
        if current == nil and scrimGui ~= nil then
            scrimGui.Enabled = false
        end
    end)
end

-- Quick scale 0.85 -> 1.0 pop (Back/Out) on the panel's main frame.
local function animateIn(frame)
    if frame == nil then
        return
    end
    local base = frame:GetAttribute("PMBaseSize")
    if base == nil then
        base = frame.Size
        frame:SetAttribute("PMBaseSize", base)
    end
    if openTween ~= nil then
        openTween:Cancel()
    end
    frame.Size = UDim2.new(base.X.Scale * 0.85, base.X.Offset, base.Y.Scale * 0.85, base.Y.Offset)
    openTween = TweenService:Create(
        frame,
        TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = base }
    )
    openTween:Play()
end

-- Reacts to ANY registered panel's Enabled flipping -- the single point that enforces the invariant.
local function onEnabledChanged(name)
    local entry = panels[name]
    if entry == nil then
        return
    end
    if entry.gui.Enabled then
        if current == name then
            return
        end
        local prev = current
        current = name -- set first so the prev's own change handler no-ops (won't drop the scrim)
        if prev ~= nil and panels[prev] ~= nil and panels[prev].gui.Enabled then
            panels[prev].gui.Enabled = false
        end
        showScrim()
        animateIn(entry.frame)
        notify(name)
    else
        if current == name then
            current = nil
            hideScrim()
            notify(nil)
        end
    end
end

-- Closes whatever is open (nothing if already closed).
function PanelManager.close()
    if current ~= nil and panels[current] ~= nil then
        panels[current].gui.Enabled = false
    end
end

-- The nav-button entry point: open `name` if closed, close it if it is the open one. Closing the
-- previous panel first is handled by onEnabledChanged, so this just flips the requested panel.
function PanelManager.toggle(name)
    local now = os.clock()
    if now - lastToggle < DEBOUNCE then
        return
    end
    lastToggle = now
    local entry = panels[name]
    if entry == nil then
        warn("[PanelManager] toggle unknown panel: " .. tostring(name))
        return
    end
    entry.toggle() -- the panel's own toggle flips .Enabled (+ runs its refresh on open)
end

-- Opens `name` (no-op if already open). Used by the Menu list entries, which close the Menu first;
-- not debounced so a fast tap-through (Menu -> sub-panel) can't be swallowed.
function PanelManager.open(name)
    local entry = panels[name]
    if entry == nil then
        warn("[PanelManager] open unknown panel: " .. tostring(name))
        return
    end
    if current == name then
        return
    end
    if not entry.gui.Enabled then
        entry.toggle()
    end
end

-- Registers a primary panel by the NAME of the ScreenGui it created (Builder.screenGui(name,...)),
-- and the panel's own toggle function. Applies the translucent glass look to the panel's main frame.
function PanelManager.register(name, toggleFn)
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local gui = playerGui:WaitForChild(name, 5)
    if gui == nil then
        warn("[PanelManager] no ScreenGui named '" .. name .. "' to register.")
        return
    end
    gui.DisplayOrder = PANEL_ORDER
    local frame = gui:FindFirstChildWhichIsA("Frame")
    if frame ~= nil then
        UIStyle.applyGlass(frame)
    end
    panels[name] = { gui = gui, toggle = toggleFn, frame = frame }
    gui:GetPropertyChangedSignal("Enabled"):Connect(function()
        onEnabledChanged(name)
    end)
    -- If the panel somehow starts enabled, coordinate it immediately.
    if gui.Enabled then
        onEnabledChanged(name)
    end
end

function PanelManager.init(context)
    local playerGui = context.player:WaitForChild("PlayerGui")

    scrimGui = Builder.screenGui("PanelScrim", playerGui, false)
    scrimGui.DisplayOrder = SCRIM_ORDER

    scrim = Instance.new("TextButton")
    scrim.Name = "Scrim"
    scrim.Size = UDim2.fromScale(1, 1)
    scrim.Position = UDim2.fromScale(0, 0)
    UIStyle.styleScrim(scrim)
    scrim.Parent = scrimGui
    scrim.Activated:Connect(PanelManager.close)

    -- Escape (or the console/back equivalent) closes the open panel.
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.KeyCode == Enum.KeyCode.Escape and current ~= nil then
            PanelManager.close()
        end
    end)
end

return PanelManager
