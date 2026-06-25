-- GameInfo: the single build/version constant + the player-facing changelog. Bump Version on
-- every update; the server shows the "What's New" card once per player per new Version (a saved
-- LastSeenVersion flag). This is the vehicle for announcing new codes/content that drive return
-- visits -- so put the LIVE CODES right in the changelog each update.

local GameInfo = {}

GameInfo.Version = "1.0.0"

-- Shown once when a player first sees a new Version. Keep it short + lead with the active code(s).
GameInfo.Changelog = table.concat({
    "🎉 Welcome! The game is LIVE.",
    "",
    "🎁 Use code  LAUNCH  for free cash!",
    "⚡ Use code  BOOST2X  for 2x cash for 10 minutes!",
    "",
    "Steal brainrots, get rich, climb the boards. More codes every update — come back soon!",
}, "\n")

return GameInfo
