-- BiomeConfig (M10.2): THE single source of truth for the BIOME LADDER. The world is a continuous
-- PROGRESSION: each biome spawns a different rarity band, and you unlock deeper biomes by WALKING
-- THROUGH physical gates that open when you meet a cash/rebirth requirement. NO portals/teleport.
-- Fills M10.1's region hook with real per-biome rarity routing. Put EVERY number here.
--
-- THE CURVE: each biome's weights skew one rarity tier up from the last (with a thin tail into the
-- next), and the UNLOCK cost escalates ~25-50x per tier (the new primary CASH SINK, replacing buying
-- units; net upgrades are the other sink in M10.4). The top biomes also gate on rebirth so they pace
-- behind prestige. Tag flat stand-in parts as biome volumes + gates to test before real geometry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WildConfig = require(ReplicatedStorage.Shared.WildConfig)

local BiomeConfig = {}

BiomeConfig.StarterBiome = "sunny_meadow"

-- Ordered ladder. Weights REPLACE the global wild weights for that biome (the routing). Unlock =
-- { Cash, Rebirth }. Gates = the gate ids (tagged parts) that lead INTO this biome.
BiomeConfig.Ladder = {
    {
        BiomeId = "sunny_meadow",
        Name = "Sunny Meadow",
        Weights = { Common = 1000, Rare = 60 },
        Unlock = { Cash = 0, Rebirth = 0 }, -- open from the start
        Gates = {},
    },
    {
        BiomeId = "sundae_shores",
        Name = "Sundae Shores",
        Weights = { Common = 280, Rare = 1000, Epic = 70 },
        Unlock = { Cash = 50000, Rebirth = 0 },
        Gates = { "gate_shores" },
    },
    {
        BiomeId = "croco_swamp",
        Name = "Croco Swamp",
        Weights = { Rare = 280, Epic = 1000, Legendary = 55 },
        Unlock = { Cash = 2000000, Rebirth = 0 },
        Gates = { "gate_swamp" },
    },
    {
        BiomeId = "magma_peak",
        Name = "Magma Peak",
        Weights = { Epic = 280, Legendary = 1000, Mythic = 40 },
        Unlock = { Cash = 50000000, Rebirth = 1 },
        Gates = { "gate_magma" },
    },
    {
        BiomeId = "cosmic_rift",
        Name = "Cosmic Rift",
        Weights = { Legendary = 280, Mythic = 1000, Secret = 18 },
        Unlock = { Cash = 1000000000, Rebirth = 2 },
        Gates = { "gate_rift" },
    },
    {
        BiomeId = "the_void",
        Name = "The Void",
        Weights = { Mythic = 280, Secret = 1000 },
        Unlock = { Cash = 50000000000, Rebirth = 4 },
        Gates = { "gate_void" },
    },
}

BiomeConfig.ById = {}
BiomeConfig.Order = {} -- biomeId -> ladder index (for "highest unlocked")
for index, biome in ipairs(BiomeConfig.Ladder) do
    BiomeConfig.ById[biome.BiomeId] = biome
    BiomeConfig.Order[biome.BiomeId] = index
end

function BiomeConfig.Get(biomeId)
    return BiomeConfig.ById[biomeId]
end

function BiomeConfig.WeightsFor(biomeId)
    local biome = BiomeConfig.ById[biomeId] or BiomeConfig.ById[BiomeConfig.StarterBiome]
    return biome.Weights
end

-- SERVER-SIDE rarity roll for a biome's weights (+ a HUNT spawn-rate boost on Epic+ tiers). Reuses
-- M10.1's spawnable-rarity set so a biome can't roll a rarity with no species. Returns a rarity key.
function BiomeConfig.RollRarity(weights, rareBoost)
    rareBoost = (type(rareBoost) == "number" and rareBoost > 0) and rareBoost or 0
    local total = 0
    local list = {}
    for _, rarityKey in ipairs(WildConfig.SpawnableRarities) do
        local w = weights[rarityKey]
        if type(w) == "number" and w > 0 then
            if WildConfig.IsBoostable(rarityKey) then
                w = w * (1 + rareBoost)
            end
            total += w
            table.insert(list, { key = rarityKey, w = w })
        end
    end
    if total <= 0 then
        return nil
    end
    local pick = math.random() * total
    local acc = 0
    for _, entry in ipairs(list) do
        acc += entry.w
        if pick <= acc then
            return entry.key
        end
    end
    return list[#list].key
end

return BiomeConfig
