-- HUD (VM-THEME): the reference-matched heads-up display. Bottom-left STAT STACK (cash / HP-shield /
-- XP), a left DIAMOND RAIL (shop + level-gated entries), a bottom-right LUCK counter, and the existing
-- bottom-center nav bar (panel access -- kept, restyled as the hotbar). Every element reads Theme +
-- Builder (single source) and binds to REAL replicated attributes, defaulting safely when one is
-- absent. The objective banner + minimap are their own modules. Mobile-first: scale + safe insets.
--
-- BINDINGS (all replicated player Attributes; default safely if missing):
--   Cash -> "Cash"            Level -> "RebirthCount"        Luck -> "Luck"
--   Shield -> "ShieldSeconds" / "ShieldMax"   XP -> "PlayerXP" / "PlayerXPMax" (hook; defaults empty)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local HUD = {}

local player = nil
local cashRow = nil
local cashLabel = nil
local hpSet = nil
local xpSet = nil
local levelLabel = nil
local luckLabel = nil
local powerLabel = nil
local inviteLabel = nil
local railDiamonds = {} -- { entry, diamondFrame, contentLabel } for live lock updates
local displayedCash = 0
local targetCash = 0

-- ── safe attribute reads ──────────────────────────────────────────────────────────────────
local function attr(name, default)
    local v = player:GetAttribute(name)
    if type(v) == "number" then
        return v
    end
    return default
end

local function readLevel()
    return math.floor(attr("RebirthCount", 0))
end

-- ── stat-stack row builder (an icon chip + content, in a dark pill) ─────────────────────────
local function statRow(parent, order, icon, height)
    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, height or 34),
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = parent,
    })
    local iconLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(height or 34, height or 34),
        BackgroundTransparency = 1,
        Text = icon,
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Parent = row,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 26 }) })
    Builder.styleText(iconLabel, { keepColor = true })
    return row
end

