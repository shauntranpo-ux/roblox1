-- SlingshotConfig (M-map): tunables for the SLINGSHOT travel mechanic. The slingshot flings the player
-- on a ballistic arc to a chosen UNLOCKED biome instead of a long walk (NOT a teleport). The server
-- validates the destination is unlocked + returns the landing point; the client applies the launch to
-- its OWN character (Roblox owns local character physics). Pure config -- no gameplay/economy state.

local SlingshotConfig = {}

SlingshotConfig.FlightTime = 1.7 -- seconds the arc takes to reach the target (drives the launch velocity)
SlingshotConfig.Cooldown = 3 -- seconds between launches (server-enforced, anti-spam)
SlingshotConfig.LandingHeight = 6 -- studs above the biome ground center to aim for (land ON the ground)
SlingshotConfig.MaxFlightTime = 4 -- safety clamp so a far biome can't compute an absurd velocity

return SlingshotConfig
