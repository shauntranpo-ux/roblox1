-- Audio: swappable Sound asset IDs for the optional background music + SFX juice. ALL audio IDs
-- live here (IP-safe -- no hardcoded copyrighted audio anywhere in logic). A 0 means "no asset":
-- the client skips that sound SILENTLY, so the game is fully playable with none filled in.
--
-- To use your own / licensed audio: paste the numeric asset id (the number from
-- "rbxassetid://12345" -> 12345). Music plays only when the player's Music setting is on.

local Audio = {}

Audio.MusicId = 0 -- looping background track (optional)
Audio.MusicVolume = 0.3
Audio.SfxVolume = 0.5

-- Keyed by the juice cues the client raises (see UI/Effects). Fill any you have an asset for.
Audio.Sfx = {
    buy = 0, -- bought a brainrot
    deposit = 0, -- deposited a stolen unit
    steal = 0, -- you stole one
    robbed = 0, -- you got robbed
    milestone = 0, -- cash crossed a milestone
}

return Audio
