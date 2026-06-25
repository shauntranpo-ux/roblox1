-- HUD: the persistent top-of-screen readout (Cash + Cash/sec) plus the Shop and
-- Inventory buttons. Mobile-first: Scale layout, large tap targets, safe-area aware.
-- Cash counts up smoothly toward the replicated value but never drifts from it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local HUD = {}

local player = nil
local cashLabel = nil
local rateLabel = nil
local displayedCash = 0
local targetCash = 0

local function readCash()
    return player:GetAttribute("Cash") or 0
end

local function readRate()
    return player:GetAttribute("IncomePerSec") or 0
end

local function makeButton(parent, text, order, onClick)
    local button = Builder.create("TextButton", {
        LayoutOrder = order,
        Size = UDim2.fromScale(0.42, 1),
        BackgroundColor3 = Theme.Colors.Accent,
        BorderSizePixel = 0,
        AutoButtonColor = true,
        Font = Theme.FontBold,
        Text = text,
        TextColor3 = Theme.Colors.Text,
        TextScaled = true,
        Parent = parent,
    }, {
        Builder.corner(UDim.new(0, 14)),
        Builder.padding(10),
        Builder.create("UITextSizeConstraint", { MaxTextSize = 26 }),
    })
    button.Activated:Connect(onClick)
    return button
end

function HUD.mount(context, actions)
    player = context.player
    local gui = Builder.screenGui("HUD", player:WaitForChild("PlayerGui"), true)

    -- Top-center cash pill.
    local pill = Builder.create("Frame", {
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

    makeButton(bar, "🛒 Shop", 1, actions.onShop)
    makeButton(bar, "🎒 Inventory", 2, actions.onInventory)

    -- Initial values + live listeners.
    targetCash = readCash()
    displayedCash = targetCash
    cashLabel.Text = "$" .. Format.short(displayedCash)
    rateLabel.Text = "+$" .. Format.short(readRate()) .. "/s"

    player:GetAttributeChangedSignal("Cash"):Connect(function()
        targetCash = readCash()
    end)
    player:GetAttributeChangedSignal("IncomePerSec"):Connect(function()
        rateLabel.Text = "+$" .. Format.short(readRate()) .. "/s"
    end)

    -- Smooth count-up toward the true value; snaps when within a dollar so it can never
    -- visually drift away from the authoritative number.
    RunService.RenderStepped:Connect(function(deltaTime)
        if displayedCash ~= targetCash then
            displayedCash += (targetCash - displayedCash) * math.min(1, deltaTime * 6)
            if math.abs(targetCash - displayedCash) < 1 then
                displayedCash = targetCash
            end
            cashLabel.Text = "$" .. Format.short(displayedCash)
        end
    end)
end

return HUD
