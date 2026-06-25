-- Announce: a one-off "What's New" modal. The server fires the WhatsNew remote once per version
-- bump (it owns the saved last-seen-version flag); this just renders GameInfo's changelog. Reusable
-- for any future one-shot announcement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameInfo = require(Shared:WaitForChild("GameInfo"))

local Announce = {}

local player = nil
local gui = nil

function Announce.mount(context)
    player = context.player
    gui = Builder.screenGui("Announce", player:WaitForChild("PlayerGui"), false)
    gui.DisplayOrder = 30
end

-- Shows a centered modal with a title + scrollable body + dismiss button. Rebuilds each call.
function Announce.show(title, body)
    if gui == nil then
        return
    end
    for _, child in ipairs(gui:GetChildren()) do
        child:Destroy()
    end

    local panel = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.86, 0.6),
        BackgroundColor3 = Theme.Colors.Background,
        BorderSizePixel = 0,
        Parent = gui,
    }, {
        Builder.corner(UDim.new(0, 18)),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(520, 620) }),
        Builder.padding(16),
    })

    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
        Font = Theme.FontBold,
        Text = title,
        TextColor3 = Theme.Colors.Accent,
        TextSize = 26,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = panel,
    })

    Builder.create("ScrollingFrame", {
        Position = UDim2.fromOffset(0, 48),
        Size = UDim2.new(1, 0, 1, -110),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = panel,
    }, {
        Builder.create("TextLabel", {
            Size = UDim2.fromScale(1, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Font = Theme.Font,
            Text = body,
            TextColor3 = Theme.Colors.Text,
            TextSize = 18,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
        }),
    })

    local ok = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromScale(0.5, 1),
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = "Let's go!",
        TextColor3 = Theme.Colors.Text,
        TextSize = 20,
        Parent = panel,
    }, { Builder.corner(UDim.new(0, 10)) })
    ok.Activated:Connect(function()
        gui.Enabled = false
    end)

    gui.Enabled = true
end

-- Convenience: show the current build's changelog (used by the WhatsNew remote handler).
function Announce.showWhatsNew()
    Announce.show("What's New -- v" .. GameInfo.Version, GameInfo.Changelog)
end

return Announce
