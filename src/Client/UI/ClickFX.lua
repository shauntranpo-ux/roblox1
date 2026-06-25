-- ClickFX: the code-built "bubble-pop" click feedback. A small POOLED, CAPPED set of translucent
-- circles that expand + fade on every press for a soft, satisfying ripple -- universal with zero
-- per-button wiring via one global input hook. The same hook plays the soft click sound whenever a
-- GuiButton sits under the press (so world taps ripple silently, button taps also pop).
--
-- PERFORMANCE: a fixed ring pool reused round-robin (never leaks/uncaps), each tween cancelled +
-- reused. Tune intensity/size/color/everywhere in Theme.Juice.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)

local ClickFX = {}

local POOL_SIZE = 16
local overlay = nil
local pool = {}
local poolIndex = 0
local mounted = false

local function nextRing()
    poolIndex = (poolIndex % POOL_SIZE) + 1
    return pool[poolIndex]
end

-- Spawns one expanding bubble at a screen-space pixel position.
function ClickFX.ripple(x, y)
    if overlay == nil then
        return
    end
    local ring = nextRing()
    if ring.Tween ~= nil then
        ring.Tween:Cancel()
    end
    local frame = ring.Frame
    frame.Position = UDim2.fromOffset(x, y)
    frame.Size = UDim2.fromOffset(10, 10)
    frame.BackgroundTransparency = Theme.Juice.RippleStartTransparency
    ring.Stroke.Transparency = 0.25
    frame.Visible = true

    local size = Theme.Juice.RippleSize
    local info =
        TweenInfo.new(Theme.Juice.RippleTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(ring.Stroke, info, { Transparency = 1 }):Play()
    local tween = TweenService:Create(frame, info, {
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
    })
    ring.Tween = tween
    tween:Play()
    tween.Completed:Once(function()
        frame.Visible = false
    end)
end

function ClickFX.mount(context)
    if mounted then
        return
    end
    mounted = true
    local player = context.player or Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    overlay = Instance.new("ScreenGui")
    overlay.Name = "ClickFX"
    overlay.ResetOnSpawn = false
    overlay.IgnoreGuiInset = true -- positions match raw input.Position
    overlay.DisplayOrder = 100 -- above every panel
    overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    overlay.Parent = playerGui

    for i = 1, POOL_SIZE do
        local frame = Instance.new("Frame")
        frame.Name = "Ripple" .. i
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        frame.Size = UDim2.fromOffset(10, 10)
        frame.BackgroundColor3 = Theme.Juice.RippleColor
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.Visible = false
        frame.ZIndex = 10
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = frame
        local stroke = Instance.new("UIStroke")
        stroke.Color = Theme.Juice.RippleColor
        stroke.Thickness = 2
        stroke.Transparency = 1
        stroke.Parent = frame
        frame.Parent = overlay
        pool[i] = { Frame = frame, Stroke = stroke, Tween = nil }
    end

    UserInputService.InputBegan:Connect(function(input)
        if
            input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch
        then
            return
        end
        local pos = input.Position
        if Theme.Juice.RippleEverywhere then
            ClickFX.ripple(pos.X, pos.Y)
        end
        -- Soft click sound only when a button is under the press point.
        local ok, objects = pcall(function()
            return playerGui:GetGuiObjectsAtPosition(pos.X, pos.Y)
        end)
        if ok and objects ~= nil then
            for _, object in ipairs(objects) do
                if object:IsA("GuiButton") then
                    if not Theme.Juice.RippleEverywhere then
                        ClickFX.ripple(pos.X, pos.Y)
                    end
                    Effects.playSfx("click")
                    break
                end
            end
        end
    end)
end

return ClickFX
