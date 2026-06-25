-- QuestConfig (M12.1): THE single source of truth for the TUTORIAL chain + DAILY / WEEKLY / MILESTONE
-- quests. Quests are pure DATA: an objective metric + target, a reward, and (for the tutorial) ordering.
-- Progress is tracked SERVER-SIDE by observing real gameplay signals (see GameSignals + QuestService);
-- the client only renders + sends claim intent. Put EVERY number here. Validate defensively.
--
-- ============================  HOW TO AUTHOR  ================================================
-- * Add/edit a quest: drop an entry in Tutorial / DailyPool / WeeklyPool / Milestones with a UNIQUE
--   Id, a Metric (must be one of Metrics below), a Target, and a Reward { Cash?, Unit? (species id) }.
-- * Mode: "count" (incremental events accumulate) or "reached" (progress = an absolute value, e.g. cash).
-- * How many dailies/weeklies are active: DailyActiveCount / WeeklyActiveCount (rotated per period,
--   deterministically from the period id -> identical on every server).
-- * Reset cadence: DayLength / WeekLength (seconds; SHORTEN to test, RESET for production). Boundaries
--   derive purely from os.time() so every server agrees.
-- * Unclaimed-at-reset rule: a COMPLETED-but-unclaimed daily/weekly EXPIRES at the boundary (claim
--   within the window). Documented + enforced by the deterministic period reset.
-- ===========================================================================================

local QuestConfig = {}

-- Tracked metrics -> the gameplay signal that feeds them (a metric whose source isn't wired stays
-- DORMANT with no error -- forward-compat). "reached" metrics carry an absolute value, not a count.
QuestConfig.Metrics = {
    catch_count = "count", -- a wild/shared brainrot caught (M10)
    catch_new = "count", -- a NEW species discovered on catch (M10)
    earn_cash = "count", -- passive/earned cash accrued (M3 income)
    cash_reached = "reached", -- total cash reached an absolute threshold
    steals_succeeded = "count", -- a successful steal (M4)
    steal_survived = "count", -- survived a steal as defender (M4; forward-compat)
    evolutions = "count", -- a unit evolved (M11.2)
    boss_kills = "count", -- a world-boss kill credited (M11.3)
    fusions = "count", -- a successful fusion (M9.2)
    biome_unlocked = "count", -- a biome gate unlocked (M10.2)
    rebirths = "count", -- a rebirth (M7)
    sell_count = "count", -- units sold (M9.1)
    open_mystery = "count", -- opened the base Mystery Block (M12.2; forward-compat)
}

-- ── Period cadence (server time) ────────────────────────────────────────────────────────────
QuestConfig.DayLength = 86400 -- s per daily period (SHORTEN to test, e.g. 120)
QuestConfig.WeekLength = 604800 -- s per weekly period
QuestConfig.DayEpoch = 0 -- 86400 divides the unix epoch -> days align to UTC midnight
QuestConfig.WeekEpoch = 345600 -- unix epoch was a Thursday; +4d aligns weeks to Monday 00:00 UTC
QuestConfig.DailyActiveCount = 3 -- how many daily quests are active per day
QuestConfig.WeeklyActiveCount = 3 -- how many weekly quests are active per week

