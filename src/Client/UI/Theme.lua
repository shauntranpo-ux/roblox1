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
Theme.FontBody = Theme.FontDisplay
Theme.FontBold = Theme.FontDisplay
Theme.Font = Theme.FontDisplay

-- ── Palette: SOFT / CLOUDY / BUBBLY (light airy cloud interiors; kept keys so screens inherit) ──
-- TWO domains share this table:
--   * PANEL interiors are LIGHT (Cloud body + white Card rows + Ink text) -- soft, pillowy, readable.
--   * HUD / world billboards sit OVER the 3D world, so they keep the WHITE-fill + dark-Outline recipe
--     and the bright voxel accents (DarkPill chips, Gold/HpFill/XpFill, ...). White-fill+dark-rim text
--     reads on BOTH light and dark, so a panel label is legible even before it is upgraded to Ink.
Theme.Colors = {
    -- ── Light cloud panel interiors ─────────────────────────────────────────────────────────
    Background = Color3.fromRGB(245, 242, 255), -- panel BODY base (soft lavender-white cloud)
    Cloud = Color3.fromRGB(245, 242, 255), -- alias of Background (the cloud body)
    CloudTop = Color3.fromRGB(255, 254, 255), -- panel body gradient TOP (bright gloss)
    Panel = Color3.fromRGB(236, 232, 252), -- a deeper cloud for sub-surfaces (dropdown lists, wells)
    Card = Color3.fromRGB(255, 255, 255), -- near-white item/row card fill
    CardTop = Color3.fromRGB(255, 255, 255), -- card gloss top
    Row = Color3.fromRGB(226, 221, 247), -- soft periwinkle (idle pill tabs / secondary chips)
    Ink = Color3.fromRGB(74, 58, 122), -- PRIMARY text on light interiors (deep indigo)
    InkSoft = Color3.fromRGB(132, 118, 168), -- muted ink (subtext on light)
    InkHalo = Color3.fromRGB(255, 255, 255), -- soft light halo behind ink text (separates on pastels)

    Accent = Color3.fromRGB(167, 120, 255), -- candy purple (primary accent)
    Positive = Color3.fromRGB(74, 232, 150), -- income green
    Danger = Color3.fromRGB(255, 104, 130), -- close-button pink (softened)
    Text = Color3.fromRGB(248, 248, 255), -- WHITE fill (HUD / over-accent / over-world recipe)
    SubText = Color3.fromRGB(198, 190, 226),
    Disabled = Color3.fromRGB(196, 188, 214), -- grayed-out on light interiors
    Outline = Color3.fromRGB(36, 22, 60), -- heavy dark rim for the WHITE-text / over-world recipe
    GlossTop = Color3.fromRGB(255, 255, 255), -- white sheen overlay top for the glossy look

    -- ── VM-THEME reference palette (the bright voxel HUD + world dressing) ──
    -- Used by the HUD + world dressing (over the 3D world). Slightly brightened for the candy look.
    Sky = Color3.fromRGB(150, 212, 255), -- bright sky blue
    Grass = Color3.fromRGB(120, 214, 120), -- lush grass green
    Sand = Color3.fromRGB(238, 214, 162), -- warm sand / tan
    PathRed = Color3.fromRGB(232, 104, 112), -- soft red path-trim accent
    Gold = Color3.fromRGB(255, 206, 64), -- cash gold
    HpFill = Color3.fromRGB(108, 232, 128), -- HP bar green (top of gradient)
    HpFillDark = Color3.fromRGB(48, 184, 96), -- HP bar green (bottom of gradient)
    XpFill = Color3.fromRGB(96, 206, 255), -- XP bar cyan/blue (top)
    XpFillDark = Color3.fromRGB(48, 142, 240), -- XP bar cyan/blue (bottom)
    Clover = Color3.fromRGB(96, 220, 96), -- luck clover green
    DarkPill = Color3.fromRGB(44, 38, 72), -- HUD chip base over the world (soft indigo, was near-black)
    White = Color3.fromRGB(255, 255, 255),
    Yellow = Color3.fromRGB(255, 222, 56), -- banner keyword highlight (<hl>) color
}

