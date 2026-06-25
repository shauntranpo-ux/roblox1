-- BrainrotService: grants the starter brainrot to new players, restores owned
-- brainrots onto their saved pads, and spawns the placeholder visuals. Throwaway art
-- for now -- a single anchored Part with a name/income BillboardGui. A real model from
-- ServerStorage/Assets will replace makeBrainrotPart() in a later milestone.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local BrainrotService = {}

local spawnedParts = {} -- [Player] = array of Instances to clean up on leave

-- Resolves a brainrot's display definition from its Type. Buyable units come from the
-- shop Catalog; the free starter comes from Config; an unknown type falls back to the
-- starter so a stale save never errors.
local function resolveDef(brainrotType)
    return Catalog.Get(brainrotType)
        or Config.Brainrots[brainrotType]
        or Config.Brainrots[Config.StarterType]
end

-- Builds the placeholder visual for one brainrot on a pad.
local function makeBrainrotPart(def, brainrot, pad)
    local part = Instance.new("Part")
    part.Name = "Brainrot_" .. brainrot.Id
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.new(4, 4, 4)
    part.Material = Enum.Material.SmoothPlastic
    part.Color = Color3.fromRGB(205, 120, 220)
    part.CFrame = pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + 2, 0)

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
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.4
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Text = def.Name .. "\n+$" .. tostring(brainrot.IncomePerSec) .. "/s"
    label.Parent = billboard

    return part
end

-- Spawns a single brainrot onto its pad and tracks it for cleanup. Shared by both the
-- join-time restore and M2 purchases, so placement lives in exactly one place.
function BrainrotService.SpawnBrainrot(player, plot, brainrot)
    local pad = plot.Pads[brainrot.PadIndex]
    if pad == nil then
        return
    end

    local part = makeBrainrotPart(resolveDef(brainrot.Type), brainrot, pad)
    part.Parent = plot.Model

    if spawnedParts[player] == nil then
        spawnedParts[player] = {}
    end
    table.insert(spawnedParts[player], part)
end

-- Grants the brand-new player exactly one starter brainrot at pad 1, or leaves an
-- existing roster untouched. Then spawns every owned brainrot on its pad.
function BrainrotService.SetupPlayer(player, profile, plot)
    spawnedParts[player] = {}

    if #profile.Data.OwnedBrainrots == 0 then
        local starter = Config.Brainrots[Config.StarterType]
        table.insert(profile.Data.OwnedBrainrots, {
            Id = HttpService:GenerateGUID(false),
            Type = Config.StarterType,
            IncomePerSec = starter.IncomePerSec,
            PadIndex = 1,
        })
        -- ProfileStore auto-saves periodically and on session end; no manual save needed.
    end

    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
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
