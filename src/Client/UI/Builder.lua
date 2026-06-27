-- Builder: declarative UI construction helpers + the THEMED COMPONENT KIT (the glossy "simulator"
-- look). Everything reads Theme tokens, so the whole game restyles from Theme. No Studio-authored
-- GUI anywhere. Click ripple + click sound are global (see ClickFX), so buttons only need the squish.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Builder = {}

-- Creates an Instance from a class name, a props table, and optional children.
-- Parent (if given in props) is applied LAST, after children, for fewer reflows.
function Builder.create(className, props, children)
    local instance = Instance.new(className)
    if props ~= nil then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                instance[key] = value
            end
        end
    end
    if children ~= nil then
        for _, child in ipairs(children) do
            child.Parent = instance
        end
    end
    if props ~= nil and props.Parent ~= nil then
        instance.Parent = props.Parent
    end
    return instance
end

-- Rounded-corner helper.
function Builder.corner(radius)
    return Builder.create("UICorner", { CornerRadius = radius or UDim.new(0, 12) })
end

-- Uniform padding helper (pixels on all sides).
function Builder.padding(pixels)
    local amount = UDim.new(0, pixels)
    return Builder.create("UIPadding", {
        PaddingTop = amount,
        PaddingBottom = amount,
        PaddingLeft = amount,
        PaddingRight = amount,
    })
end

-- A ScreenGui with sensible, safe-area-aware defaults.
function Builder.screenGui(name, parent, enabled)
    local gui = Builder.create("ScreenGui", {
        Name = name,
        ResetOnSpawn = false,
        Enabled = enabled ~= false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    pcall(function()
        gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    end)
    gui.Parent = parent
    return gui
end

-- ===========================================================================================
-- Themed component kit (chunky font + dark outline + gloss; reads Theme)
-- ===========================================================================================

-- Gives a SOLID-color frame/button pillowy DEPTH: a vertical multiply-gradient (top bright -> bottom
-- shaded, from Theme.Gloss) so flat color reads as a rounded 3D pillow, PLUS a glossy top sheen that
-- fades to nothing by mid-height and a thin lit top-edge highlight. Idempotent (guarded by the "Depth"
-- gradient + "Sheen" child). Do NOT call on objects that already carry an accent/body UIGradient
-- (glossHeader / panel) -- a second UIGradient would fight it; those already read deep.
-- opts: { radius, sheenZIndex }.
function Builder.applyDepth(obj, opts)
    opts = opts or {}
    local radius = opts.radius or Theme.Radius.Button
    local g = Theme.Gloss
    if obj:FindFirstChild("Depth") == nil and obj:FindFirstChildOfClass("UIGradient") == nil then
        Builder.create("UIGradient", {
            Name = "Depth",
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, g.TopTint),
                ColorSequenceKeypoint.new(0.55, g.MidTint),
                ColorSequenceKeypoint.new(1, g.BottomTint),
            }),
            Parent = obj,
        })
    end
    if not opts.noSheen and obj:FindFirstChild("Sheen") == nil then
        Builder.create("Frame", {
            Name = "Sheen",
            Size = UDim2.fromScale(1, g.SheenHeight),
            BackgroundColor3 = Theme.Colors.White,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            ZIndex = opts.sheenZIndex or 0,
            Parent = obj,
        }, {
            Builder.corner(radius),
            Builder.create("UIGradient", { -- the highlight fades downward into nothing
                Rotation = 90,
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, g.SheenTop),
                    NumberSequenceKeypoint.new(1, 1),
                }),
            }),
        })
    end
    return obj
end

-- Applies the signature recipe to a text label: chunky display font + a heavy dark glyph outline +
-- a soft built-in text shadow. opts: { font, stroke, softShadow }.
function Builder.applyChrome(label, opts)
    opts = opts or {}
    label.Font = opts.font or Theme.FontDisplay
    label.TextStrokeColor3 = Theme.Colors.Outline
    label.TextStrokeTransparency = opts.softShadow == false and 1 or 0.35
    Builder.create("UIStroke", {
        Color = Theme.Stroke.Color,
        Thickness = opts.stroke or Theme.Stroke.Width,
        Transparency = Theme.Stroke.Transparency,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
        Parent = label,
    })
    return label
end

