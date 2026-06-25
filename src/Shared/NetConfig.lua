-- NetConfig (M10.4): THE single source of truth for the NET -- the equippable, upgradeable catching
-- tool that's the SECOND cash sink (alongside M10.2 gate unlocks) + a clean NON-RANDOM "Pro Net"
-- gamepass. The net adjusts catch PARAMETERS ONLY (hold time, range, flee-resist, a tiny auto-catch);
-- it NEVER touches catch atomicity / dupe-safety / the no-catch-rng rule. Every tier + the gamepass
-- is a DETERMINISTIC, named, disclosed effect -- NOTHING random is sold for Robux. Put EVERY number
-- here. Validate defensively.
--
-- HOW NET + HUNT PERKS COMBINE (server-side, under the caps below; no double-apply, no blowup):
--   holdReduce = net.HoldReduce + gamepass.HoldReduce + HUNT CatchSpeed   -> clamp(0, MaxHoldReduce)
--                effective hold = baseHold * (1 - holdReduce)
--   rangeAdd   = net.RangeAdd   + gamepass.RangeAdd   + HUNT CatchRange    -> clamp(0, MaxRangeAdd)
--   autoCatch  = net.AutoCatch  + HUNT AutoCatch (Poacher)                 -> clamp(0, MaxAutoCatch)
--   fleeResist = net.FleeResist                                           -> clamp(0, MaxFleeResist)
-- All SUMMED then clamped -- bounded, never multiplicative runaway.

local NetConfig = {}

NetConfig.BaseTier = 1 -- everyone starts with the base net (the default equipped tool)

-- Ordered tiers. Cost = EARNED cash to upgrade FROM the previous tier INTO this one (tier 1 = free).
NetConfig.Tiers = {
    {
        TierId = 1,
        Name = "Starter Net",
        HoldReduce = 0.0,
        RangeAdd = 0,
        FleeResist = 0.0,
        AutoCatch = 0.0,
        Cost = 0,
    },
    {
        TierId = 2,
        Name = "Sturdy Net",
        HoldReduce = 0.1,
        RangeAdd = 3,
        FleeResist = 0.1,
        AutoCatch = 0.0,
        Cost = 25000,
    },
    {
        TierId = 3,
        Name = "Ranger Net",
        HoldReduce = 0.2,
        RangeAdd = 6,
        FleeResist = 0.2,
        AutoCatch = 0.0,
        Cost = 500000,
    },
    {
        TierId = 4,
        Name = "Hunter Net",
        HoldReduce = 0.3,
        RangeAdd = 10,
        FleeResist = 0.35,
        AutoCatch = 0.02,
        Cost = 10000000,
    },
    {
        TierId = 5,
        Name = "Master Net",
        HoldReduce = 0.4,
        RangeAdd = 16,
        FleeResist = 0.5,
        AutoCatch = 0.05,
        Cost = 250000000,
    },
}
NetConfig.MaxTier = #NetConfig.Tiers

-- The "Pro Net" GAMEPASS bonus: a FIXED, DISCLOSED, NON-RANDOM bump that folds into the same
-- computation (so it stacks with the owned tier + perks under the caps). Wired via Monetization.
NetConfig.Gamepass = { Key = "ProNet", HoldReduce = 0.1, RangeAdd = 4 }

-- ── CAPS (net + HUNT + gamepass combined; bounded) ──────────────────────────────────────────
NetConfig.MaxHoldReduce = 0.85 -- effective hold never below 15% of the base hold
NetConfig.MaxRangeAdd = 30 -- studs
NetConfig.MaxAutoCatch = 0.1 -- combined passive auto-catch chance ceiling (per second, commons only)
NetConfig.MaxFleeResist = 0.85 -- flee distance can be cut at most this much

function NetConfig.Get(tierId)
    if type(tierId) ~= "number" then
        return NetConfig.Tiers[NetConfig.BaseTier]
    end
    tierId = math.clamp(math.floor(tierId), 1, NetConfig.MaxTier)
    return NetConfig.Tiers[tierId]
end

-- The cost to upgrade FROM `tierId` to `tierId+1` (nil if already max).
function NetConfig.UpgradeCost(tierId)
    local next_ = NetConfig.Tiers[(tierId or 0) + 1]
    return next_ ~= nil and next_.Cost or nil
end

return NetConfig
