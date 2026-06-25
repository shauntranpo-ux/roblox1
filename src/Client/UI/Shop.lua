-- Shop: a code-built panel that lists buyable items from the DATA-DRIVEN Catalog. No
-- hardcoded rows -- it renders whatever the catalog contains, so M3 expands the roster
-- by editing data only. Buy buttons grey out reactively when the player can't afford an
-- item (based on the replicated Cash attribute).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Catalog = require(Shared:WaitForChild("Catalog"))

local Shop = {}

local player = nil
local remotes = nil
local gui = nil
local rowsById = {} -- [itemId] = { buyButton, price }

local function canAfford(price)
    return (player:GetAttribute("Cash") or 0) >= price
end

-- Builds one shop row. A colored square stands in for the item icon (real icon in M3).
local function buildRow(item, parent)
    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 78),
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = item.Price,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(10) })

    Builder.create("Frame", {
        Name = "Icon",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(56, 56),
        BackgroundColor3 = Theme.Colors.Accent,
        BorderSizePixel = 0,
        Parent = row,
    }, { Builder.corner(UDim.new(0, 10)) })

    Builder.create("TextLabel", {
        Name = "ItemName",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(68, 4),
        Size = UDim2.new(1, -210, 0, 28),
        Font = Theme.FontBold,
        Text = item.Name,
        TextColor3 = Theme.Colors.Text,
        TextSize = 20,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    Builder.create("TextLabel", {
        Name = "Income",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(68, 38),
        Size = UDim2.new(1, -210, 0, 22),
        Font = Theme.Font,
        Text = "+$" .. Format.short(item.IncomePerSec) .. "/s",
        TextColor3 = Theme.Colors.Positive,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local buyButton = Builder.create("TextButton", {
        Name = "Buy",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(122, 54),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = "$" .. Format.short(item.Price),
        TextColor3 = Theme.Colors.Text,
        TextSize = 18,
        Parent = row,
    }, { Builder.corner(UDim.new(0, 10)) })

    -- Client sends ONLY the id; the server validates and decides everything.
    buyButton.Activated:Connect(function()
        remotes.PurchaseRequest:FireServer(item.Id)
    end)

    rowsById[item.Id] = { buyButton = buyButton, price = item.Price }
    row.Parent = parent
end

-- Greys out Buy buttons the player can't currently afford. Cheap; runs on Cash change.
function Shop.refreshAfford()
    for _, entry in pairs(rowsById) do
        local affordable = canAfford(entry.price)
        entry.buyButton.Active = affordable
        entry.buyButton.AutoButtonColor = affordable
        entry.buyButton.BackgroundColor3 = affordable and Theme.Colors.Positive
            or Theme.Colors.Disabled
        entry.buyButton.TextColor3 = affordable and Theme.Colors.Text or Theme.Colors.SubText
    end
end

function Shop.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Shop", player:WaitForChild("PlayerGui"), false)

    local list = Builder.panel(gui, "Shop", function()
        gui.Enabled = false
    end)

    for _, item in ipairs(Catalog.Items) do
        if item.Buyable ~= false then
            buildRow(item, list)
        end
    end

    Shop.refreshAfford()
    player:GetAttributeChangedSignal("Cash"):Connect(Shop.refreshAfford)
end

function Shop.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        Shop.refreshAfford()
    end
end

return Shop
