-- Settings: a tiny, mobile-friendly preference panel (Music / SFX / Screen Shake), reached from
-- the HUD gear button. Pulls the saved values from the server on mount and writes changes back
-- through SaveSettings (validated server-side). Preferences are presentational only.

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Settings = {}

local DEFAULTS = { Music = false, SFX = true, Shake = true }

local player = nil
local remotes = nil
local gui = nil
local current = { Music = false, SFX = true, Shake = true }
local onChanged = nil
local buttons = {} -- [key] = TextButton

local function sanitize(data)
    local out = {}
    for key, default in pairs(DEFAULTS) do
        local value = type(data) == "table" and data[key]
        out[key] = type(value) == "boolean" and value or default
    end
    return out
end

local function setVisual(button, on)
    button.Text = on and "ON" or "OFF"
    button.BackgroundColor3 = on and Theme.Colors.Positive or Theme.Colors.Disabled
    button.TextColor3 = on and Theme.Colors.Text or Theme.Colors.SubText
end

local function buildToggle(parent, key, label, order)
    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 62),
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(10) })

    Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(6, 0),
        Size = UDim2.new(1, -120, 1, 0),
        Font = Theme.FontBold,
        Text = label,
        TextColor3 = Theme.Colors.Text,
        TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local button = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(92, 44),
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        TextSize = 18,
        AutoButtonColor = true,
        Parent = row,
    }, { Builder.corner(UDim.new(0, 10)) })

    setVisual(button, current[key])
    button.Activated:Connect(function()
        current[key] = not current[key]
        setVisual(button, current[key])
        remotes.SaveSettings:FireServer(current)
        if onChanged ~= nil then
            onChanged(current)
        end
    end)

    buttons[key] = button
    row.Parent = parent
end

function Settings.mount(context, opts)
    player = context.player
    remotes = context.remotes
    onChanged = opts and opts.onChanged
    gui = Builder.screenGui("Settings", player:WaitForChild("PlayerGui"), false)

    -- Pull saved prefs (safe fallback to defaults on any failure).
    local ok, saved = pcall(function()
        return remotes.GetSettings:InvokeServer()
    end)
    current = sanitize(ok and saved or nil)

    local list = Builder.panel(gui, "Settings", function()
        gui.Enabled = false
    end)

    buildToggle(list, "Music", "Music", 1)
    buildToggle(list, "SFX", "Sound Effects", 2)
    buildToggle(list, "Shake", "Screen Shake", 3)

    -- Apply the loaded prefs immediately (music/shake state).
    if onChanged ~= nil then
        onChanged(current)
    end
end

function Settings.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
end

return Settings
