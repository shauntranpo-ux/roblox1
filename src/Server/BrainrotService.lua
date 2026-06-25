-- BrainrotService: grants the starter brainrot to new players, restores owned
-- brainrots onto their saved pads, and spawns the placeholder visuals. Throwaway
-- art for M1 -- a single anchored Part with a name/income BillboardGui.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local BrainrotService = {}

local spawnedParts = {} -- [Player] = array of Instances to clean up on leave

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
    label.Text = def.Name .. "\n+$" .. tostring(def.IncomePerSec) .. "/s"
    label.Parent = billboard

    return part
end

-- Grants the brand-new player exactly one starter brainrot at pad 1 (saved), or
-- leaves an existing roster untouched. Then spawns every owned brainrot on its pad.
function BrainrotService.SetupPlayer(player, profile, plot)
    spawnedParts[player] = {}

    if #profile.Data.OwnedBrainrots == 0 then
        local def = Config.Brainrots[Config.StarterType]
        table.insert(profile.Data.OwnedBrainrots, {
            Id = HttpService:GenerateGUID(false),
            Type = Config.StarterType,
            IncomePerSec = def.IncomePerSec,
            PadIndex = 1,
        })
        -- ProfileStore auto-saves periodically and on session end; no manual save needed.
    end

    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        local def = Config.Brainrots[brainrot.Type] or Config.Brainrots[Config.StarterType]
        local pad = plot.Pads[brainrot.PadIndex]
        if pad ~= nil then
            local part = makeBrainrotPart(def, brainrot, pad)
            part.Parent = plot.Model
            table.insert(spawnedParts[player], part)
        end
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
