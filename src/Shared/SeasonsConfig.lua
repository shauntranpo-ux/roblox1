-- SeasonsConfig: recurring, time-boxed competitive SEASONS. Each season has its OWN leaderboard
-- (a per-season OrderedDataStore) that starts fresh; at season end the board FREEZES (readable for
-- a claim window) and a new season begins -- a NON-DESTRUCTIVE rollover. The CURRENT SEASON ID is
-- derived purely from server time + this config, so every server agrees with no coordination.
--
-- SEASON SCORE METRIC = "season points" earned from ENGAGEMENT (not raw cash, which would favor
-- veterans + is gameable). Points are weighted per action below. Retune everything here.

local SeasonsConfig = {}

-- ── Cadence (absolute, UTC) ──────────────────────────────────────────────────────────────
SeasonsConfig.SeasonLength = 604800 -- s per season (604800 = 7 days / weekly)
SeasonsConfig.Anchor = 0 -- UTC epoch anchor; 0 aligns seasons to absolute week boundaries since 1970
SeasonsConfig.ClaimWindow = 604800 -- s after a season ends that its rewards remain claimable
SeasonsConfig.TopN = 25 -- entries shown / read for the season board + ranked-reward scan

-- ── Season-score weights (points per unit of signal) ─────────────────────────────────────
SeasonsConfig.ScoreWeights = {
    EARN_CASH = 0.00001, -- 1 point per 100k cash earned
    STEAL = 50, -- per successful steal
    TRADE = 25, -- per completed trade
    BUY = 5, -- per brainrot bought
    DISCOVER = 100, -- per new species/mutation discovered
    REBIRTH = 500, -- per rebirth
}

-- ── Rewards (Cash only -> always grantable, so claims can't partial-fail). Documented: brainrot/
-- multiplier rewards could be added via the established no-pad-refuse / Benefits-source patterns. ──
-- RANKED: by final rank (top players). { Min, Max, Reward }.
SeasonsConfig.RankedRewards = {
    { Min = 1, Max = 1, Reward = { Type = "Cash", Amount = 5000000 } },
    { Min = 2, Max = 3, Reward = { Type = "Cash", Amount = 2000000 } },
    { Min = 4, Max = 10, Reward = { Type = "Cash", Amount = 750000 } },
    { Min = 11, Max = 25, Reward = { Type = "Cash", Amount = 200000 } },
}
-- TRACK: every threshold the player's final score reaches grants its reward (all participants).
SeasonsConfig.TrackRewards = {
    { Score = 100, Reward = { Type = "Cash", Amount = 25000 } },
    { Score = 500, Reward = { Type = "Cash", Amount = 150000 } },
    { Score = 2000, Reward = { Type = "Cash", Amount = 750000 } },
    { Score = 10000, Reward = { Type = "Cash", Amount = 4000000 } },
}

-- The current season id from server time (same on every server). Deterministic, integer.
function SeasonsConfig.CurrentId(t)
    return math.floor((t - SeasonsConfig.Anchor) / SeasonsConfig.SeasonLength)
end

-- The [start, end) UTC window for a season id.
function SeasonsConfig.WindowFor(id)
    local start = SeasonsConfig.Anchor + id * SeasonsConfig.SeasonLength
    return start, start + SeasonsConfig.SeasonLength
end

return SeasonsConfig
