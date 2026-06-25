-- GroupRewardService (M13.6): the Roblox GROUP hook -- server-authoritative membership check + an
-- IDEMPOTENT one-time member reward (cash via the guarded accessor, or a unit via the factory, no-pad-
-- safe), or a capped LIVE passive perk. Membership is checked on the SERVER (IsInGroup / GetRankInGroup,
-- never client-trusted); the client only sends INTENT ({ Action="get"|"claim" }).
--
-- ============================  SELF-AUDIT (group)  ==========================================
-- (a) SERVER-AUTH + IDEMPOTENT: membership is verified server-side. A one-time reward (cash/unit) grants
--     EXACTLY once -- the grant and the GroupRewardClaimed flag are set in the SAME no-yield mutation, so
--     rejoin / re-check / a second server all see "claimed" and never re-grant. Leaving the group does
--     NOT clear the flag (the one-time reward is kept). No-pad-safe: a full inventory aborts WITHOUT
--     claiming, so it retries later. Cash flows through the guarded accessor (never negative).
-- (b) PASSIVE PERK CAPPED + LIVE: the "perk" reward type is a keyed benefit source ("group") set to the
--     bonus while a CURRENT member and to 0 otherwise -- re-checked every join + on re-check, so leaving
--     the group removes it cleanly with no residue, and the benefit registry caps the total. It is NOT
--     a one-time claim (membership-gated, never "spent").
-- (c) NO GAMEPLAY CHANGE: grants reuse the existing guarded accessor + factory; nothing else moves.
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroupConfig = require(ReplicatedStorage.Shared.GroupConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local ProtectionService = require(script.Parent.ProtectionService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)

local GroupRewardService = {}

local function isConfigured()
    return type(GroupConfig.GroupId) == "number" and GroupConfig.GroupId > 0
end

local function refresh(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
end

-- Server-side membership check (YIELDS). pcall-guarded so a transient API failure degrades to "not a
-- member" (never errors, never wrongly grants). Honors MinRank when set.
local function checkMembership(player)
    if not isConfigured() then
        return false
    end
    local ok, isMember = pcall(function()
        return player:IsInGroup(GroupConfig.GroupId)
    end)
    if not ok or not isMember then
        return false
    end
    if GroupConfig.MinRank > 0 then
        local okRank, rank = pcall(function()
            return player:GetRankInGroup(GroupConfig.GroupId)
        end)
        if not okRank or (tonumber(rank) or 0) < GroupConfig.MinRank then
            return false
        end
    end
    return true
end

-- The capped LIVE passive perk (only for Reward.Type == "perk"). Keyed benefit source = bonus while a
-- member, 0 otherwise. Idempotent overwrite; the registry caps the total. No-op for other reward types.
local function applyPerk(player, isMember)
    if GroupConfig.Reward.Type ~= "perk" then
        return
    end
    Benefits.SetIncomeSource(player, "group", isMember and GroupConfig.Reward.PerkBonus or 0)
    local profile = ProfileManager.GetProfile(player)
    if profile ~= nil then
        PlayerStats.UpdateIncome(player, profile)
    end
end

-- Grants the ONE-TIME reward (cash/unit) idempotently. The caller has already verified membership + a
-- live profile; this is the no-yield claim mutation (grant + flag together). Returns (ok, message).
local function grantOneTime(player, profile)
    if profile.Data.GroupRewardClaimed then
        return false, "You already claimed the group reward."
    end
    local r = GroupConfig.Reward
    if r.Type == "cash" then
        ProfileManager.AddCash(player, r.Cash) -- guarded accessor (never negative)
        profile.Data.GroupRewardClaimed = true -- set in the SAME mutation -> granted exactly once
        refresh(player)
        ProfileManager.ForceSave(player)
        Analytics.custom(player, Analytics.Events.GroupReward, 1)
        return true, "Thanks for joining! Granted $" .. tostring(r.Cash) .. "."
    elseif r.Type == "unit" then
        local def = Catalog.Get(r.UnitId)
        if def == nil then
            return false, "The group reward unit is misconfigured."
        end
        local plot = PlotService.GetPlot(player)
        local padIndex = plot ~= nil and PlotService.FindFreePad(player, profile) or nil
        if padIndex == nil then
            return false, "Free a pad first, then re-check." -- no-pad-safe: nothing granted, NOT claimed
        end
        local unit =
            BrainrotFactory.create(player, def, padIndex, BrainrotFactory.RollFor.Product, true)
        if unit == nil then
            return false, "Couldn't grant the unit -- try again."
        end
        table.insert(profile.Data.OwnedBrainrots, unit)
        profile.Data.Discovered[def.Id] = true
        profile.Data.GroupRewardClaimed = true -- grant + flag together (exactly once)
        BrainrotService.SpawnBrainrot(player, plot, unit)
        ProtectionService.RefreshPrompts(player)
        refresh(player)
        ProfileManager.ForceSave(player)
        Analytics.custom(player, Analytics.Events.GroupReward, 1)
        return true, "Thanks for joining! Granted a " .. def.DisplayName .. "."
    end
    return false, "The group reward is misconfigured."
end

-- Join setup: apply the live perk (if any) + auto-grant the one-time reward if a member + unclaimed.
function GroupRewardService.SetupPlayer(player, profile)
    if not isConfigured() then
        return
    end
    local isMember = checkMembership(player) -- yields
    if ProfileManager.GetProfile(player) == nil then
        return -- left mid-check
    end
    applyPerk(player, isMember)
    if isMember and GroupConfig.Reward.Type ~= "perk" and not profile.Data.GroupRewardClaimed then
        grantOneTime(player, profile)
    end
end

-- Manual claim / re-check (the UI button). Re-verifies membership server-side, applies the perk, and
-- grants the one-time reward if eligible + unclaimed.
function GroupRewardService.Claim(player)
    if not isConfigured() then
        return { Result = "Error", Message = "Group rewards aren't set up yet." }
    end
    if not RateLimiter.check(player, "group", 2) then
        return { Result = "Error", Message = "Slow down." }
    end
    if ProfileManager.GetProfile(player) == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    local isMember = checkMembership(player) -- yields
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    applyPerk(player, isMember)
    if not isMember then
        return { Result = "Error", Message = "Join the group first, then tap Re-check!" }
    end
    if GroupConfig.Reward.Type == "perk" then
        return { Result = "Success", Message = "Member perk is active!" }
    end
    if profile.Data.GroupRewardClaimed then
        return { Result = "AlreadyClaimed", Message = "You already claimed the group reward." }
    end
    local ok, message = grantOneTime(player, profile)
    return { Result = ok and "Success" or "Error", Message = message }
end

-- State the settings "Community" section renders from.
function GroupRewardService.GetState(player)
    if not isConfigured() then
        return { Configured = false }
    end
    local isMember = checkMembership(player)
    local profile = ProfileManager.GetProfile(player)
    return {
        Configured = true,
        GroupName = GroupConfig.GroupName,
        GroupUrl = GroupConfig.GroupUrl,
        GroupId = GroupConfig.GroupId,
        PromptText = GroupConfig.PromptText,
        RewardSummary = GroupConfig.RewardSummary(),
        RewardType = GroupConfig.Reward.Type,
        IsMember = isMember,
        Claimed = profile ~= nil and profile.Data.GroupRewardClaimed == true,
    }
end

function GroupRewardService.Init()
    Remotes.GroupAction.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return { Result = "Error", Message = "Invalid request." }
        end
        if payload.Action == "get" then
            return { Result = "Success", State = GroupRewardService.GetState(player) }
        elseif payload.Action == "claim" then
            return GroupRewardService.Claim(player)
        end
        return { Result = "Error", Message = "Unknown action." }
    end
end

return GroupRewardService
