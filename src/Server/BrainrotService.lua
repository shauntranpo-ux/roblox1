-- BrainrotService: grants the starter brainrot to new players, restores owned brainrots
-- onto their saved pads, and spawns the in-world visuals.
--
-- Until real art exists each unit is a placeholder anchored Part, TINTED to its rarity
-- color with a matching outline + a rarity-colored name/income BillboardGui, so tiers are
-- distinguishable at a glance. FORWARD-COMPAT (same pattern as plots): if a Model named
-- after the entry's ModelName exists in ServerStorage/Assets, that real art is cloned
-- instead; the placeholder is only the fallback.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Format = require(ReplicatedStorage.Shared.Format)

local BrainrotService = {}

local spawnedParts = {} -- [Player] = array of Instances to clean up on leave

-- Resolves a brainrot's definition from its Type (a roster Id). Unknown/stale types fall
-- back to the starter entry so an old save can never error a lookup.
local function resolveDef(brainrotType)
    return Catalog.Get(brainrotType) or Catalog.GetStarter()
end

-- Looks for an optional real-art Model in ServerStorage/Assets named after def.ModelName.
-- Returns nil while ModelName is unset (the M3 placeholder era).
local function getModelTemplate(def)
    if def.ModelName == nil then
        return nil
    end
    local assets = ServerStorage:FindFirstChild("Assets")
    if assets ~= nil then
        return assets:FindFirstChild(def.ModelName)
    end
    return nil
end

-- The world position for a unit sitting on a pad.
local function placementCFrame(pad)
    return pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + 2, 0)
end

-- Builds the rarity-tinted placeholder visual for one brainrot on a pad.
local function makeBrainrotPart(def, brainrot, pad)
    local rarity = Rarity.Get(def.Rarity)

    local part = Instance.new("Part")
    part.Name = "Brainrot_" .. brainrot.Id
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.new(4, 4, 4)
    part.Material = Enum.Material.SmoothPlastic
    part.Color = rarity.Color -- rarity tint: the tier reads from the unit's color
    part.CFrame = placementCFrame(pad)

    -- Subtle rarity accent: a colored outline + faint surface glow around the unit.
    local box = Instance.new("SelectionBox")
    box.Adornee = part
    box.LineThickness = 0.06
    box.Color3 = rarity.Color
    box.SurfaceColor3 = rarity.Color
    box.SurfaceTransparency = 0.85
    box.Parent = part

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Info"
    billboard.Size = UDim2.fromScale(4.5, 1.6)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextColor3 = rarity.Color -- name + rate in the rarity color
    label.TextStrokeTransparency = 0.4
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Text = def.DisplayName .. "\n+$" .. Format.short(brainrot.IncomePerSec) .. "/s"
    label.Parent = billboard

    return part
end

-- Spawns a single brainrot onto its pad and tracks it for cleanup. Shared by both the
-- join-time restore and purchases, so placement lives in exactly one place.
function BrainrotService.SpawnBrainrot(player, plot, brainrot)
    local pad = plot.Pads[brainrot.PadIndex]
    if pad == nil then
        return
    end

    local def = resolveDef(brainrot.Type)

    -- Real-art path: clone the Model from Assets the instant it exists; otherwise build the
    -- tinted placeholder. Same forward-compat pattern PlotService uses for plot templates.
    local template = getModelTemplate(def)
    local instance
    if template ~= nil then
        instance = template:Clone()
        instance.Name = "Brainrot_" .. brainrot.Id
        if instance:IsA("Model") then
            instance:PivotTo(placementCFrame(pad))
        end
    else
        instance = makeBrainrotPart(def, brainrot, pad)
    end
    instance.Parent = plot.Model

    if spawnedParts[player] == nil then
        spawnedParts[player] = {}
    end
    table.insert(spawnedParts[player], instance)
end

-- Grants a brand-new player exactly one starter brainrot (the cheapest Common in the
-- roster) at pad 1, or leaves an existing roster untouched. Then spawns every owned
-- brainrot on its pad and records each as discovered.
function BrainrotService.SetupPlayer(player, profile, plot)
    spawnedParts[player] = {}

    if #profile.Data.OwnedBrainrots == 0 then
        local starter = Catalog.GetStarter()
        table.insert(profile.Data.OwnedBrainrots, {
            Id = HttpService:GenerateGUID(false),
            Type = starter.Id,
            IncomePerSec = starter.IncomePerSec,
            PadIndex = 1,
        })
        -- ProfileStore auto-saves periodically and on session end; no manual save needed.
    end

    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        -- Seed discovery for existing saves too: anything currently owned counts as owned.
        profile.Data.Discovered[brainrot.Type] = true
        BrainrotService.SpawnBrainrot(player, plot, brainrot)
    end
end

-- Destroys the player's spawned brainrot visuals on leave.
function BrainrotService.ClearPlayer(player)
    local list = spawnedParts[player]
    if list ~= nil then
        for _, instance in ipairs(list) do
            instance:Destroy()
        end
        spawnedParts[player] = nil
    end
end

return BrainrotService
