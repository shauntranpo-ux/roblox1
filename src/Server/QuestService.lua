-- QuestService (M12.1): the SERVER-AUTHORITATIVE tutorial + quest engine. It OBSERVES real gameplay
-- via GameSignals (it modifies none of those systems), tracks progress per player in the profile,
-- decides completion, and grants rewards through the existing IDEMPOTENT claim pattern (atomic
-- grant+record, no-pad-safe, cash via the guarded accessor, units via the factory). Daily/weekly
-- resets derive purely from server time. The client renders + sends CLAIM INTENT only.
--
-- ============================  SELF-AUDIT (quests)  =========================================
-- (a) SERVER-AUTHORITATIVE: progress only advances inside onSignal from GameSignals (real server-side
--     events); the claim handler re-checks completion server-side. The client never pushes progress or
--     asserts completion -- ClaimQuest takes only a scope + quest id (validated/rate-limited).
-- (b) IDEMPOTENT CLAIMS: a reward is granted inside a no-yield COMMIT that grants THEN records the
--     Claimed* flag; a second claim (double-click / rejoin / cross-server) sees the flag -> no-op. A
--     unit reward with no free pad is REFUSED (not recorded) -> retry-safe, never lost/duped.
-- (c) RESETS FROM SERVER TIME: daily/weekly period ids = floor(time/length); ensurePeriods clears the
--     period's progress + claimed flags deterministically at the boundary (consistent across servers).
--     A completed-but-unclaimed daily EXPIRES at reset (documented rule).
-- (d) TUTORIAL ONE-SHOT: TutorialStep + ClaimedTutorial persist; only the current step accrues, claimed
--     steps never re-trigger, a returning player resumes at their step. Forward-compat steps don't block.
-- (e) FORWARD-COMPAT: a metric whose system isn't wired simply never fires -> that quest stays at 0, no
--     error (e.g. open_mystery until M12.2).
-- (f) OBSERVE-ONLY: nothing here mutates catch/steal/evolution/boss/fusion/economy; it only subscribes.
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local BrainrotService = require(script.Parent.BrainrotService)
local ProtectionService = require(script.Parent.ProtectionService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local GameSignals = require(script.Parent.GameSignals)
local Remotes = require(script.Parent.Remotes)

local QuestService = {}

local function now()
    return os.time()
end

-- ── Period reset (server time; deterministic boundary) ──────────────────────────────────────
local function ensurePeriods(profile)
    local changed = false
    local day = QuestConfig.CurrentDay(now())
    if profile.Data.DailyPeriod ~= day then
        profile.Data.DailyPeriod = day
        profile.Data.DailyProgress = {} -- the period's progress + claims reset together
        profile.Data.ClaimedDaily = {}
        changed = true
    end
    local week = QuestConfig.CurrentWeek(now())
    if profile.Data.WeeklyPeriod ~= week then
        profile.Data.WeeklyPeriod = week
        profile.Data.WeeklyProgress = {}
        profile.Data.ClaimedWeekly = {}
        changed = true
    end
    return changed
end

local function isComplete(quest, progress)
    return (progress or 0) >= quest.Target
end

-- "reached" metrics (e.g. cash_reached) store an ABSOLUTE value synced from the relevant stat; "count"
-- metrics accumulate. Returns (changed, freshlyCompleted).
local function applyMetric(progressTable, quest, metric, amount, profile)
    local before = progressTable[quest.Id] or 0
    local after = before
    if (quest.Mode or "count") == "reached" then
        if
            quest.Metric == "cash_reached" and (metric == "earn_cash" or metric == "cash_reached")
        then
            after = math.min(quest.Target, math.floor(profile.Data.Cash or 0))
        end
    elseif quest.Metric == metric then
        after = math.min(quest.Target, before + amount)
    end
    if after == before then
        return false, false
    end
    progressTable[quest.Id] = after
    return true, (after >= quest.Target and before < quest.Target)
end

-- ── Reward grant (prepare-then-commit; no-pad-safe; cash guarded; units via factory) ────────
local function prepareReward(player, profile, reward)
    local mintUnit = nil
    if reward.Unit ~= nil then
        local def = Catalog.Get(reward.Unit)
        if def ~= nil then
            local plot = PlotService.GetPlot(player)
            local padIndex = plot ~= nil and PlotService.FindFreePad(player, profile) or nil
            if padIndex == nil then
                return nil -- no free pad -> refuse (NOT recorded); retry-safe
            end
            mintUnit = function()
                local unit =
                    BrainrotFactory.create(player, def, padIndex, BrainrotFactory.RollFor.Index)
                table.insert(profile.Data.OwnedBrainrots, unit)
                profile.Data.Discovered[def.Id] = true
                BrainrotService.SpawnBrainrot(player, plot, unit)
                ProtectionService.RefreshPrompts(player)
            end
        end
    end
    return function()
        if type(reward.Cash) == "number" and reward.Cash > 0 then
            ProfileManager.AddCash(player, reward.Cash) -- guarded accessor; never negative
        end
        if mintUnit ~= nil then
            mintUnit()
        end
    end
end

local function refreshDisplays(player, profile)
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
end

-- ── The objective banner driver: the player's current PRIMARY objective (display-only attribute) ──
local function rewardText(reward)
    local parts = {}
    if (reward.Cash or 0) > 0 then
        table.insert(parts, "$" .. reward.Cash)
    end
    if reward.Unit ~= nil then
        table.insert(parts, "a brainrot")
    end
    return table.concat(parts, " + ")
end

local function publishObjective(player, profile)
    local text = nil
    -- The current required (non-forward-compat) tutorial step takes priority.
    for i = profile.Data.TutorialStep, #QuestConfig.Tutorial do
        local s = QuestConfig.Tutorial[i]
        if not s.ForwardCompat and not profile.Data.ClaimedTutorial[s.Id] then
            local prog = math.min(profile.Data.TutorialProgress[s.Id] or 0, s.Target)
            text = s.Desc .. "  (" .. prog .. "/" .. s.Target .. ")"
            break
        end
    end
    -- Otherwise, highlight the first incomplete active daily.
    if text == nil then
        for _, q in ipairs(QuestConfig.ActiveDaily(profile.Data.DailyPeriod)) do
            local prog = profile.Data.DailyProgress[q.Id] or 0
            if not profile.Data.ClaimedDaily[q.Id] and prog < q.Target then
                text = "Daily: " .. q.Desc .. "  (" .. prog .. "/" .. q.Target .. ")"
                break
            end
        end
    end
    player:SetAttribute("Objective", text or "")
end

local function ping(player)
    if Remotes.QuestsUpdate ~= nil then
        Remotes.QuestsUpdate:FireClient(player)
    end
end

-- ── Tutorial auto-claim (server-validated + idempotent, like a manual claim) ────────────────
local function autoClaimTutorial(player, profile, step)
    if profile.Data.ClaimedTutorial[step.Id] then
        return
    end
    local apply = prepareReward(player, profile, step.Reward)
    if apply == nil then
        return -- unit reward, no pad: leave claimable; it'll grant once a pad frees up
    end
    -- COMMIT: grant + record + advance, no yields.
    apply()
    profile.Data.ClaimedTutorial[step.Id] = true
    profile.Data.TutorialStep = profile.Data.TutorialStep + 1
    refreshDisplays(player, profile)
    Remotes.NotifyPlayer(
        player,
        "success",
        "Tutorial: " .. step.Title .. " done! +" .. rewardText(step.Reward),
        "buy"
    )
    Analytics.custom(player, Analytics.Events.TutorialStep, profile.Data.TutorialStep)
    ProfileManager.ForceSave(player)
end

-- ── The observer: increments active quests from real gameplay signals ───────────────────────
function QuestService.onSignal(player, metric, amount)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    local changed = ensurePeriods(profile)
    local completedTitles = {}

    -- TUTORIAL: only the current step accrues (ordered, one-shot).
    local step = QuestConfig.Tutorial[profile.Data.TutorialStep]
    if step ~= nil and not profile.Data.ClaimedTutorial[step.Id] then
        local didChange = applyMetric(profile.Data.TutorialProgress, step, metric, amount, profile)
        if didChange then
            changed = true
            if isComplete(step, profile.Data.TutorialProgress[step.Id]) then
                autoClaimTutorial(player, profile, step)
            end
        end
    end

    local function runSet(quests, progressTable, claimedTable)
        for _, q in ipairs(quests) do
            if not claimedTable[q.Id] then
                local didChange, fresh = applyMetric(progressTable, q, metric, amount, profile)
                if didChange then
                    changed = true
                    if fresh then
                        table.insert(completedTitles, q.Title)
                    end
                end
            end
        end
    end
    runSet(
        QuestConfig.ActiveDaily(profile.Data.DailyPeriod),
        profile.Data.DailyProgress,
        profile.Data.ClaimedDaily
    )
    runSet(
        QuestConfig.ActiveWeekly(profile.Data.WeeklyPeriod),
        profile.Data.WeeklyProgress,
        profile.Data.ClaimedWeekly
    )
    runSet(QuestConfig.Milestones, profile.Data.MilestoneProgress, profile.Data.ClaimedMilestone)

    if changed then
        publishObjective(player, profile)
        ping(player)
        for _, title in ipairs(completedTitles) do
            Remotes.NotifyPlayer(
                player,
                "success",
                "Quest complete: " .. title .. "! Claim it in the log."
            )
        end
    end
end

-- ── Manual claim (RemoteFunction). Client sends ONLY a scope + quest id (intent). ───────────
local SCOPES = {
    tutorial = { list = "TutorialById", progress = "TutorialProgress", claimed = "ClaimedTutorial" },
    daily = { list = "DailyById", progress = "DailyProgress", claimed = "ClaimedDaily" },
    weekly = { list = "WeeklyById", progress = "WeeklyProgress", claimed = "ClaimedWeekly" },
    milestone = {
        list = "MilestoneById",
        progress = "MilestoneProgress",
        claimed = "ClaimedMilestone",
    },
}

local function isActiveInPeriod(scope, profile, questId)
    if scope == "daily" then
        for _, q in ipairs(QuestConfig.ActiveDaily(profile.Data.DailyPeriod)) do
            if q.Id == questId then
                return true
            end
        end
        return false
    elseif scope == "weekly" then
        for _, q in ipairs(QuestConfig.ActiveWeekly(profile.Data.WeeklyPeriod)) do
            if q.Id == questId then
                return true
            end
        end
        return false
    end
    return true -- tutorial + milestone are always claimable when complete
end

function QuestService.Claim(player, scope, questId)
    if not RateLimiter.check(player, "questclaim", 0.3) then
        return { Result = "Error", Message = "Slow down." }
    end
    if type(scope) ~= "string" or type(questId) ~= "string" or #questId > 60 then
        return { Result = "Error", Message = "Invalid." }
    end
    local meta = SCOPES[scope]
    if meta == nil then
        return { Result = "Error", Message = "Unknown quest type." }
    end
    local quest = QuestConfig[meta.list][questId]
    if quest == nil then
        return { Result = "Error", Message = "Unknown quest." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    ensurePeriods(profile)
    if not isActiveInPeriod(scope, profile, questId) then
        return { Result = "Error", Message = "Not active this period." }
    end
    local claimedTable = profile.Data[meta.claimed]
    if claimedTable[questId] then
        return { Result = "AlreadyClaimed", Message = "Already claimed." }
    end
    local prog = profile.Data[meta.progress][questId] or 0
    if prog < quest.Target then
        return { Result = "Locked", Message = "Not complete yet." }
    end
    local apply = prepareReward(player, profile, quest.Reward)
    if apply == nil then
        return { Result = "Error", Message = "Free a pad first to claim the unit." }
    end
    -- COMMIT: grant + record together (no yields) -> exactly once.
    apply()
    claimedTable[questId] = true
    if
        scope == "tutorial"
        and profile.Data.TutorialStep == (QuestConfig.TutorialIndex[questId] or -1)
    then
        profile.Data.TutorialStep = profile.Data.TutorialStep + 1
    end

    refreshDisplays(player, profile)
    publishObjective(player, profile)
    ProfileManager.ForceSave(player)
    Analytics.custom(player, Analytics.Events.QuestClaim, 1)
    ping(player)
    return { Result = "Success", Message = "Reward claimed! +" .. rewardText(quest.Reward) }
end

-- ── State the quest-log UI renders from ─────────────────────────────────────────────────────
local function packSet(quests, progressTable, claimedTable)
    local out = {}
    for _, q in ipairs(quests) do
        local prog = progressTable[q.Id] or 0
        table.insert(out, {
            Id = q.Id,
            Title = q.Title,
            Desc = q.Desc,
            Target = q.Target,
            Progress = math.min(prog, q.Target),
            Reward = rewardText(q.Reward),
            Complete = prog >= q.Target,
            Claimed = claimedTable[q.Id] == true,
        })
    end
    return out
end

function QuestService.GetState(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Now = now() }
    end
    ensurePeriods(profile)
    local tutorial = {}
    for i, s in ipairs(QuestConfig.Tutorial) do
        table.insert(tutorial, {
            Id = s.Id,
            Title = s.Title,
            Desc = s.Desc,
            Target = s.Target,
            Progress = math.min(profile.Data.TutorialProgress[s.Id] or 0, s.Target),
            Reward = rewardText(s.Reward),
            Complete = (profile.Data.TutorialProgress[s.Id] or 0) >= s.Target,
            Claimed = profile.Data.ClaimedTutorial[s.Id] == true,
            Current = i == profile.Data.TutorialStep,
            ForwardCompat = s.ForwardCompat == true,
        })
    end
    return {
        Now = now(),
        Tutorial = tutorial,
        Daily = packSet(
            QuestConfig.ActiveDaily(profile.Data.DailyPeriod),
            profile.Data.DailyProgress,
            profile.Data.ClaimedDaily
        ),
        DailyEndsAt = QuestConfig.DayEndsAt(profile.Data.DailyPeriod),
        Weekly = packSet(
            QuestConfig.ActiveWeekly(profile.Data.WeeklyPeriod),
            profile.Data.WeeklyProgress,
            profile.Data.ClaimedWeekly
        ),
        WeeklyEndsAt = QuestConfig.WeekEndsAt(profile.Data.WeeklyPeriod),
        Milestone = packSet(
            QuestConfig.Milestones,
            profile.Data.MilestoneProgress,
            profile.Data.ClaimedMilestone
        ),
    }
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────────────────────
-- An ESTABLISHED pre-M12.1 player (reconciled fresh to TutorialStep 1) shouldn't be forced back through
-- onboarding -- and could otherwise get stuck on a step they're already past (e.g. all biomes unlocked).
-- Heuristic: any rebirth, a few discovered species, or a non-starter biome unlocked = skip onboarding.
local function isEstablished(profile)
    if (profile.Data.RebirthCount or 0) > 0 then
        return true
    end
    local discovered = 0
    for _ in pairs(profile.Data.Discovered or {}) do
        discovered += 1
    end
    if discovered >= 3 then
        return true
    end
    local biomes = 0
    for _ in pairs(profile.Data.UnlockedBiomes or {}) do
        biomes += 1
    end
    return biomes > 1 -- more than just the starter biome
end

function QuestService.SetupPlayer(player, profile)
    ensurePeriods(profile)
    -- One-shot: established players who never engaged the tutorial skip straight past it.
    if profile.Data.TutorialStep == 1 and isEstablished(profile) then
        profile.Data.TutorialStep = #QuestConfig.Tutorial + 1
    end
    -- Sync any "reached" quests (cash) from the loaded stat so progress reflects reality on join.
    QuestService.onSignal(player, "cash_reached", 0)
    publishObjective(player, profile)
end

function QuestService.Init()
    GameSignals.subscribe(function(player, metric, amount)
        QuestService.onSignal(player, metric, amount)
    end)
    Remotes.GetQuests.OnServerInvoke = function(player)
        return QuestService.GetState(player)
    end
    Remotes.ClaimQuest.OnServerInvoke = function(player, scope, questId)
        return QuestService.Claim(player, scope, questId)
    end
end

return QuestService
