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
local EvolutionConfig = require(ReplicatedStorage.Shared.EvolutionConfig)
local BrainrotBillboard = require(ReplicatedStorage.Shared.BrainrotBillboard)
local BrainrotFactory = require(script.Parent.BrainrotFactory)

local BrainrotService = {}

local spawnedModels = {} -- [Player] = { [brainrotId] = Instance } on-pad models
local holdMultByPlayer = {} -- [Player] = steal-hold multiplier vs this player (DEF perks; default 1)

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
    billboard.AlwaysOnTop = false
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
    label.Font = Enum.Font.FredokaOne -- VM-THEME: bubble font on world labels
    local nameStroke = Instance.new("UIStroke") -- + a black rim
    nameStroke.Color = Color3.fromRGB(24, 12, 44)
    nameStroke.Thickness = 2
    nameStroke.Transparency = 0.1
    nameStroke.Parent = label
    local prefix = (mutation ~= nil and mutation.DisplayName ~= "")
            and (mutation.DisplayName .. " ")
        or ""
    -- M11.2: show the evolution stage badge once a unit is past stage 1.
    local stage = EvolutionConfig.StageOf(unit)
    local stageTag = stage > 1 and ("[S" .. stage .. "] ") or ""
    label.Text = stageTag
        .. prefix
        .. def.DisplayName
        .. "\n+$"
        .. Format.short(UnitIncome.effective(unit))
        .. "/s"
    label.Parent = billboard
end

-- M11.2 placeholder evolved look: a stage-colored outline/glow on a unit past stage 1 (thicker +
-- glowing at higher stages). Works for both the picture path and the placeholder path. Real evolved
-- models are reserved (EvolutionConfig.Visual.ModelName) for a later art pass.
local function addEvolutionAura(part, brainrot)
    if part == nil then
        return
    end
    local stage = EvolutionConfig.StageOf(brainrot)
    if stage <= 1 then
        return
    end
    local visual = EvolutionConfig.Visual(stage)
    if visual.Aura == nil then
        return
    end
    local box = Instance.new("SelectionBox")
    box.Name = "EvoAura"
    box.Adornee = part
    box.LineThickness = 0.05 + stage * 0.03
    box.Color3 = visual.Aura
    box.SurfaceColor3 = visual.Aura
    box.SurfaceTransparency = visual.Glow and 0.3 or 0.7
    box.Parent = part
end

local function makeBrainrotPart(def, brainrot, pad)
    local rarity = Rarity.Get(def.Rarity)
    local mutation = brainrot.Mutation ~= nil and MutationConfig.Get(brainrot.Mutation) or nil
    local tint = mutation ~= nil and mutation.Color or rarity.Color

    -- M11.2: evolved units are visibly bigger (placeholder evolved look; real models reserved).
    local evoScale = EvolutionConfig.Visual(EvolutionConfig.StageOf(brainrot)).Scale or 1
    local size = 4 * evoScale

    local part = Instance.new("Part")
    part.Name = "Brainrot_" .. brainrot.Id
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.new(size, size, size)
    part.Material = mutation ~= nil and mutation.Material or Enum.Material.SmoothPlastic
    part.Color = tint
    part.CFrame = placementCFrame(pad)

    -- The cube is an INVISIBLE anchor; a camera-facing 2D BILLBOARD is the unit's whole look (a flat
    -- "2D brainrot", never a 3D block) -- the species sprite if it has one, else a tinted name card.
    -- Shared with the wild + shared-event billboards (one implementation, no fork).
    part.Transparency = 1
    BrainrotBillboard.attach(part, def, {
        size = UDim2.fromScale(5.5, 6),
        offset = Vector3.new(0, 1.5, 0),
        maxDistance = 130,
        tint = tint,
        mutationColor = mutation ~= nil and mutation.Color or nil,
        name = def.DisplayName,
    })

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
    prompt.ActionText = "Tap to Steal"
    prompt.ObjectText = def.DisplayName
    -- TAP-TO-PROGRESS: the StealPrompt is now only a TARGET marker; stealing fills by TAPPING (the client
    -- routes taps via TapBatch -> StealService.TapComplete). HoldDuration 0 = press shows the target.
    prompt.HoldDuration = 0
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
    addEvolutionAura(mainPart(instance), brainrot) -- M11.2: stage glow on evolved units
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

