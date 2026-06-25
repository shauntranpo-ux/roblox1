-- Menu: a simple scrollable list of buttons that open the secondary panels (Codes, Rebirth,
-- Index, Settings, and future Trade/Events/Seasons). Keeps the bottom HUD bar to the essentials
-- (Shop/Inventory/Menu) and scales as later milestones add panels -- each just registers a button.

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Menu = {}

local player = nil
local gui = nil
local list = nil
local count = 0

function Menu.mount(context)
    player = context.player
    gui = Builder.screenGui("Menu", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Menu", function()
        gui.Enabled = false
    end)
end

-- Registers a menu entry. Tapping it closes the menu and runs onClick (typically a panel toggle).
function Menu.addButton(label, onClick)
    if list == nil then
        return
    end
    count += 1
    local button = Builder.create("TextButton", {
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundColor3 = Theme.Colors.Accent,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = label,
        TextColor3 = Theme.Colors.Text,
        TextSize = 22,
        LayoutOrder = count,
        Parent = list,
    }, { Builder.corner(UDim.new(0, 12)) })
    button.Activated:Connect(function()
        gui.Enabled = false
        onClick()
    end)
end

function Menu.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
end

return Menu
