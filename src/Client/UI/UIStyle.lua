-- UIStyle: a SMALL, self-contained styling helper for the translucent "glass" look. Intentionally
-- minimal -- a future full Theme module will absorb/expand this. It only provides a palette + a few
-- apply-in-place helpers (glass panel, scrim, rarity accent bar, nav-button states). No animation
-- framework, no effects library here.

local UIStyle = {}

UIStyle.Colors = {
    -- Deep grape / navy glass tint the panels sit on.
    Glass = Color3.fromRGB(34, 17, 65), -- ~#221141
    GlassTop = Color3.fromRGB(52, 30, 92), -- gradient top (slightly lifted)
    Row = Color3.fromRGB(48, 30, 86), -- translucent row card
    Stroke = Color3.fromRGB(155, 77, 255), -- electric purple #9B4DFF
    Danger = Color3.fromRGB(255, 84, 112), -- #FF5470 close button
    Income = Color3.fromRGB(70, 224, 138), -- #46E08A income green
    Text = Color3.fromRGB(245, 245, 252),
    SubText = Color3.fromRGB(186, 178, 214),
    NavIdle = Color3.fromRGB(46, 30, 82),
    NavActive = Color3.fromRGB(155, 77, 255),
    Scrim = Color3.fromRGB(0, 0, 0),
}

UIStyle.PanelTransparency = 0.18
UIStyle.RowTransparency = 0.25
UIStyle.ScrimTransparency = 0.45

local function ensureCorner(instance, radius)
    local existing = instance:FindFirstChildOfClass("UICorner")
    if existing ~= nil then
        return existing
    end
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = instance
    return corner
end

-- Turns a solid panel Frame into translucent glass: dark grape tint that the world shows through
-- faintly, a subtle vertical gradient, a purple stroke, rounded corners, and an assetless soft
-- drop-shadow behind it (a larger, offset, dark translucent rounded frame -- no image asset, so it
-- can never render as a broken icon). Idempotent: safe to call once per panel on registration.
function UIStyle.applyGlass(frame)
    if frame == nil or frame:GetAttribute("Glassed") then
        return
    end
    frame:SetAttribute("Glassed", true)

    frame.BackgroundColor3 = UIStyle.Colors.Glass
    frame.BackgroundTransparency = UIStyle.PanelTransparency
    ensureCorner(frame, 14)

    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new(UIStyle.Colors.GlassTop, UIStyle.Colors.Glass)
    gradient.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = UIStyle.Colors.Stroke
    stroke.Thickness = 2
    stroke.Transparency = 0.1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = frame

    -- Assetless soft shadow: a larger, offset, dark, very translucent rounded frame BEHIND the
    -- panel. Reads as depth on the dimmed scrim without risking a broken shadow image.
    local shadow = Instance.new("Frame")
    shadow.Name = "GlassShadow"
    shadow.AnchorPoint = frame.AnchorPoint
    shadow.Position = frame.Position + UDim2.fromOffset(0, 6)
    shadow.Size = frame.Size + UDim2.fromOffset(14, 16)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.55
    shadow.BorderSizePixel = 0
    shadow.ZIndex = frame.ZIndex - 1
    ensureCorner(shadow, 20)
    shadow.Parent = frame.Parent
end

-- The full-screen scrim look (semi-transparent black so the world dims behind a panel).
function UIStyle.styleScrim(button)
    button.BackgroundColor3 = UIStyle.Colors.Scrim
    button.BackgroundTransparency = UIStyle.ScrimTransparency
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = ""
end

-- Adds (once) a rarity-colored left accent bar to a row card and makes it translucent, so a Common
-- row visibly differs from a rarer one at a glance. `rarityColor` comes from the existing ladder.
function UIStyle.accentRow(row, rarityColor)
    if row == nil or row:GetAttribute("Accented") then
        return
    end
    row:SetAttribute("Accented", true)
    row.BackgroundColor3 = UIStyle.Colors.Row
    row.BackgroundTransparency = UIStyle.RowTransparency
    ensureCorner(row, 10)

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

-- Makes a row card translucent + rounded WITHOUT an accent bar (for rows that already carry their
-- rarity color another way, e.g. the Shop's rarity-tinted icon swatch).
function UIStyle.glassRow(row)
    if row == nil or row:GetAttribute("Glassed") then
        return
    end
    row:SetAttribute("Glassed", true)
    row.BackgroundColor3 = UIStyle.Colors.Row
    row.BackgroundTransparency = UIStyle.RowTransparency
    ensureCorner(row, 10)
end

-- Nav-button selected/idle visual (the open panel's button looks highlighted).
function UIStyle.setNavActive(button, active)
    button.BackgroundColor3 = active and UIStyle.Colors.NavActive or UIStyle.Colors.NavIdle
    button.TextColor3 = UIStyle.Colors.Text
end

return UIStyle
