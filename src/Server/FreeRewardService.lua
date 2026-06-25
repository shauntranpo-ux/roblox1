-- FreeRewardService (M12.2): the recurring FREE-reward economy -- daily-streak CHEST, timed GIFT, SPIN
-- wheel, base MYSTERY BLOCK. Every grant is SERVER-AUTHORITATIVE, server-time-gated (persisted last-
-- claim day/timestamps -> unfarmable by rejoin/hop/clock-spoof), and IDEMPOTENT per availability. All
-- RNG is rolled SERVER-SIDE and is FREE (earned by play) -- nothing random is sold for Robux. Cash via
-- the guarded accessor; units via the factory; no-pad-safe. (No prior daily system existed -> this is
-- the single source; nothing to unify.)
--
-- ============================  SELF-AUDIT (free rewards)  ===================================
-- (a) SERVER-AUTH + IDEMPOTENT: each reward is gated by a persisted server-time marker -- the daily by
--     LastDailyDay == today, the gift/mystery by (now - lastClaim) >= cooldown, the spin by a banked
--     count accrued from LastSpinGrantTime. The grant + marker update run in a no-yield COMMIT, so a
--     double-click / rejoin / server-hop within the window re-checks the marker -> no-op. Granted
--     exactly once per availability.
-- (b) UNFARMABLE: all gating is os.time() + persisted markers (never client-sent). A client can't
--     assert a timer, a streak, a spin, or a roll; it sends INTENT only and animates the SERVER result.
-- (c) NO PAID RANDOM ITEMS: every RNG table is rolled here and awarded for FREE; the only monetization
--     touchpoint (DoubleDaily) is a DETERMINISTIC gamepass that doubles the daily CASH -- never a Robux
--     purchase of a random pull.
-- (d) LUCK (legal): a Lucky-flagged roll entry has its weight x the player's luck -- the reward is
--     earned, not bought, so this is not a paid random item.
-- (e) NO-PAD-SAFE: a unit reward with no free pad refuses the claim (marker NOT advanced) -> retry-safe,
--     never lost/duped. Mystery block binds to a tagged part; absent -> the feature no-ops (no error).
-- ===========================================================================================

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FreeRewardConfig = require(ReplicatedStorage.Shared.FreeRewardConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local BrainrotService = require(script.Parent.BrainrotService)
local ProtectionService = require(script.Parent.ProtectionService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local Benefits = require(script.Parent.Benefits)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local GameSignals = require(script.Parent.GameSignals)
local Remotes = require(script.Parent.Remotes)

local FreeRewardService = {}

local function now()
    return os.time()
end

-- ── Server-side weighted roll (luck applies to Lucky-flagged entries) ───────────────────────
local function luckOf(player)
    local ok, mult = pcall(function()
        return Benefits.GetLuckMultiplier(player)
    end)
    return (ok and type(mult) == "number" and mult > 0) and mult or 1
end

-- Returns (chosenEntry, index). For a direct reward (no .Roll) returns it as-is at index 0.
local function rollReward(player, reward)
    if type(reward) ~= "table" then
        return nil, 0
    end
    if reward.Roll == nil then
        return reward, 0
    end
    local luck = luckOf(player)
    local total, weights = 0, {}
    for i, entry in ipairs(reward.Roll) do
        local w = (entry.Weight or 0) * (entry.Lucky and luck or 1)
        weights[i] = w
        total += w
    end
    if total <= 0 then
        return reward.Roll[1], 1
    end
    local pick = math.random() * total
    local acc = 0
    for i, entry in ipairs(reward.Roll) do
        acc += weights[i]
        if pick <= acc then
            return entry, i
        end
    end
    return reward.Roll[#reward.Roll], #reward.Roll
end

-- ── Prepare-then-commit grant (cash guarded; unit via factory; no-pad-safe) ─────────────────
local function prepareGrant(player, profile, grant)
    local mintUnit = nil
    if grant.Unit ~= nil then
        local def = Catalog.Get(grant.Unit)
        if def ~= nil then
            local plot = PlotService.GetPlot(player)
            local padIndex = plot ~= nil and PlotService.FindFreePad(player, profile) or nil
            if padIndex == nil then
                return nil -- no free pad -> refuse (marker NOT advanced)
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
        if type(grant.Cash) == "number" and grant.Cash > 0 then
            ProfileManager.AddCash(player, grant.Cash)
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

local function grantLabel(grant)
    if grant == nil then
        return "loot"
    end
    if (grant.Cash or 0) > 0 then
        return "$" .. grant.Cash
    end
    if grant.Unit ~= nil then
        local def = Catalog.Get(grant.Unit)
        return def ~= nil and def.DisplayName or "a brainrot"
    end
    return "loot"
end

local function ping(player)
    if Remotes.FreeRewardUpdate ~= nil then
        Remotes.FreeRewardUpdate:FireClient(player)
    end
end

-- ── Spin accrual (banked spins earned from server time) ─────────────────────────────────────
local function refreshSpins(profile)
    local cfg = FreeRewardConfig.Spin
    if profile.Data.LastSpinGrantTime <= 0 then
        return -- new player handled in SetupPlayer
    end
    local elapsed = now() - profile.Data.LastSpinGrantTime
    if elapsed >= cfg.EarnCooldown then
        local earned = math.floor(elapsed / cfg.EarnCooldown)
        profile.Data.SpinsAvailable = math.min(cfg.MaxBanked, profile.Data.SpinsAvailable + earned)
        profile.Data.LastSpinGrantTime += earned * cfg.EarnCooldown
    end
end

-- ── Claim handlers ──────────────────────────────────────────────────────────────────────────
local function handleDaily(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    local today = FreeRewardConfig.CurrentDay(now())
    if profile.Data.LastDailyDay == today then
        return { Result = "AlreadyClaimed", Message = "Come back tomorrow!" }
    end
    -- Streak: consecutive day -> +1, missed a day -> reset to 1 (documented rule).
    local newStreak = (profile.Data.LastDailyDay == today - 1) and (profile.Data.DailyStreak + 1)
        or 1
    local reward = FreeRewardConfig.DailyReward(newStreak)
    local grant = { Cash = reward.Cash, Unit = reward.Unit }
    if
        grant.Cash ~= nil
        and player:GetAttribute(FreeRewardConfig.Daily.GamepassDoubleKey) == true
    then
        grant.Cash *= 2 -- deterministic, disclosed gamepass: 2x the daily CASH (never a random pull)
    end
    local apply = prepareGrant(player, profile, grant)
    if apply == nil then
        return { Result = "Error", Message = "Free a pad first." }
    end
    -- COMMIT: grant + advance the day marker + streak, no yields.
    apply()
    profile.Data.DailyStreak = newStreak
    profile.Data.LastDailyDay = today
    refreshDisplays(player, profile)
    ProfileManager.ForceSave(player)
    Analytics.custom(player, Analytics.Events.DailyClaim, newStreak)
    Remotes.NotifyPlayer(
        player,
        "success",
        "Day " .. newStreak .. " reward: " .. grantLabel(grant) .. "!",
        "buy"
    )
    ping(player)
    return { Result = "Success", Message = "Daily reward claimed!", Streak = newStreak }
end

local function handleGift(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    local ready = profile.Data.LastGiftTime + FreeRewardConfig.Gift.Cooldown
    if now() < ready then
        return { Result = "Cooldown", Message = "Not ready yet.", ReadyAt = ready }
    end
    local grant = rollReward(player, FreeRewardConfig.Gift.Reward)
    local apply = grant ~= nil and prepareGrant(player, profile, grant) or nil
    if apply == nil then
        return { Result = "Error", Message = "Free a pad first." }
    end
    apply()
    profile.Data.LastGiftTime = now()
    refreshDisplays(player, profile)
    ProfileManager.ForceSave(player)
    Analytics.custom(player, Analytics.Events.GiftClaim, 1)
    Remotes.NotifyPlayer(player, "success", "Free gift: " .. grantLabel(grant) .. "!", "buy")
    ping(player)
    return { Result = "Success", Message = "Gift claimed!" }
end

local function handleSpin(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    refreshSpins(profile)
    if profile.Data.SpinsAvailable <= 0 then
        return { Result = "NoSpins", Message = "No spins available yet." }
    end
    local seg, index = rollReward(player, { Roll = FreeRewardConfig.Spin.Segments })
    local apply = seg ~= nil and prepareGrant(player, profile, seg) or nil
    if apply == nil then
        return { Result = "Error", Message = "Free a pad first." }
    end
    -- COMMIT: consume a spin + grant, no yields.
    apply()
    profile.Data.SpinsAvailable -= 1
    refreshDisplays(player, profile)
    ProfileManager.ForceSave(player)
    Analytics.custom(player, Analytics.Events.Spin, index)
    ping(player)
    return {
        Result = "Success",
        Index = index,
        Reward = grantLabel(seg),
        Message = "You won " .. grantLabel(seg) .. "!",
    }
end

local function handleMystery(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    local ready = profile.Data.LastMysteryTime + FreeRewardConfig.Mystery.Cooldown
    if now() < ready then
        Remotes.NotifyPlayer(
            player,
            "error",
            "The Mystery Block is recharging (" .. math.ceil(ready - now()) .. "s)."
        )
        return
    end
    local grant = rollReward(player, FreeRewardConfig.Mystery.Reward)
    local apply = grant ~= nil and prepareGrant(player, profile, grant) or nil
    if apply == nil then
        Remotes.NotifyPlayer(player, "error", "Free a pad first to open the block.")
        return
    end
    apply()
    profile.Data.LastMysteryTime = now()
    GameSignals.fire(player, "open_mystery", 1) -- satisfies the M12.1 tutorial step (if present)
    refreshDisplays(player, profile)
    ProfileManager.ForceSave(player)
    Analytics.custom(player, Analytics.Events.MysteryOpen, 1)
    Remotes.NotifyPlayer(player, "success", "Mystery Block: " .. grantLabel(grant) .. "!", "buy")
    ping(player)
end

-- ── State the rewards UI renders from ───────────────────────────────────────────────────────
function FreeRewardService.GetState(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Now = now() }
    end
    refreshSpins(profile)
    local today = FreeRewardConfig.CurrentDay(now())
    local ladder = {}
    for i, entry in ipairs(FreeRewardConfig.Daily.Ladder) do
        ladder[i] = { Day = i, Cash = entry.Cash, Unit = entry.Unit }
    end
    return {
        Now = now(),
        Daily = {
            Streak = profile.Data.DailyStreak,
            CanClaim = profile.Data.LastDailyDay ~= today,
            ResetsAt = FreeRewardConfig.DayEndsAt(today),
            Ladder = ladder,
        },
        Gift = {
            ReadyAt = profile.Data.LastGiftTime + FreeRewardConfig.Gift.Cooldown,
            Cooldown = FreeRewardConfig.Gift.Cooldown,
        },
        Spin = {
            Available = profile.Data.SpinsAvailable,
            NextAt = profile.Data.LastSpinGrantTime + FreeRewardConfig.Spin.EarnCooldown,
            MaxBanked = FreeRewardConfig.Spin.MaxBanked,
            Segments = FreeRewardConfig.Spin.Segments,
        },
        Mystery = {
            ReadyAt = profile.Data.LastMysteryTime + FreeRewardConfig.Mystery.Cooldown,
            Cooldown = FreeRewardConfig.Mystery.Cooldown,
        },
    }
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────────────────────
function FreeRewardService.SetupPlayer(_player, profile)
    if profile.Data.LastSpinGrantTime <= 0 then -- first contact: seed the starter spins + clock
        profile.Data.SpinsAvailable =
            math.max(profile.Data.SpinsAvailable, FreeRewardConfig.Spin.StartSpins)
        profile.Data.LastSpinGrantTime = now()
    end
    refreshSpins(profile)
end

local function bindMysteryPrompt(part)
    if not part:IsA("BasePart") or part:FindFirstChild("MysteryPrompt") then
        return
    end
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "MysteryPrompt"
    prompt.ActionText = "Open"
    prompt.ObjectText = "Mystery Block"
    prompt.HoldDuration = 0.3
    prompt.MaxActivationDistance = 12
    prompt.RequiresLineOfSight = false
    prompt.Parent = part
end

function FreeRewardService.Init()
    Remotes.FreeRewardAction.OnServerInvoke = function(player, action)
        if not RateLimiter.check(player, "freereward", 0.4) then
            return { Result = "Error", Message = "Slow down." }
        end
        if action == "get" then
            return { Result = "Success", State = FreeRewardService.GetState(player) }
        elseif action == "daily" then
            return handleDaily(player)
        elseif action == "gift" then
            return handleGift(player)
        elseif action == "spin" then
            return handleSpin(player)
        end
        return { Result = "Error", Message = "Unknown action." }
    end

    -- Mystery block: bind an "Open" prompt to every tagged base part (now + future). Absent -> no-op.
    for _, part in ipairs(CollectionService:GetTagged(FreeRewardConfig.Mystery.Tag)) do
        bindMysteryPrompt(part)
    end
    CollectionService:GetInstanceAddedSignal(FreeRewardConfig.Mystery.Tag)
        :Connect(bindMysteryPrompt)
    ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if prompt.Name == "MysteryPrompt" then
            if RateLimiter.check(player, "mystery", 0.5) then
                handleMystery(player)
            end
        end
    end)
end

return FreeRewardService
