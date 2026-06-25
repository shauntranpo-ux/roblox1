-- Builder: tiny declarative helpers for constructing UI in code. Keeps every screen
-- terse and consistent. No Studio-authored GUI anywhere.

local Theme = require(script.Parent.Theme)

local Builder = {}

-- Creates an Instance from a class name, a props table, and optional children.
-- Parent (if given in props) is applied LAST, after children, for fewer reflows.
function Builder.create(className, props, children)
    local instance = Instance.new(className)
    if props ~= nil then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                instance[key] = value
            end
        end
    end
    if children ~= nil then
        for _, child in ipairs(children) do
            child.Parent = instance
        end
    end
    if props ~= nil and props.Parent ~= nil then
        instance.Parent = props.Parent
    end
    return instance
end

-- Rounded-corner helper.
function Builder.corner(radius)
    return Builder.create("UICorner", { CornerRadius = radius or UDim.new(0, 12) })
end

-- Uniform padding helper (pixels on all sides).
function Builder.padding(pixels)
    local amount = UDim.new(0, pixels)
    return Builder.create("UIPadding", {
        PaddingTop = amount,
        PaddingBottom = amount,
        PaddingLeft = amount,
        PaddingRight = amount,
    })
end

-- A ScreenGui with sensible, safe-area-aware defaults. ScreenInsets is set defensively
-- in case an older client lacks the enum value.
function Builder.screenGui(name, parent, enabled)
    local gui = Builder.create("ScreenGui", {
        Name = name,
        ResetOnSpawn = false,
        Enabled = enabled ~= false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    pcall(function()
        gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    end)
    gui.Parent = parent
    return gui
end

-- Builds a standard centered modal panel: dark background, a titled header with a close
-- button, and a scrolling content area. Returns the ScrollingFrame to fill with rows.
function Builder.panel(parent, title, onClose)
    local panel = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.8, 0.64),
        BackgroundColor3 = Theme.Colors.Background,
        BorderSizePixel = 0,
    }, {
        Builder.corner(UDim.new(0, 18)),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(500, 660) }),
    })

    local header = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundTransparency = 1,
        Parent = panel,
    })

    Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -76, 1, 0),
        Font = Theme.FontBold,
        Text = title,
        TextColor3 = Theme.Colors.Text,
        TextSize = 26,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })

    local close = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(42, 42),
        BackgroundColor3 = Theme.Colors.Danger,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = "X",
        TextColor3 = Theme.Colors.Text,
        TextSize = 22,
        Parent = header,
    }, { Builder.corner(UDim.new(1, 0)) })
    close.Activated:Connect(onClose)

    local list = Builder.create("ScrollingFrame", {
        Position = UDim2.fromOffset(0, 56),
        Size = UDim2.new(1, 0, 1, -56),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = panel,
    }, {
        Builder.create("UIListLayout", {
            Padding = UDim.new(0, 10),
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        }),
        Builder.padding(12),
    })

    panel.Parent = parent
    return list
end

return Builder