-- A glossy rounded button that squishes on press (ripple + sound are handled globally by ClickFX).
-- props: Size/Position/AnchorPoint/LayoutOrder/Parent/Text/color/textColor/radius/maxText/font.
function Builder.glossButton(props, onClick)
    props = props or {}
    local radius = props.radius or Theme.Radius.Button
    local button = Builder.create("TextButton", {
        Size = props.Size or UDim2.fromOffset(120, 48),
        Position = props.Position,
        AnchorPoint = props.AnchorPoint,
        LayoutOrder = props.LayoutOrder,
        BackgroundColor3 = props.color or Theme.Colors.Accent,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = props.font or Theme.FontDisplay,
        Text = props.Text or "",
        TextColor3 = props.textColor or Theme.Colors.Text,
        TextScaled = props.TextScaled ~= false,
        Parent = props.Parent,
    }, {
        Builder.corner(radius),
        Builder.create("UIStroke", {
            Color = Theme.Colors.Outline,
            Thickness = 2.5,
            Transparency = 0.15,
        }),
        Builder.create("UITextSizeConstraint", { MaxTextSize = props.maxText or 22 }),
    })
    -- Pillowy depth: multiply-shade gradient + glossy top sheen (behind the text).
    Builder.applyDepth(button, { radius = radius, sheenZIndex = 0 })
    button.TextStrokeColor3 = Theme.Colors.Outline
    button.TextStrokeTransparency = 0.4

    local function squish()
        if button:GetAttribute("BaseSize") == nil then
            button:SetAttribute("BaseSize", button.Size)
        end
        local base = button:GetAttribute("BaseSize")
        local k = Theme.Juice.ButtonSquish
        button.Size =
            UDim2.new(base.X.Scale * k, base.X.Offset * k, base.Y.Scale * k, base.Y.Offset * k)
    end
    local function restore()
        local base = button:GetAttribute("BaseSize")
        if base ~= nil then
            TweenService:Create(button, Theme.Tween.Squish, { Size = base }):Play()
        end
    end
    button.InputBegan:Connect(function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            squish()
        end
    end)
    button.InputEnded:Connect(function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            restore()
        end
    end)
    if onClick ~= nil then
        button.Activated:Connect(onClick)
    end
    return button
end

-- A glossy gradient header bar (its own accent), chunky title on the left, round red X on the right.
function Builder.glossHeader(parent, title, accentKey, onClose)
    local header = Builder.create("Frame", {
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(1, -16, 0, Theme.HeaderHeight),
        BackgroundColor3 = Theme.accentColor(accentKey),
        BorderSizePixel = 0,
        Parent = parent,
    }, {
        Builder.corner(Theme.Radius.Card),
        Theme.gradient(accentKey),
        Builder.create("UIStroke", {
            Color = Theme.Colors.Outline,
            Thickness = 2,
            Transparency = 0.25,
        }),
        Builder.create("Frame", { -- top gloss sheen
            Size = UDim2.fromScale(1, 0.5),
            BackgroundColor3 = Theme.Colors.GlossTop,
            BackgroundTransparency = 0.78,
            BorderSizePixel = 0,
            ZIndex = 0,
        }, { Builder.corner(Theme.Radius.Card) }),
    })

    local titleLabel = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(16, 0),
        Size = UDim2.new(1, -72, 1, 0),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = Theme.Colors.Text,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 30 }) })
    Builder.applyChrome(titleLabel)

    Builder.glossButton({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(38, 38),
        color = Theme.Colors.Danger,
        Text = "X",
        radius = UDim.new(1, 0),
        maxText = 22,
        Parent = header,
    }, onClose)
    return header
end

-- A rounded glossy PILL tab button. Pair with setPillSelected for the selected state.
function Builder.pillTab(parent, text, order, onClick)
    local tab = Builder.create("TextButton", {
        LayoutOrder = order,
        Size = UDim2.fromScale(0, 1),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Colors.Row,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Theme.FontDisplay,
        Text = "  " .. text .. "  ",
        TextColor3 = Theme.Colors.InkSoft, -- readable on the light pill / cloud body
        TextSize = 18,
        Parent = parent,
    }, {
        Builder.corner(Theme.Radius.Pill),
        Builder.create("UIStroke", {
            Color = Theme.Colors.Accent,
            Thickness = 2,
            Transparency = 0.55, -- soft accent rim instead of a hard dark border
        }),
    })
    if onClick ~= nil then
        tab.Activated:Connect(onClick)
    end
    return tab
end

