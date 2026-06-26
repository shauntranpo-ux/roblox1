-- UIStyle: a thin LEGACY COMPATIBILITY SHIM over the Theme design system. It used to hold its own
-- "grape glass" palette; that parallel palette is gone -- every value here now resolves straight from
-- Theme, so there is ONE source of truth. Kept only so any older caller (applyGlass / accentRow /
-- glassRow / setNavActive / styleScrim) still produces the cohesive soft/cloudy look. New code should
-- use Builder + Theme directly. applyGlass is a no-op on Builder panels (already marked "Glassed").

local Theme = require(script.Parent.Theme)

local UIStyle = {}

-- All values resolve from Theme (no independent palette).
UIStyle.Colors = {
    Glass = Theme.Colors.Cloud, -- light cloud panel body
    GlassTop = Theme.Colors.CloudTop, -- gradient top (gloss)
    Row = Theme.Colors.Card, -- near-white row card
    Stroke = Theme.Colors.Accent, -- soft accent rim
    Danger = Theme.Colors.Danger,
    Income = Theme.Colors.Positive,
    Text = Theme.Colors.Ink, -- dark ink on the light interiors
    SubText = Theme.Colors.InkSoft,
    NavIdle = Theme.Colors.Row,
    NavActive = Theme.Colors.Accent,
    Scrim = Color3.fromRGB(0, 0, 0), -- base for the invisible click-catcher only
}

UIStyle.PanelTransparency = Theme.BodyTransparency
UIStyle.RowTransparency = Theme.RowTransparency
-- Scrim is FULLY transparent (1) -- no background dimming. It stays only as an invisible click catcher.
UIStyle.ScrimTransparency = 1

local function ensureCorner(instance, radius)
    local existing = instance:FindFirstChildOfClass("UICorner")
    if existing ~= nil then
        return existing
    end
    local corner = Instance.new("UICorner")
    corner.CornerRadius = radius or Theme.Radius.Card
    corner.Parent = instance
    return corner
end

-- Turns a legacy (non-Builder) panel Frame into the soft light cloud look: light body, gloss gradient,
-- soft accent rim, rounded corners. Idempotent. A no-op on Builder panels (already marked "Glassed").
function UIStyle.applyGlass(frame)
    if frame == nil or frame:GetAttribute("Glassed") then
        return
    end
    frame:SetAttribute("Glassed", true)

    frame.BackgroundColor3 = UIStyle.Colors.Glass
    frame.BackgroundTransparency = UIStyle.PanelTransparency
    ensureCorner(frame, Theme.Radius.Panel)

    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new(UIStyle.Colors.GlassTop, UIStyle.Colors.Glass)
    gradient.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = UIStyle.Colors.Stroke
    stroke.Thickness = Theme.Rim.Thickness
    stroke.Transparency = Theme.Rim.Transparency
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = frame
end

-- The full-screen scrim: an INVISIBLE click catcher (no dimming).
function UIStyle.styleScrim(button)
    button.BackgroundColor3 = UIStyle.Colors.Scrim
    button.BackgroundTransparency = UIStyle.ScrimTransparency
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = ""
end

-- Adds (once) a rarity-colored left accent bar to a row card and makes it a light card, so a Common
-- row visibly differs from a rarer one at a glance. `rarityColor` comes from the existing ladder.
function UIStyle.accentRow(row, rarityColor)
    if row == nil or row:GetAttribute("Accented") then
        return
    end
    row:SetAttribute("Accented", true)
    row.BackgroundColor3 = UIStyle.Colors.Row
    row.BackgroundTransparency = UIStyle.RowTransparency
    ensureCorner(row, Theme.Radius.Card)

    local bar = Instance.new("Frame")
    bar.Name = "RarityAccent"
    bar.AnchorPoint = Vector2.new(0, 0.5)
    bar.Position = UDim2.fromScale(0, 0.5)
    bar.Size = UDim2.new(0, 4, 0.82, 0)
    bar.BackgroundColor3 = rarityColor
    bar.BorderSizePixel = 0
    bar.ZIndex = (row.ZIndex or 1) + 1
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 2)
    corner.Parent = bar
    bar.Parent = row
end

-- Makes a row card a light card + rounded WITHOUT an accent bar (for rows that carry rarity elsewhere).
function UIStyle.glassRow(row)
    if row == nil or row:GetAttribute("Glassed") then
        return
    end
    row:SetAttribute("Glassed", true)
    row.BackgroundColor3 = UIStyle.Colors.Row
    row.BackgroundTransparency = UIStyle.RowTransparency
    ensureCorner(row, Theme.Radius.Card)
end

-- Nav-button selected/idle visual (the open panel's button looks highlighted).
function UIStyle.setNavActive(button, active)
    button.BackgroundColor3 = active and UIStyle.Colors.NavActive or UIStyle.Colors.NavIdle
    button.TextColor3 = active and Theme.Colors.Text or UIStyle.Colors.Text
end

return UIStyle