function HUD.mount(context, actions)
    player = context.player
    local gui = Builder.screenGui("HUD", player:WaitForChild("PlayerGui"), true)
    gui.DisplayOrder = 7 -- below panels (10) so an open panel layers above

    -- ===== BOTTOM-LEFT STAT STACK (cash / HP-shield / XP) =====
    local stack = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0.012, 0.86),
        Size = UDim2.fromScale(0.3, 0.2),
        BackgroundTransparency = 1,
        Parent = gui,
    }, {
        Builder.create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
        }),
        Builder.create("UISizeConstraint", {
            MinSize = Vector2.new(190, 110),
            MaxSize = Vector2.new(330, 190),
        }),
    })

    -- (a) CASH -- gold coin + bold gold "$<amount>".
    cashRow = statRow(stack, 1, "🪙", 40)
    cashLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0.26, 0.5),
        Size = UDim2.fromScale(0.74, 1),
        BackgroundTransparency = 1,
        Text = "$0",
        TextColor3 = Theme.Colors.Gold,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = cashRow,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 30 }) })
    Builder.styleText(cashLabel, { keepColor = true })

    -- (b) HP / SHIELD -- shield icon + green glossy bar "<cur>/<max>".
    local hpRow = statRow(stack, 2, "🛡", 30)
    local _, hpSetFn = Builder.statBar({
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0.26, 0.5),
        Size = UDim2.fromScale(0.74, 0.8),
        fillTop = Theme.Colors.HpFill,
        fillBottom = Theme.Colors.HpFillDark,
        Parent = hpRow,
    })
    hpSet = hpSetFn

    -- (c) XP -- cyan level badge + cyan bar "<cur>/<max>".
    local xpRow = statRow(stack, 3, "", 30)
    local badge = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = Theme.Colors.XpFill,
        BorderSizePixel = 0,
        Parent = xpRow,
    }, {
        Builder.corner(UDim.new(0, 8)),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.White, Thickness = 2, Transparency = 0.15 }
        ),
    })
    levelLabel = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "0",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Parent = badge,
    }, { Builder.padding(3) })
    Builder.styleText(levelLabel, { keepColor = true })
    local _, xpSetFn = Builder.statBar({
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0.26, 0.5),
        Size = UDim2.fromScale(0.74, 0.8),
        fillTop = Theme.Colors.XpFill,
        fillBottom = Theme.Colors.XpFillDark,
        Parent = xpRow,
    })
    xpSet = xpSetFn

    -- ===== LEFT DIAMOND RAIL (shop + level-gated entries) =====
    local rail = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0.012, 0.46),
        Size = UDim2.fromScale(0.08, 0.5),
        BackgroundTransparency = 1,
        Parent = gui,
    }, {
        Builder.create("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        }),
        Builder.create(
            "UISizeConstraint",
            { MinSize = Vector2.new(56, 0), MaxSize = Vector2.new(76, 520) }
        ),
    })
    -- Top glossy CYAN "+" diamond -> open the Shop (via the panel manager, if wired).
    Builder.diamond({
        size = 60,
        LayoutOrder = 1,
        color = Theme.Colors.XpFill,
        Text = "+",
        maxText = 34,
        Parent = rail,
    }, actions ~= nil and actions.onShop or nil)
    -- Level-gated diamonds (data-driven from Theme.DiamondRail).
    for i, entry in ipairs(Theme.DiamondRail) do
        local container, diamond, content = Builder.diamond({
            size = 58,
            LayoutOrder = i + 1,
            color = Theme.Colors.DarkPill,
            Text = "",
            maxText = 18,
            Parent = rail,
        }, function()
            -- Unlocked entries are tappable; placeholder action opens the shop until a dedicated panel
            -- is wired here. Locked entries do nothing (global ClickFX still plays the click sound).
            if readLevel() >= entry.UnlockLevel and actions ~= nil and actions.onShop ~= nil then
                actions.onShop()
            end
        end)
        table.insert(
            railDiamonds,
            { entry = entry, diamond = diamond, content = content, container = container }
        )
    end

    -- ===== BOTTOM-RIGHT LUCK =====
    local luckPill = Builder.pill({
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromScale(0.988, 0.86),
        Size = UDim2.fromScale(0.16, 0.07),
        radius = UDim.new(0, 14),
        Parent = gui,
    })
    Builder.create(
        "UISizeConstraint",
        { MinSize = Vector2.new(96, 40), MaxSize = Vector2.new(190, 70), Parent = luckPill }
    )
    Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0.04, 0.5),
        Size = UDim2.fromScale(0.34, 0.8),
        BackgroundTransparency = 1,
        Text = "🍀",
        TextColor3 = Theme.Colors.Clover,
        TextScaled = true,
        Parent = luckPill,
    })
    luckLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(0.96, 0.5),
        Size = UDim2.fromScale(0.6, 0.8),
        BackgroundTransparency = 1,
        Text = "x1",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = luckPill,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 26 }) })
    Builder.styleText(luckLabel, { keepColor = true })

    -- ===== BOTTOM-RIGHT TEAM POWER (M11.3-combat: combat strength of the equipped team) =====
    local powerPill = Builder.pill({
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromScale(0.988, 0.78),
        Size = UDim2.fromScale(0.16, 0.07),
        radius = UDim.new(0, 14),
        Parent = gui,
    })
    Builder.create(
        "UISizeConstraint",
        { MinSize = Vector2.new(96, 40), MaxSize = Vector2.new(190, 70), Parent = powerPill }
    )
    Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0.04, 0.5),
        Size = UDim2.fromScale(0.34, 0.8),
        BackgroundTransparency = 1,
        Text = "⚔️",
        TextColor3 = Theme.Colors.PathRed,
        TextScaled = true,
        Parent = powerPill,
    })
    powerLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(0.96, 0.5),
        Size = UDim2.fromScale(0.6, 0.8),
        BackgroundTransparency = 1,
        Text = "0",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = powerPill,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 26 }) })
    Builder.styleText(powerLabel, { keepColor = true })

    -- ===== BOTTOM-RIGHT INVITE BOOST (M13.1: "+X% Invite Friends") =====
    local invitePill = Builder.pill({
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromScale(0.988, 0.70),
        Size = UDim2.fromScale(0.16, 0.07),
        radius = UDim.new(0, 14),
        Parent = gui,
    })
    Builder.create(
        "UISizeConstraint",
        { MinSize = Vector2.new(96, 40), MaxSize = Vector2.new(190, 70), Parent = invitePill }
    )
    Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0.04, 0.5),
        Size = UDim2.fromScale(0.34, 0.8),
        BackgroundTransparency = 1,
        Text = "📨",
        TextColor3 = Theme.Colors.Gold,
        TextScaled = true,
        Parent = invitePill,
    })
    inviteLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(0.96, 0.5),
        Size = UDim2.fromScale(0.6, 0.8),
        BackgroundTransparency = 1,
        Text = "+0%",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = invitePill,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 26 }) })
    Builder.styleText(inviteLabel, { keepColor = true })

    -- ===== BOTTOM-CENTER NAV BAR (panel access -- kept; restyled as the hotbar) =====
    local bar = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromScale(0.5, 0.98),
        Size = UDim2.fromScale(0.62, 0.1),
        BackgroundTransparency = 1,
        Parent = gui,
    }, {
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 10),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(520, 78) }),
    })
    local navDefs = {
        { key = "Shop", label = "Shop", accent = "Shop", click = actions.onShop },
        { key = "Inventory", label = "Items", accent = "Inventory", click = actions.onInventory },
        { key = "Index", label = "Index", accent = "Index", click = actions.onIndex },
        { key = "Menu", label = "Menu", accent = "Menu", click = actions.onMenu },
    }
    local navButtons = {}
    local count = 0
    for _, def in ipairs(navDefs) do
        if def.click ~= nil then
            count += 1
        end
    end
    local widthScale = 1 / math.max(1, count) - 0.02
    local order = 0
    for _, def in ipairs(navDefs) do
        if def.click ~= nil then
            order += 1
            local button = Builder.glossButton({
                LayoutOrder = order,
                Size = UDim2.fromScale(widthScale, 1),
                color = Theme.Colors.DarkPill,
                Text = def.label,
                radius = UDim.new(0, 14),
                maxText = 22,
                Parent = bar,
            }, def.click)
            button:SetAttribute("Accent", def.accent)
            navButtons[def.key] = button
        end
    end
    PanelManager.onChange(function(active)
        for key, button in pairs(navButtons) do
            button.BackgroundColor3 = key == active
                    and Theme.accentColor(button:GetAttribute("Accent"))
                or Theme.Colors.DarkPill
        end
    end)

    -- ===== bindings =====
    local function refreshLevel()
        local level = readLevel()
        levelLabel.Text = tostring(level)
        for _, d in ipairs(railDiamonds) do
            local locked = level < d.entry.UnlockLevel
            d.content.Text = locked and ("🔒\nLv." .. d.entry.UnlockLevel) or d.entry.Label
            d.diamond.BackgroundColor3 = locked and Theme.Colors.DarkPill or Theme.Colors.XpFill
            d.diamond.BackgroundTransparency = locked and 0.25 or 0.1
        end
        xpSet(attr("PlayerXP", 0), attr("PlayerXPMax", Theme.Hud.XpFallbackMax))
    end
    local function refreshShield()
        hpSet(
            attr("ShieldSeconds", 0),
            attr("ShieldMax", Theme.Hud.ShieldDisplayMax),
            math.floor(attr("ShieldSeconds", 0))
                .. " / "
                .. math.floor(attr("ShieldMax", Theme.Hud.ShieldDisplayMax))
        )
    end
    local function refreshLuck()
        luckLabel.Text = string.format("x%.2g", math.max(1, attr("Luck", 1)))
    end
    local function refreshPower()
        powerLabel.Text = Format.short(math.max(0, attr("Power", 0)))
    end
    local function refreshInvite()
        inviteLabel.Text = "+" .. math.floor(math.max(0, attr("InviteBoost", 0))) .. "%"
    end

    targetCash = attr("Cash", 0)
    displayedCash = targetCash
    cashLabel.Text = "$" .. Format.full(displayedCash)
    refreshLevel()
    refreshShield()
    refreshLuck()
    refreshPower()
    refreshInvite()

    player:GetAttributeChangedSignal("Cash"):Connect(function()
        targetCash = attr("Cash", 0)
    end)
    player:GetAttributeChangedSignal("RebirthCount"):Connect(refreshLevel)
    player:GetAttributeChangedSignal("PlayerXP"):Connect(refreshLevel)
    player:GetAttributeChangedSignal("ShieldSeconds"):Connect(refreshShield)
    player:GetAttributeChangedSignal("ShieldMax"):Connect(refreshShield)
    player:GetAttributeChangedSignal("Luck"):Connect(refreshLuck)
    player:GetAttributeChangedSignal("Power"):Connect(refreshPower)
    player:GetAttributeChangedSignal("InviteBoost"):Connect(refreshInvite)

    -- Smooth cash count-up toward the true value; snaps within a dollar so it never drifts.
    RunService.RenderStepped:Connect(function(deltaTime)
        if displayedCash ~= targetCash then
            displayedCash += (targetCash - displayedCash) * math.min(1, deltaTime * 6)
            if math.abs(targetCash - displayedCash) < 1 then
                displayedCash = targetCash
            end
            cashLabel.Text = "$" .. Format.full(displayedCash)
        end
    end)
end

-- Exposes the cash row so the juice layer can punch it on big cash events.
function HUD.getCashPill()
    return cashRow
end

return HUD
