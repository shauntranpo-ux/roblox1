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

-- M9.1: sell one unit (client sends the Id only). High-value sells need a 2-tap confirm: the server
-- returns Result="Confirm" first; the second tap re-sends with Confirm=true. Server computes value.
local function doSell(button, entry)
    local confirmed = button:GetAttribute("PendingConfirm") == true
    local ok, result = pcall(function()
        return remotes.SellRequest:InvokeServer({
            Action = "one",
            Id = entry.Id,
            Confirm = confirmed,
        })
    end)
    if not ok or type(result) ~= "table" then
        return
    end
    if result.Result == "Confirm" then
        button.Text = "Confirm $" .. Format.full(result.Value or 0) .. "?"
        button:SetAttribute("PendingConfirm", true)
    elseif result.Result == "Success" then
        Inventory.refresh() -- the sold row disappears
    else
        button:SetAttribute("PendingConfirm", false)
        button.Text = result.Message or "Can't sell"
        task.delay(1.4, function()
            if button.Parent ~= nil then
                button.Text = "Sell $" .. Format.full(entry.SellValue or 0)
            end
        end)
    end
end

-- M9.1: bulk sell via a server-side filter (client sends the filter intent only). Same 2-tap confirm
-- on the total. `makePayload` builds a fresh filter payload each call.
local function doBulk(button, baseText, makePayload)
    local confirmed = button:GetAttribute("PendingConfirm") == true
    local payload = makePayload()
    payload.Confirm = confirmed
    local ok, result = pcall(function()
        return remotes.SellRequest:InvokeServer(payload)
    end)
    if not ok or type(result) ~= "table" then
        return
    end
    if result.Result == "Confirm" then
        button.Text = "Confirm " .. (result.Count or 0) .. " · $" .. Format.full(result.Value or 0)
        button:SetAttribute("PendingConfirm", true)
    elseif result.Result == "Success" or result.Result == "Empty" then
        button:SetAttribute("PendingConfirm", false)
        button.Text = baseText
        Inventory.refresh()
    else
        button:SetAttribute("PendingConfirm", false)
        button.Text = result.Message or baseText
        task.delay(1.4, function()
            if button.Parent ~= nil then
                button.Text = baseText
            end
        end)
    end
end

-- The bulk-sell toolbar (rebuilt each refresh since clearRows destroys Frames). Sits at the top.
local function buildToolbar()
    local bar = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
        LayoutOrder = 0,
        Parent = list,
    }, {
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 8),
        }),
    })
    local commons = Builder.glossButton({
        Size = UDim2.fromOffset(176, 40),
        color = Theme.Colors.Danger,
        Text = "Sell Commons",
        maxText = 18,
        Parent = bar,
    }, nil)
    commons.Activated:Connect(function()
        doBulk(commons, "Sell Commons", function()
            return { Action = "bulk", Mode = "RarityAtMost", Rarity = "Common" }
        end)
    end)
    local dupes = Builder.glossButton({
        Size = UDim2.fromOffset(176, 40),
        color = Theme.Colors.Danger,
        Text = "Sell Dupes (keep 1)",
        maxText = 18,
        Parent = bar,
    }, nil)
    dupes.Activated:Connect(function()
        doBulk(dupes, "Sell Dupes (keep 1)", function()
            return { Action = "bulk", Mode = "Duplicates", Keep = 1 }
        end)
    end)
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
        Position = UDim2.fromOffset(4, 3),
        Size = UDim2.new(1, -164, 0, 24),
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
        Position = UDim2.fromOffset(4, 30),
        Size = UDim2.new(1, -164, 0, 18),
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
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -4, 0, 2),
        Size = UDim2.fromOffset(152, 20),
        Font = Theme.FontBody,
        Text = "+$" .. Format.full(entry.IncomePerSec) .. "/s",
        TextColor3 = Theme.Colors.Positive,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })

    -- M9.1: sell button (server-computed value shown; premium/locked are non-sellable -> hidden).
    if entry.Sellable and (entry.SellValue or 0) > 0 then
        local sellButton = Builder.glossButton({
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -4, 1, -2),
            Size = UDim2.fromOffset(152, 28),
            color = Theme.Colors.Danger,
            Text = "Sell $" .. Format.full(entry.SellValue),
            maxText = 15,
            Parent = row,
        }, nil)
        sellButton.Activated:Connect(function()
            doSell(sellButton, entry)
        end)
    end

    row.Parent = list
end

-- Re-fetches and re-renders the owned list from the server.
function Inventory.refresh()
    if gui == nil then
        return
    end

    clearRows()
    buildToolbar() -- M9.1: bulk-sell buttons at the top

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
