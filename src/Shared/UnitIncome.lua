-- UnitIncome: THE single canonical helper for a unit's EFFECTIVE per-unit income. Every place
-- that reads a unit's income MUST go through here so the mutation multiplier is applied EXACTLY
-- ONCE and never double-counted: the income loop, the floating "+$/s" billboards, the inventory /
-- trade / leaderboard value readouts.
--
--   effective(unit) = unit.IncomePerSec (species BASE, stored unmutated) * mutation multiplier
--
-- The per-unit mutation factor is UNCAPPED (a per-unit property). The per-player global multiplier
-- (prestige/gamepass/boost/completion/event) is applied + capped SEPARATELY by IncomeService:
--   playerTotalIncome = ( sum over owned non-in-transit units of effective(unit) ) * cappedGlobal * prestige

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MutationConfig =
    require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MutationConfig"))

local UnitIncome = {}

-- Effective per-unit income for an owned-unit record { IncomePerSec, Mutation }.
function UnitIncome.effective(unit)
    local base = unit.IncomePerSec or 0
    return base * MutationConfig.MultiplierFor(unit.Mutation)
end

return UnitIncome
