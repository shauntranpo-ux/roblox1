-- ReferralConfig (M13.1): THE single source of truth for the referral / invite system. A player
-- invites friends; the INVITED friend gets a one-time WELCOME bonus on join; the INVITER is credited
-- ONLY when an invited friend reaches a genuine MILESTONE (alt-farm resistant -- a bare join is
-- worthless), earning an escalating income BOOST (registered in the benefit registry, CAPPED) +
-- milestone TIER rewards. All numbers here, documented. Every grant is server-authoritative + idempotent.

local ReferralConfig = {}

-- ── Invited-friend WELCOME bonus (granted ONCE on a valid attribution; idempotent) ──────────
ReferralConfig.Welcome = {
    Cash = 2500, -- a small one-time thank-you to the new player who joined via an invite
}

-- ── The MILESTONE the invited friend must reach for the INVITER to be credited (alt-farm gate) ──
-- Type:
--   "cash_reached" -> the invitee's total cash >= Threshold (requires ACTIVE earning; the default --
--                     a bare/idle alt never reaches it without genuinely playing)
--   "playtime"     -> Threshold seconds of session playtime
--   "rebirths"     -> Threshold rebirths (profile.Data.RebirthCount)
-- All are read from the invitee's real server-side profile/session -- never client-asserted.
ReferralConfig.Milestone = {
    Type = "cash_reached",
    Threshold = 25000,
    Label = "earn $25,000", -- shown in UI / toasts
}
ReferralConfig.CheckInterval = 20 -- s between server-side milestone checks for referred players

-- ── The INVITE BOOST: +PerInvitePct income per QUALIFIED friend, clamped to CapPct, then registered
-- in the benefit registry (which further clamps the TOTAL of all sources to the global income cap). ──
ReferralConfig.Boost = {
    PerInvitePct = 5, -- +5% income per qualified friend
    CapPct = 100, -- the invite boost alone never exceeds +100%
}

-- ── Inviter TIER rewards at qualified-friend milestones (granted once each, idempotently) ────
ReferralConfig.Tiers = {
    { Count = 1, Reward = { Cash = 10000 }, Title = "First Friend" },
    { Count = 5, Reward = { Cash = 75000 }, Title = "Connector" },
    { Count = 10, Reward = { Cash = 300000 }, Title = "Influencer" },
    { Count = 25, Reward = { Cash = 1500000 }, Title = "Ambassador" },
    { Count = 50, Reward = { Cash = 7500000 }, Title = "Legend" },
}

-- The invite-boost percentage for a given qualified-friend count (clamped to the cap).
function ReferralConfig.BoostPct(count)
    return math.min((count or 0) * ReferralConfig.Boost.PerInvitePct, ReferralConfig.Boost.CapPct)
end

-- The highest tier whose Count <= count (for "next tier" UI), or nil.
function ReferralConfig.NextTier(count)
    for _, tier in ipairs(ReferralConfig.Tiers) do
        if (count or 0) < tier.Count then
            return tier
        end
    end
    return nil
end

return ReferralConfig