-- ── Shape tokens (large, near-pill radii for the pillowy/bubbly look) ────────────────────────
Theme.Radius = {
    Panel = UDim.new(0, 32), -- big pillowy panel corners
    Card = UDim.new(0, 22),
    Button = UDim.new(0, 20),
    Bubble = UDim.new(0, 18), -- the unified HUD squircle "bubble" chip radius
    Pill = UDim.new(1, 0), -- fully rounded pill
}
Theme.Stroke = { Width = 3, Color = Theme.Colors.Outline, Transparency = 0.1 } -- WHITE-text/over-world rim
Theme.BodyTransparency = 0.04 -- panel body is a near-opaque LIGHT cloud (was 0.82 see-through grape)
Theme.RowTransparency = 0 -- crisp opaque white cards
Theme.HeaderHeight = 54

-- ── Soft drop shadow + glow rim (the cohesive depth treatment used by every panel/chip) ──────
-- softShadow: an ImageLabel using Theme.Assets.ShadowImage (a 9-slice soft-shadow id) when supplied,
-- else Builder falls back to a layered translucent rounded frame -- so it always works with no asset.
Theme.Shadow = {
    Offset = Vector2.new(0, 6), -- px down/right the shadow sits under the element
    Spread = 16, -- px the shadow extends past the element on each side
    Transparency = 0.55, -- 0 = solid black, 1 = invisible
    Color = Color3.fromRGB(40, 26, 70), -- soft indigo shadow (not harsh black)
}
-- glowRim: a soft accent-colored outer glow ring around panels/CTAs.
Theme.Rim = {
    Thickness = 2.5,
    Transparency = 0.35, -- the accent rim is soft, not a hard border
    GlowTransparency = 0.78, -- the outer halo frame
}

-- ── Pillowy DEPTH (the "not-flat" treatment) ────────────────────────────────────────────────
-- Builder.applyDepth multiplies a SOLID surface by this vertical gradient (top bright -> bottom
-- shaded) so flat color reads as a rounded 3D pillow, and lays a glossy top sheen that fades to
-- nothing by mid-height. The multiply tints are < white, so they DARKEN the lower half of whatever
-- base color the surface carries (works on white cards AND bright accent buttons alike). Tune the
-- whole game's depth from here.
Theme.Gloss = {
    TopTint = Color3.fromRGB(255, 255, 255), -- top edge catches the light (no change)
    MidTint = Color3.fromRGB(246, 245, 250), -- gentle rolloff through the middle
    BottomTint = Color3.fromRGB(202, 197, 214), -- bottom ~22% cool shade -> the pillow falloff
    SheenTop = 0.4, -- top sheen highlight strength (lower = glossier); fades to invisible by mid
    SheenHeight = 0.52, -- fraction of the surface the gloss sheen covers
    InnerHighlight = 0.55, -- thin bright top-edge inner highlight transparency (the lit rim)
}

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
    Upgrades = { Top = Color3.fromRGB(150, 240, 150), Bottom = Color3.fromRGB(60, 190, 96) }, -- boost green
    Quests = { Top = Color3.fromRGB(255, 220, 130), Bottom = Color3.fromRGB(220, 160, 50) }, -- quest gold
    Rewards = { Top = Color3.fromRGB(255, 180, 120), Bottom = Color3.fromRGB(230, 110, 60) }, -- reward orange
    Referral = { Top = Color3.fromRGB(255, 215, 120), Bottom = Color3.fromRGB(235, 165, 40) }, -- invite gold
    Social = { Top = Color3.fromRGB(150, 200, 255), Bottom = Color3.fromRGB(70, 130, 230) }, -- friend blue
    Admin = { Top = Color3.fromRGB(255, 96, 110), Bottom = Color3.fromRGB(180, 36, 56) }, -- moderation red
    Report = { Top = Color3.fromRGB(255, 170, 90), Bottom = Color3.fromRGB(220, 110, 40) }, -- report amber
    Slingshot = { Top = Color3.fromRGB(120, 230, 200), Bottom = Color3.fromRGB(40, 170, 150) }, -- launch teal
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

-- ── Tween presets (TUNE ANIMATION SPEEDS HERE) ──────────────────────────────────────────────
Theme.Tween = {
    Open = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    OpenBouncy = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), -- springier pop
    Close = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
    Squish = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    Fade = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    BarFill = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), -- progress fill
    Hover = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), -- pointer hover lift
}

