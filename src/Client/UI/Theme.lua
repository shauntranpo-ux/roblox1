-- Theme: THE single source of UI design tokens -- colors, fonts, per-panel accent gradients, corner
-- radii, stroke, body transparency, and tween presets. Builder reads these to build every themed
-- part (gloss header / pill tab / gloss button / rarity card), so the whole game restyles from here.
--
-- RETUNE THE LOOK HERE:
--   * Theme.FontDisplay  -- the chunky "simulator" font (FredokaOne). Swap to LuckiestGuy to taste.
--   * Theme.Accents      -- each panel's glossy header gradient (gold/pink/purple/...).
--   * Theme.BodyTransparency, Theme.Radius, Theme.Stroke -- glass body, corners, the dark outline.
--   * Theme.Juice        -- click ripple intensity + whether every tap ripples.

local Theme = {}

-- ── Fonts ────────────────────────────────────────────────────────────────────────────────
-- Chunky, bold, rounded display font for titles / big numbers (the signature of the look), plus a
-- clean body font. FontBold/Font are kept for any legacy callers.
Theme.FontDisplay = Enum.Font.FredokaOne
Theme.FontBody = Enum.Font.Gotham
Theme.FontBold = Enum.Font.GothamBold
Theme.Font = Enum.Font.GothamMedium

-- ── Palette (grape glass base; kept keys so existing screens inherit) ──────────────────────
Theme.Colors = {
    Background = Color3.fromRGB(48, 30, 92), -- cleaner indigo-grape (panel bodies glassed over this)
    Panel = Color3.fromRGB(64, 42, 116),
    Row = Color3.fromRGB(82, 58, 140), -- brighter card so rows pop on the translucent body
    Accent = Color3.fromRGB(167, 99, 255), -- electric purple
    Positive = Color3.fromRGB(74, 232, 150), -- income green
    Danger = Color3.fromRGB(255, 84, 112), -- close-button pink
    Text = Color3.fromRGB(248, 248, 255),
    SubText = Color3.fromRGB(198, 190, 226),
    Disabled = Color3.fromRGB(86, 72, 120),
    Outline = Color3.fromRGB(24, 12, 44), -- the heavy dark text/border outline color
    GlossTop = Color3.fromRGB(255, 255, 255), -- white sheen overlay top for the glossy look

    -- ── VM-THEME reference palette (the bright voxel look; tune these to the screenshots) ──
    -- Used by the HUD + world dressing. Panels keep the grape-glass keys above so existing screens
    -- inherit unchanged; these add the kid-friendly saturated accents from the references.
    Sky = Color3.fromRGB(120, 200, 255), -- bright sky blue
    Grass = Color3.fromRGB(96, 200, 84), -- lush grass green
    Sand = Color3.fromRGB(232, 204, 148), -- warm sand / tan
    PathRed = Color3.fromRGB(228, 72, 72), -- RED path-trim accent
    Gold = Color3.fromRGB(255, 206, 64), -- cash gold
    HpFill = Color3.fromRGB(96, 226, 96), -- HP bar green (top of gradient)
    HpFillDark = Color3.fromRGB(40, 168, 70), -- HP bar green (bottom of gradient)
    XpFill = Color3.fromRGB(86, 200, 255), -- XP bar cyan/blue (top)
    XpFillDark = Color3.fromRGB(40, 130, 232), -- XP bar cyan/blue (bottom)
    Clover = Color3.fromRGB(96, 220, 96), -- luck clover green
    DarkPill = Color3.fromRGB(18, 16, 26), -- near-black translucent for HUD pills/slots
    White = Color3.fromRGB(255, 255, 255),
    Yellow = Color3.fromRGB(255, 222, 56), -- banner keyword highlight (<hl>) color
}

-- ── Shape tokens ───────────────────────────────────────────────────────────────────────────
Theme.Radius = {
    Panel = UDim.new(0, 20),
    Card = UDim.new(0, 14),
    Button = UDim.new(0, 12),
    Pill = UDim.new(1, 0), -- fully rounded pill
}
Theme.Stroke = { Width = 3, Color = Theme.Colors.Outline, Transparency = 0.1 }
Theme.BodyTransparency = 0.5 -- panel body see-through (world shows through; no dim backdrop)
Theme.RowTransparency = 0.34 -- translucent cards/rows
Theme.HeaderHeight = 54

