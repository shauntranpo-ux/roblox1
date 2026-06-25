-- SharedEventService (M10.3): SHARED server-wide rare-event spawns. On a rare cadence the server
-- spawns ONE server-owned "mystery" brainrot in the WORLD that ALL players see + race to catch. The
-- FIRST valid completed catch WINS it -- resolved EXACTLY ONCE under contention (the steal INITIATE
-- guard) -- minted fresh via the factory (no transfer/split -> dupe-impossible); everyone else gets a
-- clean miss. Separate from the M10.1 per-player instanced registry. Reuses the boss/announce pattern.
--
-- ============================  SELF-AUDIT (shared events)  ===================================
-- (a) ONE ENTITY, EXACTLY ONE WINNER: a single server-owned model; the catch fires server-side via
--     ProximityPromptService.PromptTriggered (the client never spawns/asserts/names the winner). The
--     win is guarded by activeEvent.Resolved set synchronously before any yield -> concurrent
--     completions resolve once; losers get "someone else caught it". The winner's unit is factory-
--     minted (never split/transferred) -> no dupe, no double-grant.
-- (b) SERVER-AUTHORITATIVE + UNSPOOFABLE: existence, position, behavior, the real-character distance
--     check, and the winner declaration all live here. No catch-rng (rarity at spawn; mystery is just
--     hidden-identity presentation).
-- (c) PAD-FULL SAFE: the winner's free pad is checked BEFORE the Resolved guard -> a pad-full player's
--     completion does NOT resolve the event (it stays catchable for others / their retry); never dupes.
-- (d) UNCROSSED: instanced M10.1 spawns + M10.2 routing/gates + caps/despawn/janitor are untouched;
--     this is a separate single-entity path. HUNT/Net catch-RANGE applies per-catcher; the shared HOLD
--     is fixed (one shared prompt); spawn-rate perks do NOT affect server-global events (documented).
-- (e) ACCESS RULE: a player must physically REACH it -- the M10.2 gates gate access in the continuous
--     world; no separate unlock check is added.
-- ===========================================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedEventConfig = require(ReplicatedStorage.Shared.SharedEventConfig)
local BiomeConfig = require(ReplicatedStorage.Shared.BiomeConfig)
local WildConfig = require(ReplicatedStorage.Shared.WildConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)

local ProfileManager = require(script.Parent.ProfileManager)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local BrainrotService = require(script.Parent.BrainrotService)
local PlotService = require(script.Parent.PlotService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local ProtectionService = require(script.Parent.ProtectionService)
local EvolutionService = require(script.Parent.EvolutionService)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)
local NetService = require(script.Parent.NetService) -- M10.4 net catch range on shared catches

local SharedEventService = {}

local activeEvent = nil
local spawnAccum = 0
local hudAccum = 0
local nextInterval = nil

local function rootOf(player)
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function pickInterval()
    return SharedEventConfig.IntervalMin
        + math.random() * (SharedEventConfig.IntervalMax - SharedEventConfig.IntervalMin)
end

-- A spawn point in an eligible biome's tagged volume (placeholder-safe -> DefaultPosition). Returns
-- (position, biomeDisplayName).
local function findSpawnPoint()
    local eligible = SharedEventConfig.EligibleBiomes
    for _, part in ipairs(CollectionService:GetTagged("BiomeVolume")) do
        if part:IsA("BasePart") then
            local biomeId = part:GetAttribute("Biome")
            local biome = type(biomeId) == "string" and BiomeConfig.Get(biomeId) or nil
            if biome ~= nil and (eligible == nil or eligible[biomeId]) then
                return part.Position + Vector3.new(0, SharedEventConfig.ModelSize.Y, 0), biome.Name
            end
        end
    end
    return SharedEventConfig.DefaultPosition, "the world"
end

local function makeModel(def, rarity, position)
    local part = Instance.new("Part")
    part.Name = "SharedRare"
    part.Anchored = true
    part.CanCollide = false
    part.Size = SharedEventConfig.ModelSize
    part.Color = Rarity.Get(rarity).Color
    part.Material = Enum.Material.Neon
    part.Transparency = 0.05
    part.Position = position

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.fromScale(6, 1.6)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, SharedEventConfig.ModelSize.Y / 2 + 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.Parent = part
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.FredokaOne
    label.Text = SharedEventConfig.HideIdentity and "??? MYSTERY ???"
        or ("TITAN " .. def.DisplayName)
    label.TextColor3 = Color3.fromRGB(255, 230, 120)
    label.TextStrokeTransparency = 0.3
    label.TextScaled = true
    label.Parent = billboard

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "SharedCatchPrompt"
    prompt.ActionText = "Catch"
    prompt.ObjectText = "Mystery Brainrot"
    prompt.HoldDuration = SharedEventConfig.Hold
    prompt.MaxActivationDistance = SharedEventConfig.BaseRange + 8 -- generous; server re-validates range
    prompt.RequiresLineOfSight = false
    prompt.Parent = part

    part.Parent = Workspace
    return part, prompt
end

local function despawn(event)
    if event.Model ~= nil then
        event.Model:Destroy()
        event.Model = nil
    end
    if activeEvent == event then
        activeEvent = nil
    end
    Remotes.BroadcastSharedEvent({ Kind = "gone" })
end

