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

local Format = require(ReplicatedStorage.Shared.Format)
local Monetization = require(ReplicatedStorage.Shared.Monetization)

local LeaderboardService = require(script.Parent.LeaderboardService)
local SeasonService = require(script.Parent.SeasonService)

local LeaderboardBillboards = {}

local TOP_N = Monetization.Leaderboard.TopN
local REFRESH = 5 -- s between (cheap, in-memory) billboard redraws
local FIRST_STAND = Vector3.new(80, 0, -40) -- base of the left-most stand
local STAND_SPACING = 44 -- studs between stands

local COLORS = {
    Pillar = Color3.fromRGB(28, 31, 40),
    Panel = Color3.fromRGB(22, 24, 31),
    Title = Color3.fromRGB(240, 242, 248),
    Name = Color3.fromRGB(210, 214, 224),
    Value = Color3.fromRGB(120, 220, 150),
    Empty = Color3.fromRGB(90, 96, 110),
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

    -- ── MAIN PILLAR (the adornee for the BillboardGui -- position/size unchanged) ──────────────
    local pillar = Instance.new("Part")
    pillar.Name = "LeaderboardStand_" .. board.Key
    pillar.Anchored = true
    pillar.CanCollide = true
    pillar.Size = Vector3.new(4, 14, 4)
    pillar.Position = basePosition + Vector3.new(0, 7, 0)
    pillar.Color = COLORS.Pillar
    pillar.Material = Enum.Material.SmoothPlastic
    pillar.Parent = folder

    -- ── SIDE POSTS framing the board (two wood columns flanking the billboard face) ────────────
    for _, sx in ipairs({ -1, 1 }) do
        standPart({
            Size = Vector3.new(1.5, 20, 1.5),
            Position = basePosition + Vector3.new(sx * 6, 10, 0),
            Color = SP.Beam,
            Material = Enum.Material.Wood,
        }, podiumFolder)
    end

    -- ── WOOD FRAME around the billboard face (4 thin P.Beam strips bordering the SurfaceGui area)
    -- The BillboardGui sits at StudsOffset (0,11,0) from pillar centre; board face is at pillar +Z.
    -- Frame centre matches the billboard visual centre: basePosition + (0, 7+11, 0) = (0, 18, 0).
    local frameCX = basePosition.X
    local frameCY = basePosition.Y + 18
    local frameCZ = basePosition.Z + 2.5 -- just in front of the pillar front face
    local frameW, frameH = 11, 14 -- slightly larger than the BillboardGui StudsOffset footprint
    standPart({
        Size = Vector3.new(frameW, 1, 1),
        Position = Vector3.new(frameCX, frameCY + frameH / 2, frameCZ),
        Color = SP.Beam,
        Material = Enum.Material.Wood,
    }, podiumFolder) -- top bar
    standPart({
        Size = Vector3.new(frameW, 1, 1),
        Position = Vector3.new(frameCX, frameCY - frameH / 2, frameCZ),
        Color = SP.Beam,
        Material = Enum.Material.Wood,
    }, podiumFolder) -- bottom bar
    for _, sx in ipairs({ -1, 1 }) do
        standPart({
            Size = Vector3.new(1, frameH, 1),
            Position = Vector3.new(frameCX + sx * frameW / 2, frameCY, frameCZ),
            Color = SP.Beam,
            Material = Enum.Material.Wood,
        }, podiumFolder) -- side bars
    end

    -- ── THEMED TOPPER above the board ────────────────────────────────────────────────────────────
    -- topY = top of the board frame
    buildTopper(board.Key, basePosition, frameCY + frameH / 2 + 0.5, podiumFolder)

    -- ── BILLBOARDGUI (adornee = pillar; position/size/StudsOffset UNCHANGED so live text binds) ─
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Board"
    billboard.Size = UDim2.fromScale(10, 12)
    billboard.StudsOffset = Vector3.new(0, 11, 0)
    billboard.MaxDistance = 250
    billboard.Adornee = pillar
    billboard.Parent = pillar

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromScale(1, 1)
    panel.BackgroundColor3 = COLORS.Panel
    panel.BackgroundTransparency = 0.2
    panel.BorderSizePixel = 0
    panel.Parent = billboard
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = panel
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 2)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = panel

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 34)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = board.Title
    title.TextColor3 = COLORS.Title
    title.TextScaled = true
    title.LayoutOrder = 0
    title.Parent = panel

    local rowFrames = {}
    for i = 1, TOP_N do
        local row = Instance.new("Frame")
        row.Name = "Row" .. i
        row.Size = UDim2.new(1, 0, 0, 24)
        row.BackgroundTransparency = 1
        row.LayoutOrder = i
        row.Parent = panel

        local left = Instance.new("TextLabel")
        left.Name = "Left"
        left.Size = UDim2.fromScale(0.7, 1)
        left.BackgroundTransparency = 1
        left.Font = Enum.Font.GothamMedium
        left.TextColor3 = COLORS.Name
        left.TextScaled = true
        left.TextXAlignment = Enum.TextXAlignment.Left
        left.Text = ""
        left.Parent = row

        local right = Instance.new("TextLabel")
        right.Name = "Right"
        right.AnchorPoint = Vector2.new(1, 0)
        right.Position = UDim2.fromScale(1, 0)
        right.Size = UDim2.fromScale(0.3, 1)
        right.BackgroundTransparency = 1
        right.Font = Enum.Font.GothamBold
        right.TextColor3 = COLORS.Value
        right.TextScaled = true
        right.TextXAlignment = Enum.TextXAlignment.Right
        right.Text = ""
        right.Parent = row

        rowFrames[i] = { Frame = row, Left = left, Right = right }
    end

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
    for index, board in ipairs(boards) do
        local basePosition = FIRST_STAND + Vector3.new((index - 1) * STAND_SPACING, 0, 0)
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
    local seasonPos = FIRST_STAND + Vector3.new(#boards * STAND_SPACING, 0, 0)
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