-- Sets a pill tab's selected look (accent-filled vs muted).
function Builder.setPillSelected(tab, accentKey, selected)
    tab.BackgroundColor3 = selected and Theme.accentColor(accentKey) or Theme.Colors.Row
    tab.BackgroundTransparency = selected and 0 or 0.15
    -- selected: white on the bright accent; idle: ink on the soft periwinkle pill.
    tab.TextColor3 = selected and Theme.Colors.Text or Theme.Colors.InkSoft
end

-- Adds a rarity-colored border + translucent rounded card look to an existing frame (once).
function Builder.rarityCard(frame, rarityColor)
    if frame:GetAttribute("Carded") then
        return frame
    end
    frame:SetAttribute("Carded", true)
    frame.BackgroundColor3 = Theme.Colors.Card -- near-white card on the light cloud body
    frame.BackgroundTransparency = Theme.RowTransparency
    if frame:FindFirstChildOfClass("UICorner") == nil then
        Builder.corner(Theme.Radius.Card).Parent = frame
    end
    Builder.create("UIStroke", {
        Color = rarityColor,
        Thickness = 3,
        Transparency = 0.05,
        Parent = frame,
    })
    -- Subtle pillowy shade on the white card (no sheen -- keep ink text crisp).
    Builder.applyDepth(frame, { radius = Theme.Radius.Card, noSheen = true })
    return frame
end

-- ===========================================================================================
-- VM-THEME: the canonical text recipe + diamond / pill / stat-bar builders (all read Theme)
-- ===========================================================================================

-- THE single text-style helper: FredokaOne + white fill + black UIStroke rim + soft drop shadow.
-- Reuse this on EVERY label (HUD, panels, world billboards). opts: { font, color, stroke, shadow,
-- keepColor }. keepColor=true leaves the label's own TextColor3 (e.g. gold cash) but still adds the
-- black rim + shadow.
function Builder.styleText(label, opts)
    opts = opts or {}
    -- ink = true -> dark indigo fill + soft light halo, for LIGHT panel interiors (item names/values).
    local s = opts.ink == true and Theme.TextStyleInk or Theme.TextStyle
    label.Font = opts.font or s.Font
    if opts.keepColor ~= true then
        label.TextColor3 = opts.color or s.Fill
    end
    label.TextStrokeColor3 = s.StrokeColor
    label.TextStrokeTransparency = opts.shadow == false and 1 or s.ShadowTransparency
    if label:FindFirstChildOfClass("UIStroke") == nil then
        Builder.create("UIStroke", {
            Color = s.StrokeColor,
            Thickness = opts.stroke or s.StrokeThickness,
            Transparency = s.StrokeTransparency,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
            Parent = label,
        })
    end
    return label
end

-- A DIAMOND button (a rotated glossy square with upright centered content). Returns
-- (container, diamondFrame, contentLabel, button) so callers can recolor / relabel / lock it.
function Builder.diamond(props, onClick)
    props = props or {}
    local size = props.size or 56
    local container = Builder.create("Frame", {
        Size = UDim2.fromOffset(size, size),
        Position = props.Position,
        AnchorPoint = props.AnchorPoint,
        LayoutOrder = props.LayoutOrder,
        BackgroundTransparency = 1,
        Parent = props.Parent,
    })
    local diamond = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.72, 0.72),
        Rotation = 45, -- the diamond look
        BackgroundColor3 = props.color or Theme.Colors.DarkPill,
        BackgroundTransparency = props.transparency or 0.1,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = container,
    }, {
        Builder.corner(UDim.new(0, 8)),
        Builder.create("UIStroke", {
            Color = Theme.Colors.White,
            Thickness = 2.5,
            Transparency = 0.1,
        }),
    })
    Builder.applyDepth(diamond, { radius = UDim.new(0, 8), sheenZIndex = 1 })
    local content = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.7, 0.7),
        BackgroundTransparency = 1,
        Text = props.Text or "",
        TextColor3 = props.textColor or Theme.Colors.White,
        TextScaled = true,
        ZIndex = 3,
        Parent = container,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = props.maxText or 28 }) })
    Builder.styleText(content, { keepColor = true })
    local button = Builder.create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = container,
    })
    if onClick ~= nil then
        button.Activated:Connect(onClick)
    end
    return container, diamond, content, button
end

