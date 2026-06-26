-- PanelManager: the SINGLE client-side authority over which primary panel is open. Every primary
-- panel (Shop, Inventory, Menu, Seasons, Events, Trade, Rebirth, Index, Codes, Settings) registers
-- here. INVARIANT: at most ONE primary panel is open at any moment.
--
-- HOW IT ENFORCES THAT: each panel is still a ScreenGui that flips its own `.Enabled` (its existing
-- open/refresh/close logic is untouched). The manager OBSERVES every registered panel's `.Enabled`
-- and reacts: the instant one becomes enabled it disables whatever else was open and animates the
-- panel in. So even a panel that opens itself (Trade auto-opening on an incoming request) is
-- coordinated -- two panels can never coexist, and there is only ever one close (X).
--
-- NO BACKDROP: opening a panel does NOT dim the world or block input -- you can still drag the
-- camera and move your character with a panel open, and tapping off a panel does NOT close it.
-- Close via the panel's X, tapping its nav button again, or Escape. toggle(name) is what the
-- HUD/Menu nav buttons call: open if closed, close if it's the open one. Rapid toggles are
-- debounced and in-flight open tweens are cancelled so spamming can't leave a panel half-open.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local UIStyle = require(script.Parent.UIStyle)
local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)
local Builder = require(script.Parent.Builder)

local PanelManager = {}

local PANEL_ORDER = 10 -- every primary panel renders above the HUD
local DEBOUNCE = 0.12 -- s between accepted toggles

local panels = {} -- [name] = { gui, toggle, frame }
local listeners = {} -- active-panel-change subscribers (e.g. HUD highlight)
local current = nil -- name of the open panel, or nil
local lastToggle = 0
local openTween = nil
local closing = {} -- [name] = true while a pop-close tween is in flight (guard against double-fire)

local function notify(activeName)
    for _, fn in ipairs(listeners) do
        task.spawn(fn, activeName)
    end
end

-- Subscribe to "which panel is open" changes (passed the panel name, or nil when nothing is open).
function PanelManager.onChange(fn)
    table.insert(listeners, fn)
end

-- Pop-close a panel's gui: find its main frame, run Builder.popClose, then disable. Falls back to
-- instant disable if no frame is found or a close is already in flight for this panel.
local function disableWithPop(name)
    local entry = panels[name]
    if entry == nil then
        return
    end
    if closing[name] then
        return
    end
    local frame = entry.frame or entry.gui:FindFirstChildWhichIsA("Frame")
    if frame ~= nil then
        closing[name] = true
        Builder.popClose(frame, function()
            closing[name] = nil
            entry.gui.Enabled = false
        end)
    else
        entry.gui.Enabled = false
    end
end

-- Bouncy squash-and-stretch pop-in (overshoot Back/Out) + fade on the panel's main frame. Any in-flight
-- open tween is cancelled first so spamming toggles never leaves a panel stuck mid-tween.
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
    local k = Theme.Anim.OverShoot
    frame.Size = UDim2.new(base.X.Scale * k, base.X.Offset * k, base.Y.Scale * k, base.Y.Offset * k)
    openTween = TweenService:Create(frame, Theme.Tween.OpenBouncy, { Size = base })
    openTween:Play()

    -- Quick fade-in alongside the scale pop.
    local target = frame:GetAttribute("PMBaseTransparency")
    if target == nil then
        target = frame.BackgroundTransparency
        frame:SetAttribute("PMBaseTransparency", target)
    end
    frame.BackgroundTransparency = math.min(1, target + 0.3)
    TweenService:Create(frame, Theme.Tween.Fade, { BackgroundTransparency = target }):Play()
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
        current = name -- set first so the prev's own change handler no-ops
        if prev ~= nil and panels[prev] ~= nil and panels[prev].gui.Enabled then
            disableWithPop(prev)
        end
        animateIn(entry.frame)
        Effects.playSfx("open")
        notify(name)
    else
        if current == name then
            current = nil
            Effects.playSfx("close")
            notify(nil)
        end
    end
end

-- Closes whatever is open (nothing if already closed). Plays a pop-out before disabling.
function PanelManager.close()
    if current ~= nil and panels[current] ~= nil then
        disableWithPop(current)
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
        -- This panel's open/close animation is owned by the manager; tell Builder.panel to skip its
        -- own pop-open so there is no double animation. applyGlass is a no-op on Builder panels
        -- (already marked Glassed) and only styles any legacy non-Builder panel frame.
        frame:SetAttribute("PMManaged", true)
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

-- No backdrop is created: an open panel never dims the world or blocks input, so the camera and
-- character stay fully controllable and tapping off a panel does not close it.
function PanelManager.init(_context)
    -- Escape (PC/console) closes the open panel -- a deliberate key press, not a stray tap.
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
