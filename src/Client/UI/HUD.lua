-- HUD: the persistent top-of-screen readout (Cash + Cash/sec) plus the Shop and
-- Inventory buttons. Mobile-first: Scale layout, large tap targets, safe-area aware.
-- Cash counts up smoothly toward the replicated value but never drifts from it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local HUD = {}

local player = nil
local pill = nil
local cashLabel = nil
local rateLabel = nil
local rateBase = nil
local displayedCash = 0
local targetCash = 0

local function readCash()
    return player:GetAttribute("Cash") or 0
end

local function readRate()
    return player:GetAttribute("IncomePerSec") or 0
end

-- Glossy nav button. Idle = muted grape; when its panel is open it lights up in that panel's accent
-- (driven by PanelManager.onChange). The press ripple + click sound are global (ClickFX).
local function makeNavButton(parent, label, accentKey, order, widthScale, onClick)
    local button = Builder.glossButton({
        LayoutOrder = order,
        Size = UDim2.fromScale(widthScale, 1),
        color = Theme.Colors.Disabled,
        Text = label,
        radius = UDim.new(0, 14),
        maxText = 22,
        Parent = parent,
    }, onClick)
    button:SetAttribute("Accent", accentKey)
    return button
end

local function setNavActive(button, active)
    local accentKey = button:GetAttribute("Accent")
    button.BackgroundColor3 = active and Theme.accentColor(accentKey) or Theme.Colors.Disabled
end

function HUD.mount(context, actions)
    player = context.player
    local gui = Builder.screenGui("HUD", player:WaitForChild("PlayerGui"), true)
    gui.DisplayOrder = 7 -- below the panels (10) so an open panel layers above the HUD cash pill

    -- Top-center cash pill.
    pill = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.02),
        Size = UDim2.fromScale(0.5, 0.11),
        BackgroundColor3 = Theme.Colors.Panel,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Parent = gui,
    }, {
        Builder.corner(UDim.new(0, 16)),
        Builder.create("UISizeConstraint", {
            MinSize = Vector2.new(170, 56),
            MaxSize = Vector2.new(420, 104),
        }),
    })

    cashLabel = Builder.create("TextLabel", {
        Name = "Cash",
        BackgroundTransparency = 1,
        Position = UDim2.fromScale(0, 0.06),
        Size = UDim2.fromScale(1, 0.58),
        Font = Theme.FontBold,
        Text = "$0",
        TextColor3 = Theme.Colors.Text,
        TextScaled = true,
        Parent = pill,
    }, { Builder.padding(4) })
    Builder.applyChrome(cashLabel) -- chunky display font + heavy dark outline (the big dopamine number)

    rateLabel = Builder.create("TextLabel", {
        Name = "Rate",
        BackgroundTransparency = 1,
        Position = UDim2.fromScale(0, 0.64),
        Size = UDim2.fromScale(1, 0.3),
        Font = Theme.Font,
        Text = "+$0/s",
        TextColor3 = Theme.Colors.Positive,
        TextScaled = true,
        Parent = pill,
    })
    Builder.applyChrome(rateLabel, { font = Theme.FontDisplay })
    rateBase = rateLabel.Size

    -- Bottom button bar (thumb-friendly on phones).
    local bar = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromScale(0.5, 0.98),
        Size = UDim2.fromScale(0.92, 0.1),
        BackgroundTransparency = 1,
        Parent = gui,
    }, {
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 12),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(560, 84) }),
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
    local widthScale = 1 / math.max(1, count) - 0.015
    local order = 0
    for _, def in ipairs(navDefs) do
        if def.click ~= nil then
            order += 1
            navButtons[def.key] =
                makeNavButton(bar, def.label, def.accent, order, widthScale, def.click)
        end
    end
    -- Highlight the nav button whose panel is currently open; revert when it closes.
    PanelManager.onChange(function(active)
        for key, button in pairs(navButtons) do
            setNavActive(button, key == active)
        end
    end)

    -- Initial values + live listeners.
    targetCash = readCash()
    displayedCash = targetCash
    cashLabel.Text = "$" .. Format.full(displayedCash)
    rateLabel.Text = "+$" .. Format.full(readRate()) .. "/s"

    player:GetAttributeChangedSignal("Cash"):Connect(function()
        targetCash = readCash()
    end)
    local prevRate = readRate()
    player:GetAttributeChangedSignal("IncomePerSec"):Connect(function()
        local r = readRate()
        rateLabel.Text = "+$" .. Format.full(r) .. "/s"
        -- Juice: punch the rate label whenever income goes UP (a buy / steal landing).
        if r > prevRate then
            rateLabel.Size = UDim2.new(
                rateBase.X.Scale * 1.18,
                rateBase.X.Offset,
                rateBase.Y.Scale * 1.18,
                rateBase.Y.Offset
            )
            TweenService:Create(rateLabel, TweenInfo.new(0.22, Enum.EasingStyle.Back), {
                Size = rateBase,
            }):Play()
        end
        prevRate = r
    end)

    -- Smooth count-up toward the true value; snaps when within a dollar so it can never
    -- visually drift away from the authoritative number.
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

-- Exposes the cash pill so the juice layer can punch it on big cash events.
function HUD.getCashPill()
    return pill
end

return HUD
