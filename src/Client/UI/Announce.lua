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

    -- Built on the SHARED panel kit (glossy thick-bordered header + dark navy body) so it matches every
    -- other modal in the game instead of being a one-off flat panel with its own glow rim.
    local list = Builder.panel(gui, title, function()
        gui.Enabled = false
    end, "Default")
    local panel = list.Parent

    Builder.create("TextLabel", {
        Size = UDim2.new(1, -8, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = Theme.Font,
        Text = body,
        TextColor3 = Theme.Colors.Ink, -- light ink on the dark navy body
        TextSize = 18,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 1,
        Parent = list,
    })

    Builder.glossButton({
        Size = UDim2.new(1, -8, 0, 52),
        Text = "Let's go!",
        color = Theme.Colors.Positive,
        LayoutOrder = 2,
        Parent = list,
    }, function()
        gui.Enabled = false
    end)

    gui.Enabled = true
    Builder.popOpen(panel) -- bouncy scale-in to match the rest of the UI
end

-- Convenience: show the current build's changelog (used by the WhatsNew remote handler).
function Announce.showWhatsNew()
    Announce.show("What's New -- v" .. GameInfo.Version, GameInfo.Changelog)
end

return Announce
