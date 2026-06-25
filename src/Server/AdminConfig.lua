-- AdminConfig (M13.4): the SINGLE, SERVER-ONLY source of admin AUTHORITY. It lives under
-- ServerScriptService and is NEVER replicated, so a client can neither read the allowlist nor flip a
-- tier -- authority can only ever be asserted by the server. This is the locked allowlist that
-- CONSOLIDATES the old DevCommands admin check: DevCommands.isAdmin + AdminService both authorize
-- through here, so there is exactly ONE allowlist in the codebase (no parallel admin code).
--
-- ============================  HOW AUTHORITY WORKS  =========================================
-- Three TIERS, ranked Owner(3) > Admin(2) > Mod(1). A userId's tier comes from:
--   1. Studio test           -> Owner   (your private test environment)
--   2. the place's CREATOR    -> Owner   (a user-owned experience; you)
--   3. the explicit ID lists  -> Owner / Admin / Mod
-- Every command has a MINIMUM tier (Commands below). AdminConfig.Can(userId, command) is the gate
-- EVERY admin action re-checks SERVER-SIDE on execution. The client showing a button means nothing.
--
-- TO GRANT ADMINS: paste Roblox UserIds into Owners / Admins / Mods. To change what a tier may run,
-- edit Commands (the value is the minimum tier). Nothing here is reachable from a client.
-- ===========================================================================================

local RunService = game:GetService("RunService")

local AdminConfig = {}

-- Tier ranks (higher = more authority). Used for both "may run command" and "may target" checks.
AdminConfig.Rank = {
    Mod = 1,
    Admin = 2,
    Owner = 3,
}

-- ===========================================================================================
-- THE LOCKED ALLOWLIST. Paste Roblox UserIds as keys (value = true). Server-only.
-- ===========================================================================================
local Owners = {
    -- [123456789] = true,  -- example: your Roblox UserId (the place creator is ALSO auto-Owner)
}
local Admins = {
    -- [223456789] = true,
}
local Mods = {
    -- [323456789] = true,
}

-- Builder/owner USERNAMES granted Owner tier + a BYPASS of all biome-level locks (matched by name so you
-- don't need the UserId). Lowercase. The elevator + biome routing treat these players as fully unlocked.
local OwnerNames = {
    ["kaapv"] = true,
}

-- ===========================================================================================
-- PER-COMMAND minimum tier. Editing this is how you re-scope what each tier may do.
-- ===========================================================================================
AdminConfig.Commands = {
    -- moderation
    kick = "Mod",
    mute = "Mod",
    unmute = "Mod",
    -- (submitting a report needs NO tier -- it goes through Remotes.ReportPlayer; admins VIEW reports
    --  via the "get" log below.)
    -- movement
    tp = "Mod",
    bring = "Mod",
    -- economy / support (route through the guarded accessors + factory)
    give = "Admin",
    givecash = "Admin",
    clear = "Admin", -- clear a player's PLACED units (support; does not touch cash)
    -- bans
    ban = "Admin",
    unban = "Admin",
    -- ops (reuse the existing engines)
    announce = "Admin",
    boss = "Admin",
    event = "Admin",
    season = "Owner", -- irreversible season rollover -> Owner only
    -- panel data
    get = "Mod",
}

-- Returns "Owner" | "Admin" | "Mod" | nil for a userId. Studio + the place creator are auto-Owner.
function AdminConfig.GetTier(userId)
    if RunService:IsStudio() then
        return "Owner" -- your private test environment is always full authority
    end
    if Owners[userId] then
        return "Owner"
    end
    -- A user-owned experience: the creator is always an Owner-tier admin.
    if game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId then
        return "Owner"
    end
    if Admins[userId] then
        return "Admin"
    end
    if Mods[userId] then
        return "Mod"
    end
    return nil
end

-- Numeric rank for a userId (0 if not an admin). Used to stop a lower tier from targeting a higher one.
function AdminConfig.RankOf(userId)
    local tier = AdminConfig.GetTier(userId)
    return tier ~= nil and AdminConfig.Rank[tier] or 0
end

-- The authority gate EVERY admin command re-checks server-side: may `userId` run `command`?
function AdminConfig.Can(userId, command)
    local minTier = AdminConfig.Commands[command]
    if minTier == nil then
        return false -- unknown command is never allowed
    end
    local tier = AdminConfig.GetTier(userId)
    if tier == nil then
        return false
    end
    return AdminConfig.Rank[tier] >= AdminConfig.Rank[minTier]
end

-- True if `userId` has ANY tier (used only to decide whether to surface the admin panel button).
function AdminConfig.IsAdmin(userId)
    return AdminConfig.GetTier(userId) ~= nil or false
end

-- True if this PLAYER is an OWNER (by username in OwnerNames, or Owner-tier by UserId). Used to BYPASS
-- all biome-level locks (the builder/owner reaches every level) + to surface the admin panel for them.
function AdminConfig.IsOwnerPlayer(player)
    if player == nil then
        return false
    end
    if OwnerNames[string.lower(player.Name)] then
        return true
    end
    return AdminConfig.GetTier(player.UserId) == "Owner"
end

return AdminConfig