-- ── Idle-life motion (looping, GPU-driven tweens; pooled, no per-frame Lua churn) ────────────
-- Periods are seconds for one half-cycle (the tweens auto-reverse). Tune the "alive" feel here.
Theme.Anim = {
    PulsePeriod = 1.0, -- primary-CTA breathing pulse
    PulseScale = 1.05, -- peak scale of the pulse
    BobPeriod = 1.8, -- gentle float/bob on HUD icons
    BobAmplitude = 5, -- px the bob travels
    ShimmerPeriod = 1.4, -- soft sheen shimmer on important elements
    GlossSweepPeriod = 1.6, -- the moving gloss sweep across progress bars
    OverShoot = 0.8, -- start scale for the bouncy panel pop-in (lower = bouncier)
    HoverScale = 1.06, -- pointer-hover lift on buttons/chips (PC only; touch never fires MouseEnter)
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
    ShadowTransparency = 0.1, -- tightened for legibility on near-transparent bubble panels
}

-- INK variant: dark indigo fill + a soft light halo (no heavy black rim). Use on LIGHT panel interiors
-- (item names, descriptions, values) via Builder.styleText(label, { ink = true }).
Theme.TextStyleInk = {
    Font = Theme.FontDisplay,
    Fill = Theme.Colors.Ink,
    StrokeColor = Theme.Colors.InkHalo,
    StrokeThickness = 1.5, -- soft light halo
    StrokeTransparency = 0.55,
    ShadowTransparency = 1, -- no dark drop shadow on light
}

-- ── VM-THEME asset slots (DEV SUPPLIES THESE IDS; everything falls back cleanly when 0/empty) ──
Theme.Assets = {
    -- Sky: 6 face ids for a custom skybox. Leave all "" to use the bright-blue default Sky placeholder.
    SkyboxFaces = { Bk = "", Dn = "", Ft = "", Lf = "", Rt = "", Up = "" },
    HoneycombTexture = 0, -- decal/texture asset id for the hex shield wall (0 = skip the texture)
    -- Soft drop-shadow image: a 9-slice (SliceCenter) soft-shadow PNG id. "" -> Builder.softShadow
    -- falls back to a layered translucent rounded frame (works with zero assets). Paste an id to upgrade.
    ShadowImage = "", -- e.g. "rbxassetid://1316045217" (a classic soft 9-slice shadow)
    ShadowSlice = Rect.new(10, 10, 118, 118), -- SliceCenter rect for the supplied 9-slice image
    -- UI sounds route through Effects.playSfx / Shared.Audio.Sfx (paste ids there). Listed for clarity.
}

-- ── VM-THEME HUD config ─────────────────────────────────────────────────────────────────────
-- The top-left quick-rail entries: each opens a REAL panel (no dead placeholders). `Icon` is the bubble
-- glyph; `Panel` is the PanelManager panel name the bubble opens.
Theme.DiamondRail = {
    { Label = "Upgrades", Icon = "⬆", Panel = "UpgradesShop" },
    { Label = "Rebirth", Icon = "⭐", Panel = "Rebirth" },
}
-- Display max for the protection/shield bar (seconds) + the XP bar fallback max, when no real value.
Theme.Hud = {
    ShieldDisplayMax = 120, -- bar shows shield-seconds out of this (matches NewPlayerGrace feel)
    XpFallbackMax = 100, -- the XP bar's max when no real player-XP stat is published (hook below)
    BarTween = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- ── VM-THEME lighting / atmosphere / post-FX (soft warm midday -- no blow-out) ───────────────
Theme.Lighting = {
    ClockTime = 14, -- bright early-afternoon sun
    GeographicLatitude = 12,
    Brightness = 1.5, -- was 1.7 -- tamed so nothing over-exposes
    ExposureCompensation = -0.05, -- slight pull-back to kill the haze
    Ambient = Color3.fromRGB(120, 130, 145),
    OutdoorAmbient = Color3.fromRGB(150, 162, 178),
    FogEnd = 100000,
    Atmosphere = {
        Density = 0.32,
        Offset = 0.1,
        Haze = 0.9, -- was 1.6 -- clearer air, less white haze over distant parts
        Glare = 0.1, -- was 0.2 -- glare was cooking the sky
        Color = Color3.fromRGB(220, 235, 255),
        Decay = Color3.fromRGB(160, 190, 230),
    },
    Bloom = { Intensity = 0.15, Size = 20, Threshold = 2.4 }, -- soft glow only on the very brightest; no white-out
    ColorCorrection = {
        Saturation = 0.08, -- was 0.16 -- less over-saturation
        Contrast = 0.03,
        Brightness = -0.02,
        TintColor = Color3.fromRGB(255, 250, 240), -- warm tint
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
