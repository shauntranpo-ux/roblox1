-- LeaderboardBillboards: the physical, in-world leaderboard displays -- one stand per board
-- (Top Cash / Top Income / Rarest Collection), each a code-generated pillar + a BillboardGui
-- ranked list that refreshes from LeaderboardService on a light cadence. Mobile-readable
-- (BillboardGui faces the camera, large TextScaled rows). Placed in a central hub behind the
-- plot row.
--
-- FORWARD-COMPAT: if a Model named "LeaderboardStand" exists in ServerStorage/Assets, we clone
-- THAT per board instead of generating a pillar, and fill its labels -- a "Title" TextLabel and
-- TextLabels named "Row1".."RowN" (N = Leaderboard.TopN). Same art-swap pattern as plots.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Format = require(ReplicatedStorage.Shared.Format)
local Monetization = require(ReplicatedStorage.Shared.Monetization)

local LeaderboardService = require(script.Parent.LeaderboardService)
local SeasonService = require(script.Parent.SeasonService)

local LeaderboardBillboards = {}

local TOP_N = Monetization.Leaderboard.TopN
local REFRESH = 5 -- s between (cheap, in-memory) billboard redraws
local FIRST_STAND = Vector3.new(80, 0, -40) -- base of the left-most stand
local STAND_SPACING = 44 -- studs between stands

-- Soft / bubbly leaderboard palette (cohesive with the UI design system): a LIGHT cream board with
-- INK names + a bright per-board accent title bar, on a warm wood pillar (was near-black slabs).
local COLORS = {
    Pillar = Color3.fromRGB(150, 116, 80), -- warm wood backing pillar (was near-black)
    Panel = Color3.fromRGB(248, 245, 255), -- soft cream/lavender board (was near-black)
    Title = Color3.fromRGB(255, 255, 255), -- white title on the bright accent bar
    Name = Color3.fromRGB(74, 58, 122), -- INK names on the light board
    Value = Color3.fromRGB(46, 170, 96), -- income green values
    Empty = Color3.fromRGB(150, 142, 172), -- soft muted "no entries"
}
-- Per-board accent for the title bar (matches the UI accent families).
local BOARD_ACCENT = {
    Cash = Color3.fromRGB(240, 178, 40), -- gold
    Income = Color3.fromRGB(74, 184, 114), -- green
    Collection = Color3.fromRGB(224, 96, 168), -- pink
    Season = Color3.fromRGB(120, 150, 235), -- blue
}

local folder = nil
local stands = {} -- array of { Key, Update = function(rows) }

local function formatRow(entry)
    return string.format("%d.  %s", entry.Rank, entry.Name), "$" .. Format.short(entry.Value)
end