-- A rounded dark-translucent PILL frame (HUD chips / slots). Returns the frame.
function Builder.pill(props)
    props = props or {}
    local radius = props.radius or Theme.Radius.Pill
    local frame = Builder.create("Frame", {
        Size = props.Size,
        Position = props.Position,
        AnchorPoint = props.AnchorPoint,
        LayoutOrder = props.LayoutOrder,
        BackgroundColor3 = props.color or Theme.Colors.DarkPill,
        BackgroundTransparency = props.transparency or 0.25,
        BorderSizePixel = 0,
        Parent = props.Parent,
    }, {
        Builder.corner(radius),
        Builder.create("UIStroke", {
            Color = props.stroke or Theme.Colors.White,
            Thickness = 2,
            Transparency = 0.2,
        }),
    })
    -- Pillowy depth shade + a faint top gloss (chips read as rounded, not flat).
    Builder.applyDepth(frame, { radius = radius, sheenZIndex = 1 })
    return frame
end

-- A glossy gradient STAT BAR (HP green / XP cyan). Back-compat alias that routes through the single
-- Builder.progressBar (so HP/XP/catch/boss bars all share the animated fill + gloss sweep). Returns
-- (frame, set) where set(cur, max, text) clamps, tweens the fill, and sets the centered text.
function Builder.statBar(props)
    return Builder.progressBar(props)
end

-- Consistent scroll styling (subtle accent bar, smooth, auto canvas).
function Builder.styleScroll(scroll)
    scroll.ScrollBarThickness = 5
    scroll.ScrollBarImageColor3 = Theme.Colors.Accent
    scroll.ScrollBarImageTransparency = 0.25
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.ElasticBehavior = Enum.ElasticBehavior.Always
    return scroll
end

-- ===========================================================================================
-- SOFT/BUBBLY KIT: shadow, glow rim, the unified icon BUBBLE, progress bar, idle-life loops,
-- count-up. All read Theme tokens so the whole game stays cohesive + tunes from one place.
-- ===========================================================================================

-- Press-squish helper: scales `target` to Theme.Juice.ButtonSquish on press, springy Back-ease back on
-- release. `inputObj` (a button) drives it; `target` (defaults to inputObj) is what visually squishes.
function Builder.bindSquish(inputObj, target)
    target = target or inputObj
    local function squish()
        if target:GetAttribute("BaseSize") == nil then
            target:SetAttribute("BaseSize", target.Size)
        end
        local base = target:GetAttribute("BaseSize")
        local k = Theme.Juice.ButtonSquish
        target.Size =
            UDim2.new(base.X.Scale * k, base.X.Offset * k, base.Y.Scale * k, base.Y.Offset * k)
    end
    local function restore()
        local base = target:GetAttribute("BaseSize")
        if base ~= nil then
            TweenService:Create(target, Theme.Tween.Squish, { Size = base }):Play()
        end
    end
    inputObj.InputBegan:Connect(function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            squish()
        end
    end)
    inputObj.InputEnded:Connect(function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            restore()
        end
    end)
end

-- A SOFT DROP SHADOW placed behind `frame` as a sibling (for ABSOLUTELY-positioned elements: panels,
-- the TAP button, world-space frames -- not list items). Uses Theme.Assets.ShadowImage (a 9-slice soft
-- shadow) when supplied; otherwise a layered translucent rounded frame so it always works with no asset.
-- Idempotent (guarded by the "SoftShadow" name).
function Builder.softShadow(frame, opts)
    opts = opts or {}
    local parent = opts.parent or frame.Parent
    if parent == nil or parent:FindFirstChild("SoftShadow") ~= nil then
        return frame
    end
    local sh = Theme.Shadow
    local spread = opts.spread or sh.Spread
    local radius = opts.radius or Theme.Radius.Panel
    local img = Theme.Assets.ShadowImage
    if img ~= nil and img ~= "" then
        Builder.create("ImageLabel", {
            Name = "SoftShadow",
            AnchorPoint = frame.AnchorPoint,
            Position = frame.Position + UDim2.fromOffset(sh.Offset.X, sh.Offset.Y),
            Size = UDim2.new(
                frame.Size.X.Scale,
                frame.Size.X.Offset + spread * 2,
                frame.Size.Y.Scale,
                frame.Size.Y.Offset + spread * 2
            ),
            BackgroundTransparency = 1,
            Image = img,
            ImageColor3 = sh.Color,
            ImageTransparency = opts.transparency or sh.Transparency,
            ScaleType = Enum.ScaleType.Slice,
            SliceCenter = Theme.Assets.ShadowSlice,
            ZIndex = (frame.ZIndex or 1) - 1,
            Parent = parent,
        })
        return frame
    end
    -- Fallback is an ImageLabel (NOT a Frame) so it is never mistaken for the panel by callers that
    -- locate the main frame via FindFirstChildWhichIsA("Frame") (e.g. PanelManager.register). With no
    -- Image set it simply renders its rounded BackgroundColor3 -- a soft faux-shadow with zero assets.
    Builder.create("ImageLabel", {
        Name = "SoftShadow",
        AnchorPoint = frame.AnchorPoint,
        Position = frame.Position + UDim2.fromOffset(sh.Offset.X, sh.Offset.Y + 2),
        Size = UDim2.new(
            frame.Size.X.Scale,
            frame.Size.X.Offset + spread,
            frame.Size.Y.Scale,
            frame.Size.Y.Offset + spread
        ),
        BackgroundColor3 = sh.Color,
        BackgroundTransparency = opts.transparency or sh.Transparency,
        ImageTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = (frame.ZIndex or 1) - 1,
        Parent = parent,
    }, { Builder.corner(radius) })
    return frame
