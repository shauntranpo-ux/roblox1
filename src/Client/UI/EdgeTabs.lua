-- EdgeTabs: glossy round icon TABS pinned to the screen edges (Left + Right vertical rails). Each feature
-- gets its own tab here instead of being buried in the Menu list. Buttons reuse Builder.glossButton (press
-- squish) + a hover label. Mount once like the other HUD modules; call EdgeTabs.add per feature.

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local EdgeTabs = {}

local gui = nil
local rails = {}
local order = 0

local function makeRail(side)
    local isLeft = side == "Left"
    return Builder.create("Frame", {
        Name = side .. "Rail",
        AnchorPoint = Vector2.new(isLeft and 0 or 1, 0.5),
        Position = UDim2.new(isLeft and 0 or 1, isLeft and 12 or -12, 0.5, 0),
        Size = UDim2.fromOffset(56, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = gui,
    }, {
        Builder.create("UIListLayout", {
            Padding = UDim.new(0, 8),
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
end

function EdgeTabs.mount(context)
    local player = context.player
    gui = Builder.screenGui("EdgeTabs", player:WaitForChild("PlayerGui"), true)
    rails.Left = makeRail("Left")
    rails.Right = makeRail("Right")
end

-- Add a round icon tab to a rail. `side` = "Left"|"Right", `icon` = emoji, `label` = hover text.
function EdgeTabs.add(side, icon, label, onClick)
    local rail = rails[side] or rails.Right
    if rail == nil then
        return nil
    end
    order += 1
    local btn = Builder.glossButton({
        Size = UDim2.fromOffset(52, 52),
        color = Theme.Colors.Accent,
        Text = icon,
        maxText = 26,
        radius = Theme.Radius.Pill,
        LayoutOrder = order,
        Parent = rail,
    }, onClick)
    local tip = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(side == "Left" and 0 or 1, 0.5),
        Position = UDim2.new(side == "Left" and 1 or 0, side == "Left" and 8 or -8, 0.5, 0),
        Size = UDim2.fromOffset(0, 26),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.1,
        Font = Theme.FontDisplay,
        Text = "  " .. label .. "  ",
        TextColor3 = Theme.Colors.Text,
        TextSize = 18,
        Visible = false,
        ZIndex = 5,
        Parent = btn,
    }, { Builder.corner(UDim.new(0, 8)) })
    btn.MouseEnter:Connect(function()
        tip.Visible = true
    end)
    btn.MouseLeave:Connect(function()
        tip.Visible = false
    end)
    return btn
end

return EdgeTabs
