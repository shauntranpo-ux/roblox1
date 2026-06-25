-- ReferralService (M13.1): the SERVER-AUTHORITATIVE referral / invite system. Attribution is recorded
-- once-per-userId-forever (in the invitee's profile); the invited friend gets a one-time WELCOME
-- bonus; the INVITER is credited ONLY when an invited friend reaches a genuine MILESTONE (alt-farm
-- resistant) -- earning a CAPPED income boost (benefit registry) + escalating TIER rewards. Offline
-- inviters are credited via a durable mailbox (ReferralStore) on their next join. All grants idempotent.
--
-- ============================  SELF-AUDIT (referral)  =======================================
-- (a) ATTRIBUTION SERVER-SIDE + ONCE-PER-USER-FOREVER: the referrer is read from the invitee's
--     server-side launch/join data and recorded in profile.Data.ReferredBy, which is set EXACTLY ONCE
--     (guarded) and only for a BRAND-NEW account (FirstJoinAt was 0 at join). Self-referral + returning
--     accounts + a present ReferredBy are all rejected. The client never asserts a referrer.
-- (b) ALT-FARM RESISTANT + IDEMPOTENT INVITER REWARDS: the inviter is credited ONLY when the invitee
--     reaches the config MILESTONE (read from the invitee's real profile/session). Each invitee is
--     counted at most once via the inviter's QualifiedReferrals SET (the idempotency ledger) -- live
--     when online, else drained from the durable mailbox on next join. Tier rewards dedupe via
--     ClaimedReferralTiers. A bare join / relog / idle alt earns the inviter NOTHING.
-- (c) BOOST CAPPED, NO DOUBLE-APPLY: a keyed benefit source ("invite") = clamp(count*per, CapPct);
--     overwriting the same key on every recompute (join/live/rejoin) can't double-stack, and the
--     benefit registry further clamps the TOTAL to the global income cap.
-- (d) ALL GRANTS IDEMPOTENT: welcome bonus (ReferralWelcomeClaimed flag), tiers (claimed set), cash via
--     the guarded accessor, units via the factory, no-pad-safe. Client sends INTENT only.
-- (e) GRACEFUL: missing/malformed launchData -> no attribution, no error; DataStore down -> mock mailbox.
-- ===========================================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReferralConfig = require(ReplicatedStorage.Shared.ReferralConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local PlotService = require(script.Parent.PlotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local BrainrotService = require(script.Parent.BrainrotService)
local ProtectionService = require(script.Parent.ProtectionService)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)
local ReferralStore = require(script.Parent.ReferralStore)

local ReferralService = {}

local sessionJoin = {} -- [Player] = os.time() at join (playtime milestone)
local checkAccum = 0

local function countSet(set)
    local n = 0
    if type(set) == "table" then
        for _ in pairs(set) do
            n += 1
        end
    end
    return n
end

local function refreshDisplays(player, profile)
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
end

local function ping(player)
    if Remotes.ReferralUpdate ~= nil then
        Remotes.ReferralUpdate:FireClient(player)
    end
end

-- ── Reward grant (prepare-then-commit; cash guarded; units via factory; no-pad-safe) ────────
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

-- ── Boost (keyed benefit source; clamp(count*per, cap); idempotent overwrite) ───────────────
local function applyBoost(player, profile)
    local count = countSet(profile.Data.QualifiedReferrals)
    local pct = ReferralConfig.BoostPct(count)
    Benefits.SetIncomeSource(player, "invite", pct / 100) -- registry further clamps the total
    PlayerStats.UpdateIncome(player, profile)
    player:SetAttribute("InviteBoost", pct)
    player:SetAttribute("InviteCount", count)
end

-- ── Tier rewards (grant any newly-reached, once each) ───────────────────────────────────────
local function grantNewTiers(player, profile, count)
    for _, tier in ipairs(ReferralConfig.Tiers) do
        local key = tostring(tier.Count)
        if count >= tier.Count and not profile.Data.ClaimedReferralTiers[key] then
            local apply = prepareReward(player, profile, tier.Reward)
            if apply ~= nil then -- no-pad-safe: a unit tier with no pad waits (not recorded) -> retries
                apply()
                profile.Data.ClaimedReferralTiers[key] = true
                refreshDisplays(player, profile)
                Analytics.custom(player, Analytics.Events.ReferralTier, tier.Count)
                Remotes.NotifyPlayer(
                    player,
                    "success",
                    "Referral tier '" .. tier.Title .. "' reached! +$" .. (tier.Reward.Cash or 0),
                    "buy"
                )
            end
        end
    end
end

-- ── Credit an inviter for ONE qualified invitee (idempotent via their QualifiedReferrals set) ──
local function creditInviter(inviter, inviteeUserId)
    local profile = ProfileManager.GetProfile(inviter)
    if profile == nil then
        return
    end
    local field = tostring(inviteeUserId)
    if profile.Data.QualifiedReferrals[field] then
        return -- already counted this invitee -> no double-credit
    end
    profile.Data.QualifiedReferrals[field] = true
    local count = countSet(profile.Data.QualifiedReferrals)
    grantNewTiers(inviter, profile, count)
    applyBoost(inviter, profile)
    ProfileManager.ForceSave(inviter)
    Analytics.custom(inviter, Analytics.Events.ReferralQualified, count)
    Remotes.NotifyPlayer(
        inviter,
        "success",
        "A friend hit the milestone! Invite boost is now +" .. ReferralConfig.BoostPct(count) .. "%",
        "buy"
    )
    ping(inviter)
end

-- ── The invitee reached the milestone -> qualify their referral (credit the inviter) ────────
local function qualifyReferral(invitee, profile)
    if profile.Data.Qualified then
        return
    end
    local inviterId = profile.Data.ReferredBy
    if type(inviterId) ~= "number" or inviterId <= 0 then
        return
    end
    profile.Data.Qualified = true
    ProfileManager.ForceSave(invitee) -- persist so it never re-fires
    Analytics.custom(invitee, Analytics.Events.ReferralQualified, 0)
    -- durable mailbox (off-thread; DataStore yields) so an offline/cross-server inviter is credited later
    task.spawn(function()
        ReferralStore.AddPending(inviterId, invitee.UserId)
    end)
    -- live credit if the inviter is on THIS server right now
    local inviter = Players:GetPlayerByUserId(inviterId)
    if inviter ~= nil then
        creditInviter(inviter, invitee.UserId)
    end
    Remotes.NotifyPlayer(
        invitee,
        "success",
        "You hit the milestone -- your inviter was credited. Thanks!"
    )
end

local function milestoneMet(player, profile)
    local m = ReferralConfig.Milestone
    if m.Type == "cash_reached" then
        return (profile.Data.Cash or 0) >= m.Threshold
    elseif m.Type == "playtime" then
        return (os.time() - (sessionJoin[player] or os.time())) >= m.Threshold
    elseif m.Type == "rebirths" then
        return (profile.Data.RebirthCount or 0) >= m.Threshold
    end
    return false
end

-- A genuinely FRESH account (no prior progress): exactly the starter unit, no rebirths/purchases/codes.
-- Combined with FirstJoinAt==0, this rejects a RETURNING (pre-existing) player who happens to first join
-- post-update via an invite link -- only truly new accounts to the experience are attributable.
local function looksFresh(profile)
    return (profile.Data.RebirthCount or 0) == 0
        and #profile.Data.OwnedBrainrots <= 1
        and next(profile.Data.PurchaseHistory or {}) == nil
        and next(profile.Data.RedeemedCodes or {}) == nil
end

-- ── Attribution on join (server reads the referrer from launch data; once-per-user-forever) ──
local function parseInviter(launch)
    if type(launch) ~= "string" then
        return nil
    end
    local id = launch:match("^ref:(%d+)$")
    return id ~= nil and tonumber(id) or nil
end

local function attribute(player, profile, isNewAccount)
    if profile.Data.ReferredBy ~= 0 then
        return -- already attributed (once-per-user-forever)
    end
    if not isNewAccount then
        return -- only BRAND-NEW accounts to this experience can be attributed (anti-returning-abuse)
    end
    local ok, joinData = pcall(function()
        return player:GetJoinData()
    end)
    local launch = (ok and type(joinData) == "table") and joinData.LaunchData or nil
    local inviterId = parseInviter(launch)
    if inviterId == nil or inviterId <= 0 or inviterId == player.UserId then
        return -- missing/malformed referrer, or self-referral -> no attribution
    end
    profile.Data.ReferredBy = inviterId
    if not profile.Data.ReferralWelcomeClaimed then
        ProfileManager.AddCash(player, ReferralConfig.Welcome.Cash)
        profile.Data.ReferralWelcomeClaimed = true
        refreshDisplays(player, profile)
        Remotes.NotifyPlayer(
            player,
            "success",
            "Welcome! +$" .. ReferralConfig.Welcome.Cash .. " invite bonus!",
            "buy"
        )
    end
    Analytics.custom(player, Analytics.Events.ReferralAttributed, inviterId)
end

-- ── State the invite UI renders from ────────────────────────────────────────────────────────
function ReferralService.GetState(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Count = 0, BoostPct = 0, Tiers = {} }
    end
    local count = countSet(profile.Data.QualifiedReferrals)
    local tiers = {}
    for _, tier in ipairs(ReferralConfig.Tiers) do
        table.insert(tiers, {
            Count = tier.Count,
            Title = tier.Title,
            Cash = tier.Reward.Cash or 0,
            Claimed = profile.Data.ClaimedReferralTiers[tostring(tier.Count)] == true,
            Reached = count >= tier.Count,
        })
    end
    return {
        Count = count,
        BoostPct = ReferralConfig.BoostPct(count),
        CapPct = ReferralConfig.Boost.CapPct,
        PerPct = ReferralConfig.Boost.PerInvitePct,
        Milestone = ReferralConfig.Milestone.Label,
        Welcome = ReferralConfig.Welcome.Cash,
        WasReferred = profile.Data.ReferredBy ~= 0,
        Tiers = tiers,
    }
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────────────────────
function ReferralService.SetupPlayer(player, profile)
    sessionJoin[player] = os.time()
    -- A brand-new account = first-ever join (FirstJoinAt 0) AND genuinely fresh progress. Stamp
    -- FirstJoinAt on first contact regardless, so it can only ever be 0 once (the once-forever gate).
    local firstContact = (profile.Data.FirstJoinAt or 0) == 0
    local isNewAccount = firstContact and looksFresh(profile)
    if firstContact then
        profile.Data.FirstJoinAt = os.time()
    end
    attribute(player, profile, isNewAccount)

    -- Apply the boost immediately from the loaded set so income is correct from frame 1.
    applyBoost(player, profile)
    grantNewTiers(player, profile, countSet(profile.Data.QualifiedReferrals))

    -- Drain the inviter mailbox (this player AS an inviter) off-thread (DataStore yields), applying any
    -- credits earned while they were offline. Idempotent via the QualifiedReferrals set.
    task.spawn(function()
        local pending = ReferralStore.GetPending(player.UserId)
        for _, inviteeId in ipairs(pending) do
            creditInviter(player, inviteeId)
        end
    end)
end

function ReferralService.ClearPlayer(player)
    sessionJoin[player] = nil
end

function ReferralService.Init()
    ReferralStore.Init()

    Remotes.ReferralAction.OnServerInvoke = function(player, action)
        if not RateLimiter.check(player, "referral", 0.4) then
            return { Result = "Error", Message = "Slow down." }
        end
        if action == "get" then
            return { Result = "Success", State = ReferralService.GetState(player) }
        elseif action == "invitelog" then
            Analytics.custom(player, Analytics.Events.InviteSent, 1)
            return { Result = "Success" }
        end
        return { Result = "Error", Message = "Unknown action." }
    end

    -- Milestone check loop: qualify any referred player who has reached the milestone (alt-farm gate).
    RunService.Heartbeat:Connect(function(deltaTime)
        checkAccum += deltaTime
        if checkAccum < ReferralConfig.CheckInterval then
            return
        end
        checkAccum = 0
        for _, player in ipairs(Players:GetPlayers()) do
            local profile = ProfileManager.GetProfile(player)
            if profile ~= nil and profile.Data.ReferredBy ~= 0 and not profile.Data.Qualified then
                if milestoneMet(player, profile) then
                    qualifyReferral(player, profile)
                end
            end
        end
    end)
end

return ReferralService
