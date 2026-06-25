-- Theme: the single source of UI styling (colors, fonts, radii). Change the look in
-- one place; every screen reads from here.

local Theme = {}

Theme.Font = Enum.Font.GothamMedium
Theme.FontBold = Enum.Font.GothamBold

Theme.Colors = {
    Background = Color3.fromRGB(22, 24, 31),
    Panel = Color3.fromRGB(32, 35, 44),
    Row = Color3.fromRGB(42, 46, 57),
    Accent = Color3.fromRGB(95, 170, 255),
    Positive = Color3.fromRGB(80, 200, 120),
    Danger = Color3.fromRGB(230, 90, 90),
    Text = Color3.fromRGB(240, 242, 248),
    SubText = Color3.fromRGB(165, 172, 186),
    Disabled = Color3.fromRGB(64, 68, 78),
}

return Theme
