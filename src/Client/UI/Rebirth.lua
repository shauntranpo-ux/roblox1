-- Rebirth: the prestige panel. Shows rebirth count, current + next prestige multiplier, the cash
-- requirement with LIVE progress (reactive to the replicated Cash attribute), and a Rebirth button
-- gated behind a clear confirmation that states what is LOST vs KEPT. The client only REQUESTS a
-- rebirth; the server validates eligibility + performs the atomic reset.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local RebirthConfig = require(Shared:WaitForChild("RebirthConfig"))

local Rebirth = {}

local player = nil
local remotes = nil
local gui = nil
local infoLabel = nil
local reqLabel = nil
local progressFill = nil
local statusLabel = nil
local rebirthButton = nil
local confirmFrame = nil

local function cash()
    return player:GetAttribute("Cash") or 0
end
local function count()
    return player:GetAttribute("RebirthCount") or 0
end
local function prestige()
    return player:GetAttribute("PrestigeMultiplier") or 1
end

local function refresh()
    local c = count()
    local req = RebirthConfig.RequirementFor(c)
    infoLabel.Text = string.format(
        "Rebirths: %d\nIncome bonus: x%.2g  →  next: x%.2g",
        c,
        prestige(),
        RebirthConfig.MultiplierFor(c + 1)
    )
    reqLabel.Text = "Requirement: $" .. Format.short(req)
    local pct = math.clamp(cash() / req, 0, 1)
    progressFill.Size = UDim2.fromScale(pct, 1)
    local eligible = cash() >= req
    rebirthButton.Active = eligible
    rebirthButton.AutoButtonColor = eligible
    rebirthButton.BackgroundColor3 = eligible and Theme.Colors.Positive or Theme.Colors.Disabled
    rebirthButton.Text = eligible and "REBIRTH" or ("Need $" .. Format.short(req))
end

local function doRebirth()
    confirmFrame.Visible = false
    local ok, result = pcall(function()
        return remotes.RequestRebirth:InvokeServer()
    end)
    if ok and type(result) == "table" then
        statusLabel.Text = result.Message
        statusLabel.TextColor3 = result.Result == "Success" and Theme.Colors.Positive
            or Theme.Colors.Danger
    else
        statusLabel.Text = "Rebirth failed -- try again."
        statusLabel.TextColor3 = Theme.Colors.Danger
    end
end

function Rebirth.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Rebirth", player:WaitForChild("PlayerGui"), false)

    local list = Builder.panel(gui, "Rebirth", function()
        gui.Enabled = false
    end)

    local card = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 250),
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = 1,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(14) })

    infoLabel = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 0),
        Size = UDim2.new(1, -4, 0, 60),
        BackgroundTransparency = 1,
        Font = Theme.FontBold,
        Text = "",
        TextColor3 = Theme.Colors.Ink,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = card,
    })

    reqLabel = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 68),
        Size = UDim2.new(1, -4, 0, 22),
        BackgroundTransparency = 1,
        Font = Theme.Font,
        Text = "",
        TextColor3 = Theme.Colors.InkSoft,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    local progressBg = Builder.create("Frame", {
        Position = UDim2.fromOffset(2, 96),
        Size = UDim2.new(1, -4, 0, 18),
        BackgroundColor3 = Theme.Colors.Background,
        BorderSizePixel = 0,
        Parent = card,
    }, { Builder.corner(UDim.new(0, 8)) })
    progressFill = Builder.create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Parent = progressBg,
    }, { Builder.corner(UDim.new(0, 8)) })

    rebirthButton = Builder.create("TextButton", {
        Position = UDim2.fromOffset(2, 124),
        Size = UDim2.new(1, -4, 0, 52),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = "REBIRTH",
        TextColor3 = Theme.Colors.Text,
        TextSize = 22,
        Parent = card,
    }, { Builder.corner(UDim.new(0, 10)) })

    statusLabel = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 184),
        Size = UDim2.new(1, -4, 0, 44),
        BackgroundTransparency = 1,
        Font = Theme.Font,
        Text = "Reset cash + brainrots for a permanent income boost.",
        TextColor3 = Theme.Colors.InkSoft,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = card,
    })
    card.Parent = list

    -- Confirmation overlay (hidden until the player taps Rebirth).
    confirmFrame = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.96, 0.5),
        BackgroundColor3 = Theme.Colors.Panel,
        BorderSizePixel = 0,
        Visible = false,
        Parent = gui,
    }, {
        Builder.corner(UDim.new(0, 16)),
        Builder.padding(16),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(520, 360) }),
    })
    Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 0.6),
        BackgroundTransparency = 1,
        Font = Theme.FontBold,
        Text = "Rebirth?\n\nYOU LOSE: all cash + your placed brainrots.\nYOU KEEP: gamepasses, purchases, premium units, pads, your collection — and gain a PERMANENT income boost.",
        TextColor3 = Theme.Colors.Ink,
        TextSize = 17,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = confirmFrame,
    })
    local yes = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(0.48, 0, 0, 50),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = "Yes, rebirth",
        TextColor3 = Theme.Colors.Text,
        TextSize = 18,
        Parent = confirmFrame,
    }, { Builder.corner(UDim.new(0, 10)) })
    local no = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromScale(1, 1),
        Size = UDim2.new(0.48, 0, 0, 50),
        BackgroundColor3 = Theme.Colors.Danger,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = "Cancel",
        TextColor3 = Theme.Colors.Text,
        TextSize = 18,
        Parent = confirmFrame,
    }, { Builder.corner(UDim.new(0, 10)) })

    rebirthButton.Activated:Connect(function()
        if rebirthButton.Active then
            confirmFrame.Visible = true
        end
    end)
    yes.Activated:Connect(doRebirth)
    no.Activated:Connect(function()
        confirmFrame.Visible = false
    end)

    refresh()
    player:GetAttributeChangedSignal("Cash"):Connect(refresh)
    player:GetAttributeChangedSignal("RebirthCount"):Connect(refresh)
    player:GetAttributeChangedSignal("PrestigeMultiplier"):Connect(refresh)
end

function Rebirth.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        refresh()
    end
end

return Rebirth
