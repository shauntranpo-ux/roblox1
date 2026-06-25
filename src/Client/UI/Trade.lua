-- Trade: the player-to-player trade window. Server-driven: it renders ONLY the authoritative
-- snapshot pushed via TradeUpdate and sends INTENT actions via TradeAction. Two-stage
-- Ready -> Confirm; when the other player edits their offer the server resets both flags and the
-- snapshot reflects it (we surface that loudly), so the switcheroo scam is visible.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Trade = {}

local player = nil
local remotes = nil
local gui = nil
local list = nil
local snapshot = nil -- last "update" snapshot
local prevReady = false

local function send(action, extra)
    local payload = { Action = action }
    if extra ~= nil then
        for k, v in pairs(extra) do
            payload[k] = v
        end
    end
    remotes.TradeAction:FireServer(payload)
end

local function clear()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end
end

local order = 0
local function nextOrder()
    order += 1
    return order
end

local function label(text, color, size)
    Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, size or 26),
        BackgroundTransparency = 1,
        Font = Theme.FontBold,
        Text = text,
        TextColor3 = color or Theme.Colors.Text,
        TextSize = 16,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = list,
    })
end

local function button(text, color, onClick)
    local b = Builder.create("TextButton", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = text,
        TextColor3 = Theme.Colors.Text,
        TextSize = 18,
        LayoutOrder = nextOrder(),
        Parent = list,
    }, { Builder.corner(UDim.new(0, 10)) })
    b.Activated:Connect(onClick)
    return b
end

local function itemRow(item, removable)
    local rarity = Rarity.Get(item.Rarity)
    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
    }, { Builder.corner(UDim.new(0, 8)), Builder.padding(6) })
    Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, removable and -70 or -4, 1, 0),
        Font = Theme.Font,
        Text = string.format("%s  +$%s/s", item.Name, Format.short(item.IncomePerSec)),
        TextColor3 = rarity.Color,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })
    if removable then
        local rm = Builder.create("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(60, 30),
            BackgroundColor3 = Theme.Colors.Danger,
            BorderSizePixel = 0,
            Font = Theme.FontBold,
            Text = "X",
            TextColor3 = Theme.Colors.Text,
            TextSize = 14,
            Parent = row,
        }, { Builder.corner(UDim.new(0, 6)) })
        rm.Activated:Connect(function()
            send("removeitem", { BrainrotId = item.Id })
        end)
    end
    row.Parent = list
end

-- The add-your-units picker (tradeable owned units not already offered).
local function renderPicker()
    clear()
    order = 0
    label("Add a unit to your offer", Theme.Colors.Text)
    button("‹ Back", Theme.Colors.Disabled, function()
        if snapshot ~= nil then
            Trade.renderActive(snapshot)
        end
    end)
    local ok, owned = pcall(function()
        return remotes.GetInventory:InvokeServer()
    end)
    if not ok or typeof(owned) ~= "table" then
        return
    end
    local offered = {}
    if snapshot ~= nil then
        for _, it in ipairs(snapshot.You.Items) do
            offered[it.Id] = true
        end
    end
    for _, unit in ipairs(owned) do
        if unit.Tradeable and not offered[unit.Id] then
            local rarity = Rarity.Get(unit.Rarity)
            button(
                string.format("%s  (+$%s/s)", unit.Name, Format.short(unit.IncomePerSec)),
                rarity.Color,
                function()
                    send("additem", { BrainrotId = unit.Id })
                end
            )
        end
    end
end

function Trade.renderActive(payload)
    snapshot = payload
    clear()
    order = 0

    if payload.You.Ready and not payload.You.Confirm then
        label("Both Ready -> now press CONFIRM.", Theme.Colors.Accent)
    elseif prevReady and not payload.You.Ready then
        label(
            "⚠ Offer changed -- your Ready was reset! Re-check before confirming.",
            Theme.Colors.Danger
        )
    end
    prevReady = payload.You.Ready

    label("Trading with " .. tostring(payload.Partner), Theme.Colors.Accent, 24)

    label(
        "YOUR OFFER "
            .. (payload.You.Ready and "✓Ready" or "")
            .. (payload.You.Confirm and " ✓Confirm" or ""),
        Theme.Colors.Positive
    )
    for _, item in ipairs(payload.You.Items) do
        itemRow(item, true)
    end
    if payload.CashEnabled then
        label("Your cash offered: $" .. Format.short(payload.You.Cash), Theme.Colors.SubText, 22)
    end
    button("+ Add unit", Theme.Colors.Accent, renderPicker)

    label(
        "PARTNER'S OFFER "
            .. (payload.Them.Ready and "✓Ready" or "")
            .. (payload.Them.Confirm and " ✓Confirm" or ""),
        Theme.Colors.Positive
    )
    for _, item in ipairs(payload.Them.Items) do
        itemRow(item, false)
    end
    if payload.CashEnabled then
        label(
            "Partner cash offered: $" .. Format.short(payload.Them.Cash),
            Theme.Colors.SubText,
            22
        )
    end

    button(
        payload.You.Ready and "Unready" or "Ready",
        payload.You.Ready and Theme.Colors.Disabled or Theme.Colors.Positive,
        function()
            send("ready", { Ready = not payload.You.Ready })
        end
    )
    if payload.BothReady then
        button(
            payload.You.Confirm and "Confirmed -- waiting..." or "CONFIRM TRADE",
            Theme.Colors.Positive,
            function()
                send("confirm")
            end
        )
    end
    button("Cancel trade", Theme.Colors.Danger, function()
        send("cancel")
    end)
end

local function renderRequest(payload)
    clear()
    order = 0
    snapshot = nil
    label(tostring(payload.FromName) .. " wants to trade!", Theme.Colors.Accent, 24)
    button("Accept", Theme.Colors.Positive, function()
        send("respond", { Accept = true })
    end)
    button("Decline", Theme.Colors.Danger, function()
        send("respond", { Accept = false })
    end)
end

-- The default view when not in a trade: pick a player in this server to request.
function Trade.renderPlayerList()
    clear()
    order = 0
    snapshot = nil
    prevReady = false
    label("Trade with a player in this server:", Theme.Colors.Text)
    local any = false
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            any = true
            button("Request trade: " .. other.Name, Theme.Colors.Accent, function()
                send("request", { TargetUserId = other.UserId })
            end)
        end
    end
    if not any then
        label("No other players here right now.", Theme.Colors.SubText)
    end
end

function Trade.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Trade", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Trade", function()
        gui.Enabled = false
    end)

    remotes.TradeUpdate.OnClientEvent:Connect(function(payload)
        if typeof(payload) ~= "table" then
            return
        end
        if payload.Kind == "request" then
            gui.Enabled = true
            renderRequest(payload)
        elseif payload.Kind == "update" then
            gui.Enabled = true
            Trade.renderActive(payload)
        elseif payload.Kind == "closed" then
            Trade.renderPlayerList()
        end
    end)
end

function Trade.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled and snapshot == nil then
        Trade.renderPlayerList()
    end
end

return Trade