local function spawnEvent()
    if activeEvent ~= nil then
        return
    end
    local rarity = SharedEventConfig.RollRarity()
    if rarity == nil then
        return
    end
    local speciesId = SharedEventConfig.PickSpecies(rarity)
    if speciesId == nil then
        return
    end
    local def = Catalog.Get(speciesId)
    if def == nil then
        return
    end
    local position, biomeName = findSpawnPoint()
    local model, prompt = makeModel(def, rarity, position)
    activeEvent = {
        Def = def,
        Rarity = rarity,
        Model = model,
        Prompt = prompt,
        Position = position,
        StartTime = os.clock(),
        Resolved = false,
        Biome = biomeName,
    }
    Remotes.BroadcastSharedEvent({
        Kind = "spawn",
        Biome = biomeName,
        Drama = SharedEventConfig.Drama[rarity] or 1,
        Pos = position,
        Hidden = SharedEventConfig.HideIdentity == true,
    })
    for _, p in ipairs(Players:GetPlayers()) do
        Analytics.custom(p, Analytics.Events.SharedSpawn, Rarity.Get(rarity).Order)
    end
end

-- ── First-to-catch (server-side prompt completion; resolves the winner exactly once) ────────
local function onPromptTriggered(prompt, player)
    if prompt.Name ~= "SharedCatchPrompt" then
        return
    end
    local event = activeEvent
    if event == nil or event.Resolved or event.Prompt ~= prompt then
        return
    end
    -- Real-character distance check (anti-teleport/spoof; per-catcher range incl. HUNT/Net bonus).
    local root = rootOf(player)
    if root == nil then
        return
    end
    local range = SharedEventConfig.BaseRange + NetService.EffectiveCatch(player).RangeAdd
    if (root.Position - event.Position).Magnitude > range then
        Remotes.NotifyPlayer(player, "error", "Too far -- get closer to the mystery brainrot!")
        return
    end
    local profile = ProfileManager.GetProfile(player)
    local plot = PlotService.GetPlot(player)
    if profile == nil or plot == nil then
        return
    end
    -- PAD-FULL SAFE: check BEFORE the resolve guard -> a pad-full player's completion does NOT resolve
    -- the event (it stays for others / their retry); nothing minted, no dupe.
    local padIndex = PlotService.FindFreePad(player, profile)
    if padIndex == nil then
        Remotes.NotifyPlayer(player, "error", "Free a pad first to claim the prize!")
        return
    end

    -- ===== RESOLVE: guard + mint, NO yields between (the contention winner is decided here). =====
    if event.Resolved then
        return
    end
    event.Resolved = true
    if event.Prompt ~= nil then
        event.Prompt.Enabled = false
    end
    local unit = BrainrotFactory.create(player, event.Def, padIndex, BrainrotFactory.RollFor.Catch)
    table.insert(profile.Data.OwnedBrainrots, unit)
    profile.Data.Discovered[event.Def.Id] = true
    -- ============================================================================================

    BrainrotService.SpawnBrainrot(player, plot, unit)
    ProtectionService.RefreshPrompts(player)
    EvolutionService.AwardAllXP(player, WildConfig.CatchXP) -- M11.2 catch-XP (winner)
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
    ProfileManager.ForceSave(player)

    Remotes.BroadcastSharedEvent({
        Kind = "caught",
        Winner = player.DisplayName,
        Name = event.Def.DisplayName, -- identity revealed on the win
        Rarity = event.Rarity,
    })
    Analytics.custom(player, Analytics.Events.SharedCatch, Rarity.Get(event.Rarity).Order)
    despawn(event)
end

local function escape(event)
    if event.Resolved then
        return
    end
    event.Resolved = true
    if event.Prompt ~= nil then
        event.Prompt.Enabled = false
    end
    Remotes.BroadcastSharedEvent({ Kind = "escape" })
    for _, p in ipairs(Players:GetPlayers()) do
        Analytics.custom(p, Analytics.Events.SharedEscape, Rarity.Get(event.Rarity).Order)
    end
    despawn(event)
end

-- Dev/test helper: force a shared event now.
function SharedEventService.ForceSpawn()
    if activeEvent ~= nil then
        return false
    end
    spawnEvent()
    return activeEvent ~= nil
end

function SharedEventService.Init()
    ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

    if not SharedEventConfig.Enabled then
        return
    end
    spawnAccum = SharedEventConfig.IntervalMin - SharedEventConfig.FirstDelay
    nextInterval = SharedEventConfig.IntervalMin

    RunService.Heartbeat:Connect(function(deltaTime)
        local event = activeEvent
        if event ~= nil and not event.Resolved then
            if os.clock() - event.StartTime > SharedEventConfig.DespawnTime then
                escape(event)
            else
                -- Evasive: flee from the nearest player; else wander. Server-driven; the model
                -- replicates to all (everyone converges).
                local nearest, nearestDist
                for _, p in ipairs(Players:GetPlayers()) do
                    local r = rootOf(p)
                    if r ~= nil then
                        local d = (r.Position - event.Position).Magnitude
                        if nearestDist == nil or d < nearestDist then
                            nearest, nearestDist = r, d
                        end
                    end
                end
                local b = SharedEventConfig.Behavior
                if nearest ~= nil and nearestDist < b.FleeDistance then
                    local away = event.Position - nearest.Position
                    local dir = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
                    event.Position = event.Position
                        + Vector3.new(dir.X, 0, dir.Z) * b.FleeSpeed * deltaTime
                end
                if event.Model ~= nil then
                    event.Model.Position = event.Position
                end
                hudAccum += deltaTime
                if hudAccum >= 0.3 then
                    hudAccum = 0
                    Remotes.BroadcastSharedEvent({ Kind = "update", Pos = event.Position })
                end
            end
        end

        if activeEvent == nil then
            spawnAccum += deltaTime
            if spawnAccum >= (nextInterval or SharedEventConfig.IntervalMin) then
                spawnAccum = 0
                nextInterval = pickInterval()
                spawnEvent()
            end
        end
    end)
end

return SharedEventService
