-- IndexService: the Collection Index completion milestones + their IDEMPOTENT rewards.
--
-- SELF-AUDIT: a milestone reward is claimed at most ONCE -- a profile-persisted ClaimedIndexRewards
-- set is checked first, and the grant + the claim-record are written in the SAME mutation (no yields
-- between), so a crash can't grant-without-recording. Rewards reuse guarded paths (AddCash, a keyed
-- completion income source under the global cap, free-pad brainrot placement). A brainrot reward with
-- no free pad is REFUSED and NOT recorded (no dupe/loss; retryable). The client sends only a milestone
-- Id (intent); the server verifies it's actually completed + unclaimed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Monetization = require(ReplicatedStorage.Shared.Monetization)
local IndexConfig = require(ReplicatedStorage.Shared.IndexConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local PlayerStats = require(script.Parent.PlayerStats)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local ProtectionService = require(script.Parent.ProtectionService)
local Leaderstats = require(script.Parent.Leaderstats)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)

local IndexService = {}

-- Precompute the non-premium roster grouped by rarity + the full non-premium Id list (the free
-- completion set; premium units never block free completion).
local rarityIds = {} -- [rarityKey] = { id, ... }
local allFreeIds = {} -- every non-premium roster Id
for _, item in ipairs(Catalog.Items) do
    local includeForCompletion = IndexConfig.IncludePremiumInCompletion or item.Premium ~= true
    -- M11.4: seasonal exclusives are NOT required for completion (a missed season must never lock a
    -- player out of 100%). They still appear in the Index grid as a FOMO badge.
    if item.ExclusiveSeason ~= nil then
        includeForCompletion = false
    end
    if includeForCompletion then
        rarityIds[item.Rarity] = rarityIds[item.Rarity] or {}
        table.insert(rarityIds[item.Rarity], item.Id)
        table.insert(allFreeIds, item.Id)
    end
end

local function discoveredCount(profile)
    local n = 0
    for _ in pairs(profile.Data.Discovered) do
        n += 1
    end
    return n
end

-- Rarity-weighted collection score (same weights the leaderboard uses).
local function collectionScore(profile)
    local score = 0
    for id in pairs(profile.Data.Discovered) do
        local item = Catalog.Get(id)
        if item ~= nil then
            score += Monetization.Leaderboard.RarityWeights[item.Rarity] or 0
        end
    end
    return score
end

local function allDiscovered(profile, ids)
    for _, id in ipairs(ids) do
        if not profile.Data.Discovered[id] then
            return false
        end
    end
    return true
end

-- Is a milestone's completion condition met by the player's current Discovered set?
local function isMet(profile, milestone)
    if milestone.Type == "Rarity" then
        return allDiscovered(profile, rarityIds[milestone.Rarity] or {})
    elseif milestone.Type == "Total" then
        return discoveredCount(profile) >= milestone.Count
    elseif milestone.Type == "FullRoster" then
        return allDiscovered(profile, allFreeIds)
    end
    return false
end

-- Re-applies the income-multiplier sources from already-claimed milestones (idempotent; keyed).
function IndexService.SetupPlayer(player, profile)
    for id in pairs(profile.Data.ClaimedIndexRewards) do
        local milestone = IndexConfig.ById[id]
        if milestone ~= nil and milestone.Reward.Type == "Multiplier" then
            Benefits.SetIncomeSource(player, "idx:" .. id, milestone.Reward.Bonus)
        end
    end
    PlayerStats.UpdateIncome(player, profile)
end

-- Prepare a reward WITHOUT mutating; return (applyFn, message) or (nil, reason).
local function prepareReward(player, profile, milestoneId, reward)
    if reward.Type == "Cash" then
        local amount = reward.Amount
        return function()
            ProfileManager.AddCash(player, amount)
        end,
            "Reward: +$" .. tostring(amount) .. "!"
    elseif reward.Type == "Multiplier" then
        local bonus = reward.Bonus
        return function()
            Benefits.SetIncomeSource(player, "idx:" .. milestoneId, bonus)
            PlayerStats.UpdateIncome(player, profile)
        end,
            string.format("Reward: +%d%% income!", math.floor(bonus * 100 + 0.5))
    elseif reward.Type == "Brainrot" then
        local def = Catalog.Get(reward.BrainrotId)
        if def == nil then
            return nil, "Reward unavailable."
        end
        local plot = PlotService.GetPlot(player)
        if plot == nil then
            return nil, "Base not ready."
        end
        local padIndex = PlotService.FindFreePad(player, profile)
        if padIndex == nil then
            return nil, "Free a pad first, then claim."
        end
        return function()
            local unit =
                BrainrotFactory.create(player, def, padIndex, BrainrotFactory.RollFor.Index)
            table.insert(profile.Data.OwnedBrainrots, unit)
            profile.Data.Discovered[def.Id] = true
            BrainrotService.SpawnBrainrot(player, plot, unit)
            ProtectionService.RefreshPrompts(player)
        end,
            "Reward: " .. def.DisplayName .. "!"
    end
    return nil, "Reward unavailable."
end

-- Claim handler (RemoteFunction). TRUST BOUNDARY: client sends only a milestone Id.
function IndexService.Claim(player, milestoneId)
    if not RateLimiter.check(player, "indexclaim", 0.5) then
        return { Result = "Error", Message = "Slow down." }
    end
    if type(milestoneId) ~= "string" then
        return { Result = "Error", Message = "Invalid claim." }
    end
    local milestone = IndexConfig.ById[milestoneId]
    if milestone == nil then
        return { Result = "Error", Message = "Unknown milestone." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    if profile.Data.ClaimedIndexRewards[milestoneId] then
        return { Result = "AlreadyClaimed", Message = "Already claimed." }
    end
    if not isMet(profile, milestone) then
        return { Result = "Locked", Message = "Not completed yet." }
    end

    local apply, message = prepareReward(player, profile, milestoneId, milestone.Reward)
    if apply == nil then
        return { Result = "Error", Message = message }
    end

    -- ===== COMMIT: grant + record in the SAME mutation, no yields. =====
    apply()
    profile.Data.ClaimedIndexRewards[milestoneId] = true
    -- ==================================================================

    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
    Analytics.custom(player, Analytics.Events.IndexComplete, 1)
    return { Result = "Success", Message = message }
end

-- Query handler (RemoteFunction): the state the Index UI renders from.
function IndexService.GetState(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Discovered = {}, Claimed = {}, Score = 0 }
    end
    local discovered = {}
    for id in pairs(profile.Data.Discovered) do
        discovered[id] = true
    end
    local claimed = {}
    for id in pairs(profile.Data.ClaimedIndexRewards) do
        claimed[id] = true
    end
    local mutations = {}
    for key in pairs(profile.Data.MutationsDiscovered) do
        mutations[key] = true
    end
    -- M9.4: the claimed set-perk Keys, so the Index UI can render the Sets track from the same state
    -- query (completion itself is derived client-side from SetsConfig + the Discovered set above).
    local setsClaimed = {}
    for key in pairs(profile.Data.ClaimedSetPerks or {}) do
        setsClaimed[key] = true
    end
    return {
        Discovered = discovered,
        Claimed = claimed,
        Score = collectionScore(profile),
        Mutations = mutations,
        SetsClaimed = setsClaimed,
    }
end

function IndexService.Init()
    Remotes.ClaimIndexReward.OnServerInvoke = function(player, milestoneId)
        return IndexService.Claim(player, milestoneId)
    end
    Remotes.GetIndex.OnServerInvoke = function(player)
        return IndexService.GetState(player)
    end
end

return IndexService
