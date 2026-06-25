-- DevConfig: SERVER-ONLY debug switches. This module lives under ServerScriptService and is
-- never replicated, so the client can neither read nor flip it.
--
-- SIM MODE lets you, in Studio, exercise the WHOLE monetization stack WITHOUT spending Robux
-- or publishing: simulate owning any gamepass, fire any developer-product grant through the
-- real receipt codepath, and read leaderboards from the in-memory fallback. It mirrors the
-- existing ProfileStore MOCK pattern (real path when published, sim path in Studio).
--
-- =========================  HARD SAFETY GUARANTEE  =========================================
-- SimMode can NEVER be true on a live (published) server:
--   * SIM_REQUESTED defaults to false (safe to ship as-is), AND
--   * even if SIM_REQUESTED is left true, SimMode is ANDed with RunService:IsStudio(), so a
--     real server forces it OFF and logs loudly.
-- To test in Studio: set SIM_REQUESTED = true (this one line), then set it back to false
-- before publishing. (Publishing with it true is still safe -- it is forced off on the live
-- server -- but keep it false so intent is clear.)
-- ===========================================================================================

local RunService = game:GetService("RunService")

local DevConfig = {}

-- >>> THE ONLY LINE YOU TOUCH FOR TESTING <<<  (true = simulate purchases in Studio)
local SIM_REQUESTED = false

-- Guard: sim is permitted ONLY inside Studio. Anywhere else it is forced off.
DevConfig.SimMode = SIM_REQUESTED and RunService:IsStudio()

if SIM_REQUESTED and not RunService:IsStudio() then
    -- Should be impossible to reach on a published server with SIM_REQUESTED=false, but if the
    -- flag was shipped true this makes the misconfiguration impossible to miss in the logs.
    warn(
        "[DevConfig] SIM mode was REQUESTED but this is a LIVE server -> FORCING SIM OFF. "
            .. "Real Robux + ProcessReceipt + OrderedDataStore are in use."
    )
end

return DevConfig
