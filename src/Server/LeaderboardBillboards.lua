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

-- Builds the generated pillar + BillboardGui for one board and returns an Update(rows) closure.
local function buildGeneratedStand(board, basePosition)
    local pillar = Instance.new("Part")
    pillar.Name = "LeaderboardStand_" .. board.Key
    pillar.Anchored = true
    pillar.CanCollide = true
    pillar.Size = Vector3.new(4, 14, 4)
    pillar.Position = basePosition + Vector3.new(0, 7, 0)
    pillar.Color = COLORS.Pillar
    pillar.Material = Enum.Material.SmoothPlastic
    pillar.Parent = folder

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
