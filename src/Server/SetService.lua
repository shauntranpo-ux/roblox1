-- SetService (M9.4): themed Index SET completion -> PERMANENT passive perks. The capstone of the M9
-- "purpose layer" -- a reason to KEEP units. Built on the EXACT idempotent-claim pattern as
-- IndexService (it is a near-clone), reusing the benefit registry, the luck hook, the guarded cash
-- accessor, and the brainrot factory.
--
-- ============================  SELF-AUDIT (set-perk path)  ===================================
-- (a) GRANTED EXACTLY ONCE, ATOMIC, RESTART/SERVER-SAFE: a set's reward is keyed by set Key in the
--     profile-persisted ClaimedSetPerks set, checked FIRST; the grant + the claim-record are written
--     in the SAME mutation with NO yields between (apply(); ClaimedSetPerks[key]=true), so a crash
--     can't grant-without-recording, and a rejoin / second server / restart sees it claimed and
--     refuses. The client sends only a set Key (intent); the server verifies completion + unclaimed.
-- (b) PERKS APPLY EXACTLY ONCE UNDER THE CAP: Multiplier/Luck rewards register as KEYED Benefits
--     sources ("set:<Key>"); re-applying overwrites the same key, so claim + join re-apply + rejoin
--     never double-stack; income is clamped to the existing global cap by the registry.
-- (c) DISCOVERED-BASED COMPLETION (not currently-owned): isComplete reads profile.Data.Discovered, so
--     selling / fusing a member after completing NEVER revokes the set or its perk.
-- (d) NO-PAD BRAINROT REWARD IS SAFE: prepareReward returns nil (no apply) when there's no free pad,
--     so ClaimedSetPerks is NOT recorded and the claim stays retryable -- the unit is never duped/lost.
--     Ordering: prepare (may refuse) -> only on success do apply() + record run together.
-- (e) PRIOR INVARIANTS HOLD: cash via AddCash, new units via the factory, no ownership mutation here.
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local SetsConfig = require(ReplicatedStorage.Shared.SetsConfig)

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

local SetService = {}

local function sourceKey(setKey)
    return "set:" .. setKey
end

-- Completion is DISCOVERED-based (ever owned), so it survives selling/fusing a member.
local function isComplete(profile, set)
    for _, id in ipairs(set.Members) do
        if not profile.Data.Discovered[id] then
            return false
        end
    end
    return true
end

-- Re-applies the PERMANENT perks (income/luck) of already-claimed sets. Idempotent (keyed sources
-- overwrite), so a rejoin can never double-stack. Called on join.
function SetService.SetupPlayer(player, profile)
    profile.Data.ClaimedSetPerks = profile.Data.ClaimedSetPerks or {}
    for key in pairs(profile.Data.ClaimedSetPerks) do
        local set = SetsConfig.ByKey[key]
        if set ~= nil then
            local reward = set.Reward
            if reward.Type == "Multiplier" then
                Benefits.SetIncomeSource(player, sourceKey(key), reward.Bonus)
            elseif reward.Type == "Luck" then
                Benefits.SetLuckSource(player, sourceKey(key), reward.Mult)
            end
        end
    end
    PlayerStats.UpdateIncome(player, profile)
end

-- Prepare a reward WITHOUT mutating; return (applyFn, message) or (nil, reason). A Brainrot reward
-- with no free pad returns nil so the claim is NOT recorded (retryable; never dupes/loses).
local function prepareReward(player, profile, set)
    local reward = set.Reward
    if reward.Type == "Cash" then
        local amount = reward.Amount
        return function()
            ProfileManager.AddCash(player, amount)
        end,
            "Reward: +$" .. tostring(amount) .. "!"
    elseif reward.Type == "Multiplier" then
        local bonus = reward.Bonus
        return function()
            Benefits.SetIncomeSource(player, sourceKey(set.Key), bonus)
            PlayerStats.UpdateIncome(player, profile)
        end,
            string.format("Reward: +%d%% income!", math.floor(bonus * 100 + 0.5))
    elseif reward.Type == "Luck" then
        local mult = reward.Mult
        return function()
            Benefits.SetLuckSource(player, sourceKey(set.Key), mult)
        end,
            string.format("Reward: x%.2g luck!", mult)
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

-- Claim handler (RemoteFunction). TRUST BOUNDARY: client sends only a set Key.
function SetService.Claim(player, setKey)
    if not RateLimiter.check(player, "setclaim", 0.5) then
        return { Result = "Error", Message = "Slow down." }
    end
    if type(setKey) ~= "string" then
        return { Result = "Error", Message = "Invalid claim." }
    end
    local set = SetsConfig.ByKey[setKey]
    if set == nil then
        return { Result = "Error", Message = "Unknown set." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    profile.Data.ClaimedSetPerks = profile.Data.ClaimedSetPerks or {}
    if profile.Data.ClaimedSetPerks[setKey] then
        return { Result = "AlreadyClaimed", Message = "Already claimed." }
    end
    if not isComplete(profile, set) then
        return { Result = "Locked", Message = "Set not complete yet." }
    end

    local apply, message = prepareReward(player, profile, set)
    if apply == nil then
        return { Result = "Error", Message = message }
    end

    -- ===== COMMIT: grant + record in the SAME mutation, no yields. =====
    apply()
    profile.Data.ClaimedSetPerks[setKey] = true
    -- ==================================================================

    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
    Analytics.custom(player, Analytics.Events.SetComplete, 1)
    return { Result = "Success", Message = message }
end

function SetService.Init()
    Remotes.ClaimSetPerk.OnServerInvoke = function(player, setKey)
        return SetService.Claim(player, setKey)
    end
end

return SetService
