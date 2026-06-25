-- TapConfig (tap-to-progress): THE single source of truth for the UNCAPPED-TAPPING rework that replaces
-- hold-to-X across CATCH (M10.1), STEAL (M4), and COMBAT (M11.3). Players mash as fast as they can with
-- instant client feedback; the client batches its local tap-count every interval; the SERVER validates
-- each batch against a generous HUMAN-MAX rate (a TOKEN BUCKET) and clamps excess -> an auto-clicker can
-- never exceed human-possible progress. This is an ANTI-CHEAT bound NO human reaches, NOT a gameplay throttle.

local TapConfig = {}

-- ── Client send cadence ──────────────────────────────────────────────────────────────────────
TapConfig.BatchInterval = 0.12 -- s: the client flushes its accumulated taps this often (~8 Hz)

-- ── SERVER anti-cheat ceiling (token bucket; sustained rate <= HumanMaxRate, burst <= BurstCap) ─
-- Humans sustain ~8-12 taps/s and burst ~15; these sit WELL above that, so a real player is NEVER
-- clamped, while a script firing thousands/s is bounded to human-possible progress.
TapConfig.HumanMaxRate = 22 -- taps/sec the bucket refills at (the sustained ceiling)
-- Max tokens the bucket holds = the largest single-batch burst allowed. Kept SMALL so a fresh full
-- bucket can't one-batch-complete a high-tap interaction (an exploiter can't instant-catch a Secret),
-- yet a real human is never clamped: they tap ~2-3 per 0.12s batch, far below the refill rate, so their
-- bucket never depletes. Only a script claiming huge batches drains it -> bounded to HumanMaxRate.
TapConfig.BurstCap = 12
TapConfig.MaxTapsPerBatch = 64 -- hard payload cap: a batch claiming more than this is rejected outright
TapConfig.MinBatchInterval = 0.05 -- s: server drops batches arriving faster than this (anti-firehose)

-- ── Taps-to-complete per interaction (catch + steal are progress FILLS; combat = damage per tap) ─
-- CATCH: per-rarity taps to fill the catch meter (mirrors the old per-rarity hold time at a brisk mash).
TapConfig.CatchTaps = {
    Common = 5,
    Rare = 7,
    Epic = 9,
    Legendary = 12,
    Mythic = 15,
    Secret = 18,
}
TapConfig.CatchTapsDefault = 6

-- STEAL: taps to pick a unit up off the victim's pad (was StealConfig.HoldDuration seconds).
TapConfig.StealTaps = 8

-- COMBAT has no fixed fill: each VALIDATED tap deals one CombatPower.AttackDamage hit (server-computed).
-- The token bucket bounds the effective attack rate, replacing the old per-tap AttackInterval rate cap.

function TapConfig.CatchTapsFor(rarityKey)
    return TapConfig.CatchTaps[rarityKey] or TapConfig.CatchTapsDefault
end

return TapConfig
