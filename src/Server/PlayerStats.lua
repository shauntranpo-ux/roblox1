-- PlayerStats: publishes the two live numbers the custom HUD needs as player Attributes
-- ("Cash" and "IncomePerSec"), which replicate automatically. The client reads them and listens
-- via GetAttributeChangedSignal. Precise fractional Cash stays in the profile; the replicated
-- Cash attribute is the floored display value.
--
-- PERF (M6): the player's base income/sec (sum of non-transit unit incomes) is CACHED and only
-- recomputed when the roster or multiplier CHANGES (purchase, steal in/out, benefit). The
-- income loop reads the cache every frame instead of re-summing the roster, so accrual is
-- O(players) per frame, not O(brainrots) -- the difference at a full server with hundreds of units.

local TransitRegistry = require(script.Parent.TransitRegistry)
local Benefits = require(script.Parent.Benefits)

local PlayerStats = {}

local MAX_INT_VALUE = 2147483647

local rateCache = {} -- [Player] = base income/sec (non-transit units), PRE-multiplier

-- A carried (in-transit) unit earns for no one, so it's excluded from the base rate exactly as
-- the income loop excludes it from accrual.
local function computeBaseRate(profile)
    local sum = 0
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        if not TransitRegistry.Has(brainrot.Id) then
            sum += brainrot.IncomePerSec
        end
    end
    return sum
end

local function flooredCash(profile)
    return math.clamp(math.floor(profile.Data.Cash), 0, MAX_INT_VALUE)
end

-- Recomputes + caches the base rate and refreshes the displayed (multiplier-applied, floored)
-- IncomePerSec. Call ONLY on a roster/multiplier change -- never per frame.
local function refreshRate(player, profile)
    local base = computeBaseRate(profile)
    rateCache[player] = base
    -- Display the SAME rate cash actually accrues at: capped global multiplier * prestige factor.
    local prestige = profile.Data.PrestigeMultiplier or 1
    player:SetAttribute(
        "IncomePerSec",
        math.floor(base * Benefits.GetIncomeMultiplier(player) * prestige)
    )
end

-- Initializes both attributes for a player whose profile just loaded.
function PlayerStats.Setup(player, profile)
    player:SetAttribute("Cash", flooredCash(profile))
    refreshRate(player, profile)
end

-- Pushes the current (floored) cash to the client. Called by the income loop (throttled).
function PlayerStats.PushCash(player, profile)
    player:SetAttribute("Cash", flooredCash(profile))
end

-- Recomputes income after the roster OR the income multiplier changes (purchase, steal in/out,
-- 2x Cash gamepass, product grant). This is the ONLY place the base-rate cache is refreshed.
function PlayerStats.UpdateIncome(player, profile)
    refreshRate(player, profile)
end

-- PERF: the cached base income/sec (pre-multiplier), read by the income loop every frame.
function PlayerStats.GetBaseRate(player)
    return rateCache[player] or 0
end

-- Drops a leaving player's cached rate (called from Bootstrap on leave).
function PlayerStats.ClearPlayer(player)
    rateCache[player] = nil
end

return PlayerStats
