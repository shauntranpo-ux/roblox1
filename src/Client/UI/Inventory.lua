-- Inventory: a code-built panel listing what the player owns, fetched fresh from the
-- server via the GetInventory RemoteFunction (never a client-held copy). Refreshes when
-- opened and after a successful purchase. Foundation for the later "Index".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Inventory = {}

local player = nil
local remotes = nil
local gui = nil
local list = nil
local emptyLabel = nil

-- Removes existing rows but keeps layout helpers + the empty-state label.
local function clearRows()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
end

local function addRow(entry, order)
    local rarity = Rarity.Get(entry.Rarity)

    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 62),
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.padding(10) })
    Builder.rarityCard(row, rarity.Color) -- rarity-colored border + translucent rounded card

    -- Name (line 1) + rarity (line 2, rarity-colored) on the left; income on the right.
    local nameLabel = Builder.create("TextLabel", {
        Name = "ItemName",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.new(1, -134, 0, 26),
        Text = entry.Name,
        TextColor3 = Theme.Colors.Text,
        TextSize = 18,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    Builder.applyChrome(nameLabel, { stroke = 2 })

    Builder.create("TextLabel", {
        Name = "Rarity",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(2, 30),
        Size = UDim2.new(1, -132, 0, 18),
        Font = Theme.FontBold,
        Text = rarity.DisplayName,
        TextColor3 = rarity.Color,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    Builder.create("TextLabel", {
        Name = "Income",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -2, 0.5, 0),
        Size = UDim2.fromOffset(122, 40),
        Font = Theme.FontBody,
        Text = "+$" .. Format.full(entry.IncomePerSec) .. "/s",
        TextColor3 = Theme.Colors.Positive,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })

    row.Parent = list
end

-- Re-fetches and re-renders the owned list from the server.
function Inventory.refresh()
    if gui == nil then
        return
    end

    clearRows()

    local owned = remotes.GetInventory:InvokeServer()
    if typeof(owned) ~= "table" then
        owned = {}
    end

    emptyLabel.Visible = #owned == 0
    for index, entry in ipairs(owned) do
        addRow(entry, index)
    end
end

function Inventory.refreshIfOpen()
    if gui ~= nil and gui.Enabled then
        Inventory.refresh()
    end
end

function Inventory.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Inventory", player:WaitForChild("PlayerGui"), false)

    list = Builder.panel(gui, "Inventory", function()
        gui.Enabled = false
    end)

    emptyLabel = Builder.create("TextLabel", {
        Name = "Empty",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 40),
        Font = Theme.Font,
        Text = "You don't own anything yet.",
        TextColor3 = Theme.Colors.SubText,
        TextSize = 16,
        Visible = false,
        LayoutOrder = 9999,
        Parent = list,
    })
end

function Inventory.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        Inventory.refresh()
    end
end

return Inventory
