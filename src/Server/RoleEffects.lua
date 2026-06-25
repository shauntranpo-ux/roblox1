-- RoleEffects: per-player STEAL-role effect state (Guardian interrupt chance, Raider strength +
-- deposit-reach bonus). Decoupled -- it requires nothing -- so StealService can READ it without a
-- require cycle back into DeployService (the same pattern as Benefits/TransitRegistry).
--   * DeployService WRITES it (on assign / unassign / join re-derive).
--   * StealService READS it (Guardian slap roll on a steal attempt; Raider carry + deposit reach).
-- Income + luck role buffs do NOT live here -- they ride the existing Benefits registry under the cap.

local RoleEffects = {}

local state = {} -- [Player] = { GuardianInterrupt, RaiderStrength, RaiderDepositBonus }

local function ensure(player)
    local s = state[player]
    if s == nil then
        s = { GuardianInterrupt = 0, RaiderStrength = 0, RaiderDepositBonus = 0 }
        state[player] = s
    end
    return s
end

function RoleEffects.SetGuardian(player, interruptChance)
    ensure(player).GuardianInterrupt = interruptChance
end

function RoleEffects.SetRaider(player, strength, depositBonus)
    local s = ensure(player)
    s.RaiderStrength = strength
    s.RaiderDepositBonus = depositBonus
end

function RoleEffects.GuardianInterrupt(player)
    local s = state[player]
    return s ~= nil and s.GuardianInterrupt or 0
end

function RoleEffects.RaiderStrength(player)
    local s = state[player]
    return s ~= nil and s.RaiderStrength or 0
end

function RoleEffects.RaiderDepositBonus(player)
    local s = state[player]
    return s ~= nil and s.RaiderDepositBonus or 0
end

function RoleEffects.ClearPlayer(player)
    state[player] = nil
end

return RoleEffects
