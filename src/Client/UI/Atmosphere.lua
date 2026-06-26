-- Atmosphere (VM-THEME): the global MOOD -- bright-midday Lighting + Atmosphere haze + Bloom +
-- ColorCorrection (saturation up) + SunRays + a default bright sky, plus a capped ambient-sparkle
-- emitter. All client-side (local visual only -- touches no server state, no gameplay). Every value
-- reads Theme.Lighting / Theme.Sparkle. A guarded per-zone hook (setZone) lets the future map swap the
-- look as the player crosses zone volumes; it no-ops safely until something calls it.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)

local Atmosphere = {}

local baseLightingApplied = false
local function applyBaseLighting()
    if baseLightingApplied then
        return
    end
    baseLightingApplied = true
    Lighting.Brightness = 2.1 -- was 2.6 -- softer so cream/stone surfaces don't blow out
    Lighting.ExposureCompensation = -0.05 -- slight pull-back
    Lighting.EnvironmentDiffuseScale = 0.55
    Lighting.EnvironmentSpecularScale = 0.4
    Lighting.OutdoorAmbient = Color3.fromRGB(140, 142, 150)
    Lighting.Ambient = Color3.fromRGB(80, 82, 92)
    Lighting.ShadowSoftness = 0.35
    Lighting.GlobalShadows = true
    Lighting.GeographicLatitude = 20
    if Lighting:FindFirstChildOfClass("Atmosphere") == nil then
        local atmo = Instance.new("Atmosphere")
        atmo.Density = 0.32
        atmo.Offset = 0.1
        atmo.Haze = 0.9 -- was 1.4 -- clearer
        atmo.Glare = 0.1 -- was 0.2
        atmo.Color = Color3.fromRGB(199, 209, 224)
        atmo.Decay = Color3.fromRGB(106, 134, 168)
        atmo.Parent = Lighting
    end
end

-- Find an existing Lighting child of `class` named `name`, or create one (idempotent).
local function ensure(parent, class, name)
    local found = parent:FindFirstChild(name)
    if found ~= nil and found:IsA(class) then
        return found
    end
    local inst = Instance.new(class)
    inst.Name = name
    inst.Parent = parent
    return inst
end

local atmosphere, colorCorrection

function Atmosphere.applyBase()
    applyBaseLighting()
    local L = Theme.Lighting
    pcall(function()
        Lighting.ClockTime = L.ClockTime
        Lighting.GeographicLatitude = L.GeographicLatitude
        Lighting.Brightness = L.Brightness
        Lighting.ExposureCompensation = L.ExposureCompensation
        Lighting.Ambient = L.Ambient
        Lighting.OutdoorAmbient = L.OutdoorAmbient
        Lighting.FogEnd = L.FogEnd
        Lighting.GlobalShadows = true
    end)

    atmosphere = ensure(Lighting, "Atmosphere", "Atmosphere")
    atmosphere.Density = L.Atmosphere.Density
    atmosphere.Offset = L.Atmosphere.Offset
    atmosphere.Haze = L.Atmosphere.Haze
    atmosphere.Glare = L.Atmosphere.Glare
    atmosphere.Color = L.Atmosphere.Color
    atmosphere.Decay = L.Atmosphere.Decay

    local bloom = ensure(Lighting, "BloomEffect", "VMBloom")
    bloom.Intensity = L.Bloom.Intensity
    bloom.Size = L.Bloom.Size
    bloom.Threshold = L.Bloom.Threshold

    colorCorrection = ensure(Lighting, "ColorCorrectionEffect", "VMColorCorrection")
    colorCorrection.Saturation = L.ColorCorrection.Saturation
    colorCorrection.Contrast = L.ColorCorrection.Contrast
    colorCorrection.Brightness = L.ColorCorrection.Brightness
    colorCorrection.TintColor = L.ColorCorrection.TintColor

    local sunRays = ensure(Lighting, "SunRaysEffect", "VMSunRays")
    sunRays.Intensity = L.SunRays.Intensity
    sunRays.Spread = L.SunRays.Spread

    -- SKY: only build a custom Sky if the dev supplied 6 face ids; otherwise leave Roblox's default
    -- procedural sky, which is already bright blue at ClockTime 14 (the clean fallback + swap point).
    local faces = Theme.Assets.SkyboxFaces
    if faces.Up ~= nil and faces.Up ~= "" then
        local sky = ensure(Lighting, "Sky", "VMSky")
        sky.SkyboxBk = faces.Bk
        sky.SkyboxDn = faces.Dn
        sky.SkyboxFt = faces.Ft
        sky.SkyboxLf = faces.Lf
        sky.SkyboxRt = faces.Rt
        sky.SkyboxUp = faces.Up
    end
end

-- A capped ambient-sparkle emitter over the hub (ONE emitter, low rate -- per perf discipline). The
-- anchor part is client-local + non-colliding; reposition it if the hub center moves.
function Atmosphere.mountSparkles()
    local anchor = Instance.new("Part")
    anchor.Name = "VMSparkleAnchor"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(220, 50, 220)
    anchor.CFrame = CFrame.new(0, 28, 0) -- hub center placeholder; move to taste
    anchor.Parent = Workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = Theme.Sparkle.Texture
    emitter.Rate = Theme.Sparkle.Rate -- low + fixed -> capped particle count
    emitter.Lifetime = Theme.Sparkle.Lifetime
    emitter.Speed = Theme.Sparkle.Speed
    emitter.Size = NumberSequence.new(Theme.Sparkle.Size)
    emitter.Color = ColorSequence.new(Theme.Sparkle.Color)
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.2, 0.2),
        NumberSequenceKeypoint.new(0.8, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.LightEmission = 0.6
    emitter.Rotation = NumberRange.new(0, 360)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Parent = anchor
end

-- PER-ZONE HOOK (guarded; no-op until the map calls it). `cfg` may set any of: Atmosphere props,
-- ColorCorrection props, SkyTint. The future zone-volume system calls this on a zone crossing.
function Atmosphere.setZone(cfg)
    if type(cfg) ~= "table" then
        return
    end
    if cfg.Atmosphere ~= nil and atmosphere ~= nil then
        for key, value in pairs(cfg.Atmosphere) do
            pcall(function()
                atmosphere[key] = value
            end)
        end
    end
    if cfg.ColorCorrection ~= nil and colorCorrection ~= nil then
        for key, value in pairs(cfg.ColorCorrection) do
            pcall(function()
                colorCorrection[key] = value
            end)
        end
    end
end

function Atmosphere.mount(_context)
    Atmosphere.applyBase()
    Atmosphere.mountSparkles()
end

return Atmosphere
