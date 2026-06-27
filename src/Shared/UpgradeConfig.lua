-- UpgradeConfig: the cash-sink UPGRADE definitions. Each upgrade has tiered levels the player buys with
-- cash for a permanent, PERSISTED boost -- the scaling money sink the game lacked. Server-authoritative;
-- the effects flow through the existing multiplier channels (all clamped downstream):
--   Income     -> additive income BONUS (above 1.0) -> Benefits.SetIncomeSource (capped at the 10x pool).
--   Luck       -> luck MULTIPLIER -> Benefits.SetLuckSource (product; better mutation odds).
--   CatchSpeed -> hold-reduce ADD -> NetService.EffectiveCatch (clamped to NetConfig.MaxHoldReduce).
--   CatchRange -> range ADD (studs) -> NetService.EffectiveCatch (clamped to NetConfig.MaxRangeAdd).
-- Income tops out under the 10x cap on purpose, leaving room for gamepasses. TUNE costs/effects here.

local UpgradeConfig = {}

-- Display + iteration order.
UpgradeConfig.Order = { "Income", "Luck", "CatchSpeed", "CatchRange" }

UpgradeConfig.Upgrades = {
    Income = {
        Name = "Income Boost",
        Icon = "💰",
        Desc = "Earn more from every deployed brainrot.",
        MaxLevel = 30, -- max effect +7.5 (8.5x), stays under the 10x income cap
        BaseCost = 25000,
        Growth = 1.6,
        PerLevel = 0.25, -- adds to the income bonus pool per level
        Format = function(level)
            return string.format("+%d%% income", math.floor(level * 25 + 0.5))
        end,
    },
    Luck = {
        Name = "Lucky Charm",
        Icon = "🍀",
        Desc = "Better odds of catching mutated brainrots.",
        MaxLevel = 40,
        BaseCost = 50000,
        Growth = 1.5,
        PerLevel = 0.05, -- luck multiplier add per level (max x3.0)
        Format = function(level)
            return string.format("x%.2f luck", 1 + level * 0.05)
        end,
    },
    CatchSpeed = {
        Name = "Quick Hands",
        Icon = "⚡",
        Desc = "Fill the catch meter faster.",
        MaxLevel = 20,
        BaseCost = 40000,
        Growth = 1.55,
        PerLevel = 0.015, -- hold-reduce add per level
        Format = function(level)
            return string.format("-%d%% catch time", math.floor(level * 1.5 + 0.5))
        end,
    },
    CatchRange = {
        Name = "Long Reach",
        Icon = "🎯",
        Desc = "Catch wild brainrots from farther away.",
        MaxLevel = 20,
        BaseCost = 30000,
        Growth = 1.5,
        PerLevel = 0.6, -- studs of catch range add per level
        Format = function(level)
            return string.format("+%d reach", math.floor(level * 0.6 + 0.5))
        end,
    },
}

function UpgradeConfig.Get(key)
    return UpgradeConfig.Upgrades[key]
end

-- Cost to go from `level` to `level+1` (level 0 -> 1 = BaseCost). Returns nil when already at max.
function UpgradeConfig.CostFor(key, level)
    local u = UpgradeConfig.Upgrades[key]
    if u == nil or level >= u.MaxLevel then
        return nil
    end
    return math.floor(u.BaseCost * (u.Growth ^ level))
end

-- The cumulative raw EFFECT scalar at a given level (per-level value * level).
function UpgradeConfig.EffectFor(key, level)
    local u = UpgradeConfig.Upgrades[key]
    if u == nil then
        return 0
    end
    return u.PerLevel * level
end

return UpgradeConfig
