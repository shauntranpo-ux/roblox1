-- Minimap (VM-THEME): a top-right circular frame with a blue ring, N/E/S/W compass letters that orbit
-- OPPOSITE the camera heading (letters stay upright -- positioned by trig, not rotated), and a center
-- player arrow. HONEST SCOPE: this is the styled frame + rotating compass + player dot ONLY. A fully
-- live top-down WORLD-RENDER minimap (ViewportFrame) is a heavier optional system -- Minimap.setDots()
-- + the upgrade note below are the clean hooks to add it later. No fake live render here.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Minimap = {}

local gui = nil
local letters = {}
local dotsFolder = nil

function Minimap.mount(context)
    local player = context.player
    gui = Builder.screenGui("Minimap", player:WaitForChild("PlayerGui"), true)
    gui.DisplayOrder = 7

    local frame = Builder.create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(0.985, 0.03),
        Size = UDim2.fromScale(0.12, 0.12),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Parent = gui,
    }, {
        Builder.corner(UDim.new(1, 0)),
        -- blue ring
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.XpFill, Thickness = 4, Transparency = 0.05 }
        ),
        Builder.create("UIAspectRatioConstraint", { AspectRatio = 1 }),
        Builder.create(
            "UISizeConstraint",
            { MinSize = Vector2.new(86, 86), MaxSize = Vector2.new(150, 150) }
        ),
    })

    dotsFolder = Builder.create("Folder", { Name = "Dots", Parent = frame })

    -- Center player arrow (points up = camera-forward; the world/compass rotates around it).
    local arrow = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.4, 0.4),
        BackgroundTransparency = 1,
        Text = "▲",
        TextColor3 = Theme.Colors.PathRed,
        TextScaled = true,
        Parent = frame,
    })
    Builder.styleText(arrow, { keepColor = true })

    letters = {}
    for _, def in ipairs({
        { t = "N", a = 0 },
        { t = "E", a = 90 },
        { t = "S", a = 180 },
        { t = "W", a = 270 },
    }) do
        local letterLabel = Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromScale(0.2, 0.2),
            BackgroundTransparency = 1,
            Text = def.t,
            TextColor3 = def.t == "N" and Theme.Colors.PathRed or Theme.Colors.White,
            TextScaled = true,
            Parent = frame,
        })
        Builder.styleText(letterLabel, { keepColor = true })
        table.insert(letters, { label = letterLabel, base = def.a })
    end

    -- Orbit the compass letters opposite the camera heading; keep glyphs upright.
    RunService.RenderStepped:Connect(function()
        local camera = Workspace.CurrentCamera
        if camera == nil then
            return
        end
        local look = camera.CFrame.LookVector
        local headingDeg = math.deg(math.atan2(look.X, look.Z))
        for _, entry in ipairs(letters) do
            local ang = math.rad(entry.base - headingDeg)
            entry.label.Position =
                UDim2.fromScale(0.5 + 0.38 * math.sin(ang), 0.5 - 0.38 * math.cos(ang))
        end
    end)
end

-- HOOK (optional): plot nearby base/zone dots. `dots` = { { x01, y01, color }, ... } in [0,1] frame
-- space. No-ops with no data. (A full live world-render minimap would replace the frame's interior
-- with a ViewportFrame; this dot API + the styled frame are the clean upgrade seam.)
function Minimap.setDots(dots)
    if dotsFolder == nil then
        return
    end
    dotsFolder:ClearAllChildren()
    if type(dots) ~= "table" then
        return
    end
    for _, d in ipairs(dots) do
        Builder.create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(d.x or 0.5, d.y or 0.5),
            Size = UDim2.fromOffset(8, 8),
            BackgroundColor3 = d.color or Theme.Colors.White,
            BorderSizePixel = 0,
            Parent = dotsFolder,
        }, { Builder.corner(UDim.new(1, 0)) })
    end
end

return Minimap