-- Helper: one anchored part parented to a model/folder (mirrors WorldBuilder's part() mini-helper).
local function standPart(props, parent)
    local p = Instance.new("Part")
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Size = props.Size
    p.Color = props.Color or Color3.fromRGB(235, 235, 235)
    p.Material = props.Material or Enum.Material.SmoothPlastic
    p.CFrame = props.CFrame or CFrame.new(props.Position or Vector3.zero)
    if props.Shape ~= nil then
        p.Shape = props.Shape
    end
    p.Parent = parent
    return p
end

-- Shared palette refs (mirrors WorldBuilder P; defined here to avoid a cross-require).
local SP = {
    Stone = Color3.fromRGB(163, 162, 165),
    Beam = Color3.fromRGB(140, 108, 72),
    Wood = Color3.fromRGB(106, 74, 42),
    Gold = Color3.fromRGB(251, 197, 49),
    Grape = Color3.fromRGB(107, 50, 124),
    Pillar = Color3.fromRGB(28, 31, 40),
    Panel = Color3.fromRGB(22, 24, 31),
}

-- Themed TOPPER geometry added above the board panel per board identity.
-- `topY` = Y position of the top of the board; parts are placed above that.
local function buildTopper(key, basePosition, topY, podiumFolder)
    local tx = basePosition.X
    local tz = basePosition.Z
    if key == "Cash" then
        -- Gold coin (cylinder on its side, face toward player)
        local coinCF = CFrame.new(tx, topY + 4, tz) * CFrame.Angles(0, 0, math.rad(90))
        local coin = standPart(
            { Size = Vector3.new(1.5, 8, 8), CFrame = coinCF, Color = SP.Gold },
            podiumFolder
        )
        coin.Shape = Enum.PartType.Cylinder
        -- Inner ring cutout illusion: smaller darker cylinder
        local innerCF = CFrame.new(tx, topY + 4, tz) * CFrame.Angles(0, 0, math.rad(90))
        local inner = standPart({
            Size = Vector3.new(1.6, 4, 4),
            CFrame = innerCF,
            Color = Color3.fromRGB(200, 155, 30),
        }, podiumFolder)
        inner.Shape = Enum.PartType.Cylinder
    elseif key == "Income" then
        -- Clock face: flat cylinder disc + two hand blocks
        local clockCF = CFrame.new(tx, topY + 5, tz) * CFrame.Angles(0, 0, math.rad(90))
        local clock = standPart({
            Size = Vector3.new(1.2, 8, 8),
            CFrame = clockCF,
            Color = Color3.fromRGB(240, 238, 228),
        }, podiumFolder)
        clock.Shape = Enum.PartType.Cylinder
        -- Hour hand (short, points to ~2 o'clock)
        local hourCF = CFrame.new(tx, topY + 6.5, tz)
            * CFrame.Angles(math.rad(-30), 0, math.rad(90))
            * CFrame.new(0, 0, -1.5)
        standPart(
            { Size = Vector3.new(1.3, 1, 3), CFrame = hourCF, Color = SP.Pillar },
            podiumFolder
        )
        -- Minute hand (long, points straight up)
        local minCF = CFrame.new(tx, topY + 6.5, tz)
            * CFrame.Angles(0, 0, math.rad(90))
            * CFrame.new(0, 0, -2)
        standPart(
            { Size = Vector3.new(1.3, 0.8, 4), CFrame = minCF, Color = SP.Pillar },
            podiumFolder
        )
    elseif key == "Collection" then
        -- Gem: a tall tapered block (Grape/purple)
        standPart({
            Size = Vector3.new(3.5, 7, 3.5),
            Position = Vector3.new(tx, topY + 5.5, tz),
            Color = SP.Grape,
        }, podiumFolder)
        -- Facet cap (lighter tip)
        standPart({
            Size = Vector3.new(2, 3, 2),
            Position = Vector3.new(tx, topY + 10.5, tz),
            Color = Color3.fromRGB(160, 100, 190),
        }, podiumFolder)
    else
        -- Trophy (Top Season): base cup + stem + handles
        -- Cup body
        standPart({
            Size = Vector3.new(6, 5, 4),
            Position = Vector3.new(tx, topY + 5.5, tz),
            Color = SP.Gold,
        }, podiumFolder)
        -- Stem
        standPart({
            Size = Vector3.new(1.5, 3, 1.5),
            Position = Vector3.new(tx, topY + 2.5, tz),
            Color = SP.Gold,
        }, podiumFolder)
        -- Trophy handles (left + right small blocks)
        for _, sx in ipairs({ -1, 1 }) do
            standPart({
                Size = Vector3.new(2, 3, 1),
                Position = Vector3.new(tx + sx * 4, topY + 5.5, tz),
                Color = SP.Gold,
            }, podiumFolder)
        end
        -- Gold star on top of cup
        standPart({
            Size = Vector3.new(3, 3, 1),
            Position = Vector3.new(tx, topY + 9, tz),
            Color = SP.Gold,
        }, podiumFolder)
    end
end

-- Builds the generated pillar + BillboardGui for one board and returns an Update(rows) closure.
local function buildGeneratedStand(board, basePosition)
    -- ── PODIUM GEOMETRY ─────────────────────────────────────────────────────────────────────────
    -- Stepped stone pedestal: 3 tiers beneath the pillar.
    local podiumFolder = Instance.new("Folder")
    podiumFolder.Name = "Podium_" .. board.Key
    podiumFolder.Parent = folder

    -- Tier 1 (widest, ground level)
    standPart({
        Size = Vector3.new(14, 3, 8),
        Position = basePosition + Vector3.new(0, 1.5, 0),
        Color = SP.Stone,
        Material = Enum.Material.Slate,
    }, podiumFolder)
    -- Tier 2
    standPart({
        Size = Vector3.new(11, 2, 6),
        Position = basePosition + Vector3.new(0, 4, 0),
        Color = SP.Beam,
        Material = Enum.Material.Wood,
    }, podiumFolder)
    -- Tier 3 (top step, transitions to the pillar)
    standPart({
        Size = Vector3.new(8, 1.5, 5),
        Position = basePosition + Vector3.new(0, 5.75, 0),
        Color = SP.Stone,
        Material = Enum.Material.SmoothPlastic,
    }, podiumFolder)

    -- ── MAIN PILLAR (thin backing column connecting pedestal to wall base) ───────────────────────
    local pillar = Instance.new("Part")
    pillar.Name = "LeaderboardStand_" .. board.Key
    pillar.Anchored = true
    pillar.CanCollide = true
    pillar.Size = Vector3.new(4, 7, 4)
    pillar.Position = basePosition + Vector3.new(0, 3.5 + 5.75, 0) -- sits on top of tier-3 (y=6.5)
    pillar.Color = COLORS.Pillar
    pillar.Material = Enum.Material.SmoothPlastic
    pillar.Parent = folder

    -- ── 3-D SCROLLING WALL (replaces old floating BillboardGui; physical Part + SurfaceGui) ─────
    -- Wall: Size(18,22,1), front face (+Z). Bottom sits on pillar top (pillar top = 6.5+7 = 13.5).
    local wallH = 22
    local wallW = 18
    local wallCY = 13.5 + wallH / 2 -- wall centre Y
    local wall = standPart({
        Size = Vector3.new(wallW, wallH, 1),
        Position = basePosition + Vector3.new(0, wallCY, 0),
        Color = COLORS.Panel,
        Material = Enum.Material.SmoothPlastic,
    }, podiumFolder)
    wall.Name = "LeaderboardWall_" .. board.Key

    -- ── SIDE POSTS framing the wall (two wood columns flanking the wall face) ─────────────────
    for _, sx in ipairs({ -1, 1 }) do
        standPart({
            Size = Vector3.new(1.5, wallCY + wallH / 2 + 1, 1.5),
            Position = basePosition
                + Vector3.new(sx * (wallW / 2 + 1), (wallCY + wallH / 2 + 1) / 2, 0),
            Color = SP.Beam,
            Material = Enum.Material.Wood,
        }, podiumFolder)
    end

    -- ── WOOD FRAME around the wall face (4 thin P.Beam strips bordering the SurfaceGui area) ────
    local frameCX = basePosition.X
    local frameCY = wallCY
    local frameCZ = basePosition.Z + 1 -- just proud of the wall front face
    local frameW, frameH = wallW + 1, wallH + 1
    standPart({
        Size = Vector3.new(frameW, 1, 1),
        Position = Vector3.new(frameCX, frameCY + wallH / 2 + 0.5, frameCZ),
        Color = SP.Beam,
        Material = Enum.Material.Wood,
    }, podiumFolder) -- top bar
    standPart({
        Size = Vector3.new(frameW, 1, 1),
        Position = Vector3.new(frameCX, frameCY - wallH / 2 - 0.5, frameCZ),
        Color = SP.Beam,
        Material = Enum.Material.Wood,
    }, podiumFolder) -- bottom bar
    for _, sx in ipairs({ -1, 1 }) do
        standPart({
            Size = Vector3.new(1, frameH, 1),
            Position = Vector3.new(frameCX + sx * (wallW / 2 + 0.5), frameCY, frameCZ),
            Color = SP.Beam,
            Material = Enum.Material.Wood,
        }, podiumFolder) -- side bars
    end

    -- ── THEMED TOPPER above the wall ─────────────────────────────────────────────────────────────
    buildTopper(board.Key, basePosition, frameCY + wallH / 2 + 1, podiumFolder)

    -- ── SURFACEGUI on the wall's front face (physical, not camera-facing) ────────────────────────
    -- CanvasSize is tall enough for the title + all TOP_N rows with room to scroll.
    local ROW_PX = 48 -- pixels per row in the canvas
    local TITLE_PX = 56
    local canvasH = TITLE_PX + TOP_N * ROW_PX + 40 -- a bit of bottom padding
    local sg = Instance.new("SurfaceGui")
    sg.Name = "Board"
    sg.Face = Enum.NormalId.Front
    sg.CanvasSize = Vector2.new(480, canvasH)
    sg.Adornee = wall
    sg.Parent = wall

    local accent = BOARD_ACCENT[board.Key] or BOARD_ACCENT.Cash

    -- Soft cream panel background with rounded corners + a bright accent rim (bubbly board look).
    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Size = UDim2.fromScale(1, 1)
    panel.BackgroundColor3 = COLORS.Panel
    panel.BackgroundTransparency = 0.05
    panel.BorderSizePixel = 0
    panel.Parent = sg
    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 28)
    panelCorner.Parent = panel
    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = accent
    panelStroke.Thickness = 5
    panelStroke.Transparency = 0.1
    panelStroke.Parent = panel

    -- Title bar at the top of the panel (fixed, not scrolled) -- bright accent + bubble font.
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -16, 0, TITLE_PX)
    title.Position = UDim2.fromOffset(8, 8)
    title.BackgroundColor3 = accent
    title.BackgroundTransparency = 0
    title.BorderSizePixel = 0
    title.Font = Enum.Font.FredokaOne
    title.Text = board.Title
    title.TextColor3 = COLORS.Title
    title.TextStrokeColor3 = Color3.fromRGB(36, 22, 60)
    title.TextStrokeTransparency = 0.2
    title.TextScaled = true
    title.Parent = panel
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 20)
    titleCorner.Parent = title

    -- Rows container: a Frame that will be tweened to scroll upward.
    -- Starts at the top (just below the title) and scrolls until all rows are off-screen,
    -- then resets to the top and loops.
    local ROWS_TOP = TITLE_PX + 20 -- clear the inset title bar
    local rowContainer = Instance.new("Frame")
    rowContainer.Name = "RowContainer"
    rowContainer.Size = UDim2.new(1, -16, 0, TOP_N * ROW_PX)
    rowContainer.Position = UDim2.fromOffset(8, ROWS_TOP)
    rowContainer.BackgroundTransparency = 1
    rowContainer.ClipsDescendants = false
    rowContainer.Parent = panel

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 2)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = rowContainer

    -- Build row frames (same structure + names as old BillboardGui rows so Update binding is identical)
    local rowFrames = {}
    for i = 1, TOP_N do
        local row = Instance.new("Frame")
        row.Name = "Row" .. i
        row.Size = UDim2.new(1, 0, 0, ROW_PX - 2)
        row.BackgroundTransparency = 1
        row.LayoutOrder = i
        row.Parent = rowContainer

        local left = Instance.new("TextLabel")
        left.Name = "Left"
        left.Size = UDim2.fromScale(0.68, 1)
        left.Position = UDim2.fromOffset(8, 0)
        left.BackgroundTransparency = 1
        left.Font = Enum.Font.FredokaOne
        left.TextColor3 = COLORS.Name
        left.TextScaled = true
        left.TextXAlignment = Enum.TextXAlignment.Left
        left.Text = ""
        left.Parent = row

        local right = Instance.new("TextLabel")
        right.Name = "Right"
        right.AnchorPoint = Vector2.new(1, 0)
        right.Position = UDim2.new(1, -8, 0, 0)
        right.Size = UDim2.fromScale(0.3, 1)
        right.BackgroundTransparency = 1
        right.Font = Enum.Font.FredokaOne
        right.TextColor3 = COLORS.Value
        right.TextScaled = true
        right.TextXAlignment = Enum.TextXAlignment.Right
        right.Text = ""
        right.Parent = row

        rowFrames[i] = { Frame = row, Left = left, Right = right }
    end

    -- ── AUTO-SCROLL via TweenService: rows slide upward, then snap back to top and repeat ────────
    -- Scroll distance = full height of the row container. Duration scales with row count.
    local scrollDuration = TOP_N * 1.5
    local scrollInfo =
        TweenInfo.new(scrollDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.In)
    task.spawn(function()
        while true do
            -- Reset to the row container's resting spot (x=8 inset, y=ROWS_TOP), then tween upward.
            rowContainer.Position = UDim2.fromOffset(8, ROWS_TOP)
            local targetY = ROWS_TOP - TOP_N * ROW_PX
            local tween = TweenService:Create(rowContainer, scrollInfo, {
                Position = UDim2.fromOffset(8, targetY),
            })
            tween:Play()
            tween.Completed:Wait()
            task.wait(0.5) -- brief pause at the bottom before looping
        end
    end)

    -- ── UPDATE closure: same signature as before; rebuilds row text on each leaderboard refresh ──
    return function(rows)
        for i = 1, TOP_N do
            local slot = rowFrames[i]
            local entry = rows[i]
            if entry ~= nil then
                local nameText, valueText = formatRow(entry)
                slot.Left.Text = nameText
                slot.Left.TextColor3 = COLORS.Name
                slot.Right.Text = valueText
            elseif i == 1 then
                slot.Left.Text = "(no entries yet)"
                slot.Left.TextColor3 = COLORS.Empty
                slot.Right.Text = ""
            else
                slot.Left.Text = ""
                slot.Right.Text = ""
            end
        end
    end
