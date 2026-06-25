-- FusionConfig (M9.2): THE single source of truth for STARS + FUSION. Every tunable number lives
-- here. Fusion is server-authoritative -- the client sends fodder Ids only; the server reads all
-- recipes/odds/multipliers from this file.
--
-- STARS: every unit has a Star level (>= 1). The star multiplier is a PER-UNIT income factor
-- (UNCAPPED, like the mutation factor) applied EXACTLY ONCE in Shared/UnitIncome -- it is NEVER baked
-- into the stored IncomePerSec. effective income = base * mutationMultiplier * StarMultiplier(star).
--
-- RISK FEEL: fusing 3 same-species copies usually star-ups (a clean win), sometimes CRITs (extra
-- star), rarely SOFT-FAILs (no upgrade + you lose only PART of the fodder -- never everything, so a
-- fail stings but never rage-quits). Retune the curve + odds below.

local FusionConfig = {}

-- ── Star income curve (index = star level; [1] = 1x = no bonus) ─────────────────────────────
FusionConfig.MaxStar = 5
FusionConfig.StarMultipliers = { 1, 1.6, 2.6, 4.2, 7 } -- ★1..★5  (~x1.6 per star, compounding)

-- The per-unit income multiplier for a star level (defensive: legacy/nil star -> 1x).
function FusionConfig.StarMultiplier(star)
    star = (type(star) == "number" and star >= 1) and math.floor(star) or 1
    if star > FusionConfig.MaxStar then
        star = FusionConfig.MaxStar
    end
    return FusionConfig.StarMultipliers[star] or 1
end

-- A short ★ string for UI ("★★★").
function FusionConfig.Stars(star)
    star = (type(star) == "number" and star >= 1) and math.floor(star) or 1
    return string.rep("\u{2605}", math.min(star, FusionConfig.MaxStar))
end

-- ── Same-species recipe: N copies of the SAME Type at the SAME Star -> one at Star+1 ─────────
FusionConfig.SameSpeciesCount = 3

-- ── CRIT: a lucky fusion grants EXTRA stars (clamped to MaxStar). ────────────────────────────
FusionConfig.CritChance = 0.1
FusionConfig.CritExtraStars = 1

-- ── SOFT-FAIL: NO upgrade; you lose only PART of the fodder (never all of it). On a fail the
-- fusion consumes SoftFailLose of the N fodder and KEEPS the rest unchanged. Must be < the recipe
-- count so the player always keeps something. ───────────────────────────────────────────────
FusionConfig.SoftFailChance = 0.08
FusionConfig.SoftFailLose = 1

-- ── Mutation-on-fusion: chance the successful result ROLLS a mutation (via the existing weighted
-- roll, respecting the luck hook). The result also INHERITS the best mutation among the fodder, so
-- fusing never strips your best variant. ─────────────────────────────────────────────────────
FusionConfig.MutationOnFusionChance = 0.05

-- ── Optional TIER-UP recipe (config SWITCH; OFF by default). N units of one rarity (any types) ->
-- a factory roll for a unit of the NEXT rarity tier, with the same crit/fail rolls. ────────────
FusionConfig.TierUpEnabled = false
FusionConfig.TierUpCount = 5

-- Cost hook: fusion costs nothing but fodder this milestone. A cash cost could be added here later.
FusionConfig.CashCost = 0

return FusionConfig
