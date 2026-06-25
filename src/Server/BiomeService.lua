-- BiomeService (M10.2): server-authoritative BIOME ZONES + per-biome rarity ROUTING + walk-through
-- UNLOCK GATES. Fills the M10.1 region hook. The server decides which biome a player is in (real
-- character position vs tagged volumes), which rarities spawn there (routed by the player's
-- UNLOCKED + present biome -- clip-proof), and whether a player may unlock a gate (cash/rebirth,
-- idempotent + persisted). The client renders gates/labels + sends pass/unlock INTENT only.
--
-- ============================  SELF-AUDIT (biomes)  ==========================================
-- (a) SERVER-AUTHORITATIVE: zone membership (pointBiome), routing (routedBiome), and unlock
--     validation all live here; the client can't grant itself rewards or access -- routedBiome falls
--     back to the player's HIGHEST UNLOCKED biome if they're standing in a biome they haven't unlocked
--     (so clipping past a locked gate yields ONLY their unlocked rarities -- the reward gate is routing,
--     not client position).
-- (b) UNLOCKS IDEMPOTENT + PERSISTED + PRICED: an already-unlocked biome is a no-op (no charge); a new
--     unlock checks rebirth THEN TrySpends the cash (guarded accessor) THEN records -- exactly once,
--     surviving rejoin/cross-server (persisted UnlockedBiomes set; re-unlock never double-charges).
-- (c) CONTINUOUS WORLD / NO TELEPORT: this only validates unlock state + publishes the current biome;
--     passability is the client opening unlocked gates' collision (the spatial gate). No portals.
-- (d) HUNT perks still apply: routing passes the spawn-rate boost into BiomeConfig.RollRarity on top of
--     the biome's base weights (no double-apply). M10.1 catch atomicity is untouched.
-- (e) PLACEHOLDER-SAFE: no tagged volumes -> pointBiome returns nil -> default to the starter biome;
--     logged, never errors.
-- ===========================================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeConfig = require(ReplicatedStorage.Shared.BiomeConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)

local BiomeService = {}

local VOLUME_TAG = "BiomeVolume" -- dev tags a part with this + attribute Biome = "<biomeId>"
local DETECT_INTERVAL = 0.5
local detectAccum = 0
local lastBiome = {} -- [Player] = biomeId
local warnedNoVolumes = false

-- Is `point` inside this (possibly rotated) volume part?
local function inside(part, point)
    local rel = part.CFrame:PointToObjectSpace(point)
    local half = part.Size * 0.5
    return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

-- The biome whose tagged volume contains `point`, or nil if none (untagged-safe).
local function pointBiome(point)
    local tagged = CollectionService:GetTagged(VOLUME_TAG)
    if #tagged == 0 then
        if not warnedNoVolumes then
            warnedNoVolumes = true
            warn(
                "[Biomes] No '"
                    .. VOLUME_TAG
                    .. "' volumes tagged -> defaulting everyone to the starter biome ("
                    .. BiomeConfig.StarterBiome
                    .. "). Tag flat parts (attribute Biome=<id>) to enable routing."
            )
        end
        return nil
    end
    for _, part in ipairs(tagged) do
        if part:IsA("BasePart") then
            local biomeId = part:GetAttribute("Biome")
            if
                type(biomeId) == "string"
                and BiomeConfig.Get(biomeId) ~= nil
                and inside(part, point)
            then
                return biomeId
            end
        end
    end
    return nil
end

local function rootOf(player)
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function isUnlocked(profile, biomeId)
    if biomeId == BiomeConfig.StarterBiome then
        return true
    end
    return profile.Data.UnlockedBiomes[biomeId] == true
end

-- The highest-order biome the player has unlocked (default the starter).
local function highestUnlocked(profile)
    local best = BiomeConfig.StarterBiome
    local bestOrder = BiomeConfig.Order[best]
    for biomeId in pairs(profile.Data.UnlockedBiomes) do
        local order = BiomeConfig.Order[biomeId]
        if order ~= nil and order > bestOrder then
            best, bestOrder = biomeId, order
        end
    end
    return best
end

