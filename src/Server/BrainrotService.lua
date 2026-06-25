-- BrainrotService: grants the starter brainrot, restores owned brainrots onto their saved
-- pads, and owns ALL brainrot visuals -- both the on-pad units and the carried model used
-- during a steal.
--
-- On-pad units are rarity-tinted placeholder parts (or cloned Assets models if present),
-- each carrying a "Hold to steal" ProximityPrompt tagged with its owner + unique Id so the
-- server can resolve a steal authoritatively. Models are tracked PER PLAYER, KEYED BY the
-- brainrot's unique Id, so StealService can remove/respawn exactly one unit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Format = require(ReplicatedStorage.Shared.Format)
local StealConfig = require(ReplicatedStorage.Shared.StealConfig)
local MutationConfig = require(ReplicatedStorage.Shared.MutationConfig)
local UnitIncome = require(ReplicatedStorage.Shared.UnitIncome)
local BrainrotFactory = require(script.Parent.BrainrotFactory)

local BrainrotService = {}

local spawnedModels = {} -- [Player] = { [brainrotId] = Instance } on-pad models

-- Resolves a brainrot's definition from its Type (a roster Id). Unknown/stale types fall
-- back to the starter entry so an old save can never error a lookup.
local function resolveDef(brainrotType)
    return Catalog.Get(brainrotType) or Catalog.GetStarter()
end

-- Looks for an optional real-art Model in ServerStorage/Assets named after def.ModelName.
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

local function placementCFrame(pad)
    return pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + 2, 0)
end

-- The main BasePart of a spawned instance (the part to host the prompt + adornees).
local function mainPart(instance)
    if instance:IsA("BasePart") then
        return instance
    end
    return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
end

-- Adds the name/income BillboardGui to a part. `unit` is an owned-unit record (IncomePerSec +
-- optional Mutation); the label shows the EFFECTIVE income via the canonical helper and prefixes
-- the mutation name (mutation-colored) when present.
local function addInfoLabel(part, def, unit)
    local rarity = Rarity.Get(def.Rarity)
    local mutation = unit.Mutation ~= nil and MutationConfig.Get(unit.Mutation) or nil
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Info"
    billboard.Size = UDim2.fromScale(4.5, 1.6)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
    billboard.AlwaysOnTop = true
    -- PERF: with hundreds of units server-wide, only render the floating "+$/s" label for nearby
    -- ones. Far labels stop drawing, bounding GUI cost without any logic change.
    billboard.MaxDistance = 90
    billboard.Adornee = part
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextColor3 = mutation ~= nil and mutation.Color or rarity.Color
    label.TextStrokeTransparency = 0.4
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    local prefix = (mutation ~= nil and mutation.DisplayName ~= "")
            and (mutation.DisplayName .. " ")
        or ""
    label.Text = prefix
        .. def.DisplayName
        .. "\n+$"
        .. Format.short(UnitIncome.effective(unit))
        .. "/s"
    label.Parent = billboard
end

-- True if a roster entry has a real 2D image to show.
local function hasArt(def)
    return def.IconId ~= nil and def.IconId ~= 0
end

-- Adds the brainrot's 2D PICTURE: an ImageLabel on a BillboardGui, which always faces the camera,
-- so the unit reads as a flat "2D brainrot" rather than a 3D model. A mutated unit gets a colored
-- outline so Shiny/Rainbow/etc. still read at a glance. Only used when the entry has an IconId.
local function addArtBillboard(part, def, mutation)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Art"
    billboard.Size = UDim2.fromScale(5.5, 6)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
    billboard.LightInfluence = 0
    billboard.MaxDistance = 130
    billboard.Adornee = part
    billboard.Parent = part

    local image = Instance.new("ImageLabel")
    image.Size = UDim2.fromScale(1, 1)
    image.BackgroundTransparency = 1
    image.Image = "rbxassetid://" .. tostring(def.IconId)
    image.ScaleType = Enum.ScaleType.Fit
    image.Parent = billboard
    if mutation ~= nil then
        local stroke = Instance.new("UIStroke")
        stroke.Color = mutation.Color
        stroke.Thickness = 3
        stroke.Transparency = 0.1
        stroke.Parent = image
    end
