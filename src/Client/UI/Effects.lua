-- Effects: the lightweight, performance-conscious JUICE toolbox -- particle bursts, a cash-pill
-- pop, screen flashes, a subtle camera shake, and sound hooks. Driven entirely by the client
-- reacting to server signals (Notify cues, Cash changes, kill-feed); it has NO authority and
-- never sends anything to the server.
--
-- PERFORMANCE: particles are a FIXED POOL (reused round-robin, hard cap), the shake is one
-- BindToRenderStep that no-ops when idle, and sounds are short-lived + skipped when no asset id
-- is configured. Nothing here scales with the number of players or brainrots.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))

local Effects = {}

local POOL_SIZE = 24 -- hard cap on simultaneous particle frames
local SHAKE_DECAY = 6 -- how fast a shake settles

local overlay = nil
local flash = nil
local pool = {}
local poolIndex = 0
local camera = nil
local settings = { Music = true, SFX = true, Shake = true }
local musicSound = nil

local shakeMagnitude = 0

local function toColor(hexR, hexG, hexB)
    return Color3.fromRGB(hexR, hexG, hexB)
end

-- ===== Sound =====
local function playSound(id, volume)
    if id == nil or id == 0 then
        return -- no asset configured -> silent, by design
    end
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(id)
    sound.Volume = volume or Audio.SfxVolume
    sound.Parent = SoundService
    sound:Play()
    task.delay(5, function()
        sound:Destroy()
    end)
end

function Effects.playSfx(key)
    if not settings.SFX then
        return
    end
    playSound(Audio.Sfx[key], Audio.SfxVolume)
end

-- ===== Music =====
local function refreshMusic()
    if settings.Music and Audio.MusicId ~= 0 then
        if musicSound == nil then
            musicSound = Instance.new("Sound")
            musicSound.SoundId = "rbxassetid://" .. tostring(Audio.MusicId)
            musicSound.Looped = true
            musicSound.Volume = Audio.MusicVolume
            musicSound.Parent = SoundService
        end
        if not musicSound.IsPlaying then
            musicSound:Play()
        end
    elseif musicSound ~= nil and musicSound.IsPlaying then
        musicSound:Stop()
    end
end

-- Called whenever the settings table changes (music/sfx/shake).
function Effects.applySettings(newSettings)
    if type(newSettings) ~= "table" then
        return
    end
    settings = newSettings
    refreshMusic()
end

-- ===== Camera shake =====
function Effects.shake(magnitude)
    if not settings.Shake then
        return
    end
    shakeMagnitude = math.max(shakeMagnitude, magnitude)
end

-- ===== Screen flash =====
function Effects.flash(color)
    if flash == nil then
        return
    end
    flash.BackgroundColor3 = color
    flash.BackgroundTransparency = 0.45
    TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
end

-- ===== UI pop (scale punch) on any GuiObject =====
function Effects.pop(guiObject, strength)
    if guiObject == nil then
        return
    end
    local base = guiObject:GetAttribute("BaseScale")
    if base == nil then
        base = guiObject.Size
        guiObject:SetAttribute("BaseScale", base)
    end
    local s = strength or 0.08
    local punched =
        UDim2.new(base.X.Scale * (1 + s), base.X.Offset, base.Y.Scale * (1 + s), base.Y.Offset)
    guiObject.Size = punched
    TweenService:Create(guiObject, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = base })
        :Play()
end

-- ===== Particle burst (pooled) =====
local function nextParticle()
    poolIndex = (poolIndex % POOL_SIZE) + 1
    return pool[poolIndex]
end

-- Emits a small burst of `count` particles from a screen-space anchor (UDim2 scale), tinted
-- `color`. Reuses the fixed pool, so it can never spawn unbounded instances.
function Effects.burst(anchor, color, count)
    if overlay == nil then
        return
    end
    count = math.min(count or 8, POOL_SIZE)
    for _ = 1, count do
        local dot = nextParticle()
        dot.BackgroundColor3 = color
        dot.BackgroundTransparency = 0
        dot.Position = anchor
        dot.Size = UDim2.fromOffset(12, 12)
        dot.Visible = true
        local angle = math.random() * math.pi * 2
        local dist = 0.06 + math.random() * 0.06
        local target = UDim2.new(
            anchor.X.Scale + math.cos(angle) * dist,
            0,
            anchor.Y.Scale + math.sin(angle) * dist + 0.04,
            0
        )
        local tween = TweenService:Create(
            dot,
            TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Position = target, BackgroundTransparency = 1, Size = UDim2.fromOffset(4, 4) }
        )
        tween:Play()
        tween.Completed:Connect(function()
            dot.Visible = false
        end)
    end
end

function Effects.milestone()
    Effects.burst(UDim2.fromScale(0.5, 0.12), toColor(255, 215, 90), 16)
    Effects.playSfx("milestone")
end

function Effects.mount(context)
    local player = context.player or Players.LocalPlayer
    camera = Workspace.CurrentCamera

    overlay = Instance.new("ScreenGui")
    overlay.Name = "Effects"
    overlay.ResetOnSpawn = false
    overlay.IgnoreGuiInset = true
    overlay.DisplayOrder = 50
    overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    overlay.Parent = player:WaitForChild("PlayerGui")

    flash = Instance.new("Frame")
    flash.Name = "Flash"
    flash.Size = UDim2.fromScale(1, 1)
    flash.BackgroundColor3 = toColor(255, 255, 255)
    flash.BackgroundTransparency = 1
    flash.BorderSizePixel = 0
    flash.ZIndex = 1
    flash.Active = false
    flash.Parent = overlay

    for i = 1, POOL_SIZE do
        local dot = Instance.new("Frame")
        dot.Name = "P" .. i
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
        dot.Size = UDim2.fromOffset(10, 10)
        dot.BackgroundColor3 = toColor(255, 255, 255)
        dot.BorderSizePixel = 0
        dot.Visible = false
        dot.ZIndex = 5
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = dot
        dot.Parent = overlay
        pool[i] = dot
    end

    -- Keep the camera ref current across respawns / camera swaps.
    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        camera = Workspace.CurrentCamera
    end)

    -- One render-step shake that no-ops while idle. Applied AFTER the camera updates.
    RunService:BindToRenderStep("BrainrotShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
        if shakeMagnitude < 0.01 or camera == nil then
            return
        end
        local offset = Vector3.new(
            (math.random() - 0.5) * 2 * shakeMagnitude,
            (math.random() - 0.5) * 2 * shakeMagnitude,
            0
        )
        camera.CFrame = camera.CFrame * CFrame.new(offset)
        shakeMagnitude =
            math.max(0, shakeMagnitude - shakeMagnitude * math.min(1, dt * SHAKE_DECAY))
    end)

    refreshMusic()
end

return Effects