-- ── TUTORIAL (ordered, one-shot, persisted). Drives the objective banner; auto-claims per step. ──
-- ForwardCompat steps don't BLOCK tutorial completion (they activate when their system lands, e.g. the
-- Mystery Block in M12.2); the required core-loop steps gate completion.
QuestConfig.Tutorial = {
    {
        Id = "tut_catch",
        Metric = "catch_count",
        Target = 1,
        Reward = { Cash = 500 },
        Title = "First Catch",
        Desc = "CATCH your <hl>first brainrot</hl> in the wild!",
    },
    {
        Id = "tut_earn",
        Metric = "earn_cash",
        Target = 200,
        Reward = { Cash = 500 },
        Title = "Cash Flow",
        Desc = "Let your brainrot <hl>earn $200</hl>.",
    },
    {
        Id = "tut_cash",
        Metric = "cash_reached",
        Target = 2500,
        Mode = "reached",
        Reward = { Cash = 1000 },
        Title = "Getting Rich",
        Desc = "Reach <hl>$2,500</hl> cash.",
    },
    {
        Id = "tut_biome",
        Metric = "biome_unlocked",
        Target = 1,
        Reward = { Cash = 2500 },
        Title = "Explorer",
        Desc = "Unlock your <hl>first biome gate</hl>.",
    },
    {
        Id = "tut_mystery",
        Metric = "open_mystery",
        Target = 1,
        Reward = { Cash = 1000 },
        ForwardCompat = true,
        Title = "Free Loot",
        Desc = "Open the <hl>Mystery Block</hl> at your base.",
    },
}

-- ── DAILY POOL (DailyActiveCount rotate in per day) ─────────────────────────────────────────
QuestConfig.DailyPool = {
    {
        Id = "d_catch",
        Metric = "catch_count",
        Target = 10,
        Reward = { Cash = 2000 },
        Title = "Hunter",
        Desc = "Catch <hl>10 brainrots</hl>.",
    },
    {
        Id = "d_earn",
        Metric = "earn_cash",
        Target = 50000,
        Reward = { Cash = 3000 },
        Title = "Earner",
        Desc = "Earn <hl>$50,000</hl>.",
    },
    {
        Id = "d_steal",
        Metric = "steals_succeeded",
        Target = 3,
        Reward = { Cash = 2500 },
        Title = "Thief",
        Desc = "Pull off <hl>3 steals</hl>.",
    },
    {
        Id = "d_evolve",
        Metric = "evolutions",
        Target = 1,
        Reward = { Cash = 3000 },
        Title = "Evolver",
        Desc = "Evolve <hl>1 brainrot</hl>.",
    },
    {
        Id = "d_fuse",
        Metric = "fusions",
        Target = 2,
        Reward = { Cash = 2500 },
        Title = "Fuser",
        Desc = "Fuse <hl>2 times</hl>.",
    },
    {
        Id = "d_sell",
        Metric = "sell_count",
        Target = 5,
        Reward = { Cash = 1500 },
        Title = "Trader",
        Desc = "Sell <hl>5 units</hl>.",
    },
}

-- ── WEEKLY POOL (WeeklyActiveCount rotate in per week) ──────────────────────────────────────
QuestConfig.WeeklyPool = {
    {
        Id = "w_catch",
        Metric = "catch_count",
        Target = 100,
        Reward = { Cash = 25000 },
        Title = "Master Hunter",
        Desc = "Catch <hl>100 brainrots</hl>.",
    },
    {
        Id = "w_boss",
        Metric = "boss_kills",
        Target = 3,
        Reward = { Cash = 30000 },
        Title = "Titan Slayer",
        Desc = "Defeat <hl>3 world bosses</hl>.",
    },
    {
        Id = "w_evolve",
        Metric = "evolutions",
        Target = 5,
        Reward = { Cash = 25000 },
        Title = "Evolution",
        Desc = "Evolve <hl>5 brainrots</hl>.",
    },
    {
        Id = "w_new",
        Metric = "catch_new",
        Target = 10,
        Reward = { Cash = 30000 },
        Title = "Collector",
        Desc = "Discover <hl>10 new species</hl>.",
    },
    {
        Id = "w_steal",
        Metric = "steals_succeeded",
        Target = 25,
        Reward = { Cash = 25000 },
        Title = "Bandit",
        Desc = "Steal <hl>25 brainrots</hl>.",
    },
}

