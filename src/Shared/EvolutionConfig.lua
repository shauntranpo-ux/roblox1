-- EvolutionConfig (M11.2): THE single source of truth for per-unit XP + EVOLUTION. Every owned
-- brainrot gains XP from use and EVOLVES through stages -- a bigger income multiplier, a stronger
-- signature perk (M11.1), and a placeholder evolved look. Stage + XP are INTRINSIC to the unit record
-- and travel UNCHANGED through steal/trade (exactly like Mutation + Star).
--
-- ── THE LADDER ───────────────────────────────────────────────────────────────────────────────
-- Stages[N] describes a unit AT stage N:
--   IncomeMult  -- the per-unit income multiplier at this stage (rides the canonical UnitIncome
--                  helper EXACTLY ONCE; uncapped per-unit factor, like mutation/star). Stage 1 = x1.
--   PerkScale   -- multiplies the M11.1 signature-perk magnitude at this stage (perk gets stronger).
--   Threshold   -- XP the unit must bank AT this stage to evolve to N+1 (nil at MaxStage). Escalates.
--   Cost        -- cash to evolve FROM this stage (a sink via the guarded accessor; 0 = free).
--   Visual      -- placeholder evolved look { Scale, Aura (Color3|nil), Glow }. ModelName reserved
--                  for real evolved models later (BrainrotService falls back to the placeholder).
--
-- CURVE: income roughly x1 / x1.5 / x2.5 / x4 / x7; thresholds step ~x5-6 so each stage is a longer
-- raise than the last. Retune EVERYTHING here. MAX STAGE = #Stages.

local EvolutionConfig = {}

EvolutionConfig.Stages = {
    {
        IncomeMult = 1,
        PerkScale = 1,
        Threshold = 2000,
        Cost = 0,
        Visual = { Scale = 1, Aura = nil, Glow = false },
    },
    {
        IncomeMult = 1.5,
        PerkScale = 1.25,
        Threshold = 12000,
        Cost = 5000,
        Visual = { Scale = 1.1, Aura = Color3.fromRGB(120, 230, 255), Glow = false },
    },
    {
        IncomeMult = 2.5,
        PerkScale = 1.6,
        Threshold = 60000,
        Cost = 50000,
        Visual = { Scale = 1.25, Aura = Color3.fromRGB(150, 255, 150), Glow = false },
    },
    {
        IncomeMult = 4,
        PerkScale = 2.2,
        Threshold = 300000,
        Cost = 500000,
        Visual = { Scale = 1.45, Aura = Color3.fromRGB(255, 200, 90), Glow = true },
    },
    {
        IncomeMult = 7,
        PerkScale = 3,
        Threshold = nil, -- MAX STAGE: no further evolution
        Cost = nil,
        Visual = { Scale = 1.7, Aura = Color3.fromRGB(255, 110, 200), Glow = true },
    },
}

EvolutionConfig.MaxStage = #EvolutionConfig.Stages

-- ── XP accrual tunables (lower the thresholds above to test fast) ─────────────────────────────
EvolutionConfig.XPPerCash = 0.1 -- a placed unit banks this fraction of its effective income as XP
EvolutionConfig.FlatXPPerSec = 1 -- + a flat XP trickle per second so even cheap units progress
EvolutionConfig.SurviveStealXP = 250 -- XP a unit banks when it SURVIVES a steal attempt (defense holds)
EvolutionConfig.CarryOverXP = false -- on evolve: false resets XP to 0; true carries the overflow over

-- A safe stage read (defends legacy/oddly-shaped records -> stage 1).
local function safeStage(unit)
    local stage = unit.EvolutionStage
    if type(stage) ~= "number" or stage < 1 then
        return 1
    end
    stage = math.floor(stage)
    return math.clamp(stage, 1, EvolutionConfig.MaxStage)
end
EvolutionConfig.StageOf = safeStage

-- The per-unit income multiplier for a stage. THE evolution factor the canonical helper multiplies
-- in (exactly once). Defensive: unknown/legacy -> x1.
function EvolutionConfig.IncomeMultiplier(stage)
    local s = EvolutionConfig.Stages[stage]
    return s ~= nil and s.IncomeMult or 1
end

-- The M11.1 perk-magnitude multiplier for a stage (perk gets stronger as the unit evolves).
function EvolutionConfig.PerkScale(stage)
    local s = EvolutionConfig.Stages[stage]
    return s ~= nil and s.PerkScale or 1
end

-- XP needed AT `stage` to evolve to the next (nil at max stage).
function EvolutionConfig.Threshold(stage)
    local s = EvolutionConfig.Stages[stage]
    return s ~= nil and s.Threshold or nil
end

-- Cash cost to evolve FROM `stage` (0 if free / unknown).
function EvolutionConfig.EvolveCost(stage)
    local s = EvolutionConfig.Stages[stage]
    return (s ~= nil and s.Cost) or 0
end

function EvolutionConfig.Visual(stage)
    local s = EvolutionConfig.Stages[stage]
    return s ~= nil and s.Visual or EvolutionConfig.Stages[1].Visual
end

function EvolutionConfig.IsMaxStage(stage)
    return safeStage({ EvolutionStage = stage }) >= EvolutionConfig.MaxStage
end

-- THE single XP-mutation helper (used by the income loop AND the survive-a-steal hook). Banks XP onto
-- the unit record server-side, and STOPS at max stage (graceful cap -- no overflow/error). Never
-- bakes anything into stored income; XP is its own field.
function EvolutionConfig.AddXP(unit, amount)
    if type(amount) ~= "number" or amount <= 0 then
        return
    end
    local stage = safeStage(unit)
    if stage >= EvolutionConfig.MaxStage then
        return -- max stage: XP no longer matters; bank nothing (graceful)
    end
    unit.XP = (unit.XP or 0) + amount
end

-- True if the unit has banked enough XP to evolve and isn't at max stage. Server re-checks on evolve.
function EvolutionConfig.CanEvolve(unit)
    local stage = safeStage(unit)
    if stage >= EvolutionConfig.MaxStage then
        return false
    end
    local threshold = EvolutionConfig.Threshold(stage)
    return threshold ~= nil and (unit.XP or 0) >= threshold
end

return EvolutionConfig
