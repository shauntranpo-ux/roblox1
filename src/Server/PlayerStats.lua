-- PlayerStats: publishes the two live numbers the custom HUD needs as player
-- Attributes ("Cash" and "IncomePerSec"), which replicate automatically. The client
-- reads them and listens via GetAttributeChangedSignal. Precise fractional Cash stays
-- in the profile; the replicated Cash attribute is the floored display value.
--
-- This is separate from the M1 leaderstats IntValue, which is intentionally kept for
-- the Roblox player list.

local TransitRegistry = require(script.Parent.TransitRegistry)
local Benefits = require(script.Parent.Benefits)

local PlayerStats = {}

local MAX_INT_VALUE = 2147483647

-- A brainrot being carried (in-transit) earns for no one, so it is excluded from the
-- displayed IncomePerSec exactly as IncomeService excludes it from cash accrual. The result
-- includes the player's income multiplier so the HUD shows the SAME rate cash actually accrues
-- at (floored for display).
local function totalIncome(player, profile)
    local sum = 0
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        if not TransitRegistry.Has(brainrot.Id) then
            sum += brainrot.IncomePerSec
        end
    end
    return math.floor(sum * Benefits.GetIncomeMultiplier(player))
end

local function flooredCash(profile)
    return math.clamp(math.floor(profile.Data.Cash), 0, MAX_INT_VALUE)
end

-- Initializes both attributes for a player whose profile just loaded.
function PlayerStats.Setup(player, profile)
    player:SetAttribute("Cash", flooredCash(profile))
    player:SetAttribute("IncomePerSec", totalIncome(player, profile))
end

-- Pushes the current (floored) cash to the client. Called by the income loop (throttled).
function PlayerStats.PushCash(player, profile)
    player:SetAttribute("Cash", flooredCash(profile))
end

-- Recomputes total income after the roster OR the income multiplier changes (e.g. a purchase
-- or a 2x Cash gamepass being applied).
function PlayerStats.UpdateIncome(player, profile)
    player:SetAttribute("IncomePerSec", totalIncome(player, profile))
end

return PlayerStats
