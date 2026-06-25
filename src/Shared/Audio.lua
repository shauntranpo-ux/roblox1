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

-- ===========================================================================================
-- THE SOUND TABLE. Paste Roblox Marketplace audio asset IDs here (the number from
-- "rbxassetid://12345" -> 12345). A 0 stays SILENT. This is the ONE place to wire SFX.
-- The UI-feedback sounds (added for the restyle) are at the top; gameplay cues below.
-- ===========================================================================================
Audio.Sfx = {
    -- UI FEEDBACK (the click-juice pass). SOURCE A SOFT/LOW BUBBLE-POP for `click` (NOT high-pitched).
    click = 0, -- <<< subtle bubble-pop on any button press (the headline one)
    purchase = 0, -- <<< cha-ching on a successful buy
    open = 0, -- <<< panel open
    close = 0, -- <<< panel close
    tab = 0, -- <<< tab / pill switch
    error = 0, -- <<< rejected action
    -- GAMEPLAY CUES (existing).
    buy = 0, -- bought a brainrot
    deposit = 0, -- deposited a stolen unit
    steal = 0, -- you stole one
    robbed = 0, -- you got robbed
    milestone = 0, -- cash crossed a milestone
}

return Audio
