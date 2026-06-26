-- Codes: a small code-redemption panel reachable from the HUD. The client sends ONLY the typed
-- string to the server's RedeemCode RemoteFunction and renders the precise result enum it returns
-- (Success / AlreadyRedeemed / Invalid / Expired / Inactive / Error). No client authority.

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Codes = {}

local player = nil
local remotes = nil
local gui = nil
local input = nil
local resultLabel = nil
local redeemButton = nil

-- Result enum -> colour for the feedback line.
local RESULT_COLORS = {
    Success = Theme.Colors.Positive,
    AlreadyRedeemed = Theme.Colors.Accent,
    Invalid = Theme.Colors.Danger,
    Expired = Theme.Colors.Danger,
    Inactive = Theme.Colors.Danger,
    Error = Theme.Colors.InkSoft,
}

local function doRedeem()
    local raw = input.Text
    if raw == nil or raw == "" then
        resultLabel.Text = "Enter a code first."
        resultLabel.TextColor3 = Theme.Colors.InkSoft
        return
    end
    -- Debounce the button while the server answers (also rate-limited server-side).
    redeemButton.Active = false
    redeemButton.AutoButtonColor = false
    local ok, result = pcall(function()
        return remotes.RedeemCode:InvokeServer(raw)
    end)
    redeemButton.Active = true
    redeemButton.AutoButtonColor = true

    if ok and type(result) == "table" and type(result.Message) == "string" then
        resultLabel.Text = result.Message
        resultLabel.TextColor3 = RESULT_COLORS[result.Result] or Theme.Colors.Ink
        if result.Result == "Success" then
            input.Text = ""
        end
    else
        resultLabel.Text = "Something went wrong -- try again."
        resultLabel.TextColor3 = Theme.Colors.Danger
    end
end

function Codes.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Codes", player:WaitForChild("PlayerGui"), false)

    local list = Builder.panel(gui, "Codes", function()
        gui.Enabled = false
    end)

    local card = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 188),
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = 1,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(14) })

    Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(2, 0),
        Size = UDim2.new(1, -4, 0, 26),
        Font = Theme.FontBold,
        Text = "Enter a code",
        TextColor3 = Theme.Colors.Ink,
        TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    input = Builder.create("TextBox", {
        Position = UDim2.fromOffset(2, 36),
        Size = UDim2.new(1, -4, 0, 50),
        BackgroundColor3 = Theme.Colors.Background,
        BorderSizePixel = 0,
        Font = Theme.Font,
        PlaceholderText = "e.g. LAUNCH",
        Text = "",
        TextColor3 = Theme.Colors.Ink,
        PlaceholderColor3 = Theme.Colors.InkSoft,
        TextSize = 20,
        ClearTextOnFocus = false,
        Parent = card,
    }, { Builder.corner(UDim.new(0, 10)), Builder.padding(10) })

    redeemButton = Builder.create("TextButton", {
        Position = UDim2.fromOffset(2, 96),
        Size = UDim2.new(1, -4, 0, 50),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = "Redeem",
        TextColor3 = Theme.Colors.Text,
        TextSize = 20,
        Parent = card,
    }, { Builder.corner(UDim.new(0, 10)) })

    resultLabel = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 152),
        Size = UDim2.new(1, -4, 0, 24),
        BackgroundTransparency = 1,
        Font = Theme.Font,
        Text = "",
        TextColor3 = Theme.Colors.InkSoft,
        TextSize = 16,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    redeemButton.Activated:Connect(doRedeem)
    input.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            doRedeem()
        end
    end)

    card.Parent = list
end

function Codes.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
end

return Codes
