-- NetShop (M10.4): a FUNCTIONAL net-upgrade panel (via the existing panel manager + Theme). Shows the
-- current net tier + its catch bonuses, the next tier's bonuses + cash cost + an Upgrade action, and
-- the NON-RANDOM "Pro Net" gamepass with its DISCLOSED fixed bonus + a purchase prompt. The client
-- sends INTENT only; the server owns the tier + the effective catch params. Styling is the look-pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local NetShop = {}

local player = nil
local remotes = nil
local gui = nil
local list = nil
local order = 0
local lastMessage = nil

local function nextOrder()
    order += 1
    return order
end

local function clearRows()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

local function label(text, color, size, font)
    return Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, size or 22),
        BackgroundTransparency = 1,
        Font = font or Theme.FontBody,
        Text = text,
        TextColor3 = color or Theme.Colors.Ink,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = list,
    })
end

local function bonusText(b)
    if b == nil then
        return ""
    end
    return string.format(
        "hold -%d%%  ·  reach +%d  ·  flee-resist %d%%%s",
        math.floor((b.HoldReduce or 0) * 100 + 0.5),
        math.floor(b.RangeAdd or 0),
        math.floor((b.FleeResist or 0) * 100 + 0.5),
        (b.AutoCatch or 0) > 0 and ("  ·  auto " .. math.floor(b.AutoCatch * 100 + 0.5) .. "%")
            or ""
    )
end

local function getState()
    local ok, result = pcall(function()
        return remotes.NetAction:InvokeServer({ Action = "get" })
    end)
    if ok and type(result) == "table" and type(result.State) == "table" then
        return result.State
    end
    return nil
end

local function doUpgrade()
    local ok, result = pcall(function()
        return remotes.NetAction:InvokeServer({ Action = "upgrade" })
    end)
    if ok and type(result) == "table" then
        lastMessage = result.Message
        if result.Result == "Success" then
            Effects.playSfx("net_upgrade")
        end
    end
    NetShop.refresh()
end

function NetShop.refresh()
    if gui == nil then
        return
    end
    clearRows()
    order = 0
    if lastMessage ~= nil then
        label(lastMessage, Theme.Colors.Accent, 26, Theme.FontDisplay)
    end

    local state = getState()
    if state == nil then
        label("Net unavailable.", Theme.Colors.Danger)
        return
    end

    label(
        "Your net: "
            .. tostring(state.TierName)
            .. " (Tier "
            .. tostring(state.Tier)
            .. "/"
            .. tostring(state.MaxTier)
            .. ")",
        Theme.Colors.Ink,
        28,
        Theme.FontDisplay
    )
    label("Current: " .. bonusText(state.Bonuses), Theme.Colors.Positive)

    if state.Next ~= nil then
        local card = Builder.create("Frame", {
            Size = UDim2.new(1, 0, 0, 92),
            BorderSizePixel = 0,
            LayoutOrder = nextOrder(),
        }, { Builder.padding(10) })
        Builder.rarityCard(card, Theme.accentColor("NetShop"))
        local title = Builder.create("TextLabel", {
            Position = UDim2.fromOffset(2, 2),
            Size = UDim2.new(1, -120, 0, 24),
            BackgroundTransparency = 1,
            Text = "Next: " .. tostring(state.Next.Name),
            TextColor3 = Theme.Colors.Ink,
            TextSize = 17,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = card,
        })
        Builder.styleText(title, { ink = true, keepColor = true })
        Builder.create("TextLabel", {
            Position = UDim2.fromOffset(2, 28),
            Size = UDim2.new(1, -120, 0, 36),
            BackgroundTransparency = 1,
            Font = Theme.FontBody,
            Text = bonusText(state.Next) .. "\nCost: $" .. Format.full(state.Next.Cost or 0),
            TextColor3 = Theme.Colors.InkSoft,
            TextSize = 13,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = card,
        })
        Builder.glossButton({
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(104, 60),
            color = Theme.accentColor("NetShop"),
            Text = "Upgrade",
            maxText = 18,
            Parent = card,
        }, doUpgrade)
        card.Parent = list
    else
        label("Your net is MAX TIER!", Theme.Colors.Gold, 26, Theme.FontDisplay)
    end

    -- Pro Net gamepass (NON-RANDOM, disclosed fixed bonus).
    label("Pro Net (Gamepass)", Theme.Colors.Ink, 26, Theme.FontDisplay)
    local pn = state.ProNetBonus or {}
    label(
        state.HasProNet and "OWNED -- fixed bonus active."
            or string.format(
                "A permanent +%d%% hold + %d reach on EVERY catch (stacks under the caps).",
                math.floor((pn.HoldReduce or 0) * 100 + 0.5),
                math.floor(pn.RangeAdd or 0)
            ),
        state.HasProNet and Theme.Colors.Positive or Theme.Colors.InkSoft,
        34
    )
    if not state.HasProNet then
        Builder.glossButton({
            Size = UDim2.new(1, 0, 0, 46),
            color = Theme.Colors.Gold,
            Text = "Buy Pro Net (Robux)",
            maxText = 20,
            Parent = list,
            LayoutOrder = nextOrder(),
        }, function()
            if remotes.PromptGamepass ~= nil then
                remotes.PromptGamepass:FireServer("ProNet")
            end
        end)
    end
end

function NetShop.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("NetShop", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "NetShop", function()
        gui.Enabled = false
    end)
end

function NetShop.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        lastMessage = nil
        NetShop.refresh()
    end
end

return NetShop
