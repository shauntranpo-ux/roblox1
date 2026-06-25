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
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(10) })

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

    buyButton.Activated:Connect(function()
        remotes.PurchaseRequest:FireServer(item.Id)
    end)

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
        TextColor3 = Theme.Colors.Text,
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
        TextColor3 = Theme.Colors.SubText,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = row,
    })

    local button = Builder.create("TextButton", {
        Name = "Action",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(120, 52),
        BackgroundColor3 = Theme.Colors.Accent,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = "Buy",
        TextColor3 = Theme.Colors.Text,
        TextSize = 18,
        Parent = row,
    }, { Builder.corner(UDim.new(0, 10)) })

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
        TextColor3 = Theme.Colors.SubText,
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

-- Builds the tabbed modal shell and returns the three content ScrollingFrames.
local function buildShell()
    local panel = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.92, 0.82),
        BackgroundColor3 = Theme.Colors.Background,
        BorderSizePixel = 0,
    }, {
        Builder.corner(UDim.new(0, 18)),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(580, 820) }),
    })

    local header = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        Parent = panel,
    })
    Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -72, 1, 0),
        Font = Theme.FontBold,
        Text = "Shop",
        TextColor3 = Theme.Colors.Text,
        TextSize = 26,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })
    local close = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(40, 40),
        BackgroundColor3 = Theme.Colors.Danger,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = "X",
        TextColor3 = Theme.Colors.Text,
        TextSize = 22,
        Parent = header,
    }, { Builder.corner(UDim.new(1, 0)) })
    close.Activated:Connect(function()
        gui.Enabled = false
    end)

    local tabBar = Builder.create("Frame", {
        Position = UDim2.fromOffset(12, 54),
        Size = UDim2.new(1, -24, 0, 40),
        BackgroundTransparency = 1,
        Parent = panel,
    }, {
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    local contentHolder = Builder.create("Frame", {
        Position = UDim2.fromOffset(0, 100),
        Size = UDim2.new(1, 0, 1, -100),
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
            local active = (tabKey == key)
            btn.BackgroundColor3 = active and Theme.Colors.Accent or Theme.Colors.Row
            btn.TextColor3 = active and Theme.Colors.Text or Theme.Colors.SubText
        end
    end

    for i, tab in ipairs(tabDefs) do
        local btn = Builder.create("TextButton", {
            Size = UDim2.new(1 / 3, -6, 1, 0),
            BackgroundColor3 = Theme.Colors.Row,
            BorderSizePixel = 0,
            Font = Theme.FontBold,
            Text = tab.Title,
            TextColor3 = Theme.Colors.SubText,
            TextSize = 16,
            LayoutOrder = i,
            Parent = tabBar,
        }, { Builder.corner(UDim.new(0, 10)) })

        local scroll = Builder.create("ScrollingFrame", {
            Visible = false,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = contentHolder,
        }, {
            Builder.create("UIListLayout", {
                Padding = UDim.new(0, 10),
                SortOrder = Enum.SortOrder.LayoutOrder,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
            }),
            Builder.padding(12),
        })

        built[tab.Key] = scroll
        tabButtons[tab.Key] = btn
        btn.Activated:Connect(function()
            setActive(tab.Key)
        end)
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
