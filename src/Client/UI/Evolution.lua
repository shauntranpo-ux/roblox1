-- Evolution (M11.2): a FUNCTIONAL per-unit RAISE/EVOLVE panel. For each owned unit it shows the
-- current stage, an XP bar toward the next threshold, a preview of the next stage (income jump +
-- perk-tier bump + cash cost), and an Evolve button when ready. The client sends INTENT ONLY (which
-- unit Id to evolve); the server validates the threshold + cost and evolves atomically. (Styling is a
-- later look-pass -- shared components only.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))
local Format = require(Shared:WaitForChild("Format"))
local FusionConfig = require(Shared:WaitForChild("FusionConfig"))
local PerksConfig = require(Shared:WaitForChild("PerksConfig"))
local EvolutionConfig = require(Shared:WaitForChild("EvolutionConfig"))

local Evolution = {}

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
        TextColor3 = color or Theme.Colors.Text,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = list,
    })
end

local function starSuffix(star)
    return (star and star > 1) and ("  " .. FusionConfig.Stars(star)) or ""
end

local function getUnits()
    local ok, owned = pcall(function()
        return remotes.GetInventory:InvokeServer()
    end)
    if ok and typeof(owned) == "table" then
        return owned
    end
    return {}
end

local function doEvolve(unitId)
    local _, result = pcall(function()
        return remotes.EvolveRequest:InvokeServer(unitId)
    end)
    if type(result) == "table" then
        lastMessage = result.Message
    end
    Evolution.refresh()
end

-- One unit card: stage + XP bar + next-stage preview + evolve button.
local function unitCard(unit)
    local rarity = Rarity.Get(unit.Rarity)
    local stage = unit.EvolutionStage or 1
    local maxed = stage >= EvolutionConfig.MaxStage
    local threshold = EvolutionConfig.Threshold(stage)
    local evolvable = EvolutionConfig.CanEvolve(unit)

    local card = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 118),
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
    }, { Builder.padding(10) })
    Builder.rarityCard(card, rarity.Color)

    local title = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -116, 0, 22),
        BackgroundTransparency = 1,
        Text = "[S" .. stage .. "] " .. unit.Name .. starSuffix(unit.Star),
        TextColor3 = Theme.Colors.Ink,
        TextSize = 16,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    Builder.styleText(title, { ink = true, keepColor = true })

    -- Income now -> next stage (the income jump).
    local incomeText = "+$" .. Format.short(unit.IncomePerSec) .. "/s"
    if not maxed then
        local ratio = EvolutionConfig.IncomeMultiplier(stage + 1)
            / EvolutionConfig.IncomeMultiplier(stage)
        incomeText = incomeText
            .. "  ->  +$"
            .. Format.short(math.floor(unit.IncomePerSec * ratio))
            .. "/s"
    end
    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 26),
        Size = UDim2.new(1, -116, 0, 18),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = incomeText,
        TextColor3 = Theme.Colors.Positive,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    -- XP bar (or MAX STAGE).
    local barBg = Builder.create("Frame", {
        Position = UDim2.fromOffset(2, 50),
        Size = UDim2.new(1, -116, 0, 16),
        BackgroundColor3 = Theme.Colors.Background,
        BorderSizePixel = 0,
        Parent = card,
    }, { Builder.corner(UDim.new(1, 0)) })
    local barText
    if maxed then
        barText = "MAX STAGE"
    else
        local pct = threshold and threshold > 0 and math.clamp((unit.XP or 0) / threshold, 0, 1)
            or 0
        Builder.create("Frame", {
            Size = UDim2.fromScale(pct, 1),
            BackgroundColor3 = Theme.accentColor("Evolution"),
            BorderSizePixel = 0,
            Parent = barBg,
        }, { Builder.corner(UDim.new(1, 0)) })
        barText = "XP " .. Format.short(unit.XP or 0) .. " / " .. Format.short(threshold or 0)
    end
    Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = barText,
        TextColor3 = Theme.Colors.Ink,
        TextSize = 12,
        ZIndex = 2,
        Parent = barBg,
    })

    -- Next-stage preview: perk-tier bump + cost.
    if not maxed then
        local perkKey = PerksConfig.PerkForType(unit.Type)
        local perk = PerksConfig.Get(perkKey)
        local perkRatio = EvolutionConfig.PerkScale(stage + 1) / EvolutionConfig.PerkScale(stage)
        local cost = EvolutionConfig.EvolveCost(stage)
        Builder.create("TextLabel", {
            Position = UDim2.fromOffset(2, 70),
            Size = UDim2.new(1, -116, 0, 18),
            BackgroundTransparency = 1,
            Font = Theme.FontBody,
            Text = string.format(
                "Next: %s perk x%.2f%s",
                perk ~= nil and perk.Name or "perk",
                perkRatio,
                cost > 0 and ("  -  cost $" .. Format.full(cost)) or ""
            ),
            TextColor3 = Theme.Colors.InkSoft,
            TextSize = 13,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = card,
        })
    end

    -- Evolve button (enabled only when ready).
    Builder.glossButton({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(104, 72),
        color = evolvable and Theme.accentColor("Evolution") or Theme.Colors.Disabled,
        Text = maxed and "MAXED" or (evolvable and "EVOLVE" or "Locked"),
        maxText = 18,
        Parent = card,
    }, function()
        if evolvable then
            doEvolve(unit.Id)
        end
    end)

    card.Parent = list
end

function Evolution.refresh()
    if gui == nil then
        return
    end
    clearRows()
    order = 0

    if lastMessage ~= nil then
        label(lastMessage, Theme.Colors.Accent, 26, Theme.FontDisplay)
    end
    label(
        "Raise a unit: it banks XP as it earns. Evolve for a big income + perk jump. Stage & XP travel when stolen/traded.",
        Theme.Colors.InkSoft,
        34
    )

    local units = getUnits()
    if #units == 0 then
        label("No units yet.", Theme.Colors.InkSoft)
        return
    end
    for _, unit in ipairs(units) do
        unitCard(unit)
    end
end

function Evolution.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Evolution", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Evolution", function()
        gui.Enabled = false
    end)
end

function Evolution.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        lastMessage = nil
        Evolution.refresh()
    end
end

return Evolution