-- ── Per-panel accent gradients (the glossy header bar color, top -> bottom) ─────────────────
Theme.Accents = {
    Default = { Top = Color3.fromRGB(180, 110, 255), Bottom = Color3.fromRGB(120, 55, 215) },
    Shop = { Top = Color3.fromRGB(255, 214, 92), Bottom = Color3.fromRGB(240, 160, 32) }, -- gold
    Index = { Top = Color3.fromRGB(255, 130, 205), Bottom = Color3.fromRGB(224, 66, 150) }, -- pink
    Inventory = { Top = Color3.fromRGB(96, 226, 170), Bottom = Color3.fromRGB(36, 176, 138) }, -- teal
    Trade = { Top = Color3.fromRGB(96, 176, 255), Bottom = Color3.fromRGB(46, 120, 232) }, -- blue
    Rebirth = { Top = Color3.fromRGB(190, 120, 255), Bottom = Color3.fromRGB(132, 60, 232) }, -- purple
    Events = { Top = Color3.fromRGB(255, 158, 86), Bottom = Color3.fromRGB(236, 104, 40) }, -- orange
    Seasons = { Top = Color3.fromRGB(96, 224, 236), Bottom = Color3.fromRGB(40, 172, 212) }, -- cyan
    Codes = { Top = Color3.fromRGB(126, 226, 152), Bottom = Color3.fromRGB(74, 184, 114) }, -- green
    Settings = { Top = Color3.fromRGB(168, 176, 196), Bottom = Color3.fromRGB(108, 116, 138) }, -- slate
    Menu = { Top = Color3.fromRGB(180, 110, 255), Bottom = Color3.fromRGB(120, 55, 215) },
    Fusion = { Top = Color3.fromRGB(255, 170, 90), Bottom = Color3.fromRGB(236, 96, 60) }, -- forge orange
    Deploy = { Top = Color3.fromRGB(120, 220, 190), Bottom = Color3.fromRGB(40, 150, 160) }, -- steel teal
    Loadout = { Top = Color3.fromRGB(255, 120, 160), Bottom = Color3.fromRGB(210, 50, 90) }, -- raid red
    Evolution = { Top = Color3.fromRGB(150, 245, 130), Bottom = Color3.fromRGB(60, 190, 90) }, -- bio green
    Exclusives = { Top = Color3.fromRGB(120, 200, 255), Bottom = Color3.fromRGB(60, 110, 230) }, -- frost blue
    NetShop = { Top = Color3.fromRGB(120, 230, 200), Bottom = Color3.fromRGB(40, 170, 150) }, -- net teal
    Quests = { Top = Color3.fromRGB(255, 220, 130), Bottom = Color3.fromRGB(220, 160, 50) }, -- quest gold
}

-- Returns a fresh vertical UIGradient for an accent key (top -> bottom). Caller parents it.
function Theme.gradient(accentKey)
    local a = Theme.Accents[accentKey] or Theme.Accents.Default
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(a.Top, a.Bottom)
    return g
end

-- The solid representative color of an accent (for nav highlight, tab selected, etc.).
function Theme.accentColor(accentKey)
    local a = Theme.Accents[accentKey] or Theme.Accents.Default
    return a.Bottom
end

