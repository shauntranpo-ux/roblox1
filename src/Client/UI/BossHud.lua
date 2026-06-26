-- BossHud (M11.3-combat): the FUNCTIONAL world-boss HUD. Renders ONLY from server BossUpdate broadcasts
-- -- a spawn alert banner, a live HP bar + countdown while a boss is active, an on-screen direction
-- marker, damage NUMBERS popping when YOUR attacks land (pooled + capped), and a defeat/flee outcome +
-- death spectacle. The client asserts NOTHING about the boss's HP/damage/death -- it just draws what the
-- server sends (the server computes power/damage). Degrades silently if asset ids are missing.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local BossHud = {}

local NUMBER_POOL_SIZE = 14 -- max concurrent damage numbers (capped -> no spike in a crowded fight)
local HIT_SFX_INTERVAL = 0.12 -- s: throttle the per-hit sound (attacks fire faster than this)

local gui = nil
local alertLabel = nil
local barFrame = nil
local nameLabel = nil
local bossSet = nil -- progressBar setter for the boss HP bar
local timerLabel = nil
local marker = nil
local numberPool = {} -- { label, busy } recycled damage-number labels
local lastHitSfx = 0

local bossPos = nil
local active = false
local alertToken = 0

local function setBar(meter, maxMeter)
    if bossSet == nil then
        return
    end
    -- progressBar clamps + tweens the fill (gloss sweep is automatic); the timer is a separate overlay.
    bossSet(meter, maxMeter, "")
end

-- Pop a pooled damage number at the boss's screen position (recycled labels; capped; graceful if the
-- boss is behind the camera or the pool is exhausted -> just skip, no spike).
local function popNumber(damage, worldPos)
    if gui == nil or worldPos == nil or type(damage) ~= "number" then
        return
    end
    local camera = Workspace.CurrentCamera
    if camera == nil then
        return
    end
    local screen = camera:WorldToViewportPoint(worldPos)
    if screen.Z <= 0 then
        return -- behind the camera
    end
    local slot = nil
    for _, entry in ipairs(numberPool) do
        if not entry.busy then
            slot = entry
            break
        end
    end
    if slot == nil then
        return -- pool exhausted -> drop this number (cap; never spikes)
    end
    slot.busy = true
    local label = slot.label
    label.Text = "-" .. Format.short(damage)
    label.TextTransparency = 0
    label.TextStrokeTransparency = 0.4
    local jitter = math.random(-30, 30)
    label.Position = UDim2.fromOffset(screen.X + jitter, screen.Y + math.random(-10, 10))
    label.Visible = true
    local tween = TweenService:Create(label, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {
        Position = UDim2.fromOffset(screen.X + jitter, screen.Y - 70),
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    })
    tween.Completed:Connect(function()
        label.Visible = false
        slot.busy = false
    end)
    tween:Play()
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
        setBar(payload.HP, payload.Max)
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
        setBar(payload.HP, payload.Max)
        if timerLabel ~= nil then
            timerLabel.Text = math.ceil(payload.TimeLeft or 0) .. "s"
        end
        if payload.Pos ~= nil then
            bossPos = payload.Pos
        end
    elseif kind == "hit" then
        -- Targeted to THIS attacker: pop their server-computed damage number + a throttled hit sound.
        popNumber(payload.Damage, payload.Pos or bossPos)
        local now = os.clock()
        if now - lastHitSfx >= HIT_SFX_INTERVAL then
            lastHitSfx = now
            Effects.playSfx("boss_hit")
        end
    elseif kind == "defeat" then
        showAlert(
            "The "
                .. tostring(payload.Name or "Titan")
                .. " was DEFEATED!  ("
                .. tostring(payload.Participants or 0)
                .. " hunters paid out)"
        )
        -- Death spectacle (pooled Effects; silent/no-op without assets).
        if bossPos ~= nil then
            local camera = Workspace.CurrentCamera
            if camera ~= nil then
                local screen = camera:WorldToViewportPoint(bossPos)
                if screen.Z > 0 then
                    Effects.burst(UDim2.fromOffset(screen.X, screen.Y), Theme.Colors.Gold, 24)
                end
            end
        end
        Effects.flash(Theme.Colors.Gold)
        Effects.playSfx("boss_death")
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

    -- Spawn alert: a soft dark "bubble" banner over the world with a Danger glow rim (one pill family
    -- with the quest banner + biome label). White-fill text recipe (reads over the 3D world).
    alertLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 6),
        Size = UDim2.fromOffset(720, 44),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.12,
        Font = Theme.FontDisplay,
        Text = "",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Visible = false,
        Parent = gui,
    }, {
        Builder.corner(Theme.Radius.Card),
        Builder.padding(8),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.Danger, Thickness = 2.5, Transparency = 0.2 }
        ),
        Builder.create("UITextSizeConstraint", { MaxTextSize = 28 }),
    })
    Builder.styleText(alertLabel, { keepColor = true })

    -- Boss HP bar: a soft dark pill holding the TITAN name + the shared Builder.progressBar (animated
    -- red fill + gloss sweep). Same pill style as the quest banner + biome label.
    barFrame = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 34),
        Size = UDim2.fromOffset(420, 48),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.15,
        Visible = false,
        Parent = gui,
    }, {
        Builder.corner(Theme.Radius.Card),
        Builder.padding(6),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.Danger, Thickness = 2.5, Transparency = 0.3 }
        ),
    })

    nameLabel = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(4, 0),
        Size = UDim2.new(1, -8, 0, 16),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = "TITAN",
        TextColor3 = Theme.Colors.Gold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = barFrame,
    })
    Builder.styleText(nameLabel, { keepColor = true })

    local _, bossBarSet = Builder.progressBar({
        Position = UDim2.fromOffset(4, 18),
        Size = UDim2.new(1, -8, 0, 18),
        fillTop = Color3.fromRGB(255, 96, 110), -- boss red
        fillBottom = Color3.fromRGB(196, 40, 64),
        label = false,
        Parent = barFrame,
    })
    bossSet = bossBarSet

    timerLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, 27),
        Size = UDim2.new(1, -8, 0, 18),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = "",
        TextColor3 = Theme.Colors.White,
        TextSize = 13,
        ZIndex = 6,
        Parent = barFrame,
    })
    Builder.styleText(timerLabel, { keepColor = true })

    -- Off-screen direction marker: same soft dark pill + Danger rim.
    marker = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(154, 28),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.2,
        Font = Theme.FontDisplay,
        Text = "▾ TITAN",
        TextColor3 = Theme.Colors.White,
        TextSize = 14,
        Visible = false,
        Parent = gui,
    }, {
        Builder.corner(UDim.new(1, 0)),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.Danger, Thickness = 2, Transparency = 0.3 }
        ),
    })
    Builder.styleText(marker, { keepColor = true })

    -- Pre-build the recycled damage-number pool (capped, hidden until used).
    for _ = 1, NUMBER_POOL_SIZE do
        local label = Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(140, 40),
            BackgroundTransparency = 1,
            Font = Theme.FontDisplay,
            Text = "",
            TextColor3 = Theme.Colors.Gold,
            TextStrokeColor3 = Theme.Colors.Outline,
            TextStrokeTransparency = 0.4,
            TextSize = 30,
            ZIndex = 5,
            Visible = false,
            Parent = gui,
        })
        table.insert(numberPool, { label = label, busy = false })
    end

    RunService.RenderStepped:Connect(updateMarker)
end

return BossHud
