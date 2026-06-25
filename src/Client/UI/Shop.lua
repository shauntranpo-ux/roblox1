-- Shop: a code-built panel listing the full DATA-DRIVEN roster, sorted by rarity (ascending
-- tier, then price). No hardcoded rows -- it renders whatever Catalog.GetSorted() returns,
-- so retuning the roster is a data-only change. Each row shows the rarity (color-coded),
-- DisplayName, income, and a Buy button that greys out reactively when the player can't
-- afford it (based on the replicated Cash attribute). Scrolls cleanly on mobile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Shop = {}

local player = nil
local remotes = nil
local gui = nil
local rowsById = {} -- [itemId] = { buyButton, price }

local function canAfford(price)
    return (player:GetAttribute("Cash") or 0) >= price
end

-- Color3 -> "#RRGGBB" for RichText spans.
local function toHex(color)
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

-- Builds one shop row. The icon square + rarity word are tinted by the item's rarity color
-- so tiers are obvious; the buy button shows the price.
local function buildRow(item, order, parent)
    local rarity = Rarity.Get(item.Rarity)

    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 78),
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(10) })

    -- Rarity-tinted icon placeholder (real thumbnail via IconId later).
    Builder.create("Frame", {
        Name = "Icon",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(56, 56),
        BackgroundColor3 = rarity.Color,
        BorderSizePixel = 0,
        Parent = row,
    }, { Builder.corner(UDim.new(0, 10)) })

    Builder.create("TextLabel", {
        Name = "ItemName",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(68, 4),
        Size = UDim2.new(1, -210, 0, 28),
        Font = Theme.FontBold,
        Text = item.DisplayName,
        TextColor3 = Theme.Colors.Text,
        TextSize = 20,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    -- Second line: rarity name (in its color) + income (green), via one RichText label.
    Builder.create("TextLabel", {
        Name = "Detail",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(68, 38),
        Size = UDim2.new(1, -210, 0, 22),
        Font = Theme.Font,
        RichText = true,
        Text = string.format(
            '<font color="%s"><b>%s</b></font>   +$%s/s',
            toHex(rarity.Color),
            rarity.DisplayName,
            Format.short(item.IncomePerSec)
        ),
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

    -- Render the roster pre-sorted by rarity then price; the loop index is the LayoutOrder.
    for order, item in ipairs(Catalog.GetSorted()) do
        if item.Buyable ~= false then
            buildRow(item, order, list)
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