-- ── Tween presets ────────────────────────────────────────────────────────────────────────
Theme.Tween = {
    Open = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    Squish = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    Fade = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- ── Click juice tuning ───────────────────────────────────────────────────────────────────
Theme.Juice = {
    RippleEverywhere = true, -- ripple/burst on EVERY tap (set false for buttons-only)
    RippleSize = 110, -- px diameter the burst expands to (bigger = punchier)
    RippleTime = 0.4, -- s expand+fade duration
    RippleColor = Color3.fromRGB(255, 248, 205), -- bright warm white (the ring + flash core)
    RippleStartTransparency = 0.3, -- lower = stronger
    ButtonSquish = 0.9, -- press scale before the back-ease pop to 1.0
}

-- ── VM-THEME text style (FredokaOne + white fill + black stroke + soft shadow) ──────────────
-- The single canonical text recipe. Builder.styleText applies these; tune the look here.
Theme.TextStyle = {
    Font = Theme.FontDisplay, -- FredokaOne (built-in). Swap point: upload a Luckiest-Guy FontFace + set here.
    Fill = Theme.Colors.White,
    StrokeColor = Theme.Colors.Outline,
    StrokeThickness = 2.5, -- scaled black rim
    StrokeTransparency = 0.1,
    ShadowTransparency = 0.4, -- the soft built-in TextStrokeTransparency drop shadow
}

-- ── VM-THEME asset slots (DEV SUPPLIES THESE IDS; everything falls back cleanly when 0/empty) ──
Theme.Assets = {
    -- Sky: 6 face ids for a custom skybox. Leave all "" to use the bright-blue default Sky placeholder.
    SkyboxFaces = { Bk = "", Dn = "", Ft = "", Lf = "", Rt = "", Up = "" },
    HoneycombTexture = 0, -- decal/texture asset id for the hex shield wall (0 = skip the texture)
    -- UI sounds route through Effects.playSfx / Shared.Audio.Sfx (paste ids there). Listed for clarity.
}

-- ── VM-THEME HUD config ─────────────────────────────────────────────────────────────────────
-- The left diamond rail's level-gated entries (edit freely). Level source = the player's RebirthCount
-- (the real progression stat). Unlocked entries are tappable (stub action); locked show a padlock + Lv.
Theme.DiamondRail = {
    { Label = "Upgrades", UnlockLevel = 5 },
    { Label = "Pets", UnlockLevel = 10 },
    { Label = "Zones", UnlockLevel = 15 },
    { Label = "Prestige", UnlockLevel = 20 },
}
-- Display max for the protection/shield bar (seconds) + the XP bar fallback max, when no real value.
Theme.Hud = {
    ShieldDisplayMax = 120, -- bar shows shield-seconds out of this (matches NewPlayerGrace feel)
    XpFallbackMax = 100, -- the XP bar's max when no real player-XP stat is published (hook below)
    BarTween = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- ── VM-THEME lighting / atmosphere / post-FX (the bright midday voxel mood) ──────────────────
Theme.Lighting = {
    ClockTime = 14, -- bright early-afternoon sun
    GeographicLatitude = 12,
    Brightness = 2.4,
    ExposureCompensation = 0.12,
    Ambient = Color3.fromRGB(140, 150, 165),
    OutdoorAmbient = Color3.fromRGB(170, 180, 195),
    FogEnd = 100000,
    Atmosphere = {
        Density = 0.32,
        Offset = 0.1,
        Haze = 1.6,
        Glare = 0.2,
        Color = Color3.fromRGB(220, 235, 255),
        Decay = Color3.fromRGB(160, 190, 230),
    },
    Bloom = { Intensity = 0.55, Size = 24, Threshold = 1.1 },
    ColorCorrection = {
        Saturation = 0.18,
        Contrast = 0.06,
        Brightness = 0.01,
        TintColor = Color3.fromRGB(255, 252, 245),
    },
    SunRays = { Intensity = 0.06, Spread = 0.4 },
    SkyDefault = Color3.fromRGB(120, 200, 255), -- placeholder bright-blue sky tint when no skybox ids
}

-- Floating ambient sparkle particle look (pooled/capped by Atmosphere; tune density here).
Theme.Sparkle = {
    Rate = 6, -- particles/sec (kept low; capped)
    Lifetime = NumberRange.new(3, 6),
    Speed = NumberRange.new(0.5, 1.5),
    Size = 0.5,
    Color = Color3.fromRGB(255, 252, 210),
    Texture = "rbxasset://textures/particles/sparkles_main.dds", -- built-in; no asset id needed
}

-- CollectionService tags -> the voxel material/color the WorldStyler applies to tagged geometry the
-- DEV builds in Studio. Adding a tag entry here makes that tag auto-adopt the look (no geometry made).
Theme.WorldTags = {
    Grass = { Color = Theme.Colors.Grass, Material = Enum.Material.Grass },
    Sand = { Color = Theme.Colors.Sand, Material = Enum.Material.Sand },
    Path = { Color = Theme.Colors.PathRed, Material = Enum.Material.SmoothPlastic },
    Water = {
        Color = Color3.fromRGB(90, 180, 255),
        Material = Enum.Material.Glass,
        Transparency = 0.3,
    },
    Wood = { Color = Color3.fromRGB(150, 100, 60), Material = Enum.Material.Wood },
    Stone = { Color = Color3.fromRGB(150, 150, 158), Material = Enum.Material.Slate },
}

return Theme
