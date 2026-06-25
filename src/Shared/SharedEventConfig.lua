-- SharedEventConfig (M10.3): the HYPE LAYER. On top of each player's private instanced spawns, the
-- server occasionally spawns ONE shared rare/"mystery" brainrot that EVERYONE sees + races to catch --
-- first valid catch WINS it (dupe-safe), with a server-wide alert. Keep it RARE so the alert stays
-- special. The mystery is PRESENTATION (hidden identity in the alert), NOT a hidden success roll --
-- rarity is rolled at spawn; catching is deterministic skill. Put EVERY number here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WildConfig = require(ReplicatedStorage.Shared.WildConfig)
local BiomeConfig = require(ReplicatedStorage.Shared.BiomeConfig)

local SharedEventConfig = {}

SharedEventConfig.Enabled = true
SharedEventConfig.FirstDelay = 150 -- s after server start before the first shared event
SharedEventConfig.IntervalMin = 360 -- s minimum gap between shared events (kept RARE)
SharedEventConfig.IntervalMax = 720 -- s maximum gap (randomized jitter in between)
SharedEventConfig.MaxConcurrent = 1 -- never more than this many active at once
SharedEventConfig.DespawnTime = 90 -- s the shared spawn evades before it "gets away" (no winner)
SharedEventConfig.Hold = 4 -- catch HOLD time (longer -- it's a prize; shared prompt, fixed for all)
SharedEventConfig.BaseRange = 14 -- studs: server catch-distance (+ the catcher's HUNT/Net range)
SharedEventConfig.HideIdentity = true -- the alert says "a MYSTERY brainrot" (revealed on catch)
SharedEventConfig.ModelSize = Vector3.new(6, 6, 6)
SharedEventConfig.DefaultPosition = Vector3.new(0, 8, -110) -- placeholder if no eligible biome volume

-- Evasive behavior (it's a prize; tuned harder than normal flee).
SharedEventConfig.Behavior = { Wander = 14, FleeDistance = 34, FleeSpeed = 26 }

-- Eligible rarity tiers, skewed to the rare/mystery pulls (the rng is at spawn; presentation hides it).
SharedEventConfig.RarityWeights = {
    Epic = 40,
    Legendary = 100,
    Mythic = 60,
    Secret = 20,
}

-- Eligible biomes the shared spawn can appear in (nil = any biome). M10.2 volumes place it; if the
-- biome has no tagged volume yet, it falls back to DefaultPosition (placeholder-safe).
SharedEventConfig.EligibleBiomes = nil

-- Drama tier by rarity (PRESENTATION scale only -- bigger flash/sound for higher tiers; reveals
-- nothing about identity). Read by the client for the alert intensity.
SharedEventConfig.Drama = {
    Epic = 1,
    Legendary = 2,
    Mythic = 3,
    Secret = 4,
}

-- Rolls the shared event's rarity (reuses M10.1's spawnable set via the generic weighted roll). No
-- spawn-rate perk boost here -- shared events are server-global, not per-player.
function SharedEventConfig.RollRarity()
    return BiomeConfig.RollRarity(SharedEventConfig.RarityWeights, 0)
end

function SharedEventConfig.PickSpecies(rarityKey)
    return WildConfig.PickSpecies(rarityKey)
end

return SharedEventConfig
