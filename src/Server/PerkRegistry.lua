-- PerkRegistry (M11.1): the EXTENSIBLE core. ONE generic applier reads a perk's declared effect
-- PRIMITIVES (PerksConfig.Perks[key].Effects) and routes each to its system -- income/luck to the
-- Benefits registry (capped, keyed per slot), everything else to the decoupled PerkEffects aggregate.
-- Adding a perk = a config row in PerksConfig; NO code here changes. Magnitudes are computed
-- SERVER-SIDE from the holder's rarity (baked into the perk base) x star x mutation (PerksConfig.Scale).
--
-- Idempotency: LoadoutService calls ClearSlot for EVERY slot + PerkEffects.Reset before re-applying
-- the live loadout, so apply is always part of a full recompute-from-scratch -- never double-applies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerksConfig = require(ReplicatedStorage.Shared.PerksConfig)

local PerkEffects = require(script.Parent.PerkEffects)
local Benefits = require(script.Parent.Benefits)

local PerkRegistry = {}

local function incomeKey(slot)
    return "perk:" .. slot
end
local function luckKey(slot)
    return "perkluck:" .. slot
end

-- Resets a slot's income + luck Benefits sources to neutral. Called for EVERY slot before re-apply,
-- so an emptied/swapped slot leaves no residual income or luck.
function PerkRegistry.ClearSlot(player, slot)
    Benefits.SetIncomeSource(player, incomeKey(slot), 0)
    Benefits.SetLuckSource(player, luckKey(slot), 1)
end

-- Applies the signature perk of `unit` (equipped in `slot`). Routes each effect primitive.
function PerkRegistry.Apply(player, unit, slot)
    local perk = PerksConfig.Get(PerksConfig.PerkForType(unit.Type))
    if perk == nil then
        return
    end
    local e = perk.Effects
    local s = PerksConfig.Scale(unit)

    -- EARN / ECON multiplier + luck -> capped Benefits sources (combine under the global cap).
    if e.Income ~= nil then
        Benefits.SetIncomeSource(player, incomeKey(slot), e.Income * s)
    end
    if e.Luck ~= nil then
        Benefits.SetLuckSource(player, luckKey(slot), 1 + e.Luck * s)
    end

    -- RAID (attacker steal params).
    if e.CooldownReduce ~= nil then
        PerkEffects.MulCooldown(
            player,
            math.clamp(1 - e.CooldownReduce * s, PerksConfig.CooldownFloor, 1)
        )
    end
    if e.Reach ~= nil then
        PerkEffects.AddReach(player, e.Reach * s)
    end
    if e.CarryCount ~= nil then
        PerkEffects.MaxCarry(player, e.CarryCount) -- discrete; not star/mutation scaled
    end
    if e.CarryEase ~= nil then
        PerkEffects.MaxCarryEase(player, math.clamp(e.CarryEase, 0, 1))
    end
    if e.Invisible then
        PerkEffects.SetInvisible(player)
    end

    -- DEF (defender steal params).
    if e.DefHold ~= nil then
        PerkEffects.MulDefHold(player, 1 + (e.DefHold - 1) * s)
    end
    if e.Interrupt ~= nil then
        PerkEffects.AddInterrupt(player, math.clamp(e.Interrupt * s, 0, PerksConfig.InterruptCap))
    end
    if e.Stun then
        PerkEffects.SetStun(player)
    end
    if e.Alert then
        PerkEffects.SetAlert(player)
    end
    if e.Knockback ~= nil then
        PerkEffects.MaxKnockback(player, e.Knockback * s)
    end

    -- EARN-special (custom income logic lives in IncomeService / LoadoutService).
    if e.OfflineFrac ~= nil then
        PerkEffects.AddOffline(player, e.OfflineFrac * s)
    end
    if e.Hourglass ~= nil then
        PerkEffects.SetHourglass(player, e.Hourglass.Cap * s, e.Hourglass.RampSeconds)
    end
    if e.Battalion ~= nil then
        PerkEffects.SetBattalion(player, e.Battalion.PerUnit * s, e.Battalion.Cap * s)
    end
    if e.Meltdown ~= nil then
        PerkEffects.SetMeltdown(player, e.Meltdown.Period, e.Meltdown.Mult * s)
    end

    -- ECON (fusion -- M9.2).
    if e.FusionCrit ~= nil then
        PerkEffects.AddFusionCrit(player, e.FusionCrit * s)
    end
    if e.FusionFailMult ~= nil then
        PerkEffects.MulFusionFail(player, e.FusionFailMult)
    end

    -- MOVE (walkspeed; StealService is the authority -- LoadoutService pushes the aggregate to it).
    if e.MoveMult ~= nil then
        PerkEffects.MulMove(player, 1 + e.MoveMult * s)
    end

    -- HUNT (M10 wild-catch) -- FORWARD-COMPAT: store scaled params; DORMANT no-op until M10 reads them.
    if e.Hunt ~= nil then
        local scaled = {}
        for k, v in pairs(e.Hunt) do
            scaled[k] = (type(v) == "boolean") and v or v * s
        end
        PerkEffects.AddHunt(player, scaled)
    end
end

return PerkRegistry
