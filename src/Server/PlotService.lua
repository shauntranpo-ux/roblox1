-- PlotService: builds the player bases and assigns one per session.
--
-- For M1 the plots are generated procedurally from plain anchored Parts. FORWARD-
-- COMPATIBILITY: if a Model named Config.Plots.TemplateName exists in
-- ServerStorage/Assets, we clone THAT instead and just read its numbered pads, so
-- swapping in real art later needs zero logic changes (see buildPlot()).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PlotService = {}

local PLOT_SIZE = Vector3.new(32, 1, 32)
local PAD_SIZE = Vector3.new(6, 1, 6)

local plots = {} -- array of plot records (see PlotService.Init)
local assigned = {} -- [Player] = plot record
local reserved = {} -- [Player] = { [padIndex] = true } pads held for an in-progress steal deposit
local plotsFolder = nil

-- Looks for an optional art Model in ServerStorage/Assets. Returns nil in M1.
local function getTemplate()
    local assets = ServerStorage:FindFirstChild("Assets")
    if assets ~= nil then
        return assets:FindFirstChild(Config.Plots.TemplateName)
    end
    return nil
end

-- Visible number on top of a pad so each stand is clearly identifiable.
local function addPadLabel(pad, index)
    local surface = Instance.new("SurfaceGui")
    surface.Face = Enum.NormalId.Top
    surface.Adornee = pad
    surface.CanvasSize = Vector2.new(200, 200)
    surface.Parent = pad

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = tostring(index)
    label.TextColor3 = Color3.fromRGB(20, 20, 20)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = surface
end

-- Generates one procedural plot at the given world origin. Returns a Model whose
-- children include a "Base" part and "Pad1".."PadN" parts -- the same shape a real
-- template Model is expected to follow.
local function buildProceduralPlot(index, origin)
    local model = Instance.new("Model")
    model.Name = "Plot" .. index

    local base = Instance.new("Part")
    base.Name = "Base"
    base.Anchored = true
    base.Size = PLOT_SIZE
    base.CFrame = origin
    base.Color = Color3.fromRGB(85, 90, 100)
    base.Material = Enum.Material.SmoothPlastic
    base.Parent = model

    local count = Config.Plots.PadsPerPlot
    for padIndex = 1, count do
        local offsetX = (padIndex - (count + 1) / 2) * Config.Plots.PadSpacing
        local pad = Instance.new("Part")
        pad.Name = "Pad" .. padIndex
        pad.Anchored = true
        pad.Size = PAD_SIZE
        pad.CFrame = origin * CFrame.new(offsetX, PLOT_SIZE.Y / 2 + PAD_SIZE.Y / 2, 0)
        pad.Color = Color3.fromRGB(120, 200, 130)
        pad.Material = Enum.Material.Neon
        pad.Parent = model
        addPadLabel(pad, padIndex)
    end

    model.PrimaryPart = base
    return model
end

-- Builds a single plot: clones the art template if present, else generates parts.
local function buildPlot(index, origin)
    local template = getTemplate()
    local model
    if template ~= nil then
        -- Real-art path (later milestones). The template Model must contain parts
        -- named "Pad1".."PadN" matching Config.Plots.PadsPerPlot.
        model = template:Clone()
        model.Name = "Plot" .. index
        model:PivotTo(origin)
    else
        model = buildProceduralPlot(index, origin)
    end
    return model
end

-- Creates every plot in the world. Call once at startup.
function PlotService.Init()
    if plotsFolder ~= nil then
        return
    end

    plotsFolder = Instance.new("Folder")
    plotsFolder.Name = "Plots"
    plotsFolder.Parent = workspace

    for index = 1, Config.Plots.Count do
        local origin = CFrame.new((index - 1) * Config.Plots.Spacing, 0, 0)
        local model = buildPlot(index, origin)
        model.Parent = plotsFolder

        local pads = {}
        for padIndex = 1, Config.Plots.PadsPerPlot do
            pads[padIndex] = model:FindFirstChild("Pad" .. padIndex, true)
        end

        plots[index] = {
            Index = index,
            Model = model,
            Pads = pads,
            Owner = nil,
            Origin = origin, -- plot center CFrame (used to place the protection dome)
            -- Where the player's character is placed so the plot reads as "their base".
            SpawnCFrame = origin * CFrame.new(0, 6, 14),
        }
    end
