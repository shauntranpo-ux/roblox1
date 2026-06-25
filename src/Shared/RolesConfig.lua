-- RolesConfig (M9.3): THE single source of truth for DEPLOY ROLES. Deploying TAGS an owned unit to a
-- role SLOT; the unit stays on its pad and keeps earning (deploy is an EXTRA job, never an income
-- penalty). One unit per slot, one role per unit; a deployed unit is item-locked. Every role buff is
-- computed SERVER-SIDE from the assigned unit's power and CLAMPED to a sane maximum.
--
-- UNIT POWER = rarity order (1-6) x star LEVEL (1-5) x mutation multiplier (1-25). Stronger units ->
-- stronger buffs (capped). Buffs ride the EXISTING systems: Lucky/Totem register income/luck SOURCES
-- through the benefit registry (idempotent, under the global cap); Guardian/Raider feed steal
-- difficulty/speed knobs read by StealService (they NEVER touch the ownership transfer).
--
-- Retune EVERYTHING here. To add more slots later: add a slot name to Slots and (if it's a new role)
-- a Roles entry + an Effect branch; multiple slots of the same role just need per-slot benefit keys
-- (already keyed by slot) -- Guardian/Raider would then need RoleEffects to AGGREGATE across slots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))
local Catalog = require(Shared:WaitForChild("Catalog"))

local RolesConfig = {}

-- One slot per role for now (slot name == role key). Add "GUARDIAN2" etc. later (see header note).
RolesConfig.Slots = { "GUARDIAN", "RAIDER", "LUCKY", "TOTEM" }

RolesConfig.Roles = {
    GUARDIAN = { Name = "Guardian", Desc = "Defends your base: a chance to slap thieves away." },
    RAIDER = { Name = "Raider", Desc = "Boosts YOUR steals: longer deposit reach + faster carry." },
    LUCKY = { Name = "Lucky Charm", Desc = "More mutation luck + a small cash boost." },
    TOTEM = { Name = "Totem", Desc = "A global cash boost for everything you own." },
}

-- ── Tunables (scaling per unit-power + hard caps) ──────────────────────────────────────────
RolesConfig.GuardianChancePerPower = 0.006 -- interrupt chance added per power point
RolesConfig.GuardianChanceMax = 0.6 -- never block more than 60% of steals
RolesConfig.RaiderStrengthPerPower = 0.008 -- 0..1 raider strength per power
RolesConfig.RaiderMaxDepositBonus = 30 -- studs of extra deposit reach at full strength
RolesConfig.LuckPerPower = 0.004 -- luck multiplier added per power
RolesConfig.LuckMaxMult = 2 -- role luck multiplier ceiling
RolesConfig.LuckIncomePerPower = 0.0008 -- income SOURCE bonus per power (under the global cap)
RolesConfig.LuckIncomeMax = 0.15
RolesConfig.TotemIncomePerPower = 0.0015 -- income SOURCE bonus per power (under the global cap)
RolesConfig.TotemIncomeMax = 0.4

-- A unit's deploy power from its REAL stored stats (read server-side, never from the client).
function RolesConfig.UnitPower(unit)
    local def = Catalog.Get(unit.Type)
    local order = def ~= nil and Rarity.Get(def.Rarity).Order or 1
    local star = (type(unit.Star) == "number" and unit.Star >= 1) and math.floor(unit.Star) or 1
    local mut = MutationConfig.MultiplierFor(unit.Mutation)
    return order * star * mut
end

-- Computes a role's EFFECT for a unit. Returns the magnitudes + a short UI Label. The server uses
-- the magnitudes to register buffs; the UI shows the Label.
function RolesConfig.Effect(roleKey, unit)
    local power = RolesConfig.UnitPower(unit)
    if roleKey == "GUARDIAN" then
        local chance =
            math.clamp(power * RolesConfig.GuardianChancePerPower, 0, RolesConfig.GuardianChanceMax)
        return {
            InterruptChance = chance,
            Label = string.format("%d%% to slap thieves", math.floor(chance * 100 + 0.5)),
        }
    elseif roleKey == "RAIDER" then
        local strength = math.clamp(power * RolesConfig.RaiderStrengthPerPower, 0, 1)
        local deposit = strength * RolesConfig.RaiderMaxDepositBonus
        return {
            Strength = strength,
            DepositBonus = deposit,
            Label = string.format("+%d reach, faster carry", math.floor(deposit + 0.5)),
        }
    elseif roleKey == "LUCKY" then
        local luck = math.clamp(1 + power * RolesConfig.LuckPerPower, 1, RolesConfig.LuckMaxMult)
        local income =
            math.clamp(power * RolesConfig.LuckIncomePerPower, 0, RolesConfig.LuckIncomeMax)
        return {
            LuckMult = luck,
            IncomeBonus = income,
            Label = string.format("x%.2g luck, +%d%% cash", luck, math.floor(income * 100 + 0.5)),
        }
    elseif roleKey == "TOTEM" then
        local income =
            math.clamp(power * RolesConfig.TotemIncomePerPower, 0, RolesConfig.TotemIncomeMax)
        return {
            IncomeBonus = income,
            Label = string.format("+%d%% cash", math.floor(income * 100 + 0.5)),
        }
    end
    return { Label = "" }
end

return RolesConfig
