-- Biomes (M10.2): renders the BIOME progression UI. Shows the biome NAME as you enter one (reusing
-- the announce banner), dresses tagged GATE parts with a lock-state billboard + an Unlock prompt
-- (sends unlock INTENT; the server validates + persists), and makes UNLOCKED gates locally PASSABLE
-- (per-player collision off -- the spatial gate; the real reward gate is the server's rarity routing).
-- Fires the per-zone ATMOSPHERE hook on biome change. Server-authoritative throughout; the client
-- only renders + sends intent. Placeholder-safe: no tagged gates/volumes -> nothing to do, no error.
--
-- DEV: tag each biome-boundary barrier part "BiomeGate" with attribute TargetBiome = "<biomeId>".
-- Tag biome region parts "BiomeVolume" with attribute Biome = "<biomeId>" (server reads those).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Banner = require(script.Parent.Banner)
local Atmosphere = require(script.Parent.Atmosphere)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local BiomeConfig = require(Shared:WaitForChild("BiomeConfig"))
local WorldConfig = require(Shared:WaitForChild("WorldConfig")) -- VM6 per-biome atmosphere profiles

local Biomes = {}

local GATE_TAG = "BiomeGate"

local remotes = nil
local player = nil
local indicator = nil
local unlockedSet = {} -- [biomeId] = true (server truth, refreshed on get/unlock)
local gates = {} -- [part] = { billboard, label, prompt }

local function requirementText(biomeId)
    local biome = BiomeConfig.Get(biomeId)
    if biome == nil then
        return "?"
    end
    local req = biome.Unlock or {}
    local parts = {}
    if (req.Cash or 0) > 0 then
        table.insert(parts, "$" .. Format.full(req.Cash))
    end
    if (req.Rebirth or 0) > 0 then
        table.insert(parts, "Rebirth " .. req.Rebirth)
    end
    if #parts == 0 then
        return "Open"
    end
    return table.concat(parts, " + ")
end

local function refreshGate(part, entry)
    local biomeId = part:GetAttribute("TargetBiome")
    local biome = type(biomeId) == "string" and BiomeConfig.Get(biomeId) or nil
    if biome == nil then
        return
    end
    local unlocked = unlockedSet[biomeId] == true
    -- Per-player passability: open gate = local collision off + see-through; locked = solid barrier.
    part.CanCollide = not unlocked
    part.Transparency = unlocked and 0.65 or 0.1
    entry.label.Text = unlocked and (biome.Name .. "\n[OPEN]")
        or (biome.Name .. "\nLocked: " .. requirementText(biomeId))
    entry.label.TextColor3 = unlocked and Theme.Colors.HpFill or Theme.Colors.Gold
    entry.prompt.Enabled = not unlocked
end

local function refreshAllGates()
    for part, entry in pairs(gates) do
        if part.Parent ~= nil then
            refreshGate(part, entry)
        end
    end
end

local function fetchState()
    local ok, result = pcall(function()
        return remotes.BiomeAction:InvokeServer({ Action = "get" })
    end)
    if ok and type(result) == "table" and type(result.State) == "table" then
        unlockedSet = result.State.Unlocked or {}
    end
    refreshAllGates()
end

local function doUnlock(biomeId)
    local ok, result = pcall(function()
        return remotes.BiomeAction:InvokeServer({ Action = "unlock", BiomeId = biomeId })
    end)
    if ok and type(result) == "table" then
        if result.Result == "Success" and type(result.State) == "table" then
            unlockedSet = result.State.Unlocked or unlockedSet
            refreshAllGates()
            local biome = BiomeConfig.Get(biomeId)
            if biome ~= nil then
                Banner.show("<hl>" .. biome.Name .. "</hl> UNLOCKED!", 5)
            end
        end
    end
end

local function dressGate(part)
    if not part:IsA("BasePart") or gates[part] ~= nil then
        return
    end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "GateUI"
    billboard.Size = UDim2.fromScale(6, 2)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 3, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 120
    billboard.Adornee = part
    billboard.Parent = part
    local label = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Parent = billboard,
    })
    Builder.styleText(label, { keepColor = true })

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "UnlockPrompt"
    prompt.ActionText = "Unlock"
    prompt.ObjectText = "Gate"
    prompt.HoldDuration = 0.4
    prompt.MaxActivationDistance = 14
    prompt.RequiresLineOfSight = false
    prompt.Parent = part
    prompt.Triggered:Connect(function()
        local biomeId = part:GetAttribute("TargetBiome")
        if type(biomeId) == "string" then
            doUnlock(biomeId)
        end
    end)

    gates[part] = { billboard = billboard, label = label, prompt = prompt }
    refreshGate(part, gates[part])
end

function Biomes.mount(context)
    remotes = context.remotes
    player = context.player or Players.LocalPlayer
    local gui = Builder.screenGui("Biomes", player:WaitForChild("PlayerGui"), true)
    gui.DisplayOrder = 7

    -- Current-biome indicator (top-left chip).
    indicator = Builder.pill({
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromScale(0.012, 0.03),
        Size = UDim2.fromScale(0.18, 0.05),
        radius = Theme.Radius.Card, -- one pill family with the objective strip + boss HP bar
        Parent = gui,
    })
    Builder.create(
        "UISizeConstraint",
        { MinSize = Vector2.new(120, 34), MaxSize = Vector2.new(240, 56), Parent = indicator }
    )
    local biomeLabel = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "Sunny Meadow",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Parent = indicator,
    }, { Builder.padding(4), Builder.create("UITextSizeConstraint", { MaxTextSize = 20 }) })
    Builder.styleText(biomeLabel, { keepColor = true })

    -- Dress existing + future tagged gates.
    for _, part in ipairs(CollectionService:GetTagged(GATE_TAG)) do
        dressGate(part)
    end
    CollectionService:GetInstanceAddedSignal(GATE_TAG):Connect(dressGate)

    -- React to the server's published current biome: label + banner + the per-zone atmosphere hook.
    local function onBiome()
        local id = player:GetAttribute("CurrentBiome")
        local biome = type(id) == "string" and BiomeConfig.Get(id) or nil
        if biome ~= nil then
            biomeLabel.Text = biome.Name
            Banner.show("ENTERING <hl>" .. biome.Name .. "</hl>", 3.5)
            Atmosphere.setZone(WorldConfig.AtmosphereFor(id)) -- VM6 per-biome atmosphere swap (nil-safe)
        end
    end
    player:GetAttributeChangedSignal("CurrentBiome"):Connect(onBiome)

    fetchState()
    if player:GetAttribute("CurrentBiome") ~= nil then
        onBiome()
    end
end

return Biomes
