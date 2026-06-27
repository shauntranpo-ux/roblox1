-- UpgradesShop: the cash-sink UPGRADES panel. One row per upgrade — name + level, the current effect,
-- the next-level cost + a Buy button. The client sends INTENT only ({ Key }); the server (UpgradeService)
-- owns the atomic cash spend + applies the boost through the existing income/luck/catch channels. The
-- panel just reads state via GetUpgrades and re-fetches after each buy. Styling reuses the design system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)
local Notifications = require(script.Parent.Notifications)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local UpgradesShop = {}

local player, remotes, gui, list = nil, nil, nil, nil

local function clearRows()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

local function getState()
    local ok, result = pcall(function()
        return remotes.GetUpgrades:InvokeServer()
    end)
    if ok and type(result) == "table" and type(result.State) == "table" then
        return result.State
    end
    return nil
end

local function doBuy(key)
    local ok, result = pcall(function()
        return remotes.UpgradeAction:InvokeServer({ Key = key })
    end)
    if ok and type(result) == "table" then
        if result.Result == "Success" then
            Effects.playSfx("buy")
        elseif result.Message ~= nil then
            Notifications.show("error", result.Message)
        end
    end
    UpgradesShop.refresh()
end

local function label(text, color, size, font, order)
    return Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, size or 24),
        BackgroundTransparency = 1,
        Font = font or Theme.FontDisplay,
        Text = text,
        TextColor3 = color or Theme.Colors.Ink,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = order or 0,
        Parent = list,
    })
end

local function buildRow(order, up)
    local card = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 96),
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.padding(10) })
    Builder.rarityCard(card, Theme.accentColor("Upgrades"))

    local title = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -140, 0, 24),
        BackgroundTransparency = 1,
        Text = up.Icon .. "  " .. up.Name .. "   (Lv " .. up.Level .. "/" .. up.MaxLevel .. ")",
        TextColor3 = Theme.Colors.Ink,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = card,
    })
    Builder.styleText(title, { ink = true, keepColor = true })

    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 28),
        Size = UDim2.new(1, -140, 0, 44),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = up.Desc .. "\nNow: " .. up.Effect,
        TextColor3 = Theme.Colors.InkSoft,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    if up.NextCost == nil then
        local maxed = Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(120, 52),
            BackgroundTransparency = 1,
            Font = Theme.FontDisplay,
            Text = "MAX",
            TextColor3 = Theme.Colors.Gold,
            TextSize = 22,
            Parent = card,
        })
        Builder.styleText(maxed, { ink = true, keepColor = true })
    else
        Builder.glossButton({
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(124, 64),
            color = up.CanAfford and Theme.Colors.Positive or Theme.Colors.DarkPill,
            Text = "$" .. Format.short(up.NextCost),
            maxText = 18,
            Parent = card,
        }, function()
            doBuy(up.Key)
        end)
    end
    card.Parent = list
end

function UpgradesShop.refresh()
    if gui == nil then
        return
    end
    clearRows()
    local state = getState()
    if state == nil then
        label("Upgrades unavailable.", Theme.Colors.Danger, 26)
        return
    end
    label("Cash: $" .. Format.full(state.Cash), Theme.Colors.Gold, 28, Theme.FontDisplay, 0)
    label(
        "Spend cash on permanent boosts. They persist and stack with everything else.",
        Theme.Colors.InkSoft,
        34,
        Theme.FontBody,
        1
    )
    for i, up in ipairs(state.Upgrades) do
        buildRow(i + 1, up)
    end
end

function UpgradesShop.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("UpgradesShop", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Upgrades", function()
        gui.Enabled = false
    end)
end

function UpgradesShop.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        UpgradesShop.refresh()
    end
end

return UpgradesShop
