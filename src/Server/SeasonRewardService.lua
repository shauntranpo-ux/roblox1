-- SeasonRewardService: PULL-BASED, idempotent, offline-safe end-of-season reward claims.
--
-- SELF-AUDIT: rewards are NOT pushed by any server. On a player's JOIN (and on a live rollover for
-- online players), for each FROZEN season within its claim window that the player hasn't claimed
-- (profile-persisted ClaimedSeasonRewards keyed by season id), the server reads their FINAL score +
-- rank from that season's FROZEN store, computes ranked + track rewards (Cash -> always grantable,
-- no partial-fail), and grants + records the season id in the SAME mutation. Because the profile is
-- session-locked to ONE server and the claim is deduped by season id, a reward is granted EXACTLY
-- ONCE regardless of how many servers / sessions / restarts occur, and works for OFFLINE players on
-- their next login within the window. Reads yield; the grant+record commit is synchronous.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonsConfig = require(ReplicatedStorage.Shared.SeasonsConfig)
local Format = require(ReplicatedStorage.Shared.Format)

local ProfileManager = require(script.Parent.ProfileManager)
local SeasonService = require(script.Parent.SeasonService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local Remotes = require(script.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)

local SeasonRewardService = {}

local checking = {} -- [Player] = true while a claim pass is running (guards re-entry)

-- Is a season id claimable now? In mock/Studio (or under dev force), any past unclaimed season is
-- claimable so testing works; on a live server, only a season that ended within the claim window.
local function isClaimable(seasonId, currentId)
    if seasonId < 0 or seasonId >= currentId then
        return false
    end
    if SeasonService.IsMock() then
        return true
    end
    local _, endAt = SeasonsConfig.WindowFor(seasonId)
    local nowT = os.time()
    return nowT >= endAt and nowT < endAt + SeasonsConfig.ClaimWindow
end

local function rewardsFor(score, rank)
    local total = 0
    if rank ~= nil then
        for _, tier in ipairs(SeasonsConfig.RankedRewards) do
            if rank >= tier.Min and rank <= tier.Max then
                total += tier.Reward.Amount
                break
            end
        end
    end
    for _, tier in ipairs(SeasonsConfig.TrackRewards) do
        if score >= tier.Score then
            total += tier.Reward.Amount
        end
    end
    return total
end

-- Reads + grants any unclaimed frozen-season rewards for a player. Safe to call repeatedly.
function SeasonRewardService.CheckPlayer(player)
    if checking[player] then
        return
    end
    checking[player] = true

    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        checking[player] = nil
        return
    end
    local currentId = SeasonService.CurrentId()
    -- Candidate frozen seasons: the few most recent that could still be within the claim window.
    local span = math.ceil(SeasonsConfig.ClaimWindow / SeasonsConfig.SeasonLength) + 1
    for delta = 1, span do
        local seasonId = currentId - delta
        if isClaimable(seasonId, currentId) and not profile.Data.ClaimedSeasonRewards[seasonId] then
            -- Reads yield; re-fetch profile guard afterwards (player may have left).
            local score = SeasonService.GetScore(seasonId, player.UserId)
            local rank = SeasonService.GetRankInTop(seasonId, player.UserId)
            profile = ProfileManager.GetProfile(player)
            if profile == nil then
                break
            end
            if not profile.Data.ClaimedSeasonRewards[seasonId] then
                local total = rewardsFor(score, rank)
                -- ===== COMMIT: grant (cash -> never partial-fails) + record together, no yields. =====
                if total > 0 then
                    ProfileManager.AddCash(player, total)
                end
                profile.Data.ClaimedSeasonRewards[seasonId] = true
                -- ====================================================================================
                if total > 0 or score > 0 then
                    PlayerStats.PushCash(player, profile)
                    Leaderstats.Update(player, profile)
                    Remotes.NotifyPlayer(
                        player,
                        "success",
                        string.format(
                            "Season %d: you finished %s with %d pts  ->  +$%s!",
                            seasonId,
                            rank ~= nil and ("rank " .. rank) or "unranked",
                            math.floor(score),
                            Format.short(total)
                        )
                    )
                    Analytics.custom(player, Analytics.Events.SeasonReward, total)
                end
            end
        end
    end

    checking[player] = nil
end

function SeasonRewardService.ClearPlayer(player)
    checking[player] = nil
end

function SeasonRewardService.Init()
    -- A rollover makes the just-ended season claimable for everyone online right now.
    SeasonService.RolloverCallback = function(_oldId)
        for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
            task.spawn(SeasonRewardService.CheckPlayer, player)
        end
    end
end

return SeasonRewardService
