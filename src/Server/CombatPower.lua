-- CombatPower (M11.3-combat): THE single server-side site computing a unit's COMBAT POWER and a
-- player's TEAM POWER, PARALLEL to (never overloading) the canonical effective-income helper. Combat
-- power reuses the SAME per-unit factor configs as income (mutation x star x evolution) on top of a
-- per-species BasePower, but is its own helper. The team power = the player's EQUIPPED loadout units'
-- combined power + per-unit combat-perk bonuses (under caps). Read SERVER-SIDE from the player's REAL
-- profile -- the client never asserts power or damage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local MutationConfig = require(ReplicatedStorage.Shared.MutationConfig)
local FusionConfig = require(ReplicatedStorage.Shared.FusionConfig)
local EvolutionConfig = require(ReplicatedStorage.Shared.EvolutionConfig)
local PerksConfig = require(ReplicatedStorage.Shared.PerksConfig)

local ProfileManager = require(script.Parent.ProfileManager)

local CombatPower = {}

-- Combat power of ONE owned-unit record: BasePower (per species; defaults to income x scalar, which
-- encodes rarity) x the SAME mutation/star/evolution factors income uses. Its own helper.
function CombatPower.UnitPower(unit)
    if type(unit) ~= "table" then
        return 0
    end
    local def = Catalog.Get(unit.Type)
    if def == nil then
        return 0
    end
    local base = (type(def.BasePower) == "number" and def.BasePower)
        or ((def.IncomePerSec or 0) * CombatConfig.IncomeToPower)
    return base
        * MutationConfig.MultiplierFor(unit.Mutation)
        * FusionConfig.StarMultiplier(unit.Star)
        * EvolutionConfig.IncomeMultiplier(EvolutionConfig.StageOf(unit))
end

local function findUnit(profile, unitId)
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        if unit.Id == unitId then
            return unit
        end
    end
    return nil
end

-- The player's TEAM POWER: the combined combat power of their EQUIPPED loadout units, each scaled by
-- its signature-perk category combat bonus (applied ONCE per unit, capped). Empty loadout -> 0 (the
-- base tap in AttackDamage still lets them participate). Read server-side from the real profile.
function CombatPower.TeamPower(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil or type(profile.Data.Loadout) ~= "table" then
        return 0
    end
    local total = 0
    for slot = 1, PerksConfig.SlotCount do
        local unitId = profile.Data.Loadout[tostring(slot)]
        if unitId ~= nil then
            local unit = findUnit(profile, unitId)
            if unit ~= nil then
                local perk = PerksConfig.Get(PerksConfig.PerkForType(unit.Type))
                local category = perk ~= nil and perk.Category or nil
                local mod = (category ~= nil and CombatConfig.PerkCombatMod[category]) or 0
                mod = math.clamp(mod, 0, CombatConfig.MaxPerkMod)
                total += CombatPower.UnitPower(unit) * (1 + mod)
            end
        end
    end
    return total
end

-- The damage one validated attack deals: team power x attack scalar + the flat base tap (so an empty /
-- weak loadout still chips in). Server-authoritative.
function CombatPower.AttackDamage(player)
    return CombatPower.TeamPower(player) * CombatConfig.AttackScalar + CombatConfig.BaseTapDamage
end

return CombatPower
