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

return Theme
