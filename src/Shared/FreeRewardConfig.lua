-- FreeRewardConfig (M12.2): THE single source of truth for the recurring FREE-reward economy -- the
-- daily-streak CHEST, the timed GIFT, the SPIN wheel, and the base MYSTERY BLOCK. Every reward is FREE
-- (earned by play), server-rolled, and server-time-gated. NOTHING here is sold for Robux: any
-- randomized outcome is awarded by play only (the optional DoubleDaily gamepass is a DETERMINISTIC,
-- disclosed convenience -- it just doubles the daily CASH, never buys a random pull). Tune everything
-- here; SHORTEN the cooldowns to test, RESET for production. Validate defensively.
--
-- REWARD SHAPE: a reward is either a DIRECT grant { Cash = n } / { Unit = "<species>" } or an RNG table
-- { Roll = { { Weight, Cash?/Unit?, Lucky? }, ... } } rolled SERVER-SIDE (an entry flagged Lucky=true
-- has its weight multiplied by the player's luck -- legal, since the reward is earned, not purchased).

local FreeRewardConfig = {}

FreeRewardConfig.DayLength = 86400 -- s per daily-chest period (SHORTEN to test, e.g. 120)
FreeRewardConfig.DayEpoch = 0 -- day boundary aligns to UTC midnight (86400 divides the unix epoch)

-- ── DAILY STREAK CHEST ──────────────────────────────────────────────────────────────────────
-- One claim per server-day. The streak grows if you claim on consecutive days; MISS a day -> it
-- RESETS to day 1 (documented). Reward = ladder[min(streak, #Ladder)] (the top rung repeats).
FreeRewardConfig.Daily = {
    Ladder = {
        { Cash = 1000 },
        { Cash = 2500 },
        { Cash = 5000 },
        { Cash = 10000 },
        { Cash = 20000 },
        { Cash = 35000 },
        { Cash = 75000 }, -- day 7+ (repeats at the cap)
    },
    GamepassDoubleKey = "DoubleDaily", -- a DETERMINISTIC gamepass that 2x's the daily CASH (non-random)
}

-- ── TIMED FREE GIFT (refills on a server-time cooldown; banks at most 1 ready) ───────────────
FreeRewardConfig.Gift = {
    Cooldown = 300, -- s between gifts (the reference's "free brainblock" hook)
    Reward = {
        Roll = {
            { Weight = 60, Cash = 500 },
            { Weight = 30, Cash = 1500 },
            { Weight = 9, Cash = 4000 },
            { Weight = 1, Cash = 15000, Lucky = true },
        },
    },
}

-- ── SPIN / WHEEL (earn a free spin every cooldown, bank up to Max; NEVER bought with Robux) ──
FreeRewardConfig.Spin = {
    EarnCooldown = 1800, -- s to earn one free spin
    MaxBanked = 3, -- cap on banked spins
    StartSpins = 1, -- a new player starts with this many
    Segments = { -- server-rolled by Weight; the client animates to the server result. Odds shown in UI.
        { Weight = 40, Cash = 1000 },
        { Weight = 25, Cash = 3000 },
        { Weight = 15, Cash = 8000 },
        { Weight = 10, Cash = 20000 },
        { Weight = 6, Cash = 40000 },
        { Weight = 3, Cash = 90000, Lucky = true },
        { Weight = 1, Cash = 250000, Lucky = true },
    },
}

-- ── MYSTERY BLOCK (at the base; a tagged dev-placed part; server-gated cooldown) ────────────
FreeRewardConfig.Mystery = {
    Tag = "MysteryBlock", -- CollectionService tag the dev applies to the base block part
    Cooldown = 600, -- s between opens (per player)
    Reward = {
        Roll = {
            { Weight = 50, Cash = 2000 },
            { Weight = 30, Cash = 6000 },
            { Weight = 15, Cash = 15000 },
            { Weight = 4, Cash = 40000, Lucky = true },
            { Weight = 1, Cash = 120000, Lucky = true },
        },
    },
}

-- ── Period helper (pure server-time -> cross-server consistent) ──────────────────────────────
function FreeRewardConfig.CurrentDay(t)
    return math.floor((t - FreeRewardConfig.DayEpoch) / FreeRewardConfig.DayLength)
end

function FreeRewardConfig.DayEndsAt(dayId)
    return FreeRewardConfig.DayEpoch + (dayId + 1) * FreeRewardConfig.DayLength
end

-- The daily ladder reward for a given streak length (top rung repeats).
function FreeRewardConfig.DailyReward(streak)
    local ladder = FreeRewardConfig.Daily.Ladder
    local idx = math.clamp(streak, 1, #ladder)
    return ladder[idx]
end

return FreeRewardConfig