end

-- Builds the on-pad visual for one brainrot: the 2D picture (if it has an IconId) or, until art is
-- added, a rarity-tinted placeholder cube. A mutated unit overrides the tint/accent so it reads.
local function makeBrainrotPart(def, brainrot, pad)
    local rarity = Rarity.Get(def.Rarity)
    local mutation = brainrot.Mutation ~= nil and MutationConfig.Get(brainrot.Mutation) or nil
    local tint = mutation ~= nil and mutation.Color or rarity.Color

    local part = Instance.new("Part")
    part.Name = "Brainrot_" .. brainrot.Id
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.new(4, 4, 4)
    part.Material = mutation ~= nil and mutation.Material or Enum.Material.SmoothPlastic
    part.Color = tint
    part.CFrame = placementCFrame(pad)

    if hasArt(def) then
        -- 2D picture path: the cube is an invisible anchor; the billboard image IS the unit.
        part.Transparency = 1
        addArtBillboard(part, def, mutation)
    else
        -- Placeholder path: rarity/mutation-colored accent outline + faint glow.
        local box = Instance.new("SelectionBox")
        box.Adornee = part
        box.LineThickness = mutation ~= nil and 0.14 or 0.06
        box.Color3 = tint
        box.SurfaceColor3 = tint
        box.SurfaceTransparency = mutation ~= nil and 0.55 or 0.85
        box.Parent = part
    end

    addInfoLabel(part, def, brainrot)
    return part
end

-- Attaches the "Hold to steal" prompt to an on-pad unit. The prompt is tagged with the
-- owner + brainrot Id; StealService re-validates EVERYTHING on the server when it fires, so
-- this prompt is only a trigger, never a source of truth. Owner-side hiding and protection
-- disabling are layered on top (see StealController / ProtectionService).
local function attachStealPrompt(targetPart, owner, brainrot, def)
    if targetPart == nil then
        return
    end
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "StealPrompt"
    prompt.ActionText = "Steal"
    prompt.ObjectText = def.DisplayName
    prompt.HoldDuration = StealConfig.HoldDuration
    prompt.MaxActivationDistance = StealConfig.PromptMaxDistance
    prompt.RequiresLineOfSight = false
    prompt:SetAttribute("BrainrotId", brainrot.Id)
    prompt:SetAttribute("OwnerUserId", owner.UserId)
    prompt.Parent = targetPart
end

-- Spawns a single on-pad brainrot and tracks it by Id for steal lookups + cleanup. Shared by
-- the join-time restore, purchases, and steal deposits, so placement lives in one place.
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
        local part = mainPart(instance)
        if part ~= nil then
            -- FORWARD-COMPAT: real art keeps its model; the mutation reads as an accent overlay +
            -- the label below. (A richer aura/particle overlay can be added here later.)
            addInfoLabel(part, def, brainrot)
            local mutation = brainrot.Mutation ~= nil and MutationConfig.Get(brainrot.Mutation)
                or nil
            if mutation ~= nil then
                local box = Instance.new("SelectionBox")
                box.Adornee = part
                box.LineThickness = 0.14
                box.Color3 = mutation.Color
                box.SurfaceColor3 = mutation.Color
                box.SurfaceTransparency = 0.55
                box.Parent = part
            end
        end
        if instance:IsA("Model") then
            instance:PivotTo(placementCFrame(pad))
        end
    else
        instance = makeBrainrotPart(def, brainrot, pad)
    end

    attachStealPrompt(mainPart(instance), player, brainrot, def)
    instance.Parent = plot.Model

    if spawnedModels[player] == nil then
        spawnedModels[player] = {}
    end
    spawnedModels[player][brainrot.Id] = instance
