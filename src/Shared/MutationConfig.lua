-- MutationConfig: the per-UNIT "chase" modifier. A brainrot can roll a mutation at ACQUISITION
-- (server-side, in the central factory) that multiplies THAT unit's income + makes it visually
-- distinct. The mutation is INTRINSIC to the unit record and travels unchanged through steal/trade
-- -- it is NEVER re-rolled on transfer. Retune all odds + multipliers here.
--
-- INCOME (documented, anti-double-count): stored per-unit IncomePerSec stays the species BASE.
-- Effective per-unit income = base * IncomeMultiplier (see Shared/UnitIncome -- the ONE place this
-- multiply happens). The per-unit mutation factor is UNCAPPED (a per-unit property); the per-player
-- global multiplier (prestige/gamepass/boost/completion/event) stays capped. No double-application.
--
-- Normal dominates the weight table so mutations feel rare. Approx odds with the weights below
-- (total 1170): Normal ~85.5%, Shiny ~10.3%, Golden ~3.4%, Rainbow ~0.68%, Diamond ~0.17%.
-- (A future fusion/upgrade system is intentionally NOT built -- mutations are roll-once, permanent.)

local MutationConfig = {}

-- Ordered (weakest -> strongest). `Available` reserved for future event-only mutations (data only).
MutationConfig.Mutations = {
    {
        Key = "normal",
        DisplayName = "",
        IncomeMultiplier = 1,
        RollWeight = 1000,
        Color = Color3.fromRGB(255, 255, 255),
        Material = Enum.Material.SmoothPlastic,
        Available = true,
    },
    {
        Key = "shiny",
        DisplayName = "Shiny",
        IncomeMultiplier = 2,
        RollWeight = 120,
        Color = Color3.fromRGB(150, 220, 255),
        Material = Enum.Material.Glass,
        Available = true,
    },
    {
        Key = "golden",
        DisplayName = "Golden",
        IncomeMultiplier = 4,
        RollWeight = 40,
        Color = Color3.fromRGB(255, 215, 60),
        Material = Enum.Material.Neon,
        Available = true,
    },
    {
        Key = "rainbow",
        DisplayName = "Rainbow",
        IncomeMultiplier = 10,
        RollWeight = 8,
        Color = Color3.fromRGB(255, 90, 200),
        Material = Enum.Material.Neon,
        Available = true,
    },
    {
        Key = "diamond",
        DisplayName = "Diamond",
        IncomeMultiplier = 25,
        RollWeight = 2,
        Color = Color3.fromRGB(130, 235, 255),
        Material = Enum.Material.Neon,
        Available = true,
    },
    -- BOSS-ONLY (M11.3): Available=false -> NEVER rolls via the normal acquisition roll. Granted ONLY
    -- as a world-boss reward (BossService sets unit.Mutation directly). A huge chase multiplier.
    {
        Key = "cosmic",
        DisplayName = "Cosmic",
        IncomeMultiplier = 50,
        RollWeight = 0,
        Color = Color3.fromRGB(180, 80, 255),
        Material = Enum.Material.Neon,
        Available = false,
    },
}

-- A documented config switch: if true, higher-rarity species get slightly better mutation odds.
-- Kept simple/off by default (the roll is rarity-independent). Hook reserved for future tuning.
MutationConfig.RarityConditioned = false

MutationConfig.ByKey = {}
for _, m in ipairs(MutationConfig.Mutations) do
    MutationConfig.ByKey[m.Key] = m
end

local NORMAL = "normal"

function MutationConfig.Get(key)
    return MutationConfig.ByKey[key or NORMAL] or MutationConfig.ByKey[NORMAL]
end

-- The income multiplier for a mutation key (1 for Normal/nil/unknown).
function MutationConfig.MultiplierFor(key)
    if key == nil then
        return 1
    end
    local m = MutationConfig.ByKey[key]
    return m ~= nil and m.IncomeMultiplier or 1
end

-- SERVER-SIDE weighted roll. `luck` (>= 1, default 1) multiplies every NON-normal weight, so a
-- future luck boost makes mutations more likely WITHOUT changing this core. Returns a mutation Key,
-- or nil for Normal (stored as nil to keep legacy/normal units clean). Only `Available` mutations
-- can roll.
function MutationConfig.Roll(luck)
    luck = (type(luck) == "number" and luck > 0) and luck or 1
    local total = 0
    for _, m in ipairs(MutationConfig.Mutations) do
        if m.Available ~= false then
            total += m.Key == NORMAL and m.RollWeight or m.RollWeight * luck
        end
    end
    local pick = math.random() * total
    local acc = 0
    for _, m in ipairs(MutationConfig.Mutations) do
        if m.Available ~= false then
            acc += m.Key == NORMAL and m.RollWeight or m.RollWeight * luck
            if pick <= acc then
                return m.Key ~= NORMAL and m.Key or nil
            end
        end
    end
    return nil
end

return MutationConfig
