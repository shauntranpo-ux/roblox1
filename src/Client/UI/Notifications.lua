-- Notifications: client toast system. Transient, auto-dismissing messages stacked at
-- the bottom of the screen, driven by the server's Notify remote.

local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

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

    local toast = Builder.create("Frame", {
        BackgroundColor3 = Theme.Colors.Panel,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
    }, {
        Builder.corner(UDim.new(0, 10)),
        Builder.padding(12),
        Builder.create("Frame", {
            Name = "Stripe",
            BackgroundColor3 = color,
            Size = UDim2.new(0, 4, 1, 0),
            BorderSizePixel = 0,
        }, { Builder.corner(UDim.new(0, 2)) }),
        Builder.create("TextLabel", {
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
        }),
    })
    toast.Parent = container

    -- Fade in, hold ~3s, fade out, destroy.
    TweenService:Create(toast, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()

    task.delay(3, function()
        if toast.Parent == nil then
            return
        end
        local fade = TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
        fade:Play()
        fade.Completed:Wait()
        toast:Destroy()
    end)
end

-- M4: the server drives steal alerts through this same channel -- StealService sends the
-- victim an "error" toast ("<Thief> stole your <rarity-colored Name>!") via the Notify
-- remote, rendered here with RichText. (The everyone-sees kill-feed banner is separate; see
-- UI/KillFeed.)

return Notifications
