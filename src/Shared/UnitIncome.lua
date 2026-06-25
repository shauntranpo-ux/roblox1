-- UnitIncome: THE single canonical helper for a unit's EFFECTIVE per-unit income. Every place
-- that reads a unit's income MUST go through here so the mutation AND star multipliers are applied
-- EXACTLY ONCE and never double-counted: the income loop, the floating "+$/s" billboards, the
-- inventory / index / trade / leaderboard value readouts.
--
--   effective(unit) = unit.IncomePerSec (species BASE, stored unmutated/unstarred)
--                     * mutation multiplier (per-unit, uncapped)
--                     * star multiplier     (per-unit, uncapped -- M9.2)
--
-- The per-unit mutation + star factors are UNCAPPED (per-unit properties); the stored IncomePerSec
-- is ALWAYS the species base -- star/mutation are NEVER baked into it. The per-player global
-- multiplier (prestige/gamepass/boost/completion/event) is applied + capped SEPARATELY by
-- IncomeService:
--   playerTotalIncome = ( Σ over owned non-in-transit units of effective(unit) ) * cappedGlobal * prestige

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))
local FusionConfig = require(Shared:WaitForChild("FusionConfig"))

local UnitIncome = {}

-- Effective per-unit income for an owned-unit record { IncomePerSec, Mutation, Star }. Star is read
-- DEFENSIVELY (legacy units without the field -> star 1 -> 1x), so this never errors on old saves.
function UnitIncome.effective(unit)
    local base = unit.IncomePerSec or 0
    return base
        * MutationConfig.MultiplierFor(unit.Mutation)
        * FusionConfig.StarMultiplier(unit.Star)
end

return UnitIncome
