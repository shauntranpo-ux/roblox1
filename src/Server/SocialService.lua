-- SocialService (M13.3): friends & social play -- GIFTING policy (anti-abuse gate + confirmation; the
-- atomic dupe-proof transfer is reused from TradeService.GiftUnit), VIP / PRIVATE-server perk grants
-- (server-side detection, idempotent, capped via the benefit registry), and the social state the UI
-- renders. Server-authoritative throughout: the client sends INTENT only. Friend join/follow + the
-- invite are client-side (TeleportService / M13.1's PromptGameInvite); this logs them.
--
-- ============================  SELF-AUDIT (social)  =========================================
-- (a) GIFTING DUPE-SAFE: the actual move is TradeService.GiftUnit -- the SAME no-yield, dupe-proof
--     remove-from-giver + add-to-receiver as a trade, refusing locked/favorited/equipped/in-transit/
--     in-trade units + no-pad-safe. This module only gates it (rate-limit, account-age vs fresh-alt
--     funneling, RequireFriendship, daily cap) + requires confirmation; the server re-validates all.
-- (b) ANTI-ABUSE: confirmation required; rate-limited; the sender must be old enough + (config) a
--     friend; a per-server-day cap is enforced + persisted. The cap is incremented BEFORE the move and
--     reverted if the move fails, so a refused gift never burns a cap slot.
-- (c) VIP/PRIVATE SERVER-SIDE + CAPPED: game.PrivateServerId/OwnerId are read on the SERVER; the perk
--     is a keyed benefit source = clamp(boost, cap), overwritten on every join (no double-apply); a
--     non-private server sets it to 0 (no residue). The benefit registry further caps the total.
-- (d) SERVER-AUTHORITATIVE: client INTENT only; units via the factory/transfer; cash N/A here.
-- ===========================================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SocialConfig = require(ReplicatedStorage.Shared.SocialConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local PlayerStats = require(script.Parent.PlayerStats)
local TradeService = require(script.Parent.TradeService)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)

local SocialService = {}

local isPrivate = false
local ownerId = 0

local function ping(player)
    if Remotes.SocialUpdate ~= nil then
        Remotes.SocialUpdate:FireClient(player)
    end
end

local function ensureDay(profile)
    local day = SocialConfig.CurrentDay(os.time())
    if profile.Data.GiftDay ~= day then
        profile.Data.GiftDay = day
        profile.Data.GiftCount = 0
    end
end

-- The vip-server boost fraction this player gets right now (0 in a public server).
local function vipBoostFor(player)
    if not isPrivate then
        return 0
    end
    local boost = SocialConfig.Vip.IncomeBoost
    if player.UserId == ownerId and ownerId ~= 0 then
        boost += SocialConfig.Vip.OwnerBonus
    end
    return math.min(boost, SocialConfig.Vip.CapPct / 100)
end

-- ── VIP perk (keyed benefit source; idempotent overwrite; 0 in public servers -> no residue) ──
local function applyVip(player, profile)
    Benefits.SetIncomeSource(player, "vipserver", vipBoostFor(player))
    PlayerStats.UpdateIncome(player, profile)
    player:SetAttribute("VipServer", isPrivate and vipBoostFor(player) > 0)
end

-- ── Gifting (gate + confirm; the dupe-proof move is TradeService.GiftUnit) ──────────────────
local function handleGift(sender, targetUserId, unitId, confirm)
    if not RateLimiter.check(sender, "gift", SocialConfig.Gift.Cooldown) then
        return { Result = "Error", Message = "Slow down." }
    end
    if type(targetUserId) ~= "number" or type(unitId) ~= "string" then
        return { Result = "Error", Message = "Invalid request." }
    end
    if confirm ~= true then
        return { Result = "Error", Message = "Confirmation required." } -- server enforces explicit confirm
    end
    local recipient = Players:GetPlayerByUserId(targetUserId)
    if recipient == nil then
        return { Result = "Error", Message = "They must be in this server to receive a gift." }
    end
    if recipient == sender then
        return { Result = "Error", Message = "You can't gift yourself." }
    end
    -- ANTI FRESH-ALT FUNNELING: the sender's account must be old enough.
    if sender.AccountAge < SocialConfig.Gift.MinSenderAccountAgeDays then
        return { Result = "Error", Message = "Your account is too new to send gifts." }
    end
    -- Friendship gate (yields; deliberate action).
    if SocialConfig.Gift.RequireFriendship then
        local ok, isFriend = pcall(function()
            return sender:IsFriendsWith(targetUserId)
        end)
        if not ok or not isFriend then
            return { Result = "Error", Message = "You can only gift your friends." }
        end
    end
    local profile = ProfileManager.GetProfile(sender)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    ensureDay(profile)
    if profile.Data.GiftCount >= SocialConfig.Gift.DailyCap then
        return {
            Result = "Error",
            Message = "Daily gift limit reached (" .. SocialConfig.Gift.DailyCap .. ").",
        }
    end

    -- Reserve a cap slot BEFORE the move; revert if the move is refused (so a refusal never burns it).
    profile.Data.GiftCount += 1
    local ok, reason, _unitType, name = TradeService.GiftUnit(sender, recipient, unitId)
    if not ok then
        profile.Data.GiftCount -= 1
        return { Result = "Error", Message = reason or "Couldn't gift that unit." }
    end

    Analytics.custom(sender, Analytics.Events.GiftSent, 1)
    Analytics.custom(recipient, Analytics.Events.GiftReceived, 1)
    Remotes.NotifyPlayer(
        sender,
        "success",
        "Gifted " .. name .. " to " .. recipient.DisplayName .. "!",
        "buy"
    )
    Remotes.NotifyPlayer(
        recipient,
        "success",
        sender.DisplayName .. " gifted you a " .. name .. "!",
        "buy"
    )
    ping(sender)
    ping(recipient)
    return { Result = "Success", Message = "Gifted " .. name .. "!" }
end

-- ── State the social UI renders from ────────────────────────────────────────────────────────
function SocialService.GetState(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { GiftsLeft = 0, DailyCap = SocialConfig.Gift.DailyCap }
    end
    ensureDay(profile)
    return {
        GiftsLeft = math.max(0, SocialConfig.Gift.DailyCap - profile.Data.GiftCount),
        DailyCap = SocialConfig.Gift.DailyCap,
        MinAge = SocialConfig.Gift.MinSenderAccountAgeDays,
        AccountAge = player.AccountAge,
        RequireFriendship = SocialConfig.Gift.RequireFriendship,
        Vip = isPrivate,
        IsOwner = isPrivate and player.UserId == ownerId and ownerId ~= 0,
        VipBoostPct = math.floor(vipBoostFor(player) * 100 + 0.5),
        VipIncomePct = math.floor(SocialConfig.Vip.IncomeBoost * 100 + 0.5),
        VipOwnerPct = math.floor(SocialConfig.Vip.OwnerBonus * 100 + 0.5),
        PrivateNote = SocialConfig.PrivateServerNote,
    }
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────────────────────
function SocialService.SetupPlayer(player, profile)
    ensureDay(profile)
    applyVip(player, profile) -- idempotent (keyed source); capped; 0 in public servers
    if isPrivate then
        Analytics.custom(player, Analytics.Events.VipSession, (player.UserId == ownerId) and 1 or 0)
    end
end

function SocialService.Init()
    isPrivate = game.PrivateServerId ~= ""
    ownerId = game.PrivateServerOwnerId
    if isPrivate then
        print(
            "[Social] PRIVATE server detected (owner "
                .. tostring(ownerId)
                .. ") -> VIP perks active."
        )
    end

    Remotes.SocialAction.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return { Result = "Error", Message = "Invalid request." }
        end
        local action = payload.Action
        if action == "get" then
            return { Result = "Success", State = SocialService.GetState(player) }
        elseif action == "gift" then
            return handleGift(player, payload.TargetUserId, payload.UnitId, payload.Confirm == true)
        elseif action == "friendjoin" then
            if RateLimiter.check(player, "friendjoin", 1) then
                Analytics.custom(player, Analytics.Events.FriendJoin, 1) -- the teleport itself is client-side
            end
            return { Result = "Success" }
        end
        return { Result = "Error", Message = "Unknown action." }
    end
end

return SocialService
