-- TextFilter (M13.4): the SINGLE helper every piece of user-authored display text routes through.
-- TextService:FilterStringAsync runs SERVER-SIDE only (a client cannot be trusted to filter), so this
-- module owns all filtering and the rest of the game asks it for a safe string. Every call is
-- pcall-wrapped and YIELDS (the API is async), and on ANY failure it FAILS SAFE (never returns the
-- raw text for genuinely user-authored free text).
--
-- ============================  TWO CLASSES OF TEXT  =========================================
-- 1. FREE TEXT a player typed (a REPORT reason, an admin ANNOUNCE): FilterForBroadcast / FilterForUser.
--    On filter failure these return a PLACEHOLDER ("[hidden]") -- NEVER the raw string. This is the
--    strict "no user-authored text renders unfiltered, fail safe" guarantee.
-- 2. NAMES (display names on nameplates / leaderboards / kill-feed): PublishName stamps a filtered
--    "SafeName" attribute the client reads instead of the raw name. Names are ALSO pre-moderated by
--    Roblox's account system, so on a transient filter failure PublishName falls back to the player's
--    (already-moderated) name rather than hiding everyone's name on an API blip -- a documented, safe
--    exception that applies ONLY to this pre-moderated class, never to free text.
-- ===========================================================================================

local TextService = game:GetService("TextService")

local TextFilter = {}

local PLACEHOLDER = "[hidden]" -- shown when free text can't be filtered (fail-safe; never raw)
local MAX_LEN = 200 -- hard cap before filtering (defends against huge payloads)

-- Filters `text` (authored by `fromUserId`) for a BROADCAST audience (everyone sees the same result).
-- Returns (ok, safeText). ok=false + PLACEHOLDER on empty/invalid input or any API failure.
function TextFilter.FilterForBroadcast(text, fromUserId)
    if type(text) ~= "string" then
        return false, PLACEHOLDER
    end
    text = text:sub(1, MAX_LEN)
    if text:gsub("%s", "") == "" then
        return false, PLACEHOLDER -- whitespace-only -> nothing to show
    end
    local ok, result = pcall(function()
        local obj = TextService:FilterStringAsync(text, fromUserId)
        return obj:GetNonChatStringForBroadcastAsync()
    end)
    if not ok or type(result) ~= "string" or result == "" then
        return false, PLACEHOLDER
    end
    return true, result
end

-- Filters `text` for a SINGLE viewer (per-viewer filtering -- e.g. an admin reading a report). Returns
-- (ok, safeText); same fail-safe placeholder behavior.
function TextFilter.FilterForUser(text, fromUserId, toUserId)
    if type(text) ~= "string" then
        return false, PLACEHOLDER
    end
    text = text:sub(1, MAX_LEN)
    if text:gsub("%s", "") == "" then
        return false, PLACEHOLDER
    end
    local ok, result = pcall(function()
        local obj = TextService:FilterStringAsync(text, fromUserId)
        return obj:GetNonChatStringForUserAsync(toUserId)
    end)
    if not ok or type(result) ~= "string" or result == "" then
        return false, PLACEHOLDER
    end
    return true, result
end

-- Stamps a filtered "SafeName" attribute on the player that client name displays read instead of the
-- raw name. Yields (filters once per join). On a transient filter failure, falls back to the player's
-- already-Roblox-moderated name (documented exception for this pre-moderated class -- see header).
function TextFilter.PublishName(player)
    if player == nil or player.Parent == nil then
        return
    end
    local ok, safe = TextFilter.FilterForBroadcast(player.DisplayName, player.UserId)
    if player.Parent == nil then
        return -- left mid-filter
    end
    if ok then
        player:SetAttribute("SafeName", safe)
    else
        -- Filter API blipped: names are pre-moderated by Roblox, so the raw name is safe to show and
        -- preferable to hiding every player's name. This fallback is NEVER used for free text.
        player:SetAttribute("SafeName", player.DisplayName)
    end
end

-- The canonical "name to display" for a player: the filtered SafeName if published, else the
-- (pre-moderated) display name. Server-side convenience for building broadcast payloads.
function TextFilter.NameFor(player)
    if player == nil then
        return "?"
    end
    return player:GetAttribute("SafeName") or player.DisplayName
end

return TextFilter
