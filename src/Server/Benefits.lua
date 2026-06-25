-- Benefits: per-player, in-memory MONETIZATION BENEFIT STATE, deliberately decoupled (it
-- requires nothing from the rest of the server) so consumers can READ it without a require
-- cycle back into MonetizationService -- exactly the pattern TransitRegistry uses.
--
--   * MonetizationService WRITES this (on join ownership-check + on live purchase).
--   * IncomeService / PlayerStats READ the income multiplier.
--   * StealService READS the steal-cooldown multiplier (VIP edge).
--
-- IDEMPOTENCY: the income multiplier is built from a KEYED set of sources (one key per
-- gamepass). Re-applying the same source overwrites its entry, so applying a benefit twice
-- (rejoin, duplicate purchase event) can never double-stack. See Shared/Monetization.Income
-- for the stacking rule + cap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Monetization)

local Benefits = {}

-- [Player] = { IncomeSources = { [sourceKey] = bonus }, IncomeMultiplier = 1, StealCooldownMult = 1 }
local state = {}

local function ensure(player)
    local s = state[player]
    if s == nil then
        s = {
            IncomeSources = {},
            IncomeMultiplier = 1,
            StealCooldownMult = 1,
        }
        state[player] = s
    end
    return s
end

-- Recomputes the effective income multiplier from all keyed sources, applying the additive
-- stacking rule and the clamp from config.
local function recomputeIncome(s)
    local total = 0
    for _, bonus in pairs(s.IncomeSources) do
        total += bonus
    end
    s.IncomeMultiplier = math.clamp(1 + total, 1, Monetization.Income.MaxMultiplier)
end

-- Sets (or overwrites) one keyed income source's bonus and recomputes. `bonus` is the amount
-- ABOVE 1.0 the source adds (a "2x" pass passes 1.0). Idempotent per key.
function Benefits.SetIncomeSource(player, sourceKey, bonus)
    local s = ensure(player)
    s.IncomeSources[sourceKey] = bonus
    recomputeIncome(s)
end

-- The effective income multiplier (>= 1). Read every frame by IncomeService and on display
-- refresh by PlayerStats. Returns 1 when the player has no benefit state.
function Benefits.GetIncomeMultiplier(player)
    local s = state[player]
    return s ~= nil and s.IncomeMultiplier or 1
end

-- VIP edge: a multiplier (<= 1 shortens) applied to StealConfig.StealCooldown for this player.
function Benefits.SetStealCooldownMult(player, mult)
    ensure(player).StealCooldownMult = mult
end

function Benefits.GetStealCooldownMult(player)
    local s = state[player]
    return s ~= nil and s.StealCooldownMult or 1
end

-- M8.3 MUTATION-LUCK HOOK: a per-player luck multiplier (default 1.0) the mutation roll respects.
-- Keyed sources (product, like income) so a future "Lucky" pass / code boost can feed it without
-- touching the roll. Nothing feeds it this milestone -- rolls run at base odds.
function Benefits.SetLuckSource(player, sourceKey, mult)
    local s = ensure(player)
    s.LuckSources = s.LuckSources or {}
    s.LuckSources[sourceKey] = mult
end

function Benefits.GetLuckMultiplier(player)
    local s = state[player]
    if s == nil or s.LuckSources == nil then
        return 1
    end
    local product = 1
    for _, mult in pairs(s.LuckSources) do
        product *= mult
    end
    return product
end

-- Drops all benefit state for a leaving player.
function Benefits.ClearPlayer(player)
    state[player] = nil
end

return Benefits