-- M11.1 DEFENDER perks: set the steal-hold multiplier vs this player's base, applied to ALL their
-- current StealPrompts AND remembered so units spawned later (e.g. a stolen-in unit) inherit it.
-- LoadoutService calls this on every loadout change with the aggregated DefenderHoldMult.
function BrainrotService.SetHoldMultiplier(player, mult)
    holdMultByPlayer[player] = mult
    local models = spawnedModels[player]
    if models == nil then
        return
    end
    for _, instance in pairs(models) do
        local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt ~= nil then
            prompt.HoldDuration = 0 -- TAP-TO-PROGRESS: hold retired (a target marker only)
        end
    end
end

-- Builds the carried model for a steal: a lightweight rarity-tinted part welded above the
-- thief's HumanoidRootPart. Server-created so the weld replicates to every client. The weld
-- is named "CarryWeld" so StealService can bob it. Returns the part (nil if no HRP).
-- `stackIndex` (0-based) stacks multiple simultaneously-carried models (M11.1 multi-carry perks)
-- above one another so they don't overlap.
function BrainrotService.MakeCarriedModel(character, unit, stackIndex)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp == nil then
        return nil
    end
    local height = 3 + (stackIndex or 0) * 3.2
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
    part.CFrame = hrp.CFrame * CFrame.new(0, height, 0)

    -- Carried (stolen-on-back) units keep the 3D cube when there is no art; only swap to the flat
    -- sprite when the species actually has one (unchanged behavior, now via the shared builder).
    if BrainrotBillboard.spriteId(def) ~= 0 then
        part.Transparency = 1
        BrainrotBillboard.attach(part, def, {
            size = UDim2.fromScale(5.5, 6),
            offset = Vector3.new(0, 1.5, 0),
            maxDistance = 130,
            mutationColor = mutation ~= nil and mutation.Color or nil,
        })
    end

    addInfoLabel(part, def, unit)

    local weld = Instance.new("Weld")
    weld.Name = "CarryWeld"
    weld.Part0 = hrp
    weld.Part1 = part
    weld.C0 = CFrame.new(0, height, 0)
    weld.Parent = part

    part.Parent = character
    return part
end

-- Grants a brand-new player exactly one starter brainrot (the cheapest Common in the
-- roster) at pad 1, or leaves an existing roster untouched. Then spawns every owned
-- brainrot on its pad and records each as discovered.
function BrainrotService.SetupPlayer(player, profile, plot)
    spawnedModels[player] = {}

    -- M10.1: the GUARANTEED STARTER, granted EXACTLY ONCE (idempotent flag). Direct-buy is retired,
    -- so a brand-new player (empty roster, not yet granted) gets one starter to begin; an existing
    -- save (already owns units) is just MARKED granted on first post-update load -> no bonus starter;
    -- a player who later sells everything is NOT re-granted (they catch in the wild). No dead-end.
    if not profile.Data.StarterGranted then
        if #profile.Data.OwnedBrainrots == 0 then
            local starter = Catalog.GetStarter()
            table.insert(
                profile.Data.OwnedBrainrots,
                BrainrotFactory.create(player, starter, 1, BrainrotFactory.RollFor.Starter)
            )
        end
        profile.Data.StarterGranted = true
    end

    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        -- Seed discovery for existing saves too: anything currently owned counts as owned.
        profile.Data.Discovered[brainrot.Type] = true
        BrainrotFactory.MarkDiscovered(profile, brainrot.Mutation)
        -- M9.2 RECONCILE: legacy units have no Star field -> default to ★1 (persists on next save).
        brainrot.Star = brainrot.Star or 1
        -- M11.2 RECONCILE: legacy units default to evolution stage 1 / XP 0 (persists on next save).
        brainrot.EvolutionStage = brainrot.EvolutionStage or 1
        brainrot.XP = brainrot.XP or 0
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
    holdMultByPlayer[player] = nil
end

return BrainrotService
