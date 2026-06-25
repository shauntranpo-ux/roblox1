-- DevConfig: SERVER-ONLY debug switches. This module lives under ServerScriptService and is
-- never replicated, so the client can neither read nor flip it.
--
-- SIM MODE lets you exercise the WHOLE monetization stack in Studio WITHOUT spending Robux or
-- publishing: simulate owning any gamepass, fire any developer-product grant through the REAL
-- receipt codepath, and read leaderboards from the in-memory fallback. It mirrors the existing
-- ProfileStore MOCK pattern (real path when published, sim path in Studio).
--
-- =========================  HARD SAFETY GUARANTEE  =========================================
-- SIM can NEVER be on in production: SimMode is gated on RunService:IsStudio(), so a live
-- (published) server ALWAYS has it OFF and uses real MarketplaceService / ProcessReceipt /
-- OrderedDataStore. There is nothing to remember to switch off before publishing.
--
-- By DEFAULT SIM auto-enables in Studio so the monetization shop populates and is testable the
-- moment you press Play. Set ALLOW_SIM_IN_STUDIO = false to instead test the REAL marketplace
-- path inside Studio (needs a published place + Game Settings > Security > Enable Studio Access
-- to API Services).
-- ===========================================================================================

local RunService = game:GetService("RunService")

local DevConfig = {}

-- Set false to test the REAL marketplace path inside Studio instead of simulating.
local ALLOW_SIM_IN_STUDIO = true

-- SimMode is only ever true inside Studio. On a live server IsStudio() is false, so SIM is off.
DevConfig.SimMode = ALLOW_SIM_IN_STUDIO and RunService:IsStudio()

return DevConfig
