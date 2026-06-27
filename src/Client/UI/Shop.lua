-- Shop: a code-built, tabbed panel. THREE tabs, all data-driven:
--   * Brainrots  -- the cash-buyable roster (Catalog), grouped by rarity. Buy = server-validated
--                   cash purchase (unchanged from M2/M3).
--   * Passes     -- gamepasses (Shared/Monetization). Buy = REQUEST a Robux prompt; the server +
--                   Roblox own the outcome. Owned passes show "Owned" reactively.
--   * Products   -- developer products (cash packs / pads / premium unit). Buy = request a Robux
--                   product prompt; grants flow only through the server's ProcessReceipt.
-- The Robux items are rendered straight from the monetization config and HIDE any row whose Id
-- is still a 0 placeholder (unless the server reports SIM mode, so they're testable in Studio).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Monetization = require(Shared:WaitForChild("Monetization"))

local Shop = {}

local player = nil
local remotes = nil
local gui = nil
local scrolls = nil -- { Roster, Passes, Products } ScrollingFrames
local rowsById = {} -- [itemId] = { buyButton, price } (cash roster afford state)
local passButtons = {} -- [passKey] = TextButton (gamepass owned/buy state)
local moneyState = { Owned = {}, SimMode = false }

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

-- Sorts a config dict ({ key = { Order, ... } }) into an array by Order.
local function sortedByOrder(dict)
    local arr = {}
    for key, def in pairs(dict) do
        table.insert(arr, { Key = key, Def = def })
    end
    table.sort(arr, function(a, b)
        return (a.Def.Order or 0) < (b.Def.Order or 0)
    end)
    return arr
end

-- ===== Cash roster row (unchanged behavior from M3) =======================================
local function buildRow(item, order, parent)
    local rarity = Rarity.Get(item.Rarity)

    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 78),
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.padding(10) })
    Builder.rarityCard(row, rarity.Color) -- rarity-colored border + translucent rounded card

    -- Icon swatch (roster IconId would slot in here later; rarity-tinted placeholder for now).
    Builder.create("ImageLabel", {
        Name = "Icon",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(56, 56),
        BackgroundColor3 = rarity.Color,
        BorderSizePixel = 0,
        Image = (item.IconId ~= nil and item.IconId ~= 0) and ("rbxassetid://" .. tostring(
            item.IconId
        )) or "",
        ScaleType = Enum.ScaleType.Fit,
        Parent = row,
    }, {
        Builder.corner(UDim.new(0, 10)),
        Builder.create("UIStroke", {
            Color = Theme.Colors.Outline,
            Thickness = 2,
            Transparency = 0.3,
        }),
    })

    local nameLabel = Builder.create("TextLabel", {
        Name = "ItemName",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(68, 4),
        Size = UDim2.new(1, -232, 0, 28),
        Text = item.DisplayName,
        TextColor3 = Theme.Colors.Ink,
        TextSize = 20,
        TextScaled = false,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    Builder.styleText(nameLabel, { ink = true, keepColor = true }) -- clean ink, not a heavy dark outline

    Builder.create("TextLabel", {
        Name = "Detail",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(68, 40),
        Size = UDim2.new(1, -232, 0, 22),
        Font = Theme.FontBody,
        RichText = true,
        Text = string.format(
            '<font color="%s"><b>%s</b></font>   +$%s/s',
            toHex(rarity.Color),
            rarity.DisplayName,
            Format.full(item.IncomePerSec)
        ),
        TextColor3 = Theme.Colors.Positive,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local buyButton = Builder.glossButton({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(150, 56),
        color = Theme.Colors.Positive,
        Text = "$" .. Format.full(item.Price),
        maxText = 20,
        Parent = row,
    }, function()
        remotes.PurchaseRequest:FireServer(item.Id)
    end)
    buyButton.Name = "Buy"

    rowsById[item.Id] = { buyButton = buyButton, price = item.Price }
    row.Parent = parent
end

-- ===== Robux item row (gamepass OR product) ===============================================
-- `kind` = "Pass" or "Product". For passes we keep a button ref so owned state is reactive.
local function buildRobuxRow(entry, kind, parent)
    local key, def = entry.Key, entry.Def

    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 96),
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = def.Order or 0,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(10) })

    Builder.create("TextLabel", {
        Name = "Name",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(4, 2),
        Size = UDim2.new(1, -150, 0, 26),
        Font = Theme.FontBold,
        Text = def.Name,
        TextColor3 = Theme.Colors.Ink,
        TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    Builder.create("TextLabel", {
        Name = "Desc",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(4, 32),
        Size = UDim2.new(1, -150, 0, 52),
        Font = Theme.Font,
        Text = def.Description,
        TextColor3 = Theme.Colors.InkSoft,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = row,
    })

    local button = Builder.glossButton({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(120, 52),
        color = Theme.Colors.Accent,
        Text = "Buy",
        maxText = 20,
        Parent = row,
    })
    button.Name = "Action"

    if kind == "Pass" then
        button.Activated:Connect(function()
            remotes.PromptGamepass:FireServer(key)
        end)
        passButtons[key] = button
    else
        button.Activated:Connect(function()
            remotes.PromptProduct:FireServer(key)
        end)
    end

    row.Parent = parent
end

-- A centered placeholder shown when a Robux tab has no configured rows.
local function buildPlaceholder(parent, text)
    Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 80),
        BackgroundTransparency = 1,
        Font = Theme.Font,
        Text = text,
        TextColor3 = Theme.Colors.InkSoft,
        TextSize = 16,
        TextWrapped = true,
        Parent = parent,
    })