end

-- Assigns the first free plot to the player. Idempotent. Returns the plot record,
-- or nil when every base is taken (server full).
function PlotService.AssignPlot(player)
    if assigned[player] ~= nil then
        return assigned[player]
    end
    for _, plot in ipairs(plots) do
        if plot.Owner == nil then
            plot.Owner = player
            assigned[player] = plot
            return plot
        end
    end
    return nil
end

-- Frees the player's plot on leave so the next player can use it. Also drops any pad
-- reservations they were holding.
function PlotService.FreePlot(player)
    local plot = assigned[player]
    if plot ~= nil then
        plot.Owner = nil
        assigned[player] = nil
    end
    reserved[player] = nil
end

function PlotService.GetPlot(player)
    return assigned[player]
end

-- Returns the player's pad instances keyed by PadIndex (used to find a free pad on
-- purchase). Empty table if the player has no plot.
function PlotService.GetPads(player)
    local plot = assigned[player]
    if plot == nil then
        return {}
    end
    return plot.Pads
end

-- Returns a single pad instance by index (nil if absent). Used for the server-side deposit
-- distance check against the thief's real character position.
function PlotService.GetPad(player, index)
    local plot = assigned[player]
    if plot == nil then
        return nil
    end
    return plot.Pads[index]
end

-- Finds the lowest free PadIndex for a player: a pad that physically exists, is within the
-- player's unlocked-pad cap, is NOT occupied by an owned brainrot, and is NOT reserved by an
-- in-progress steal deposit. THE single free-pad authority used by both purchases and steals
-- so the two can never hand out the same pad. Returns the index, or nil if the base is full.
function PlotService.FindFreePad(player, profile)
    local plot = assigned[player]
    if plot == nil then
        return nil
    end

    local used = {}
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        used[brainrot.PadIndex] = true
    end
    local heldPads = reserved[player]
    if heldPads ~= nil then
        for index in pairs(heldPads) do
            used[index] = true
        end
    end

    local unlocked = profile.Data.UnlockedPads or Config.Plots.PadsPerPlot
    local cap = math.min(unlocked, Config.Plots.PadsPerPlot)
    for index = 1, cap do
        if plot.Pads[index] ~= nil and not used[index] then
            return index
        end
    end
    return nil
end

-- Counts how many pads are currently free for a player (within the unlocked cap, excluding owned
-- + reserved). Used for the net-pad capacity check at a trade COMMIT.
function PlotService.CountFreePads(player, profile)
    local plot = assigned[player]
    if plot == nil then
        return 0
    end
    local used = {}
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        used[brainrot.PadIndex] = true
    end
    local heldPads = reserved[player]
    if heldPads ~= nil then
        for index in pairs(heldPads) do
            used[index] = true
        end
    end
    local unlocked = profile.Data.UnlockedPads or Config.Plots.PadsPerPlot
    local cap = math.min(unlocked, Config.Plots.PadsPerPlot)
    local free = 0
    for index = 1, cap do
        if plot.Pads[index] ~= nil and not used[index] then
            free += 1
        end
    end
    return free
end

-- Reserves a pad for an in-progress steal so nothing else (a purchase or another steal)
-- can claim it before the carried unit is deposited there.
function PlotService.ReservePad(player, index)
    if reserved[player] == nil then
        reserved[player] = {}
    end
    reserved[player][index] = true
end

-- Releases a previously reserved pad (on deposit success or any revert/failure).
function PlotService.ReleasePad(player, index)
    local heldPads = reserved[player]
    if heldPads ~= nil then
        heldPads[index] = nil
    end
end

-- Teleports the player's character onto their assigned base.
function PlotService.MovePlayerToPlot(player)
    local plot = assigned[player]
    if plot == nil then
        return
    end
    local character = player.Character
    if character == nil then
        return
    end
    -- Wait briefly for the body so PivotTo moves the whole character cleanly.
    local root = character:WaitForChild("HumanoidRootPart", 5)
    if root ~= nil then
        character:PivotTo(plot.SpawnCFrame)
    end
end

return PlotService