end

-- Removes one on-pad model by Id (used when a steal lifts it off the pad). Safe if missing.
function BrainrotService.RemoveModel(player, brainrotId)
    local models = spawnedModels[player]
    if models == nil then
        return
    end
    local instance = models[brainrotId]
    if instance ~= nil then
        instance:Destroy()
        models[brainrotId] = nil
    end
end

function BrainrotService.GetModel(player, brainrotId)
    local models = spawnedModels[player]
    if models == nil then
        return nil
    end
    return models[brainrotId]
end

-- Enables/disables the steal prompts on all of a player's on-pad units (used by
-- ProtectionService to lock a protected plot). Server re-validates regardless.
function BrainrotService.SetPromptsEnabled(player, enabled)
    local models = spawnedModels[player]
    if models == nil then
        return
    end
    for _, instance in pairs(models) do
        local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt ~= nil then
            prompt.Enabled = enabled
        end
    end
end

-- Builds the carried model for a steal: a lightweight rarity-tinted part welded above the
-- thief's HumanoidRootPart. Server-created so the weld replicates to every client. The weld
-- is named "CarryWeld" so StealService can bob it. Returns the part (nil if no HRP).
function BrainrotService.MakeCarriedModel(character, unit)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp == nil then
        return nil
    end
    local def = resolveDef(unit.Type)
    local rarity = Rarity.Get(def.Rarity)
    local mutation = unit.Mutation ~= nil and MutationConfig.Get(unit.Mutation) or nil

    local part = Instance.new("Part")
    part.Name = "CarriedBrainrot"
    part.Anchored = false
    part.CanCollide = false
    part.Massless = true -- never affect the thief's movement physics
    part.Size = Vector3.new(3, 3, 3)
    part.Material = mutation ~= nil and mutation.Material or Enum.Material.SmoothPlastic
    part.Color = mutation ~= nil and mutation.Color or rarity.Color
    part.CFrame = hrp.CFrame * CFrame.new(0, 3, 0)

    if hasArt(def) then
        part.Transparency = 1
        addArtBillboard(part, def, mutation)
    end

    addInfoLabel(part, def, unit)

    local weld = Instance.new("Weld")
    weld.Name = "CarryWeld"
    weld.Part0 = hrp
    weld.Part1 = part
    weld.C0 = CFrame.new(0, 3, 0)
    weld.Parent = part

    part.Parent = character
    return part
end

-- Grants a brand-new player exactly one starter brainrot (the cheapest Common in the
-- roster) at pad 1, or leaves an existing roster untouched. Then spawns every owned
-- brainrot on its pad and records each as discovered.
function BrainrotService.SetupPlayer(player, profile, plot)
    spawnedModels[player] = {}

    if #profile.Data.OwnedBrainrots == 0 then
        -- The starter is a CLEAN grant (no mutation roll) via the central factory.
        local starter = Catalog.GetStarter()
        table.insert(
            profile.Data.OwnedBrainrots,
            BrainrotFactory.create(player, starter, 1, BrainrotFactory.RollFor.Starter)
        )
        -- ProfileStore auto-saves periodically and on session end; no manual save needed.
    end

    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        -- Seed discovery for existing saves too: anything currently owned counts as owned.
        profile.Data.Discovered[brainrot.Type] = true
        BrainrotFactory.MarkDiscovered(profile, brainrot.Mutation)
        BrainrotService.SpawnBrainrot(player, plot, brainrot)
    end
end

-- Destroys the player's spawned on-pad brainrot visuals on leave. (The carried model, if
-- any, is owned by StealService and resolved separately before this runs.)
function BrainrotService.ClearPlayer(player)
    local models = spawnedModels[player]
    if models ~= nil then
        for _, instance in pairs(models) do
            instance:Destroy()
        end
        spawnedModels[player] = nil
    end
end

return BrainrotService
