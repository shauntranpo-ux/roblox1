-- BrainrotFactory: THE one server-side place an owned-unit record is created. A mutation is rolled
-- HERE at acquisition (and NOWHERE else) respecting the per-player luck hook; STEAL and TRADE never
-- roll -- they MOVE the existing record so the Mutation field travels unchanged. The client can
-- never influence the outcome (the roll is server-side).
--
-- Per-source roll policy (documented; flip in RollFor): cash PURCHASE rolls; the STARTER + code /
-- dev-product / index brainrot grants do NOT (clean grants), so the random roll is never sold for
-- Robux (policy-clean -- PolicyService exists for paid-random compliance but isn't needed here).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MutationConfig = require(ReplicatedStorage.Shared.MutationConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local Analytics = require(script.Parent.Analytics)

local BrainrotFactory = {}

-- Which grant sources roll a mutation. Retune freely; STEAL/TRADE are not here (they never roll).
BrainrotFactory.RollFor = {
    Purchase = true, -- cash shop purchase -> the core mutation source
    Starter = false, -- starter + post-rebirth re-grant -> clean
    Code = false, -- code brainrot reward
    Product = false, -- Robux dev-product brainrot grant (never sell randomness)
    Index = false, -- completion-reward brainrot
    Catch = true, -- M10.1 wild-catch -> rolls a mutation (respects the luck hook), like a purchase
}

-- Marks a mutation Key as discovered on a profile (called when a player comes to own a mutated
-- unit -- via the factory OR by receiving one through steal/trade).
function BrainrotFactory.MarkDiscovered(profile, mutationKey)
    if profile ~= nil and mutationKey ~= nil then
        profile.Data.MutationsDiscovered[mutationKey] = true
    end
end

-- Creates a fresh owned-unit record. `def` is a Catalog roster entry; stored IncomePerSec is the
-- species BASE (the mutation multiplier is applied only by Shared/UnitIncome). `rollMutation` rolls
-- a server-side weighted mutation respecting the player's luck. Returns the record.
function BrainrotFactory.create(player, def, padIndex, rollMutation, allowExclusive)
    -- M11.4 EXCLUSIVITY GATE (central default-deny): refuse to create a seasonal-exclusive species
    -- unless this is an AUTHORIZED grant (an in-window / earned source that validated eligibility and
    -- passes allowExclusive=true). EVERY other creation path (purchase / fusion / index / set / boss /
    -- normal grants) omits allowExclusive, so an EXPIRED (or any unauthorized) exclusive can NEVER be
    -- minted by any path. Trading an already-owned copy is a MOVE (no factory call) and is unaffected.
    if def.ExclusiveSeason ~= nil and allowExclusive ~= true then
        return nil
    end
    local mutation = nil
    if rollMutation then
        mutation = MutationConfig.Roll(Benefits.GetLuckMultiplier(player))
        if mutation ~= nil then
            Analytics.custom(
                player,
                Analytics.Events.MutationRoll,
                MutationConfig.MultiplierFor(mutation)
            )
            local profile = ProfileManager.GetProfile(player)
            BrainrotFactory.MarkDiscovered(profile, mutation)
        end
    end
    return {
        Id = HttpService:GenerateGUID(false),
        Type = def.Id,
        IncomePerSec = def.IncomePerSec, -- species BASE, never mutated/starred/evolved in storage
        PadIndex = padIndex,
        Mutation = mutation, -- nil = Normal
        Star = 1, -- M9.2: every unit starts at ★1; FusionService raises it. Income star factor
        -- is applied ONLY by Shared/UnitIncome (never baked into IncomePerSec).
        EvolutionStage = 1, -- M11.2: every unit starts at stage 1; EvolutionService raises it. The
        XP = 0, -- evolution income factor is applied ONLY by Shared/UnitIncome (never baked in).
        -- XP is banked server-side (income loop + surviving steals); the client never sets it.
    }
end

return BrainrotFactory
