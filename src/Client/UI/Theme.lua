-- Theme: the single source of UI styling (colors, fonts, radii). Change the look in
-- one place; every screen reads from here.

local Theme = {}

Theme.Font = Enum.Font.GothamMedium
Theme.FontBold = Enum.Font.GothamBold

-- VM-UI: retuned to the translucent "grape glass" palette. Every panel/row/button reads these, so
-- the new look propagates without per-screen edits. (A future full Theme module will expand this;
-- the small UIStyle helper holds the glass-apply functions + the same colors.)
Theme.Colors = {
    Background = Color3.fromRGB(34, 17, 65), -- deep grape (panels are glassed over this)
    Panel = Color3.fromRGB(46, 26, 84),
    Row = Color3.fromRGB(48, 30, 86),
    Accent = Color3.fromRGB(155, 77, 255), -- electric purple #9B4DFF
    Positive = Color3.fromRGB(70, 224, 138), -- income green #46E08A
    Danger = Color3.fromRGB(255, 84, 112), -- close-button pink #FF5470
    Text = Color3.fromRGB(245, 245, 252),
    SubText = Color3.fromRGB(186, 178, 214),
    Disabled = Color3.fromRGB(70, 58, 98),
}

return Theme
