-- PerkEffects (M11.1): per-player AGGREGATE of all equipped perks' non-income/luck effects (steal
-- attacker + defender params, special-income params, fusion params, movement, dormant hunt params).
-- Decoupled -- it requires nothing -- so StealService / FusionService / IncomeService can READ it
-- without a require cycle back into LoadoutService (the same pattern the old RoleEffects used, which
-- this REPLACES). Income + luck perks do NOT live here; they ride the existing Benefits registry under
-- the global cap.
--
-- LoadoutService is the SOLE writer: on every loadout change it calls Reset(player) then, for each
-- equipped slot, the perk's primitives call the COMBINE setters below. Recompute-from-scratch makes
-- the whole thing idempotent (equip/join/rejoin/swap can never double-apply or leave residue).

local PerkEffects = {}

local function defaults()
    return {
        -- attacker (steal offense)
        CooldownMult = 1, -- product of (1-reduce); your steal cooldown is multiplied by this
        Reach = 0, -- + deposit reach (studs)
        CarryCount = 1, -- max simultaneous carries
        CarryEase = 0, -- 0..1 ease of the carry slowdown
        Invisible = false, -- stealth while raiding
        -- defender (steal defense)
        DefHoldMult = 1, -- product; multiplies thieves' hold time vs your base
        Interrupt = 0, -- probabilistic-OR chance a steal attempt on you is blocked
        Stun = false, -- knock back + stun + block a thief attempting your base
        Alert = false, -- always alerted, even vs stealth
        Knockback = 0, -- knockback impulse (studs/s-ish) for Stun
        -- special income
        OfflineFrac = 0, -- earn this fraction of income while offline
        Hourglass = nil, -- { Cap, RampSeconds }
        Battalion = nil, -- { PerUnit, Cap }
        Meltdown = nil, -- { Period, Mult }
        -- fusion (M9.2)
        FusionCritBonus = 0, -- + to fusion crit chance
        FusionFailMult = 1, -- multiplies fusion fail chance (lower = better)
        -- movement
        MoveMult = 1, -- product; walkspeed multiplier
        -- hunt (M10 wild-catch) -- DORMANT: stored, no consumer yet
        Hunt = nil,
    }
end

local state = {} -- [Player] = aggregate table

local function ensure(player)
    local s = state[player]
    if s == nil then
        s = defaults()
        state[player] = s
    end
    return s
end

-- Reset to neutral before LoadoutService re-applies the live loadout (idempotency cornerstone).
function PerkEffects.Reset(player)
    state[player] = defaults()
end

-- ── Combine setters (called by the perk primitives during recompute) ─────────────────────────
function PerkEffects.MulCooldown(player, mult)
    local s = ensure(player)
    s.CooldownMult *= mult
end
function PerkEffects.AddReach(player, studs)
    ensure(player).Reach += studs
end
function PerkEffects.MaxCarry(player, n)
    local s = ensure(player)
    s.CarryCount = math.max(s.CarryCount, n)
end
function PerkEffects.MaxCarryEase(player, ease)
    local s = ensure(player)
    s.CarryEase = math.max(s.CarryEase, ease)
end
function PerkEffects.SetInvisible(player)
    ensure(player).Invisible = true
end
function PerkEffects.MulDefHold(player, mult)
    local s = ensure(player)
    s.DefHoldMult *= mult
end
function PerkEffects.AddInterrupt(player, chance)
    local s = ensure(player)
    s.Interrupt = 1 - (1 - s.Interrupt) * (1 - chance) -- probabilistic OR
end
function PerkEffects.SetStun(player)
    ensure(player).Stun = true
end
function PerkEffects.SetAlert(player)
    ensure(player).Alert = true
end
function PerkEffects.MaxKnockback(player, studs)
    local s = ensure(player)
    s.Knockback = math.max(s.Knockback, studs)
end
function PerkEffects.AddOffline(player, frac)
    ensure(player).OfflineFrac += frac
end
function PerkEffects.SetHourglass(player, cap, rampSeconds)
    local s = ensure(player)
    if s.Hourglass == nil or cap > s.Hourglass.Cap then
        s.Hourglass = { Cap = cap, RampSeconds = rampSeconds }
    end
end
function PerkEffects.SetBattalion(player, perUnit, cap)
    local s = ensure(player)
    if s.Battalion == nil or cap > s.Battalion.Cap then
        s.Battalion = { PerUnit = perUnit, Cap = cap }
    end
end
function PerkEffects.SetMeltdown(player, period, mult)
    local s = ensure(player)
    if s.Meltdown == nil or mult > s.Meltdown.Mult then
        s.Meltdown = { Period = period, Mult = mult }
    end
end
function PerkEffects.AddFusionCrit(player, frac)
    ensure(player).FusionCritBonus += frac
end
function PerkEffects.MulFusionFail(player, mult)
    local s = ensure(player)
    s.FusionFailMult *= mult
end
function PerkEffects.MulMove(player, mult)
    local s = ensure(player)
    s.MoveMult *= mult
end
function PerkEffects.AddHunt(player, params) -- DORMANT (M10): just remember the strongest values
    local s = ensure(player)
    s.Hunt = s.Hunt or {}
    for key, value in pairs(params) do
        if type(value) == "boolean" then
            s.Hunt[key] = s.Hunt[key] or value
        else
            s.Hunt[key] = math.max(s.Hunt[key] or 0, value)
        end
    end
end

-- ── Getters (read by the consuming systems) ──────────────────────────────────────────────────
local function get(player)
    return state[player] or defaults()
end

function PerkEffects.AttackerCooldownMult(player)
    return get(player).CooldownMult
end
function PerkEffects.AttackerReach(player)
    return get(player).Reach
end
function PerkEffects.CarryCount(player)
    return get(player).CarryCount
end
function PerkEffects.CarryEase(player)
    return get(player).CarryEase
end
function PerkEffects.IsInvisible(player)
    return get(player).Invisible
end
function PerkEffects.DefenderHoldMult(player)
    return get(player).DefHoldMult
end
function PerkEffects.DefenderInterrupt(player)
    return get(player).Interrupt
end
function PerkEffects.DefenderStun(player)
    return get(player).Stun
end
function PerkEffects.DefenderAlert(player)
    return get(player).Alert
end
function PerkEffects.DefenderKnockback(player)
    return get(player).Knockback
end
function PerkEffects.OfflineFrac(player)
    return get(player).OfflineFrac
end
function PerkEffects.GetHourglass(player)
    return get(player).Hourglass
end
function PerkEffects.GetBattalion(player)
    return get(player).Battalion
end
function PerkEffects.GetMeltdown(player)
    return get(player).Meltdown
end
function PerkEffects.FusionCritBonus(player)
    return get(player).FusionCritBonus
end
function PerkEffects.FusionFailMult(player)
    return get(player).FusionFailMult
end
function PerkEffects.MoveMult(player)
    return get(player).MoveMult
end
function PerkEffects.GetHunt(player) -- DORMANT (M10 reads this when it lands)
    return get(player).Hunt
end

function PerkEffects.ClearPlayer(player)
    state[player] = nil
end

return PerkEffects
