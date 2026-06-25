-- RebirthConfig: THE single source of truth for the prestige/rebirth economy. Retune the whole
-- long-tail loop here.
--
-- WHAT REBIRTH DOES: once a player is rich enough, they reset Cash -> 0 and clear their placed
-- (non-premium) brainrots in exchange for a PERMANENT prestige income multiplier that grows with
-- each rebirth. Paid entitlements (gamepasses, premium units, bought pads) are NEVER wiped.
--
-- INCOME-MULTIPLIER INTERACTION (documented, important):
--   The existing per-player GLOBAL multiplier (gamepasses + timed boosts + completion + events) is
--   ADDITIVE and CAPPED (Monetization.Income.MaxMultiplier). Prestige is a SEPARATE MULTIPLICATIVE
--   axis applied OUTSIDE that cap, so:
--       playerTotalIncome = (sum of effective per-unit income) * cappedGlobalMultiplier * prestigeMultiplier
--   Rationale: if prestige were just another additive source it would either get crushed by the
--   cap (killing the long-tail loop) or force the cap so high it becomes meaningless for gamepasses.
--   Keeping it a separate factor preserves the gamepass/boost cap AND lets prestige compound.
--   Prestige has its own high safety cap (PrestigeCap) to stay well under 2^53.

local RebirthConfig = {}

-- ── Requirement curve ────────────────────────────────────────────────────────────────────
-- Cash required to perform rebirth N (0-indexed by current RebirthCount):
--   requirement(count) = BaseRequirement * (RequirementGrowth ^ count)
-- e.g. with 1,000,000 and 5: first rebirth needs 1M, then 5M, 25M, 125M, ...
RebirthConfig.BaseRequirement = 1000000
RebirthConfig.RequirementGrowth = 5

-- ── Prestige multiplier curve ────────────────────────────────────────────────────────────
-- prestigeMultiplier(count) = 1 + PrestigePerRebirth * count   (linear, simple + predictable)
--   e.g. 0.5 -> rebirth 1 = 1.5x, rebirth 4 = 3x, rebirth 10 = 6x income, forever.
RebirthConfig.PrestigePerRebirth = 0.5
RebirthConfig.PrestigeCap = 1000 -- hard safety cap on the prestige factor

-- ── Behavior toggles ─────────────────────────────────────────────────────────────────────
RebirthConfig.RegrantStarter = true -- re-grant the free starter after a rebirth
RebirthConfig.KeepActiveBoost = true -- a still-valid timed code boost survives a rebirth
-- Premium/limited units (Catalog Premium=true) ALWAYS survive a rebirth (paid value protected).
-- Unlocked pads ALWAYS persist (never strip a paid/earned pad upgrade).

-- Returns the cash required to rebirth from the given current rebirth count.
function RebirthConfig.RequirementFor(rebirthCount)
    local count = math.max(0, math.floor(rebirthCount or 0))
    return RebirthConfig.BaseRequirement * (RebirthConfig.RequirementGrowth ^ count)
end

-- Returns the prestige income multiplier for a given rebirth count (clamped to the safety cap).
function RebirthConfig.MultiplierFor(rebirthCount)
    local count = math.max(0, math.floor(rebirthCount or 0))
    return math.clamp(1 + RebirthConfig.PrestigePerRebirth * count, 1, RebirthConfig.PrestigeCap)
end

return RebirthConfig
