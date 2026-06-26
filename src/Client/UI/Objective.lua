-- Objective (M12.1): the persistent top-center OBJECTIVE strip -- drives the player's current primary
-- objective (the active tutorial step, or a highlighted daily) from the server-published "Objective"
-- attribute, with <hl>keyword</hl> -> yellow markup and a subtle pop on change. Sits just below the
-- transient announce Banner so boss/biome alerts don't clobber it. Empty objective -> hides cleanly.
-- Pure presentation: it only renders a replicated attribute the server owns.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Objective = {}

local frame = nil
local label = nil

local YELLOW = string.format(
    '<font color="rgb(%d,%d,%d)">',
    math.floor(Theme.Colors.Yellow.R * 255 + 0.5),
    math.floor(Theme.Colors.Yellow.G * 255 + 0.5),
    math.floor(Theme.Colors.Yellow.B * 255 + 0.5)
)

local function render(text)
    text = string.upper(tostring(text))
    return (text:gsub("<HL>", YELLOW):gsub("</HL>", "</font>"))
end

local function refresh(player)
    local text = player:GetAttribute("Objective")
    if frame == nil then
        return
    end
    if type(text) ~= "string" or text == "" then
        frame.Visible = false
        return
    end
    label.Text = render(text)
    frame.Visible = true
    local base = UDim2.fromScale(0.6, 0.05)
    frame.Size = UDim2.fromScale(base.X.Scale * 0.9, base.Y.Scale * 0.9)
    TweenService:Create(
        frame,
        TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = base }
    ):Play()
end

function Objective.mount(context)
    local player = context.player or Players.LocalPlayer
    local gui = Builder.screenGui("Objective", player:WaitForChild("PlayerGui"), true)
    gui.DisplayOrder = 7 -- below the announce banner (8)

    frame = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.06),
        Size = UDim2.fromScale(0.6, 0.05),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.25,
        Visible = false,
        Parent = gui,
    }, {
        Builder.corner(UDim.new(0, 10)),
        Builder.padding(6),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(700, 56) }),
    })

    label = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        RichText = true,
        Text = "",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Parent = frame,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 24 }) })
    Builder.styleText(label, { keepColor = true, stroke = 3 })

    player:GetAttributeChangedSignal("Objective"):Connect(function()
        refresh(player)
    end)
    refresh(player)
end

return Objective
