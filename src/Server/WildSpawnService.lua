-- WildSpawnService (M10.1): the WILD-CATCH spawn engine + catch mechanic. The SERVER owns the wild
-- spawn registry (data only -- no server-side world instances); each spawn is replicated ONLY to its
-- owner, whose CLIENT renders it + the "Catch" prompt and sends catch INTENT. The server rolls
-- rarity->species at SPAWN (rarity IS the rng), drives wander/flee from the owner's REAL character,
-- and validates + atomically mints a caught unit via the factory EXACTLY ONCE. No client spawning; no
-- catch-rng; pooled by caps; despawned on a timer; cleaned on leave.
--
-- ============================  SELF-AUDIT (wild-catch)  ======================================
-- (a) SERVER-AUTHORITATIVE: the registry, rarity roll, positions, flee behavior, and catch validation
--     all live here. The client only renders from WildUpdate + sends a spawn id to WildCatch -- it
--     cannot spawn a unit or assert a catch (the server re-checks existence/owner/uncaught/real range).
-- (b) ATOMIC + DUPE-SAFE: commitCatch checks a free pad FIRST (pad-full -> reject, spawn STAYS, no
--     loss), then sets spawn.Caught + removes from the registry + mints via the factory, all with NO
--     yields -> a concurrent/double catch finds it gone (or Caught) and misses cleanly. Exactly one
--     unit, never two, never lost.
-- (c) NO CATCH-RNG: WildConfig.RollRarity decides rarity at SPAWN (weighted, + HUNT spawn-rate);
--     the catch is deterministic skill (approach + the client hold). No hidden success roll.
-- (d) HUNT PERKS LIVE (M11.1) + CATCH-XP (M11.2): catch range/hold-speed, no-flee, rare spawn-rate,
--     reveal, and a dormant auto-catch hook all read PerkEffects.GetHunt (guarded -> default if absent);
--     a catch fires EvolutionService.AwardAllXP. None breaks atomicity (all magnitudes server-side).
-- (e) BOUNDED + CLEAN: per-player MaxAlive cap, despawn timer, ClearPlayer teardown before release.
-- ===========================================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WildConfig = require(ReplicatedStorage.Shared.WildConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local TapConfig = require(ReplicatedStorage.Shared.TapConfig) -- tap-to-progress: per-rarity taps-to-catch

local ProfileManager = require(script.Parent.ProfileManager)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local BrainrotService = require(script.Parent.BrainrotService)
local PlotService = require(script.Parent.PlotService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local ProtectionService = require(script.Parent.ProtectionService)
local PerkEffects = require(script.Parent.PerkEffects)
local EvolutionService = require(script.Parent.EvolutionService)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)
local BiomeService = require(script.Parent.BiomeService) -- M10.2 biome rarity routing
local NetService = require(script.Parent.NetService) -- M10.4 net catch-param bonuses
local GameSignals = require(script.Parent.GameSignals) -- M12.1 quest observation bus

local WildSpawnService = {}

local LOOP_INTERVAL = 0.15 -- s: server wander/flee + move-replication tick (~6.6 Hz)

local spawns = {} -- [spawnId] = { Owner, Type, Rarity, Position(Vector3), Origin, WanderTarget, SpawnTime, Caught }
local countByOwner = {} -- [Player] = live spawn count
local spawnAccum = 0
local loopAccum = 0
local nextId = 0

-- ── HUNT perk reads (M11.1; guarded -> default when no perk equipped) ───────────────────────
local function hunt(player)
    return PerkEffects.GetHunt(player) -- table or nil
end
local function huntSpawnRate(player)
    local h = hunt(player)
    return (h ~= nil and type(h.SpawnRate) == "number") and h.SpawnRate or 0
end
local function huntNoFlee(player)
    local h = hunt(player)
    return h ~= nil and h.NoFlee == true
end
local function huntReveal(player)
    local h = hunt(player)
    return h ~= nil and h.RareReveal == true
end

local function rootOf(player)
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

-- ── Replication (owner-only) ────────────────────────────────────────────────────────────────
local function sendSpawn(spawn)
    Remotes.WildUpdate:FireClient(spawn.Owner, {
        Kind = "spawn",
        Id = spawn.Id,
        Type = spawn.Type,
        Rarity = spawn.Rarity,
        Pos = spawn.Position,
        Hold = spawn.Hold,
        Range = spawn.Range,
        Need = spawn.TapsToCatch, -- tap-to-progress: taps to fill the catch meter (client shows it)
        Revealed = spawn.Revealed,
        Name = spawn.DisplayName,
    })
end

local function removeSpawn(spawnId, caught)
    local spawn = spawns[spawnId]
    if spawn == nil then
        return
    end
    spawns[spawnId] = nil
    local owner = spawn.Owner
    countByOwner[owner] = math.max(0, (countByOwner[owner] or 1) - 1)
    if owner.Parent == Players then
        Remotes.WildUpdate:FireClient(
            owner,
            { Kind = "despawn", Id = spawnId, Caught = caught == true }
        )
    end
end

-- ── Spawning (server rolls rarity -> species at spawn; positions near the owner) ─────────────
local function spawnFor(player)
    if (countByOwner[player] or 0) >= WildConfig.MaxAlivePerPlayer then
        return
    end
    local root = rootOf(player)
    if root == nil then
        return
    end
    -- M10.2: rarity is ROUTED by the player's unlocked + present biome (clip-proof), with the HUNT
    -- spawn-rate boost applied on top of the biome's base weights (no double-apply).
    local rarity = BiomeService.RollRarityFor(player, huntSpawnRate(player))
    if rarity == nil then
        return
    end
    local speciesId = WildConfig.PickSpecies(rarity)
    if speciesId == nil then
        return
    end
    local def = Catalog.Get(speciesId)
    if def == nil then
        return
    end

    local angle = math.random() * math.pi * 2
    local dist = WildConfig.SpawnRadiusMin
        + math.random() * (WildConfig.SpawnRadiusMax - WildConfig.SpawnRadiusMin)
    local position = root.Position
        + Vector3.new(math.cos(angle) * dist, -1.5, math.sin(angle) * dist)

    nextId += 1
    local spawnId = "w" .. nextId
    local behavior = WildConfig.BehaviorFor(rarity)
    local eff = NetService.EffectiveCatch(player) -- M10.4: net + HUNT combined catch params (capped)
    local spawn = {
        Id = spawnId,
        Owner = player,
        Type = speciesId,
        DisplayName = def.DisplayName,
        Rarity = rarity,
        Position = position,
        Origin = position,
        WanderTarget = nil,
        SpawnTime = os.clock(),
        Caught = false,
        Hold = behavior.Hold * eff.HoldMult,
        TapsToCatch = TapConfig.CatchTapsFor(rarity), -- tap-to-progress: taps to catch this spawn
        Range = WildConfig.CatchBaseRange + eff.RangeAdd,
        Revealed = huntReveal(player) and WildConfig.IsRarePlus(rarity),
    }
    spawns[spawnId] = spawn
    countByOwner[player] = (countByOwner[player] or 0) + 1
    sendSpawn(spawn)
    Analytics.custom(player, Analytics.Events.WildSpawn, Rarity.Get(rarity).Order)
end

-- ── The atomic catch commit (shared by the remote + the dormant auto-catch hook) ────────────
-- Validation (existence/owner/range) is done by the caller. Returns (ok, nameOrReason, mutation).
local function commitCatch(player, spawn)
    if spawn.Caught then
        return false, "It already got away."
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return false, "Not ready yet."
    end
    local plot = PlotService.GetPlot(player)
    if plot == nil then
        return false, "Your base isn't ready."
    end
    -- PAD-FULL SAFE: check a free pad BEFORE committing -> on no pad we reject and the spawn STAYS
    -- (catchable later); nothing is removed or minted, so no loss + no dupe.
    local padIndex = PlotService.FindFreePad(player, profile)
    if padIndex == nil then
        return false, "Free a pad first, then catch!"
    end

    -- ===== COMMIT: guard + remove + mint, NO yields between. =====
    spawn.Caught = true
    removeSpawn(spawn.Id, true)
    local def = Catalog.Get(spawn.Type)
    if def == nil then
        return false, "That creature is unknown."
    end
    local unit = BrainrotFactory.create(player, def, padIndex, BrainrotFactory.RollFor.Catch)
    local isNewSpecies = profile.Data.Discovered[def.Id] ~= true
    table.insert(profile.Data.OwnedBrainrots, unit)
    profile.Data.Discovered[def.Id] = true
    -- ===========================================================

    BrainrotService.SpawnBrainrot(player, plot, unit)
    ProtectionService.RefreshPrompts(player)
    EvolutionService.AwardAllXP(player, WildConfig.CatchXP) -- M11.2 catch-XP hook
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
    ProfileManager.ForceSave(player)
    Analytics.custom(player, Analytics.Events.WildCatch, Rarity.Get(spawn.Rarity).Order)
    -- M12.1 observation hooks (pure emit; no behavior change) -> quest progress.
    GameSignals.fire(player, "catch_count", 1)
    if isNewSpecies then
        GameSignals.fire(player, "catch_new", 1)
    end
    return true, def.DisplayName, unit.Mutation
end

-- The server-side in-range check on the REAL character (anti-teleport / anti-spoof), shared by the tap
-- validate + complete. Fleeing OUT of range fails this -> TapService resets the catch fill cleanly.
local function inCatchRange(player, spawn)
    local root = rootOf(player)
    if root == nil then
        return false
    end
    local range = WildConfig.CatchBaseRange + NetService.EffectiveCatch(player).RangeAdd
    return (root.Position - spawn.Position).Magnitude <= range
end

-- TAP-TO-PROGRESS: is this catch interaction valid right now? Returns (ok, tapsNeeded). The client only
-- accrues progress while ok; out-of-range/fled/gone -> not ok -> the fill resets.
function WildSpawnService.TapValidate(player, spawnId)
    local spawn = spawns[spawnId]
    if spawn == nil or spawn.Owner ~= player or spawn.Caught then
        return false, 0
    end
    return inCatchRange(player, spawn), spawn.TapsToCatch
end

-- TAP-TO-PROGRESS completion: the tap meter filled -> re-validate range, then the EXISTING atomic
-- factory-catch fires EXACTLY ONCE (commitCatch's spawn.Caught guard). Returns true on a real catch.
function WildSpawnService.TapComplete(player, spawnId)
    local spawn = spawns[spawnId]
    if spawn == nil or spawn.Owner ~= player or spawn.Caught then
        return false
    end
    if not inCatchRange(player, spawn) then
        return false
    end
    local ok = commitCatch(player, spawn)
    return ok == true
end

-- The old one-shot catch remote is RETIRED by the tap rework (a single call could bypass the human-max-
-- clamped tap progress). It stays bound but INERT so a direct/injected call can never instant-catch.
local function handleCatch(_player, _spawnId)
    return { Result = "Miss", Message = "Tap to catch!" }
end

-- ── Behavior + despawn loop (server-driven; positions stream to the owner) ───────────────────
local function step(dt)
    local now = os.clock()
    for spawnId, spawn in pairs(spawns) do
        if spawn.Caught then
            removeSpawn(spawnId, true) -- defensive: a resolved spawn is already gone (no-op)
        elseif now - spawn.SpawnTime > WildConfig.DespawnTime then
            removeSpawn(spawnId, false) -- timed out, uncaught
        else
            local owner = spawn.Owner
            local root = rootOf(owner)
            local behavior = WildConfig.BehaviorFor(spawn.Rarity)
            local eff = NetService.EffectiveCatch(owner) -- M10.4: net + HUNT (flee-resist + auto-catch)
            local toOwner = root ~= nil and (root.Position - spawn.Position) or nil
            local fleeing = root ~= nil
                and behavior.FleeDistance > 0
                and not huntNoFlee(owner)
                and toOwner.Magnitude < behavior.FleeDistance * (1 - eff.FleeResist)

            if fleeing then
                local away = -toOwner
                local dir = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
                spawn.Position = spawn.Position
                    + Vector3.new(dir.X, 0, dir.Z) * behavior.FleeSpeed * dt
            else
                if
                    spawn.WanderTarget == nil
                    or (spawn.Position - spawn.WanderTarget).Magnitude < 3
                then
                    local a = math.random() * math.pi * 2
                    local r = math.random() * 14
                    spawn.WanderTarget = spawn.Origin
                        + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
                end
                local d = spawn.WanderTarget - spawn.Position
                if d.Magnitude > 0.1 then
                    local dir = d.Unit
                    spawn.Position = spawn.Position
                        + Vector3.new(dir.X, 0, dir.Z) * behavior.Wander * dt
                end
                -- AUTO-CATCH (M10.4 net tiers + M11.1 Poacher, combined + capped by NetService): a
                -- passing common may auto-catch. 0 with no net auto-catch/perk -> never fires.
                local auto = eff.AutoCatch
                if
                    auto > 0
                    and spawn.Rarity == "Common"
                    and root ~= nil
                    and toOwner.Magnitude <= (WildConfig.CatchBaseRange + eff.RangeAdd)
                    and math.random() < auto * dt
                then
                    commitCatch(owner, spawn)
                end
            end

            if spawns[spawnId] ~= nil and not spawn.Caught and owner.Parent == Players then
                Remotes.WildUpdate:FireClient(owner, {
                    Kind = "move",
                    Id = spawnId,
                    Pos = spawn.Position,
                    Revealed = huntReveal(owner) and WildConfig.IsRarePlus(spawn.Rarity),
                })
            end
        end
    end
end

-- Removes every spawn owned by a leaving player (before profile release; no leaks).
function WildSpawnService.ClearPlayer(player)
    for spawnId, spawn in pairs(spawns) do
        if spawn.Owner == player then
            spawns[spawnId] = nil
        end
    end
    countByOwner[player] = nil
end

function WildSpawnService.Init()
    Remotes.WildCatch.OnServerInvoke = function(player, spawnId)
        return handleCatch(player, spawnId)
    end

    if not WildConfig.Enabled then
        return
    end

    RunService.Heartbeat:Connect(function(deltaTime)
        loopAccum += deltaTime
        if loopAccum >= LOOP_INTERVAL then
            step(loopAccum)
            loopAccum = 0
        end
        spawnAccum += deltaTime
        if spawnAccum >= WildConfig.SpawnInterval then
            spawnAccum = 0
            for _, player in ipairs(Players:GetPlayers()) do
                if ProfileManager.GetProfile(player) ~= nil then
                    spawnFor(player)
                end
            end
        end
    end)
end

return WildSpawnService