end

-- Flips a gamepass button between Buy and Owned.
local function setPassOwned(key, owned)
    local button = passButtons[key]
    if button == nil then
        return
    end
    if owned then
        button.Text = "Owned"
        button.BackgroundColor3 = Theme.Colors.Positive
        button.Active = false
        button.AutoButtonColor = false
    else
        button.Text = "Buy"
        button.BackgroundColor3 = Theme.Colors.Accent
        button.Active = true
        button.AutoButtonColor = true
    end
end

-- Server -> client: a gamepass became owned. Wired from Client.client.lua.
function Shop.applyMonetizationUpdate(payload)
    if payload.Key == nil then
        return
    end
    moneyState.Owned[payload.Key] = payload.Owned
    setPassOwned(payload.Key, payload.Owned)
end

-- Greys out cash Buy buttons the player can't afford. Runs on Cash change.
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

-- Builds the glossy tabbed shell (gold accent) and returns the three content ScrollingFrames.
local function buildShell()
    local panel = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.82, 0.74),
        BackgroundColor3 = Theme.Colors.Background,
        BackgroundTransparency = Theme.BodyTransparency,
        BorderSizePixel = 0,
    }, {
        Builder.corner(Theme.Radius.Panel),
        Builder.create(
            "UIStroke",
            { -- standard thick bright panel border (matches every other panel)
                Color = Theme.Border.Color,
                Thickness = Theme.Border.Width,
                Transparency = Theme.Border.Transparency,
            }
        ),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(520, 720) }),
        Builder.create("UIGradient", { -- bright gloss top -> soft cloud body
            Rotation = 90,
            Color = ColorSequence.new(Theme.Colors.CloudTop, Theme.Colors.Cloud),
        }),
    })
    panel:SetAttribute("Glassed", true) -- PanelManager.applyGlass skips it (no double styling)

    Builder.glossHeader(panel, "Shop", "Shop", function()
        gui.Enabled = false
    end)

    local tabBar = Builder.create("Frame", {
        Position = UDim2.fromOffset(8, Theme.HeaderHeight + 16),
        Size = UDim2.new(1, -16, 0, 34),
        BackgroundTransparency = 1,
        Parent = panel,
    }, {
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    local contentTop = Theme.HeaderHeight + 16 + 34 + 10
    local contentHolder = Builder.create("Frame", {
        Position = UDim2.fromOffset(8, contentTop),
        Size = UDim2.new(1, -16, 1, -(contentTop + 10)),
        BackgroundTransparency = 1,
        Parent = panel,
    })

    local tabDefs = {
        { Key = "Roster", Title = "Brainrots" },
        { Key = "Passes", Title = "Passes" },
        { Key = "Products", Title = "Products" },
    }
    local built = {}
    local tabButtons = {}

    local function setActive(key)
        for tabKey, scroll in pairs(built) do
            scroll.Visible = (tabKey == key)
        end
        for tabKey, btn in pairs(tabButtons) do
            Builder.setPillSelected(btn, "Shop", tabKey == key)
        end
    end

    for i, tab in ipairs(tabDefs) do
        local btn = Builder.pillTab(tabBar, tab.Title, i, function()
            setActive(tab.Key)
        end)

        local scroll = Builder.create("ScrollingFrame", {
            Visible = false,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = contentHolder,
        }, {
            Builder.create("UIListLayout", {
                Padding = UDim.new(0, 10),
                SortOrder = Enum.SortOrder.LayoutOrder,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
            }),
            Builder.padding(6),
        })
        Builder.styleScroll(scroll)

        built[tab.Key] = scroll
        tabButtons[tab.Key] = btn
    end

    panel.Parent = gui
    setActive("Roster")
    return built
end

function Shop.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Shop", player:WaitForChild("PlayerGui"), false)

    -- Pull the monetization state (owned passes + SIM flag). Retries briefly in case the shop
    -- mounts before the server bound the handler; safe fallback if it never answers.
    for _ = 1, 10 do
        local ok, state = pcall(function()
            return remotes.GetMonetization:InvokeServer()
        end)
        if ok and type(state) == "table" then
            moneyState = state
            moneyState.Owned = moneyState.Owned or {}
            break
        end
        task.wait(0.2)
    end

    scrolls = buildShell()

    -- Brainrots tab: the cash roster, pre-sorted by rarity then price (premium units excluded).
    for order, item in ipairs(Catalog.GetSorted()) do
        if item.Buyable ~= false then
            buildRow(item, order, scrolls.Roster)
        end
    end

    -- Passes tab: configured gamepasses (or all of them in SIM mode, so they're testable).
    local anyPass = false
    for _, entry in ipairs(sortedByOrder(Monetization.Gamepasses)) do
        if entry.Def.Id ~= 0 or moneyState.SimMode then
            buildRobuxRow(entry, "Pass", scrolls.Passes)
            setPassOwned(entry.Key, moneyState.Owned[entry.Key] == true)
            anyPass = true
        end
    end
    if not anyPass then
        buildPlaceholder(scrolls.Passes, "Gamepasses coming soon!")
    end

    -- Products tab: configured developer products (or all of them in SIM mode).
    local anyProduct = false
    for _, entry in ipairs(sortedByOrder(Monetization.Products)) do
        if entry.Def.Id ~= 0 or moneyState.SimMode then
            buildRobuxRow(entry, "Product", scrolls.Products)
            anyProduct = true
        end
    end
    if not anyProduct then
        buildPlaceholder(scrolls.Products, "Products coming soon!")
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