end

-- A soft accent GLOW RIM on any frame/button: recolors its stroke to a soft accent (no hard dark border).
function Builder.glowRim(obj, accentKey)
    local stroke = obj:FindFirstChildOfClass("UIStroke")
    if stroke == nil then
        stroke = Builder.create("UIStroke", { Parent = obj })
    end
    stroke.Color = Theme.accentColor(accentKey)
    stroke.Thickness = Theme.Rim.Thickness
    stroke.Transparency = Theme.Rim.Transparency
    return obj
end

-- The unified soft rounded-square "BUBBLE" icon chip (the ONE shape language for the HUD rail + edge
-- columns): squircle + gloss sheen + soft shadow + glow rim + press squish. Returns
-- (container, bubble, content, button) -- mirrors Builder.diamond so it is a drop-in replacement.
function Builder.iconBubble(props, onClick)
    props = props or {}
    local size = props.size or 56
    local radius = props.radius or Theme.Radius.Bubble
    local container = Builder.create("Frame", {
        Size = UDim2.fromOffset(size, size),
        Position = props.Position,
        AnchorPoint = props.AnchorPoint,
        LayoutOrder = props.LayoutOrder,
        BackgroundTransparency = 1,
        Parent = props.Parent,
    })
    -- soft shadow behind the bubble (a child of the transparent container, lower ZIndex)
    Builder.create("Frame", {
        Name = "BubbleShadow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 4),
        Size = UDim2.fromScale(1.02, 1.05),
        BackgroundColor3 = Theme.Shadow.Color,
        BackgroundTransparency = Theme.Shadow.Transparency,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = container,
    }, { Builder.corner(radius) })
    local bubble = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = props.color or Theme.Colors.DarkPill,
        BackgroundTransparency = props.transparency or 0.05,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = container,
    }, {
        Builder.corner(radius),
        Builder.create("UIStroke", {
            Color = Theme.Colors.White,
            Thickness = 2.5,
            Transparency = 0.2,
        }),
    })
    Builder.applyDepth(bubble, { radius = radius, sheenZIndex = 2 })
    local content = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.74, 0.74),
        BackgroundTransparency = 1,
        Text = props.Text or "",
        TextColor3 = props.textColor or Theme.Colors.White,
        TextScaled = true,
        ZIndex = 4,
        Parent = container,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = props.maxText or 26 }) })
    Builder.styleText(content, { keepColor = true })
    local button = Builder.create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 6,
        Parent = container,
    })
    Builder.bindSquish(button, bubble)
    if onClick ~= nil then
        button.Activated:Connect(onClick)
    end
    return container, bubble, content, button
end

