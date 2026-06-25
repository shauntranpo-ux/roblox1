-- WildConfig (M10.1): THE single source of truth for the WILD-CATCH spawn engine. Brainrots spawn +
-- roam the world; players CATCH them (the primary acquisition, replacing direct-buy). THE RARITY IS
-- THE RNG: a wild spawn's rarity (then species) is rolled SERVER-SIDE at SPAWN time, rarity-weighted
-- (common frequent, apex almost never). Completing a catch is pure deterministic SKILL -- there is NO
-- hidden success roll on catch. Retune EVERY number here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)

local WildConfig = {}

-- ── Spawn cadence + caps (instanced per-player baseline; M10.3 adds shared rare events) ──────
WildConfig.Enabled = true
WildConfig.SpawnInterval = 8 -- s between spawn attempts per player (lower to test fast)
WildConfig.MaxAlivePerPlayer = 6 -- per-player live-spawn cap (bounds flooding + the registry)
WildConfig.DespawnTime = 45 -- s an uncaught spawn roams before it leaves + frees its slot
WildConfig.SpawnRadiusMin = 24 -- studs: nearest a spawn appears to the player
WildConfig.SpawnRadiusMax = 60 -- studs: farthest a spawn appears to the player
WildConfig.CatchBaseRange = 12 -- studs: server-validated catch distance (+ Big Net perk range)
WildConfig.BehaviorHz = 8 -- server wander/flee update rate
WildConfig.MoveSendHz = 5 -- replicated position-update rate to the owner (client lerps between)
WildConfig.CatchXP = 200 -- M11.2: XP each of the player's units gains on a catch

-- ── Rarity weights = THE acquisition RNG (rolled at spawn; common frequent, secret almost never) ──
WildConfig.RarityWeights = {
    Common = 1000,
    Rare = 220,
    Epic = 55,
    Legendary = 12,
    Mythic = 3,
    Secret = 0.5,
}

-- "Rare+" rarities: these FLEE the approaching player (the chase) + are what reveal perks surface.
WildConfig.RarePlus = {
    Epic = false, -- epics amble (don't flee), but count toward "rare" spawn-rate boosts
    Legendary = true,
    Mythic = true,
    Secret = true,
}

-- ── Per-rarity behavior profile (server-authoritative movement + the catch hold time) ─────────
WildConfig.Behavior = {
    Common = { Wander = 4, FleeDistance = 0, FleeSpeed = 0, Hold = 1.4 },
    Rare = { Wander = 7, FleeDistance = 0, FleeSpeed = 0, Hold = 1.8 },
    Epic = { Wander = 9, FleeDistance = 0, FleeSpeed = 0, Hold = 2.3 },
    Legendary = { Wander = 11, FleeDistance = 24, FleeSpeed = 17, Hold = 2.8 },
    Mythic = { Wander = 13, FleeDistance = 28, FleeSpeed = 21, Hold = 3.3 },
    Secret = { Wander = 15, FleeDistance = 32, FleeSpeed = 25, Hold = 4 },
}

-- M10.1 retires the random direct-roster-buy (wild-catch is primary). The guaranteed STARTER still
-- grants once so a new player is never stuck. The cash-sink rebalance toward zones/nets is M10.2/M10.4.
WildConfig.DirectBuyDisabled = true

-- ── REGION/ZONE HOOK (M10.2 foundation only; no biome geometry/gates here) ───────────────────
-- One region today. RegionFor(player) returns a region descriptor; AllowedRarities = nil means "all".
-- M10.2 will route per biome (biome volumes + unlock-gated rarity) by replacing this; no-ops safely
-- until then. SpawnPointFor lets M10.2 supply per-biome spawn areas; default = near the player.
WildConfig.DefaultRegion = { Key = "hub", AllowedRarities = nil }

function WildConfig.RegionFor(_player)
    return WildConfig.DefaultRegion
end

-- ── Wild species pool: non-premium, non-boss-only, non-exclusive roster entries, grouped by rarity.
-- Built once at load (defensively). The rarity roll picks a rarity, then a species within it here.
WildConfig.SpeciesByRarity = {}
for _, item in ipairs(Catalog.Items) do
    if item.Premium ~= true and item.BossOnly ~= true and item.ExclusiveSeason == nil then
        WildConfig.SpeciesByRarity[item.Rarity] = WildConfig.SpeciesByRarity[item.Rarity] or {}
        table.insert(WildConfig.SpeciesByRarity[item.Rarity], item.Id)
    end
end

-- An ordered, weight-valid rarity list (only rarities that have at least one spawnable species).
WildConfig.SpawnableRarities = {}
for _, entry in ipairs(Rarity.Ordered) do
    local pool = WildConfig.SpeciesByRarity[entry.Key]
    local weight = WildConfig.RarityWeights[entry.Key]
    if pool ~= nil and #pool > 0 and type(weight) == "number" and weight > 0 then
        table.insert(WildConfig.SpawnableRarities, entry.Key)
    end
end

function WildConfig.IsRarePlus(rarityKey)
    return WildConfig.RarePlus[rarityKey] == true
end

-- "rare-ish for spawn-rate boosts" = Epic and above (Apex Hunter / Lucky Clover / World Eater raise
-- these). Returns true if the rarity should be boosted by a SpawnRate perk.
function WildConfig.IsBoostable(rarityKey)
    local order = Rarity.Get(rarityKey).Order
    return order >= Rarity.Get("Epic").Order
end

-- SERVER-SIDE rarity roll. `rareBoost` (>= 0, from a SpawnRate HUNT perk) multiplies the boostable
-- (Epic+) weights so a hunter sees more rares -- still rolled at SPAWN (never on catch). region may
-- restrict AllowedRarities (M10.2). Returns a rarity key, or nil if nothing is spawnable.
function WildConfig.RollRarity(rareBoost, region)
    rareBoost = (type(rareBoost) == "number" and rareBoost > 0) and rareBoost or 0
    local allowed = region ~= nil and region.AllowedRarities or nil
    local total = 0
    local weighted = {}
    for _, rarityKey in ipairs(WildConfig.SpawnableRarities) do
        if allowed == nil or allowed[rarityKey] then
            local w = WildConfig.RarityWeights[rarityKey]
            if WildConfig.IsBoostable(rarityKey) then
                w = w * (1 + rareBoost)
            end
            total += w
            table.insert(weighted, { key = rarityKey, w = w })
        end
    end
    if total <= 0 then
        return nil
    end
    local pick = math.random() * total
    local acc = 0
    for _, entry in ipairs(weighted) do
        acc += entry.w
        if pick <= acc then
            return entry.key
        end
    end
    return weighted[#weighted].key
end

-- Picks a species id within a rarity (uniform). Returns nil if the rarity has no spawnable species.
function WildConfig.PickSpecies(rarityKey)
    local pool = WildConfig.SpeciesByRarity[rarityKey]
    if pool == nil or #pool == 0 then
        return nil
    end
    return pool[math.random(1, #pool)]
end

function WildConfig.BehaviorFor(rarityKey)
    return WildConfig.Behavior[rarityKey] or WildConfig.Behavior.Common
end

return WildConfig
