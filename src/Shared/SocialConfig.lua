-- SocialConfig (M13.3): THE single source of truth for friends & social play -- GIFTING rules
-- (rate-limit + anti-abuse gates + daily cap + what's giftable), and VIP / PRIVATE-server PERKS
-- (a capped income boost for players in a private server, + an owner bonus). Every number here,
-- documented. Gifting reuses the trade atomic transfer; the boost registers in the benefit registry.

local SocialConfig = {}

-- ── GIFTING (one-directional give; reuses the dupe-proof trade transfer) ─────────────────────
SocialConfig.Gift = {
    Cooldown = 3, -- s between a sender's gifts (server rate-limit)
    -- ANTI FRESH-ALT FUNNELING: the SENDER's Roblox account must be at least this old. A throwaway
    -- alt (made to funnel its starter unit to a main) can't gift until it ages in -> the cheap
    -- alt-farm is blocked. (Combined with RequireFriendship + the daily cap.)
    MinSenderAccountAgeDays = 7,
    DailyCap = 10, -- max gifts ONE sender can send per server-day (resets at the day boundary)
    RequireFriendship = true, -- the recipient must be the sender's Roblox friend (anti-random-abuse)
    -- Giftable = a tradeable unit that is NOT locked / favorited / equipped / in-transit / in-trade
    -- (all re-checked server-side by TradeService.GiftUnit -- this is just the documented rule).
}

-- ── VIP / PRIVATE SERVER perks (server-side detection; idempotent + capped benefit source) ──
SocialConfig.Vip = {
    IncomeBoost = 0.5, -- +50% income for ANY player in a private/VIP server
    OwnerBonus = 0.25, -- an additional +25% for the VIP server's OWNER (PrivateServerOwnerId)
    CapPct = 100, -- the vip-server source alone never exceeds +100% (the registry also caps the total)
}

-- Set a VIP / Private Server PRICE on the Creator Dashboard (Experience -> Monetization -> Private
-- Servers) so Roblox handles the recurring Robux purchase + ownership; this code reads
-- game.PrivateServerId / game.PrivateServerOwnerId and grants the perks above. No price is set in code.
SocialConfig.PrivateServerNote =
    "Enable + price Private Servers on the Creator Dashboard; Roblox handles the recurring Robux."

-- ── Daily-cap period (server time; cross-server consistent) ──────────────────────────────────
SocialConfig.DayLength = 86400
SocialConfig.DayEpoch = 0

function SocialConfig.CurrentDay(t)
    return math.floor((t - SocialConfig.DayEpoch) / SocialConfig.DayLength)
end

return SocialConfig
