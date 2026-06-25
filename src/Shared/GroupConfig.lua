-- GroupConfig (M13.6): the Roblox GROUP hook -- the group to check membership against + the one-time
-- member reward (or a capped passive perk) + the rank gate. Server-authoritative + idempotent; this is
-- ONLY config (the grant + claim live in GroupRewardService).
--
-- ============================  SET THIS UP  =================================================
-- 1. GroupId: paste your Roblox group's id (0 = the whole feature is OFF -> no checks, UI shows it's
--    not configured). 2. MinRank: 0 = any member qualifies; set a rank number to gate it. 3. Reward:
--    pick ONE Type and fill its field. "cash" + "unit" are ONE-TIME (persisted claim, kept even if the
--    player later leaves the group). "perk" is a LIVE passive income boost re-checked every join (it
--    applies only while the player is currently a member; it's capped by the benefit registry).
-- ===========================================================================================

local GroupConfig = {}

GroupConfig.GroupId = 0 -- <-- PASTE YOUR GROUP ID (0 = feature disabled)
GroupConfig.MinRank = 0 -- 0 = any member; else the minimum GetRankInGroup value required

-- The reward. Type is "cash" | "unit" | "perk".
GroupConfig.Reward = {
    Type = "cash",
    Cash = 5000, -- Type == "cash": one-time cash grant (via the guarded accessor)
    UnitId = "garama", -- Type == "unit": a Catalog id, granted via the factory (no-pad-safe), one-time
    PerkBonus = 0.05, -- Type == "perk": income bonus ABOVE 1.0 (0.05 = +5%), keyed + capped, membership-gated
}

-- Display / linking for the settings "Community" section.
GroupConfig.GroupName = "Our Group"
GroupConfig.GroupUrl = "https://www.roblox.com/communities/0" -- shown so members can find + join it
GroupConfig.PromptText = "Join our group for a reward!"

-- A short human-readable summary of the reward (shown in the UI). Kept in sync with Reward above.
function GroupConfig.RewardSummary()
    local r = GroupConfig.Reward
    if r.Type == "cash" then
        return "$" .. tostring(r.Cash) .. " cash"
    elseif r.Type == "unit" then
        return "a free " .. tostring(r.UnitId)
    elseif r.Type == "perk" then
        return "+"
            .. tostring(math.floor(r.PerkBonus * 100 + 0.5))
            .. "% income while you're a member"
    end
    return "a reward"
end

return GroupConfig
