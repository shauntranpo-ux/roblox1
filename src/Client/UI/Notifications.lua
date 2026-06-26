-- Notifications: client toast system. Transient, auto-dismissing messages stacked at
-- the bottom of the screen, driven by the server's Notify remote.

local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)

local Notifications = {}

local container = nil

local KIND_COLORS = {
    success = Theme.Colors.Positive,
    error = Theme.Colors.Danger,
    info = Theme.Colors.Accent,
}

function Notifications.mount(context)
    local gui = Builder.screenGui("Toasts", context.player:WaitForChild("PlayerGui"), true)

    container = Builder.create("Frame", {
        Name = "Container",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromScale(0.5, 0.82),
        Size = UDim2.fromScale(0.9, 0.4),
        BackgroundTransparency = 1,
        Parent = gui,
    }, {
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
        }),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(520, 9999) }),
    })
end

-- Shows a transient toast. kind = "success" | "error" | "info".
function Notifications.show(kind, message)
    if container == nil then
        return
    end

    local color = KIND_COLORS[kind] or Theme.Colors.Accent

    -- Soft dark "bubble" toast (sits over the 3D world, so it keeps the white-fill text recipe + a soft
    -- kind-colored glow rim) -- cohesive with the HUD chips.
    local label = Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -14, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Font = Theme.FontBold,
        RichText = true, -- lets server-sent messages rarity-color a name span
        Text = tostring(message),
        TextColor3 = Theme.Colors.Text,
        TextSize = 18,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    Builder.styleText(label, { keepColor = true })

    local toast = Builder.create("Frame", {
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
    }, {
        Builder.corner(Theme.Radius.Card),
        Builder.create("UIStroke", { Color = color, Thickness = 2.5, Transparency = 0.3 }),
        Builder.padding(12),
        Builder.create("Frame", {
            Name = "Stripe",
            BackgroundColor3 = color,
            Size = UDim2.new(0, 5, 1, 0),
            BorderSizePixel = 0,
        }, { Builder.corner(UDim.new(1, 0)) }),
        label,
    })
    -- Bouncy slide in from below + fade in (overshoot Back/Out).
    toast.Position = UDim2.fromOffset(0, 22) -- start below the final resting position
    toast.BackgroundTransparency = 1
    toast.Parent = container
    local fadeTi = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local inTi = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    TweenService:Create(toast, fadeTi, { BackgroundTransparency = 0.08 }):Play()
    TweenService:Create(toast, inTi, { Position = UDim2.new(0, 0, 0, 0) }):Play()
    -- Success toasts get a pooled sparkle pop near the toast stack.
    if kind == "success" then
        Effects.burst(UDim2.fromScale(0.5, 0.74), color, 10)
    end

    task.delay(3, function()
        if toast.Parent == nil then
            return
        end
        -- Slide down + fade out (~0.25s) then destroy.
        local outTi = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(toast, outTi, { BackgroundTransparency = 1 }):Play()
        local slideOut = TweenService:Create(toast, outTi, { Position = UDim2.fromOffset(0, 20) })
        slideOut:Play()
        slideOut.Completed:Wait()
        toast:Destroy()
    end)
end

-- M4: the server drives steal alerts through this same channel -- StealService sends the
-- victim an "error" toast ("<Thief> stole your <rarity-colored Name>!") via the Notify
-- remote, rendered here with RichText. (The everyone-sees kill-feed banner is separate; see
-- UI/KillFeed.)

return Notifications
