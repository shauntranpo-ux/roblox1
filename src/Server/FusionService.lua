-- FusionService (M9.2): turns duplicates into FUEL. The client sends a set of fodder unit Ids
-- (INTENT ONLY); the server reads the units' real Type/Star/Mutation, validates the recipe, rolls
-- the outcome server-side, and performs the fusion as ONE atomic, dupe-proof mutation.
--
-- ============================  SELF-AUDIT (fusion path)  ====================================
-- (a) ATOMIC, NO DUPE / NO LOSS: validation + outcome roll happen with NO yields; the COMMIT
--     (rebuild OwnedBrainrots WITHOUT the fodder ids + insert the ONE result) is a single yield-free
--     block. The fodder vanishes exactly once and the result is created exactly once. A concurrent
--     sell/steal/trade/fusion targeting the same fodder re-validates ownership and finds it gone ->
--     clean no-op (single-threaded Luau + the yield-free commit make this impossible to interleave).
--     A crash can only leave the profile fully pre-fusion or fully post-fusion -- never half-fused.
-- (b) FODDER CONSUMED ONLY WHEN THE RESULT IS CREATED: the result reuses one of the FODDER's own
--     pads (guaranteed free the instant the fodder is removed), so a same-species/tier-up fusion can
--     never "have no pad". If a result pad can't be determined (impossible for a valid recipe), the
--     fusion REFUSES up front and consumes NOTHING.
-- (c) STAR/MUTATION applied ONCE: the result's stored IncomePerSec is the species BASE; its Star +
--     Mutation are fields read by the canonical Shared/UnitIncome helper (the SOLE multiply site).
--     Nothing here bakes star/mutation into stored income.
-- (d) LOCKED units can't be fodder: isLocked() consults the SAME registries steal/trade/sell use
--     (in-transit + in-trade). FORWARD-COMPAT: M9.3 deploy makes units un-fodderable by adding its
--     lock here. Fusion itself is synchronous, so there is no separate "in-flight fusion" lock to
--     maintain -- the atomic commit is the lock.
-- (e) SOFT-FAIL is SAFE: a fail consumes only SoftFailLose (< recipe count) fodder and KEEPS the
--     rest unchanged -- never total loss.
-- (f) CASH via the guarded accessor only (fusion has no cash cost this milestone; the hook exists).
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local MutationConfig = require(ReplicatedStorage.Shared.MutationConfig)
local FusionConfig = require(ReplicatedStorage.Shared.FusionConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local ProtectionService = require(script.Parent.ProtectionService)
local Benefits = require(script.Parent.Benefits)
local Analytics = require(script.Parent.Analytics)
local GameSignals = require(script.Parent.GameSignals) -- M12.1 quest observation bus
local RateLimiter = require(script.Parent.RateLimiter)
local TransitRegistry = require(script.Parent.TransitRegistry)
local TradeLockRegistry = require(script.Parent.TradeLockRegistry)
local DeployLockRegistry = require(script.Parent.DeployLockRegistry)
local PerkEffects = require(script.Parent.PerkEffects)
local Remotes = require(script.Parent.Remotes)

local FusionService = {}

-- A unit can't be fodder while in-transit (steal), in a trade offer, or DEPLOYED to a role (M9.3).
local function isLocked(unitId)
    return TransitRegistry.Has(unitId)
        or TradeLockRegistry.Has(unitId)
        or DeployLockRegistry.Has(unitId)
end

local function findEntry(profile, unitId)
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        if unit.Id == unitId then
            return unit
        end
    end
    return nil
end

local function mutationValue(key)
    return MutationConfig.MultiplierFor(key)
end

-- Rebuilds OwnedBrainrots WITHOUT the given id-set (the atomic removal). Returns the new array.
local function withoutIds(profile, removeSet)
    local kept = {}
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        if not removeSet[unit.Id] then
            table.insert(kept, unit)
        end
    end
    return kept
end

local function refresh(player, profile)
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
    ProtectionService.RefreshPrompts(player)
end

-- Validates + collects the fodder units (all owned + unlocked). Returns (units array, err).
local function collectFodder(profile, ids)
    if type(ids) ~= "table" then
        return nil, "Invalid fodder."
    end
    local n = #ids
    if n < 2 or n > 64 then
        return nil, "Invalid fodder count."
    end
    local seen = {}
    local units = {}
    for _, id in ipairs(ids) do
        if type(id) ~= "string" or #id == 0 or #id > 100 or seen[id] then
            return nil, "Invalid fodder."
        end
        seen[id] = true
        local unit = findEntry(profile, id)
        if unit == nil then
            return nil, "You don't own those units."
        end
        if isLocked(id) then
            return nil, "A unit is busy (in a trade or being stolen)."
        end
        table.insert(units, unit)
    end
    return units
end

-- ===========================================================================================
-- Same-species star-up: N copies of the SAME Type at the SAME Star -> one at Star+1 (+crit).
-- ===========================================================================================
local function fuseStarUp(player, profile, fodder)
    if #fodder ~= FusionConfig.SameSpeciesCount then
        return {
            Result = "Error",
            Message = "Need "
                .. FusionConfig.SameSpeciesCount
                .. " of the same unit at the same star.",
        }
    end
    local type0 = fodder[1].Type
    local star0 = fodder[1].Star or 1
    for _, unit in ipairs(fodder) do
        if unit.Type ~= type0 or (unit.Star or 1) ~= star0 then
            return { Result = "Error", Message = "All fodder must be the same unit + star." }
        end
    end
    if star0 >= FusionConfig.MaxStar then
        return {
            Result = "Error",
            Message = "Already at max star (" .. FusionConfig.MaxStar .. ").",
        }
    end
    local def = Catalog.Get(type0)
    if def == nil then
        return { Result = "Error", Message = "Unknown unit." }
    end
    local plot = PlotService.GetPlot(player)
    if plot == nil then
        return { Result = "Error", Message = "Your base isn't ready." }
    end
    -- The result reuses a fodder's pad (free the instant the fodder is removed) -> never no-pad.
    local resultPad = fodder[1].PadIndex
    if resultPad == nil then
        return { Result = "Error", Message = "No pad for the result." } -- safe no-op (fodder kept)
    end

    -- ----- roll the outcome (server-side) -----
    -- M11.1 ECON perk (Cosmic Forge): the holder's FusionFailMult lowers the fail chance.
    local fail = math.random() < FusionConfig.SoftFailChance * PerkEffects.FusionFailMult(player)
    if fail then
        local lose = math.clamp(FusionConfig.SoftFailLose, 1, #fodder - 1)
        local removeSet = {}
        for i = 1, lose do
            removeSet[fodder[i].Id] = true
        end
        -- ===== COMMIT (soft-fail): consume only `lose` fodder, keep the rest. No result. =====
        profile.Data.OwnedBrainrots = withoutIds(profile, removeSet)
        -- ====================================================================================
        for id in pairs(removeSet) do
            BrainrotService.RemoveModel(player, id)
        end
        refresh(player, profile)
        Analytics.custom(player, Analytics.Events.FusionFail, lose)
        ProfileManager.ForceSave(player)
        Remotes.NotifyPlayer(player, "error", "Fusion FAILED! Lost " .. lose .. " fodder.")
        return {
            Result = "Fail",
            Lost = lose,
            Message = "Fusion failed -- lost " .. lose .. " fodder (kept the rest).",
        }
    end

    -- M11.1 ECON perk (Cosmic Forge): the holder's FusionCritBonus raises the crit chance (capped 1).
    local crit = math.random()
        < math.clamp(FusionConfig.CritChance + PerkEffects.FusionCritBonus(player), 0, 1)
    local newStar = star0 + 1 + (crit and FusionConfig.CritExtraStars or 0)
    if newStar > FusionConfig.MaxStar then
        newStar = FusionConfig.MaxStar
    end

    -- Result inherits the BEST mutation among the fodder (never strip the player's best variant);
    -- the mutation-on-fusion chance may roll a fresh one (respecting the luck hook) and keep the better.
    local bestMut = nil
    for _, unit in ipairs(fodder) do
        if mutationValue(unit.Mutation) > mutationValue(bestMut) then
            bestMut = unit.Mutation
        end
    end
    local resultMut = bestMut
    if math.random() < FusionConfig.MutationOnFusionChance then
        local rolled = MutationConfig.Roll(Benefits.GetLuckMultiplier(player))
        if mutationValue(rolled) > mutationValue(resultMut) then
            resultMut = rolled
        end
    end

    -- ===== COMMIT (success): remove ALL fodder + create the ONE result, NO yields. =====
    local removeSet = {}
    for _, unit in ipairs(fodder) do
        removeSet[unit.Id] = true
    end
    profile.Data.OwnedBrainrots = withoutIds(profile, removeSet)
    -- M11.2 FUSION INTERACTION: the result is a NEW factory record, so it starts at Evolution Stage 1
    -- / XP 0 -- the fodder's evolution is CONSUMED with the fodder (a deliberate "raise this one vs
    -- sacrifice it" tension). Only Star + Mutation are carried up; EvolutionStage/XP are NOT.
    local result = BrainrotFactory.create(player, def, resultPad, false) -- clean record (Star 1, Stage 1)
    result.Star = newStar
    result.Mutation = resultMut
    table.insert(profile.Data.OwnedBrainrots, result)
    profile.Data.Discovered[def.Id] = true
    if resultMut ~= nil then
        profile.Data.MutationsDiscovered[resultMut] = true
    end
    -- ===================================================================================

    for id in pairs(removeSet) do
        BrainrotService.RemoveModel(player, id)
    end
    BrainrotService.SpawnBrainrot(player, plot, result)
    refresh(player, profile)

    Analytics.custom(player, Analytics.Events.Fusion, newStar)
    GameSignals.fire(player, "fusions", 1) -- M12.1 quests; pure emit, no behavior change
    if crit then
        Analytics.custom(player, Analytics.Events.FusionCrit, newStar)
    end
    if resultMut ~= nil then
        Analytics.custom(player, Analytics.Events.MutationRoll, mutationValue(resultMut))
    end
    ProfileManager.ForceSave(player)

    local stars = FusionConfig.Stars(newStar)
    Remotes.NotifyPlayer(
        player,
        "success",
        "Fused into " .. stars .. " " .. def.DisplayName .. "!" .. (crit and " CRIT!" or "")
    )
    return {
        Result = "Success",
        Star = newStar,
        Crit = crit,
        Mutation = resultMut,
        Type = def.Id,
        Message = "Fused into " .. stars .. " " .. def.DisplayName .. (crit and "  (CRIT!)" or ""),
    }
end

-- ===========================================================================================
-- Optional tier-up (config switch OFF by default): N units of a rarity -> a factory roll for a
-- random unit of the NEXT rarity tier, same crit/fail rolls.
-- ===========================================================================================
local function nextTierKey(rarityKey)
    local tier = Rarity.Get(rarityKey)
    for _, entry in ipairs(Rarity.Ordered) do
        if entry.Order == tier.Order + 1 then
            return entry.Key
        end
    end
    return nil
end

local function randomUnitOfRarity(rarityKey)
    local pool = {}
    for _, item in ipairs(Catalog.Items) do
        -- Exclude premium, boss-only (M11.3), AND seasonal-exclusive (M11.4) units so tier-up can never
        -- mint a gated reward unit (the factory would refuse an exclusive anyway -- this avoids the nil).
        if
            item.Rarity == rarityKey
            and item.Buyable ~= false
            and item.Premium ~= true
            and item.BossOnly ~= true
            and item.ExclusiveSeason == nil
        then
            table.insert(pool, item)
        end
    end
    if #pool == 0 then
        return nil
    end
    return pool[math.random(1, #pool)]
end

local function fuseTierUp(player, profile, fodder)
    if not FusionConfig.TierUpEnabled then
        return { Result = "Error", Message = "Tier-up fusion is disabled." }
    end
    if #fodder ~= FusionConfig.TierUpCount then
        return {
            Result = "Error",
            Message = "Need " .. FusionConfig.TierUpCount .. " units of the same rarity.",
        }
    end
    local rarity0 = Catalog.Get(fodder[1].Type) and Catalog.Get(fodder[1].Type).Rarity or nil
    if rarity0 == nil then
        return { Result = "Error", Message = "Unknown unit." }
    end
    for _, unit in ipairs(fodder) do
        local def = Catalog.Get(unit.Type)
        if def == nil or def.Rarity ~= rarity0 then
            return { Result = "Error", Message = "All fodder must be the same rarity." }
        end
    end
    local nextKey = nextTierKey(rarity0)
    if nextKey == nil then
        return { Result = "Error", Message = "Already the top rarity." }
    end
    local resultDef = randomUnitOfRarity(nextKey)
    if resultDef == nil then
        return { Result = "Error", Message = "No unit to roll for that tier." }
    end
    local plot = PlotService.GetPlot(player)
    if plot == nil then
        return { Result = "Error", Message = "Your base isn't ready." }
    end
    local resultPad = fodder[1].PadIndex
    if resultPad == nil then
        return { Result = "Error", Message = "No pad for the result." }
    end

    -- M11.1 ECON perk (Cosmic Forge): the holder's FusionFailMult lowers the fail chance.
    local fail = math.random() < FusionConfig.SoftFailChance * PerkEffects.FusionFailMult(player)
    if fail then
        local lose = math.clamp(FusionConfig.SoftFailLose, 1, #fodder - 1)
        local removeSet = {}
        for i = 1, lose do
            removeSet[fodder[i].Id] = true
        end
        profile.Data.OwnedBrainrots = withoutIds(profile, removeSet)
        for id in pairs(removeSet) do
            BrainrotService.RemoveModel(player, id)
        end
        refresh(player, profile)
        Analytics.custom(player, Analytics.Events.FusionFail, lose)
        ProfileManager.ForceSave(player)
        Remotes.NotifyPlayer(player, "error", "Tier-up FAILED! Lost " .. lose .. " fodder.")
        return {
            Result = "Fail",
            Lost = lose,
            Message = "Tier-up failed -- lost " .. lose .. " fodder.",
        }
    end

    -- M11.1 ECON perk (Cosmic Forge): the holder's FusionCritBonus raises the crit chance (capped 1).
    local crit = math.random()
        < math.clamp(FusionConfig.CritChance + PerkEffects.FusionCritBonus(player), 0, 1)
    local rollMut = math.random() < FusionConfig.MutationOnFusionChance

    -- ===== COMMIT: remove fodder + create the next-tier result, NO yields. =====
    local removeSet = {}
    for _, unit in ipairs(fodder) do
        removeSet[unit.Id] = true
    end
    profile.Data.OwnedBrainrots = withoutIds(profile, removeSet)
    local result = BrainrotFactory.create(player, resultDef, resultPad, rollMut)
    result.Star = crit and 2 or 1 -- a crit tier-up arrives at ★2
    table.insert(profile.Data.OwnedBrainrots, result)
    profile.Data.Discovered[resultDef.Id] = true
    if result.Mutation ~= nil then
        profile.Data.MutationsDiscovered[result.Mutation] = true
    end
    -- =========================================================================

    for id in pairs(removeSet) do
        BrainrotService.RemoveModel(player, id)
    end
    BrainrotService.SpawnBrainrot(player, plot, result)
    refresh(player, profile)
    Analytics.custom(player, Analytics.Events.Fusion, result.Star)
    GameSignals.fire(player, "fusions", 1) -- M12.1 quests; pure emit, no behavior change
    if crit then
        Analytics.custom(player, Analytics.Events.FusionCrit, result.Star)
    end
    ProfileManager.ForceSave(player)
    Remotes.NotifyPlayer(player, "success", "Tier up! Got " .. resultDef.DisplayName .. "!")
    return {
        Result = "Success",
        Star = result.Star,
        Crit = crit,
        Mutation = result.Mutation,
        Type = resultDef.Id,
        Message = "Tier up -- got "
            .. resultDef.DisplayName
            .. (crit and " (CRIT ★2!)" or "")
            .. "!",
    }
end

local function handleFuse(player, payload)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    local fodder, err = collectFodder(profile, payload.FodderIds)
    if fodder == nil then
        return { Result = "Error", Message = err }
    end
    if payload.Mode == "TierUp" then
        return fuseTierUp(player, profile, fodder)
    end
    return fuseStarUp(player, profile, fodder)
end

function FusionService.Init()
    Remotes.FuseRequest.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" then
            return { Result = "Error", Message = "Invalid request." }
        end
        if not RateLimiter.check(player, "fuse", 0.5) then
            return { Result = "Error", Message = "Slow down." }
        end
        return handleFuse(player, payload)
    end
end

return FusionService
