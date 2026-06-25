-- BossConfig (M11.3): THE single source of truth for WORLD-BOSS CO-OP HUNTS. Periodically the SERVER
-- spawns ONE giant "Titan" brainrot that's infeasible to catch solo; the whole server gets alerted,
-- teams up ad-hoc, and drains its catch-meter together. When it falls, EVERY player who met the
-- participation threshold gets their OWN freshly-FACTORY-MINTED reward -- nothing is shared/split, so
-- no dupe/loss is possible. Co-op is EPHEMERAL (no clans/rosters) -- it dissolves when the boss is gone.
--
-- Retune EVERYTHING here. All boss state lives in server memory (BossService) -- NOTHING is persisted,
-- so there is no schema change. Boss-only species/mutations are availability-gated (Catalog.BossOnly /
-- MutationConfig Available=false) so they're obtainable ONLY here.

local BossConfig = {}

BossConfig.Enabled = true
BossConfig.MaxConcurrent = 1 -- at most this many active bosses server-wide (default 1)
BossConfig.SpawnInterval = 600 -- s between boss spawns (lower this + the meter to test fast)
BossConfig.FirstSpawnDelay = 120 -- s after server start before the first boss
-- Placeholder spawn point (biomes/map phases aren't built; real per-biome locations come later).
BossConfig.DefaultSpawnPosition = Vector3.new(0, 14, -140)

-- Each boss is data. Tuning note: the meter must be infeasible for ONE player within the Timeout but
-- beatable by a group. Solo drain rate ~= HitDamage / HoldDuration; ensure Meter / (that) > Timeout.
BossConfig.Bosses = {
    {
        Key = "titan_sahur",
        DisplayName = "Titan Sahur",
        Biome = "the Plaza", -- placeholder label shown in the alert
        Meter = 240, -- total catch-meter / HP (drained by validated holds)
        HitDamage = 1, -- meter drained per validated hold (before catch-perk boost)
        HoldDuration = 1.2, -- s ProximityPrompt hold per hit
        PromptRange = 28, -- studs: prompt activation distance
        ValidateRange = 34, -- studs: server-side proximity re-check (a touch > PromptRange)
        HitInterval = 0.25, -- s minimum between a player's validated hits (server rate-limit)
        Timeout = 180, -- s before the boss enrages + leaves (no rewards) if not beaten
        ParticipationThreshold = 5, -- minimum banked contribution (damage) to qualify for loot
        BossXP = 1500, -- M11.2: XP each qualifying player's units gain from the fight
        ModelSize = Vector3.new(18, 26, 18),
        Color = Color3.fromRGB(180, 60, 220),
        Reward = {
            Cash = { Min = 8000, Max = 40000 }, -- everyone who qualifies gets some (scales w/ contribution)
            NoPadCash = 30000, -- safe fallback when a unit reward has no free pad (delivered as cash)
            -- ONE weighted entry is rolled per qualifying player. Boss-only species/mutations live here.
            Table = {
                { Type = "Brainrot", Species = "titan_spawn", Weight = 58 },
                { Type = "Brainrot", Species = "titan_spawn", Mutation = "cosmic", Weight = 12 },
                { Type = "Brainrot", Species = "graipuss_medussi", Weight = 22 }, -- a real Mythic floor
                { Type = "Cash", Amount = 100000, Weight = 8 },
            },
        },
    },
}

BossConfig.ByKey = {}
for _, boss in ipairs(BossConfig.Bosses) do
    BossConfig.ByKey[boss.Key] = boss
end

-- Defensive read: a boss definition by key (nil if unknown).
function BossConfig.Get(key)
    return BossConfig.ByKey[key]
end

-- Picks a boss definition to spawn (random among configured + valid). Validates Meter > 0 so a
-- malformed entry can never spawn an un-killable boss. Returns nil if none are valid.
function BossConfig.PickSpawn()
    local valid = {}
    for _, boss in ipairs(BossConfig.Bosses) do
        if type(boss.Meter) == "number" and boss.Meter > 0 and type(boss.HitDamage) == "number" then
            table.insert(valid, boss)
        end
    end
    if #valid == 0 then
        return nil
    end
    return valid[math.random(1, #valid)]
end

return BossConfig
