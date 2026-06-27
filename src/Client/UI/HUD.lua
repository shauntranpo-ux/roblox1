-- HUD (VM-THEME): the reference-matched heads-up display. Bottom-left STAT STACK (cash / HP-shield),
-- a left DIAMOND RAIL (shop + level-gated entries), a bottom-right LUCK counter, and the existing
-- bottom-center nav bar (panel access -- kept, restyled as the hotbar). Every element reads Theme +
-- Builder (single source) and binds to REAL replicated attributes, defaulting safely when one is
-- absent. The objective banner + minimap are their own modules. Mobile-first: scale + safe insets.
--
-- BINDINGS (all replicated player Attributes; default safely if missing):
--   Cash -> "Cash"            Level -> "RebirthCount"        Luck -> "Luck"
--   Shield -> "ShieldSeconds" / "ShieldMax"

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

    -- ===== BOTTOM-LEFT STAT PANEL (cash / HP-shield, grouped on a soft dark backing) =====
    local stack = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0.012, 0.86),
        Size = UDim2.fromScale(0.3, 0.2),
        BackgroundColor3 = Theme.Colors.DarkPill, -- grouped panel backing (was floating text)
        BackgroundTransparency = 0.22,
        BorderSizePixel = 0,
        Parent = gui,
    }, {
        Builder.corner(Theme.Radius.Card),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.White, Thickness = 2, Transparency = 0.45 }
        ),
        Builder.padding(8),
        Builder.create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
        }),
        Builder.create("UISizeConstraint", {
            MinSize = Vector2.new(200, 96),
            MaxSize = Vector2.new(330, 150),
        }),
    })
    Builder.softShadow(stack, { radius = Theme.Radius.Card, spread = 10 })

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

    -- ===== TOP-LEFT QUICK RAIL (shop + level-gated entries) -- distinct zone under the biome label,
    -- so it no longer collides with the centre-left EdgeTabs feature rail =====
    local rail = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromScale(0.012, 0.12),
        Size = UDim2.fromScale(0.34, 0.08),
        BackgroundTransparency = 1,
        Parent = gui,
    }, {
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Center,
        }),
        Builder.create(
            "UISizeConstraint",
            { MinSize = Vector2.new(280, 52), MaxSize = Vector2.new(440, 74) }
        ),
    })
    -- Top glossy CYAN "+" BUBBLE -> open the Shop (via the panel manager, if wired). The rail + the
    -- edge icon columns now share ONE shape language (Builder.iconBubble squircle), not diamonds.
    local _, _, plusContent = Builder.iconBubble({
        size = 60,
        LayoutOrder = 1,
        color = Theme.Colors.XpFill,
        Text = "+",
        maxText = 34,
        Parent = rail,
    }, actions ~= nil and actions.onShop or nil)
    Builder.bob(plusContent) -- gentle idle life on the icon glyph
    -- Level-gated bubbles (data-driven from Theme.DiamondRail).
    for i, entry in ipairs(Theme.DiamondRail) do
        local container, bubble, content = Builder.iconBubble({
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
            { entry = entry, frame = bubble, content = content, container = container }
        )
    end

    -- ===== BOTTOM-RIGHT INFO PANEL (luck / power / invite -- grouped on ONE backing, inset clear of
    -- the edge rail; was three separate floating pills) =====
    local rightInfo = Builder.create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -76, 0.88, 0),
        Size = UDim2.fromScale(0.17, 0.22),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.22,
        BorderSizePixel = 0,
        Parent = gui,
    }, {
        Builder.corner(Theme.Radius.Card),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.White, Thickness = 2, Transparency = 0.45 }
        ),
        Builder.padding(6),
        Builder.create("UIListLayout", {
            Padding = UDim.new(0, 5),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Center,
        }),
        Builder.create(
            "UISizeConstraint",
            { MinSize = Vector2.new(126, 120), MaxSize = Vector2.new(200, 196) }
        ),
    })
    Builder.softShadow(rightInfo, { radius = Theme.Radius.Card, spread = 10 })

    -- One info row: an icon on the left + a right-aligned white value. Returns the value label.
    local function infoRow(order, icon, iconColor, initial)
        local row = Builder.create("Frame", {
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = rightInfo,
        })
        Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.fromScale(0.02, 0.5),
            Size = UDim2.fromScale(0.3, 0.92),
            BackgroundTransparency = 1,
            Text = icon,
            TextColor3 = iconColor,
            TextScaled = true,
            Parent = row,
        })
        local value = Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(0.98, 0.5),
            Size = UDim2.fromScale(0.64, 0.92),
            BackgroundTransparency = 1,
            Text = initial,
            TextColor3 = Theme.Colors.White,
            TextScaled = true,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = row,
        }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 24 }) })
        Builder.styleText(value, { keepColor = true })
        return value
    end
    luckLabel = infoRow(1, "🍀", Theme.Colors.Clover, "x1")
    powerLabel = infoRow(2, "⚔️", Theme.Colors.PathRed, "0")
    inviteLabel = infoRow(3, "📨", Theme.Colors.Gold, "+0%")

    -- ===== BOTTOM-CENTER NAV BAR (a SOLID hotbar so the labels read clearly over the world) =====
    local bar = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -12), -- fixed 12px off the bottom (top sits ~90px up, predictable)
        Size = UDim2.fromScale(0.62, 0.1),
        BackgroundColor3 = Theme.Colors.DarkPill, -- solid dark hotbar (was transparent -> unreadable)
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        Parent = gui,
    }, {
        Builder.corner(Theme.Radius.Card),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.White, Thickness = 2, Transparency = 0.4 }
        ),
        Builder.padding(7),
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(540, 84) }),
    })
    Builder.softShadow(bar, { radius = Theme.Radius.Card, spread = 12 }) -- depth so it reads as a hotbar
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
            -- SOLID accent button (opaque; was glossify'd translucent -> unreadable). White Fredoka
            -- + outline reads clearly on the bright fill; the open panel's button brightens.
            local button = Builder.glossButton({
                LayoutOrder = order,
                Size = UDim2.fromScale(widthScale, 1),
                color = Theme.accentColor(def.accent),
                Text = def.label,
                radius = Theme.Radius.Bubble,
                maxText = 22,
                Parent = bar,
            }, def.click)
            button:SetAttribute("Accent", def.accent)
            button.BackgroundTransparency = 0.35 -- idle: muted (the dark bar shows through a touch)
            navButtons[def.key] = button
        end
    end
    PanelManager.onChange(function(active)
        for key, button in pairs(navButtons) do
            local on = key == active
            button.BackgroundColor3 = Theme.accentColor(button:GetAttribute("Accent"))
            button.BackgroundTransparency = on and 0 or 0.35 -- open panel's button = full bright accent
            local stroke = button:FindFirstChildOfClass("UIStroke")
            if stroke ~= nil then
                stroke.Transparency = on and 0 or 0.35
            end
        end
    end)

    -- ===== bindings =====
    local function refreshLevel()
        local level = readLevel()
        for _, d in ipairs(railDiamonds) do
            local locked = level < d.entry.UnlockLevel
            d.content.Text = locked and ("🔒\nLv." .. d.entry.UnlockLevel) or d.entry.Label
            d.frame.BackgroundColor3 = locked and Theme.Colors.DarkPill or Theme.Colors.XpFill
            d.frame.BackgroundTransparency = locked and 0.25 or 0.05
        end
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