end

-- Clones a real LeaderboardStand art model and returns an Update(rows) closure that fills its
-- "Title" + "Row1".."RowN" TextLabels. Falls back gracefully if a label is missing.
local function buildTemplateStand(template, board, basePosition)
    local model = template:Clone()
    model.Name = "LeaderboardStand_" .. board.Key
    if model:IsA("Model") then
        model:PivotTo(CFrame.new(basePosition + Vector3.new(0, 7, 0)))
    end
    model.Parent = folder

    local titleLabel = model:FindFirstChild("Title", true)
    if titleLabel ~= nil and titleLabel:IsA("TextLabel") then
        titleLabel.Text = board.Title
    end

    return function(rows)
        for i = 1, TOP_N do
            local label = model:FindFirstChild("Row" .. i, true)
            if label ~= nil and label:IsA("TextLabel") then
                local entry = rows[i]
                if entry ~= nil then
                    local nameText, valueText = formatRow(entry)
                    label.Text = nameText .. "   " .. valueText
                else
                    label.Text = ""
                end
            end
        end
    end
end

local function getTemplate()
    local assets = ServerStorage:FindFirstChild("Assets")
    if assets ~= nil then
        return assets:FindFirstChild("LeaderboardStand")
    end
    return nil
end

function LeaderboardBillboards.Init()
    if folder ~= nil then
        return
    end
    folder = Instance.new("Folder")
    folder.Name = "Leaderboards"
    folder.Parent = workspace

    local template = getTemplate()
    local boards = LeaderboardService.GetBoardList()
    -- Center the (#boards + 1 Season) stands as a tidy GROUNDED row on the plaza (was scattered out
    -- past the courtyard edge onto the meadow / the new foliage ring). Stands fan out from `base`.
    local base = Vector3.new(-(#boards * STAND_SPACING) / 2, FIRST_STAND.Y, FIRST_STAND.Z)
    for index, board in ipairs(boards) do
        local basePosition = base + Vector3.new((index - 1) * STAND_SPACING, 0, 0)
        local boardKey = board.Key
        local update
        if template ~= nil then
            update = buildTemplateStand(template, board, basePosition)
        else
            update = buildGeneratedStand(board, basePosition)
        end
        table.insert(stands, {
            Update = update,
            Source = function()
                return LeaderboardService.GetBoard(boardKey)
            end,
        })
    end

    -- M8.5: a 4th stand for the CURRENT SEASON board (reads SeasonService's cached top-N).
    local seasonPos = base + Vector3.new(#boards * STAND_SPACING, 0, 0)
    local seasonBoard = { Key = "Season", Title = "Top Season" }
    local seasonUpdate = template ~= nil and buildTemplateStand(template, seasonBoard, seasonPos)
        or buildGeneratedStand(seasonBoard, seasonPos)
    table.insert(stands, { Update = seasonUpdate, Source = SeasonService.GetTop })

    -- Light redraw loop: reads each stand's cached top-N (no DataStore calls here).
    task.spawn(function()
        while true do
            for _, stand in ipairs(stands) do
                stand.Update(stand.Source())
            end
            task.wait(REFRESH)
        end
    end)
end

return LeaderboardBillboards
