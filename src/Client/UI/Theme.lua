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
    Background = Color3.fromRGB(34, 17, 65), -- deep grape (panel bodies glassed over this)
    Panel = Color3.fromRGB(46, 26, 84),
    Row = Color3.fromRGB(48, 30, 86),
    Accent = Color3.fromRGB(155, 77, 255), -- electric purple
    Positive = Color3.fromRGB(70, 224, 138), -- income green
    Danger = Color3.fromRGB(255, 84, 112), -- close-button pink
    Text = Color3.fromRGB(245, 245, 252),
    SubText = Color3.fromRGB(186, 178, 214),
    Disabled = Color3.fromRGB(70, 58, 98),
    Outline = Color3.fromRGB(20, 10, 38), -- the heavy dark text/▮ outline color
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
Theme.BodyTransparency = 0.4 -- panel body see-through (world shows faintly; no dim backdrop)
Theme.HeaderHeight = 52

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
    RippleEverywhere = true, -- ripple on EVERY tap (set false for buttons-only)
    RippleSize = 84, -- px diameter the ripple expands to
    RippleTime = 0.42, -- s expand+fade duration
    RippleColor = Color3.fromRGB(255, 255, 255),
    RippleStartTransparency = 0.55, -- lower = stronger; keep subtle
    ButtonSquish = 0.92, -- press scale before the back-ease pop to 1.0
}

return Theme
