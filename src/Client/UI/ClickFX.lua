-- ClickFX: the code-built press "pop" -- a punchy burst (a bright overshoot ring + a flash core +
-- flying sparks) at the EXACT press point, on every tap, plus the soft click sound when a button is
-- under the press. POOLED + CAPPED (never leaks). Tune everything in Theme.Juice.
--
-- ALIGNMENT: the overlay ignores the GUI inset, so we add GuiService:GetGuiInset() to the
-- inset-relative input.Position. That lands the burst exactly under the cursor / finger on both
-- desktop and mobile (the previous version was offset up by the ~36px top-bar inset).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)

local ClickFX = {}

local POOL_SIZE = 14
local SPARK_COUNT = 6
local SPARK_COLORS = {
    Color3.fromRGB(255, 240, 150), -- gold
    Color3.fromRGB(150, 230, 255), -- cyan
    Color3.fromRGB(255, 150, 220), -- pink
    Color3.fromRGB(190, 160, 255), -- purple
    Color3.fromRGB(255, 255, 255), -- white
}

local overlay = nil
local pool = {}
local poolIndex = 0
local mounted = false

local function circle(diameter, color, zIndex)
    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Size = UDim2.fromOffset(diameter, diameter)
    frame.BackgroundColor3 = color
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.ZIndex = zIndex
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = frame
    return frame
end

local function nextSlot()
    poolIndex = (poolIndex % POOL_SIZE) + 1
    return pool[poolIndex]
end

-- Spawns the full burst at a screen-space pixel position (already inset-adjusted).
function ClickFX.ripple(x, y)
    if overlay == nil then
        return
    end
    local slot = nextSlot()
    for _, tween in ipairs(slot.Tweens) do
        tween:Cancel()
    end
    table.clear(slot.Tweens)

    local at = UDim2.fromOffset(x, y)
    local size = Theme.Juice.RippleSize
    local time = Theme.Juice.RippleTime

    -- Expanding ring (overshoot pop) with a bright stroke.
    local ring = slot.Ring
    ring.Position = at
    ring.Size = UDim2.fromOffset(12, 12)
    ring.BackgroundTransparency = 1
    slot.RingStroke.Color = Theme.Juice.RippleColor
    slot.RingStroke.Transparency = 0.05
    ring.Visible = true
    local ringTween = TweenService:Create(
        ring,
        TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = UDim2.fromOffset(size, size) }
    )
    local ringFade = TweenService:Create(
        slot.RingStroke,
        TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Transparency = 1 }
    )
    ringTween:Play()
    ringFade:Play()
    table.insert(slot.Tweens, ringTween)
    table.insert(slot.Tweens, ringFade)
    ringTween.Completed:Once(function()
        ring.Visible = false
    end)

    -- Bright flash core that puffs out and fades fast.
    local core = slot.Core
    core.Position = at
    core.Size = UDim2.fromOffset(10, 10)
    core.BackgroundColor3 = Theme.Juice.RippleColor
    core.BackgroundTransparency = 0.15
    core.Visible = true
    local coreTween = TweenService:Create(
        core,
        TweenInfo.new(time * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.fromOffset(size * 0.55, size * 0.55), BackgroundTransparency = 1 }
    )
    coreTween:Play()
    table.insert(slot.Tweens, coreTween)
    coreTween.Completed:Once(function()
        core.Visible = false
    end)

    -- Sparks fly outward.
    for i, spark in ipairs(slot.Sparks) do
        local angle = (i / SPARK_COUNT) * math.pi * 2 + math.random() * 0.6
        local radius = size * (0.45 + math.random() * 0.35)
        spark.Position = at
        spark.Size = UDim2.fromOffset(9, 9)
        spark.BackgroundColor3 = SPARK_COLORS[((i - 1) % #SPARK_COLORS) + 1]
        spark.BackgroundTransparency = 0
        spark.Visible = true
        local sparkTween = TweenService:Create(
            spark,
            TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                Position = UDim2.fromOffset(
                    x + math.cos(angle) * radius,
                    y + math.sin(angle) * radius
                ),
                Size = UDim2.fromOffset(2, 2),
                BackgroundTransparency = 1,
            }
        )
        sparkTween:Play()
        table.insert(slot.Tweens, sparkTween)
        sparkTween.Completed:Once(function()
            spark.Visible = false
        end)
    end
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
    overlay.IgnoreGuiInset = true
    overlay.DisplayOrder = 100
    overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    overlay.Parent = playerGui

    for i = 1, POOL_SIZE do
        local ring = circle(12, Theme.Juice.RippleColor, 10)
        local ringStroke = Instance.new("UIStroke")
        ringStroke.Color = Theme.Juice.RippleColor
        ringStroke.Thickness = 3
        ringStroke.Transparency = 1
        ringStroke.Parent = ring
        ring.Parent = overlay

        local core = circle(10, Theme.Juice.RippleColor, 11)
        core.Parent = overlay

        local sparks = {}
        for s = 1, SPARK_COUNT do
            local spark = circle(9, Color3.new(1, 1, 1), 12)
            spark.Parent = overlay
            sparks[s] = spark
        end

        pool[i] =
            { Ring = ring, RingStroke = ringStroke, Core = core, Sparks = sparks, Tweens = {} }
    end

    UserInputService.InputBegan:Connect(function(input)
        if
            input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch
        then
            return
        end
        -- input.Position is inset-relative; the overlay ignores the inset, so add it back.
        local inset = GuiService:GetGuiInset()
        local x = input.Position.X + inset.X
        local y = input.Position.Y + inset.Y
        if Theme.Juice.RippleEverywhere then
            ClickFX.ripple(x, y)
        end
        local ok, objects = pcall(function()
            return playerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
        end)
        if ok and objects ~= nil then
            for _, object in ipairs(objects) do
                if object:IsA("GuiButton") then
                    if not Theme.Juice.RippleEverywhere then
                        ClickFX.ripple(x, y)
                    end
                    Effects.playSfx("click")
                    break
                end
            end
        end
    end)
end

return ClickFX