-- A glossy rounded PROGRESS BAR with an animated fill + a looping gloss SWEEP + a centered label. The
-- single bar builder (HP / XP / catch meter / boss bar all route through it). Returns (frame, set) where
-- set(cur, max, text) clamps to [0,max], tweens the fill, and sets the centered text.
function Builder.progressBar(props)
    props = props or {}
    local fillTop = props.fillTop or Theme.Colors.HpFill
    local fillBottom = props.fillBottom or Theme.Colors.HpFillDark
    local bg = Builder.create("Frame", {
        Size = props.Size or UDim2.fromOffset(160, 22),
        Position = props.Position,
        AnchorPoint = props.AnchorPoint,
        LayoutOrder = props.LayoutOrder,
        BackgroundColor3 = props.trackColor or Theme.Colors.DarkPill,
        BackgroundTransparency = props.trackTransparency or 0.2,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = props.Parent,
    }, {
        Builder.corner(UDim.new(1, 0)),
        Builder.create("UIStroke", {
            Color = Theme.Colors.White,
            Thickness = 2,
            Transparency = 0.25,
        }),
    })
    local fill = Builder.create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = fillTop,
        BorderSizePixel = 0,
        ZIndex = 2,
        ClipsDescendants = true,
        Parent = bg,
    }, {
        Builder.corner(UDim.new(1, 0)),
        Builder.create("UIGradient", {
            Rotation = 90,
            Color = ColorSequence.new(fillTop, fillBottom),
        }),
        Builder.create("Frame", { -- static top gloss
            Size = UDim2.fromScale(1, 0.45),
            BackgroundColor3 = Theme.Colors.GlossTop,
            BackgroundTransparency = 0.7,
            BorderSizePixel = 0,
        }, { Builder.corner(UDim.new(1, 0)) }),
    })
    -- moving gloss SWEEP: a tilted highlight that slides across the fill on a loop (juicy "alive" feel).
    if props.sweep ~= false then
        local sweep = Builder.create("Frame", {
            Name = "GlossSweep",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.fromScale(-0.3, 0.5),
            Size = UDim2.fromScale(0.22, 1.4),
            Rotation = 14,
            BackgroundColor3 = Theme.Colors.White,
            BackgroundTransparency = 0.62,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = fill,
        })
        TweenService:Create(
            sweep,
            TweenInfo.new(
                Theme.Anim.GlossSweepPeriod,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.Out,
                -1,
                false,
                0.7 -- pause between sweeps
            ),
            { Position = UDim2.fromScale(1.3, 0.5) }
        ):Play()
    end
    local label = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        ZIndex = 4,
        Visible = props.label ~= false,
        Parent = bg,
    }, { Builder.padding(2), Builder.create("UITextSizeConstraint", { MaxTextSize = 16 }) })
    Builder.styleText(label, { keepColor = true })

    local function set(cur, max, text)
        cur = math.max(0, tonumber(cur) or 0)
        max = math.max(1, tonumber(max) or 1)
        local pct = math.clamp(cur / max, 0, 1)
        TweenService
            :Create(
                fill,
                props.fillTween or Theme.Tween.BarFill,
                { Size = UDim2.fromScale(pct, 1) }
            )
            :Play()
        label.Text = text or (math.floor(cur) .. " / " .. math.floor(max))
    end
    return bg, set
end

-- Breathing PULSE for primary CTAs: a child UIScale oscillates (composes with the Size-based press
-- squish without fighting it). Returns the tween (track it in a janitor to stop). Best on standalone
-- (non-list) CTAs so the scale doesn't nudge sibling layout.
function Builder.pulse(obj)
    local scale = obj:FindFirstChild("PulseScale")
    if scale == nil then
        scale = Builder.create("UIScale", { Name = "PulseScale", Scale = 1, Parent = obj })
    end
    local tween = TweenService:Create(
        scale,
        TweenInfo.new(
            Theme.Anim.PulsePeriod,
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut,
            -1,
            true
        ),
        { Scale = Theme.Anim.PulseScale }
    )
    tween:Play()
    return tween
end

-- Gentle vertical BOB (idle float) for an ABSOLUTELY-positioned element (e.g. a HUD icon glyph inside a
-- fixed-size chip). Oscillates Position.Y only; loops. Returns the tween.
function Builder.bob(obj)
    local p = obj.Position
    local up = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset - Theme.Anim.BobAmplitude)
    local tween = TweenService:Create(
        obj,
        TweenInfo.new(
            Theme.Anim.BobPeriod,
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut,
            -1,
            true
        ),
        { Position = up }
    )
    tween:Play()
    return tween
end

-- Soft SHIMMER: a white sheen overlay on `obj` whose transparency oscillates so the element feels alive.
-- Idempotent (guarded by the "Shimmer" child). Returns the tween.
function Builder.shimmer(obj)
    local sheen = obj:FindFirstChild("Shimmer")
    if sheen == nil then
        sheen = Builder.create("Frame", {
            Name = "Shimmer",
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Theme.Colors.White,
            BackgroundTransparency = 0.85,
            BorderSizePixel = 0,
            ZIndex = (obj.ZIndex or 1) + 1,
            Parent = obj,
        }, { Builder.corner(Theme.Radius.Button) })
    end
    local tween = TweenService:Create(
        sheen,
        TweenInfo.new(
            Theme.Anim.ShimmerPeriod,
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut,
            -1,
            true
        ),
        { BackgroundTransparency = 0.97 }
    )
    tween:Play()
    return tween
