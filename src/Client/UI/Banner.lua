-- Banner (VM-THEME): the top-center OBJECTIVE / announce banner. White ALL-CAPS FredokaOne with a
-- heavy black outline; <hl>keyword</hl> markup renders that substring in YELLOW. Pops in/out with a
-- subtle tween; auto-hides after a duration. Public Banner.show(text, seconds) / Banner.hide() so any
-- system (a default objective, a boss/season alert) can drive it. Reuses Builder + Theme.

local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Banner = {}

local gui = nil
local frame = nil
local label = nil
local hideToken = 0

local YELLOW_TAG = string.format(
    '<font color="rgb(%d,%d,%d)">',
    math.floor(Theme.Colors.Yellow.R * 255 + 0.5),
    math.floor(Theme.Colors.Yellow.G * 255 + 0.5),
    math.floor(Theme.Colors.Yellow.B * 255 + 0.5)
)

-- Uppercases the text, then turns <hl>..</hl> into a yellow RichText span (case-insensitively, since
-- the uppercase pass turns the tags into <HL>..</HL>). Ampersands/angle-brackets in arbitrary text
-- aren't expected here (objective strings are author-controlled), so no extra escaping.
local function render(text)
    text = string.upper(tostring(text))
    text = text:gsub("<HL>", YELLOW_TAG):gsub("</HL>", "</font>")
    return text
end

function Banner.mount(context)
    local player = context.player
    gui = Builder.screenGui("Banner", player:WaitForChild("PlayerGui"), true)
    gui.DisplayOrder = 8 -- above the HUD, below panels

    frame = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.03),
        Size = UDim2.fromScale(0.7, 0.09),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = gui,
    }, { Builder.create("UISizeConstraint", { MaxSize = Vector2.new(820, 96) }) })

    label = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        RichText = true,
        Text = "",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Parent = frame,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 40 }) })
    Builder.styleText(label, { keepColor = true, stroke = 3 })
end

-- Shows the banner. `seconds` (optional) auto-hides after that long (0/nil = stay until next show/hide).
function Banner.show(text, seconds)
    if frame == nil then
        return
    end
    label.Text = render(text)
    frame.Visible = true
    -- subtle pop in
    local base = UDim2.fromScale(0.7, 0.09)
    frame.Size = UDim2.fromScale(base.X.Scale * 0.85, base.Y.Scale * 0.85)
    TweenService
        :Create(frame, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = base,
        })
        :Play()

    hideToken += 1
    local token = hideToken
    if type(seconds) == "number" and seconds > 0 then
        task.delay(seconds, function()
            if token == hideToken then
                Banner.hide()
            end
        end)
    end
end

function Banner.hide()
    hideToken += 1
    if frame ~= nil then
        frame.Visible = false
    end
end

return Banner
