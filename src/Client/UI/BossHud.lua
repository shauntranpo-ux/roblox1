-- BossHud (M11.3): the FUNCTIONAL world-boss HUD. Renders ONLY from server BossUpdate broadcasts --
-- a spawn alert banner, a live catch-meter bar + countdown while a boss is active, an on-screen
-- direction marker toward the boss, and a defeat/flee outcome banner. The client asserts NOTHING about
-- the boss's HP/contribution/death -- it just draws what the server sends. (Styling is a later pass.)

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local BossHud = {}

local gui = nil
local alertLabel = nil
local barFrame = nil
local nameLabel = nil
local fillFrame = nil
local timerLabel = nil
local marker = nil

local bossPos = nil
local active = false
local alertToken = 0

local function setBar(meter, maxMeter)
    if fillFrame == nil then
        return
    end
    local pct = (type(meter) == "number" and type(maxMeter) == "number" and maxMeter > 0)
            and math.clamp(meter / maxMeter, 0, 1)
        or 0
    fillFrame.Size = UDim2.fromScale(pct, 1)
end

local function showAlert(text)
    if alertLabel == nil then
        return
    end
    alertLabel.Text = text
    alertLabel.Visible = true
    alertToken += 1
    local token = alertToken
    task.delay(6, function()
        if token == alertToken and alertLabel ~= nil then
            alertLabel.Visible = false
        end
    end)
end

local function hideBoss()
    active = false
    bossPos = nil
    if barFrame ~= nil then
        barFrame.Visible = false
    end
    if marker ~= nil then
        marker.Visible = false
    end
end

-- Server -> client dispatch.
function BossHud.onUpdate(payload)
    local kind = payload.Kind
    if kind == "spawn" then
        showAlert(
            "A TITAN "
                .. tostring(payload.Name)
                .. " has appeared in "
                .. tostring(payload.Biome or "the world")
                .. "!"
        )
        if nameLabel ~= nil then
            nameLabel.Text = "TITAN " .. tostring(payload.Name or "")
        end
        setBar(payload.Meter, payload.Max)
        if timerLabel ~= nil then
            timerLabel.Text = math.ceil(payload.TimeLeft or 0) .. "s"
        end
        bossPos = payload.Pos
        active = true
        if barFrame ~= nil then
            barFrame.Visible = true
        end
        if marker ~= nil then
            marker.Visible = true
        end
    elseif kind == "update" then
        setBar(payload.Meter, payload.Max)
        if timerLabel ~= nil then
            timerLabel.Text = math.ceil(payload.TimeLeft or 0) .. "s"
        end
        if payload.Pos ~= nil then
            bossPos = payload.Pos
        end
    elseif kind == "defeat" then
        showAlert(
            "The "
                .. tostring(payload.Name or "Titan")
                .. " was DEFEATED!  ("
                .. tostring(payload.Participants or 0)
                .. " hunters paid out)"
        )
        hideBoss()
    elseif kind == "flee" then
        showAlert(
            "The " .. tostring(payload.Name or "Titan") .. " fled before it could be caught..."
        )
        hideBoss()
    elseif kind == "gone" then
        hideBoss()
    end
end

-- Keeps the direction marker pointing at the boss (clamped to the screen edges), with distance.
local function updateMarker()
    if not active or bossPos == nil or marker == nil then
        return
    end
    local camera = Workspace.CurrentCamera
    if camera == nil then
        return
    end
    local viewport = camera.ViewportSize
    local screen = camera:WorldToViewportPoint(bossPos)
    local dist = (camera.CFrame.Position - bossPos).Magnitude
    local x, y = screen.X, screen.Y
    if screen.Z <= 0 then
        -- behind the camera: pin to the bottom, flipped horizontally
        x = viewport.X - x
        y = viewport.Y - 60
    end
    x = math.clamp(x, 40, viewport.X - 40)
    y = math.clamp(y, 70, viewport.Y - 50)
    marker.Position = UDim2.fromOffset(x, y)
    marker.Text = "▾ TITAN  " .. math.floor(dist) .. "m"
    marker.Visible = true -- active boss -> always show the marker (the early-return handles inactive)
end

function BossHud.mount(context)
    local player = context.player
    gui = Builder.screenGui("BossHud", player:WaitForChild("PlayerGui"), true)

    alertLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 8),
        Size = UDim2.fromOffset(720, 44),
        BackgroundColor3 = Color3.fromRGB(150, 30, 50),
        BackgroundTransparency = 0.1,
        Font = Theme.FontDisplay,
        Text = "",
        TextColor3 = Color3.fromRGB(255, 240, 200),
        TextScaled = true,
        Visible = false,
        Parent = gui,
    }, { Builder.corner(UDim.new(0, 10)), Builder.padding(6) })

    barFrame = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 58),
        Size = UDim2.fromOffset(420, 40),
        BackgroundColor3 = Color3.fromRGB(20, 14, 30),
        BackgroundTransparency = 0.2,
        Visible = false,
        Parent = gui,
    }, { Builder.corner(UDim.new(0, 8)), Builder.padding(4) })

    nameLabel = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 0),
        Size = UDim2.new(1, -4, 0, 14),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = "TITAN",
        TextColor3 = Color3.fromRGB(255, 230, 120),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = barFrame,
    })

    local barBg = Builder.create("Frame", {
        Position = UDim2.fromOffset(2, 16),
        Size = UDim2.new(1, -4, 0, 16),
        BackgroundColor3 = Color3.fromRGB(40, 28, 52),
        BorderSizePixel = 0,
        Parent = barFrame,
    }, { Builder.corner(UDim.new(1, 0)) })

    fillFrame = Builder.create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(230, 70, 90),
        BorderSizePixel = 0,
        Parent = barBg,
    }, { Builder.corner(UDim.new(1, 0)) })

    timerLabel = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = "",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 12,
        ZIndex = 2,
        Parent = barBg,
    })

    marker = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(150, 26),
        BackgroundColor3 = Color3.fromRGB(150, 30, 50),
        BackgroundTransparency = 0.25,
        Font = Theme.FontDisplay,
        Text = "▾ TITAN",
        TextColor3 = Color3.fromRGB(255, 240, 200),
        TextSize = 14,
        Visible = false,
        Parent = gui,
    }, { Builder.corner(UDim.new(0, 8)) })

    RunService.RenderStepped:Connect(updateMarker)
end

return BossHud