end

-- Animated number COUNT-UP: tweens a hidden NumberValue from->to and writes fmt(value) to `label`.
-- Cleans up the NumberValue + connection on completion. Returns the tween.
function Builder.countUp(label, from, to, fmt, dur)
    fmt = fmt or function(v)
        return tostring(math.floor(v))
    end
    local nv = Instance.new("NumberValue")
    nv.Value = from
    local conn = nv.Changed:Connect(function(v)
        label.Text = fmt(v)
    end)
    local tween = TweenService:Create(
        nv,
        TweenInfo.new(dur or 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Value = to }
    )
    tween.Completed:Connect(function()
        conn:Disconnect()
        nv:Destroy()
    end)
    tween:Play()
    return tween
end

-- Gentle infinite "floating in place" idle bob for a center-anchored panel (oscillates Position.Y only).
function Builder.floatLoop(frame)
    local p = frame.Position
    local tween = TweenService:Create(
        frame,
        TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale - 0.012, p.Y.Offset) }
    )
    tween:Play()
    return tween
end

-- A pop-in: snap to 0.85x then Back-ease up to full size. Call each time the panel opens.
function Builder.popOpen(frame)
    local target = frame:GetAttribute("PopTarget")
    if target == nil then
        target = frame.Size
        frame:SetAttribute("PopTarget", target)
    end
    frame.Size = UDim2.new(
        target.X.Scale * 0.85,
        target.X.Offset * 0.85,
        target.Y.Scale * 0.85,
        target.Y.Offset * 0.85
    )
    TweenService:Create(frame, Theme.Tween.Open, { Size = target }):Play()
end

-- Pop-OUT: scale the panel down + run onDone (gui.Enabled=false). Mirrors popOpen; resets size for next open.
function Builder.popClose(frame, onDone)
    local target = frame:GetAttribute("PopTarget") or frame.Size
    local small = UDim2.new(
        target.X.Scale * 0.82,
        target.X.Offset * 0.82,
        target.Y.Scale * 0.82,
        target.Y.Offset * 0.82
    )
    local tween = TweenService:Create(
        frame,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Size = small }
    )
    tween:Play()
    tween.Completed:Connect(function()
        frame.Size = target
        if onDone ~= nil then
            onDone()
        end
    end)
end

-- A mini DROPDOWN: a compact gloss button showing "Label: current"; clicking toggles a small option list
-- below it. `options` = array of strings, `current` = selected string, `onPick(value)` fires on choose.
function Builder.dropdown(props, options, current, onPick)
    props = props or {}
    local size = props.Size or UDim2.fromOffset(150, 34)
    local label = props.label or "Pick"
    local container = Builder.create("Frame", {
        Size = size,
        Position = props.Position,
        LayoutOrder = props.LayoutOrder,
        BackgroundTransparency = 1,
        Parent = props.Parent,
    })
    local trigger = Builder.glossButton({
        Size = UDim2.fromScale(1, 1),
        color = props.color or Theme.Colors.Row,
        Text = label .. ": " .. tostring(current),
        maxText = 15,
        Parent = container,
    }, nil)
    trigger.ZIndex = 6
    local list = Builder.create("Frame", {
        Position = UDim2.new(0, 0, 1, 4),
        Size = UDim2.fromOffset(size.X.Offset, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Colors.Panel,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 50,
        Parent = container,
    }, {
        Builder.corner(Theme.Radius.Button),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.Outline, Thickness = 2, Transparency = 0.2 }
        ),
        Builder.create(
            "UIListLayout",
            { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }
        ),
        Builder.padding(4),
    })
    local function setOpen(o)
        list.Visible = o
    end
    trigger.Activated:Connect(function()
        setOpen(not list.Visible)
    end)
    for i, opt in ipairs(options) do
        local ob = Builder.glossButton({
            Size = UDim2.new(1, -8, 0, 30),
            color = Theme.Colors.Row,
            Text = tostring(opt),
            maxText = 15,
            LayoutOrder = i,
            Parent = list,
        }, nil)
        ob.ZIndex = 51
        ob.Activated:Connect(function()
            trigger.Text = label .. ": " .. tostring(opt)
            setOpen(false)
            if onPick ~= nil then
                onPick(opt)
            end
        end)
    end
    return container