-- ── MILESTONES (long-term, one-shot, persist until done) ────────────────────────────────────
QuestConfig.Milestones = {
    {
        Id = "m_catch500",
        Metric = "catch_count",
        Target = 500,
        Reward = { Cash = 100000 },
        Title = "Legend Hunter",
        Desc = "Catch <hl>500 brainrots</hl>.",
    },
    {
        Id = "m_species25",
        Metric = "catch_new",
        Target = 25,
        Reward = { Cash = 75000 },
        Title = "Curator",
        Desc = "Discover <hl>25 species</hl>.",
    },
    {
        Id = "m_cash1m",
        Metric = "cash_reached",
        Target = 1000000,
        Mode = "reached",
        Reward = { Cash = 50000 },
        Title = "Millionaire",
        Desc = "Reach <hl>$1,000,000</hl>.",
    },
    {
        Id = "m_boss10",
        Metric = "boss_kills",
        Target = 10,
        Reward = { Cash = 150000 },
        Title = "Boss Hunter",
        Desc = "Defeat <hl>10 bosses</hl>.",
    },
    {
        Id = "m_evolve25",
        Metric = "evolutions",
        Target = 25,
        Reward = { Cash = 100000 },
        Title = "Grand Evolver",
        Desc = "Evolve <hl>25 brainrots</hl>.",
    },
    {
        Id = "m_rebirth",
        Metric = "rebirths",
        Target = 1,
        Reward = { Cash = 50000 },
        Title = "Reborn",
        Desc = "<hl>Rebirth</hl> for the first time.",
    },
    {
        Id = "m_biomes5",
        Metric = "biome_unlocked",
        Target = 5,
        Reward = { Cash = 200000 },
        Title = "World Walker",
        Desc = "Unlock <hl>5 biomes</hl>.",
    },
}

-- ── Period id helpers (pure functions of server time -> cross-server consistent) ─────────────
function QuestConfig.CurrentDay(t)
    return math.floor((t - QuestConfig.DayEpoch) / QuestConfig.DayLength)
end

function QuestConfig.CurrentWeek(t)
    return math.floor((t - QuestConfig.WeekEpoch) / QuestConfig.WeekLength)
end

-- Wall-clock end of the period a given id covers (for the UI countdown).
function QuestConfig.DayEndsAt(dayId)
    return QuestConfig.DayEpoch + (dayId + 1) * QuestConfig.DayLength
end

function QuestConfig.WeekEndsAt(weekId)
    return QuestConfig.WeekEpoch + (weekId + 1) * QuestConfig.WeekLength
end

-- Deterministic rotation: pick `count` consecutive (wrapping) entries from `pool`, offset by periodId.
local function rotate(pool, count, periodId)
    local n = #pool
    if n == 0 then
        return {}
    end
    count = math.min(count, n)
    local start = (periodId % n + n) % n -- non-negative modulo
    local out = {}
    for i = 0, count - 1 do
        table.insert(out, pool[(start + i) % n + 1])
    end
    return out
end

function QuestConfig.ActiveDaily(dayId)
    return rotate(QuestConfig.DailyPool, QuestConfig.DailyActiveCount, dayId)
end

function QuestConfig.ActiveWeekly(weekId)
    return rotate(QuestConfig.WeeklyPool, QuestConfig.WeeklyActiveCount, weekId)
end

-- Defensive lookups by id.
local function index(list)
    local byId = {}
    for _, q in ipairs(list) do
        byId[q.Id] = q
    end
    return byId
end
QuestConfig.TutorialById = index(QuestConfig.Tutorial)
QuestConfig.DailyById = index(QuestConfig.DailyPool)
QuestConfig.WeeklyById = index(QuestConfig.WeeklyPool)
QuestConfig.MilestoneById = index(QuestConfig.Milestones)

-- tutorial quest id -> its 1-based ordinal (so a manual claim can advance the step pointer).
QuestConfig.TutorialIndex = {}
for i, q in ipairs(QuestConfig.Tutorial) do
    QuestConfig.TutorialIndex[q.Id] = i
end

return QuestConfig