-- The biome whose rarities the player should ACTUALLY get: the biome they're standing in IF unlocked,
-- else their highest unlocked (so clipping into a locked biome gives no higher-rarity reward).
local function routedBiome(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return BiomeConfig.StarterBiome
    end
    local root = rootOf(player)
    local current = root ~= nil and pointBiome(root.Position) or nil
    current = current or BiomeConfig.StarterBiome
    if isUnlocked(profile, current) then
        return current
    end
    return highestUnlocked(profile)
end

-- Called by WildSpawnService: roll a rarity from the player's ROUTED biome weights (+ HUNT boost).
function BiomeService.RollRarityFor(player, rareBoost)
    return BiomeConfig.RollRarity(BiomeConfig.WeightsFor(routedBiome(player)), rareBoost)
end

-- The biome the player is physically in right now (for the shared-event biome label etc.).
function BiomeService.CurrentBiome(player)
    local root = rootOf(player)
    return (root ~= nil and pointBiome(root.Position)) or BiomeConfig.StarterBiome
end

-- ── State + unlock handlers ─────────────────────────────────────────────────────────────────
local function buildState(player, profile)
    local unlocked = {}
    for biomeId in pairs(profile.Data.UnlockedBiomes) do
        unlocked[biomeId] = true
    end
    unlocked[BiomeConfig.StarterBiome] = true
    return {
        Unlocked = unlocked,
        Current = BiomeService.CurrentBiome(player),
        RebirthCount = profile.Data.RebirthCount or 0,
        Cash = math.floor(profile.Data.Cash or 0),
    }
end

local function handleUnlock(player, biomeId)
    if type(biomeId) ~= "string" or #biomeId > 40 then
        return { Result = "Error", Message = "Invalid biome." }
    end
    local biome = BiomeConfig.Get(biomeId)
    if biome == nil then
        return { Result = "Error", Message = "Unknown biome." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    if isUnlocked(profile, biomeId) then
        return {
            Result = "Success",
            Message = "Already unlocked.",
            State = buildState(player, profile),
        }
    end
    local req = biome.Unlock or { Cash = 0, Rebirth = 0 }
    if (profile.Data.RebirthCount or 0) < (req.Rebirth or 0) then
        return {
            Result = "Error",
            Message = "Requires Rebirth " .. (req.Rebirth or 0) .. ".",
        }
    end
    -- ===== COMMIT: spend (guarded) + record, no yields. Already-unlocked returned above (idempotent).
    local cost = req.Cash or 0
    if cost > 0 and not ProfileManager.TrySpend(player, cost) then
        return { Result = "Error", Message = "You can't afford it ($" .. cost .. ")." }
    end
    profile.Data.UnlockedBiomes[biomeId] = true
    -- ====================================================================================
    ProfileManager.ForceSave(player)
    Remotes.NotifyPlayer(player, "success", biome.Name .. " unlocked! Walk on in.", "buy")
    Analytics.custom(player, Analytics.Events.BiomeUnlock, BiomeConfig.Order[biomeId] or 0)
    return {
        Result = "Success",
        Message = biome.Name .. " unlocked!",
        State = buildState(player, profile),
    }
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────────────────────
function BiomeService.SetupPlayer(_player, profile)
    profile.Data.UnlockedBiomes = profile.Data.UnlockedBiomes or {}
    profile.Data.UnlockedBiomes[BiomeConfig.StarterBiome] = true -- starter always open
end

function BiomeService.ClearPlayer(player)
    lastBiome[player] = nil
end

function BiomeService.Init()
    Remotes.BiomeAction.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return { Result = "Error", Message = "Invalid request." }
        end
        if not RateLimiter.check(player, "biome", 0.3) then
            return { Result = "Error", Message = "Slow down." }
        end
        if payload.Action == "get" then
            local profile = ProfileManager.GetProfile(player)
            if profile == nil then
                return { Result = "Error", Message = "Not ready yet." }
            end
            return { Result = "Success", State = buildState(player, profile) }
        elseif payload.Action == "unlock" then
            return handleUnlock(player, payload.BiomeId)
        end
        return { Result = "Error", Message = "Unknown action." }
    end

    -- Biome-entry detection: publish the player's current biome as an attribute (the client renders
    -- the biome label + drives the per-zone atmosphere hook from it). Throttled.
    RunService.Heartbeat:Connect(function(deltaTime)
        detectAccum += deltaTime
        if detectAccum < DETECT_INTERVAL then
            return
        end
        detectAccum = 0
        for _, player in ipairs(Players:GetPlayers()) do
            if ProfileManager.GetProfile(player) ~= nil then
                local current = BiomeService.CurrentBiome(player)
                if lastBiome[player] ~= current then
                    lastBiome[player] = current
                    player:SetAttribute("CurrentBiome", current)
                    Analytics.custom(
                        player,
                        Analytics.Events.BiomeEnter,
                        BiomeConfig.Order[current] or 0
                    )
                end
            end
        end
    end)
end

return BiomeService