end

-- Apply the canonical GLOSSY chrome look to any frame/button so HUD elements match the panels: a vertical
-- accent gradient over a white base (so the gradient reads true), a top sheen, and the outline stroke.
-- Only adds children it doesn't already have. `accentKey` is a Theme.Accents key.
function Builder.glossify(obj, accentKey)
    obj.BackgroundColor3 = Theme.accentColor(accentKey)
    obj.BackgroundTransparency = 0.78
    if obj:FindFirstChild("GlossGradient") == nil then
        local g = Theme.gradient(accentKey)
        g.Name = "GlossGradient"
        g.Transparency = NumberSequence.new(0.6)
        g.Parent = obj
    end
    if obj:FindFirstChild("GlossSheen") == nil then
        Builder.create("Frame", {
            Name = "GlossSheen",
            Size = UDim2.fromScale(1, 0.4),
            BackgroundColor3 = Theme.Colors.White,
            BackgroundTransparency = 0.9,
            BorderSizePixel = 0,
            ZIndex = 0,
            Parent = obj,
        }, { Builder.corner(Theme.Radius.Button) })
    end
    local stroke = obj:FindFirstChildOfClass("UIStroke")
    if stroke == nil then
        stroke = Builder.create("UIStroke", { Parent = obj })
    end
    stroke.Color = Theme.accentColor(accentKey)
    stroke.Thickness = 3
    stroke.Transparency = 0
    return obj
end

-- Builds the standard centered modal panel: a translucent gradient body with a thick dark outline,
-- a glossy accent header (icon-less title + round red X), and a styled scrolling content area.
-- `accentKey` (optional) picks the header gradient from Theme.Accents. Returns the ScrollingFrame.
function Builder.panel(parent, title, onClose, accentKey)
    -- Each panel's title matches a Theme.Accents key (Shop/Index/Trade/...), so the accent is
    -- auto-derived -- no per-panel wiring. Pass accentKey explicitly to override.
    accentKey = accentKey or (Theme.Accents[title] ~= nil and title) or "Default"
    local panel = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.86, 0.74),
        BackgroundColor3 = Theme.Colors.Cloud, -- LIGHT airy cloud body (was dark grape)
        BackgroundTransparency = Theme.BodyTransparency,
        BorderSizePixel = 0,
    }, {
        Builder.corner(Theme.Radius.Panel),
        Builder.create("UIStroke", { -- soft accent glow rim
            Color = Theme.accentColor(accentKey),
            Thickness = 3,
            Transparency = 0.1,
        }),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(580, 760) }),
        Builder.create("UIGradient", { -- bright-gloss top -> soft cloud body
            Rotation = 90,
            Color = ColorSequence.new(Theme.Colors.CloudTop, Theme.Colors.Cloud),
        }),
    })
    -- Mark as already glassed so PanelManager's UIStyle.applyGlass skips it (no double styling).
    panel:SetAttribute("Glassed", true)

    Builder.glossHeader(panel, title, accentKey, onClose)

    local list = Builder.create("ScrollingFrame", {
        Position = UDim2.fromOffset(8, Theme.HeaderHeight + 16),
        Size = UDim2.new(1, -16, 1, -(Theme.HeaderHeight + 24)),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = panel,
    }, {
        Builder.create("UIListLayout", {
            Padding = UDim.new(0, 14),
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        }),
        Builder.padding(12),
    })
    Builder.styleScroll(list)

    panel.Parent = parent
    -- Soft drop shadow behind the centered panel (sibling under the ScreenGui; absolute position).
    Builder.softShadow(panel, { radius = Theme.Radius.Panel })
    Builder.floatLoop(panel)
    -- Self pop-open ONLY for popups NOT coordinated by PanelManager (it owns the open/close anim for
    -- registered primary panels and sets PMManaged, so this avoids a double pop on those).
    if parent ~= nil and parent:IsA("ScreenGui") then
        parent:GetPropertyChangedSignal("Enabled"):Connect(function()
            if parent.Enabled and not panel:GetAttribute("PMManaged") then
                Builder.popOpen(panel)
            end
        end)
        if parent.Enabled and not panel:GetAttribute("PMManaged") then
            Builder.popOpen(panel)
        end
    end
    return list
end

return Builder
