-- AudioConfig (M12.4): THE single source of truth for MUSIC tracks + AMBIENCE beds + the mix. Every
-- id is a dev-supplied SWAP POINT; a 0 means "no asset" -> that channel stays SILENT with no error, so
-- the whole audio system runs perfectly (silent) until ids are pasted in. Moment STINGERS reuse the
-- existing Shared/Audio.Sfx table (catch / boss / level-up / sale / combat) -- not duplicated here.
-- Audio is PURE CLIENT-SIDE PRESENTATION: nothing here touches gameplay/economy/server state.

local AudioConfig = {}

-- MUSIC: the hub theme, one track per biome id (M10.2), + an optional boss-fight track. Paste the
-- numeric asset id (from rbxassetid://NNN -> NNN). 0 = silent (keeps the prior track / silence).
AudioConfig.Music = {
    hub = 0, -- <<< default / spawn theme
    sunny_meadow = 0, -- <<< per-biome tracks (keys = biome ids)
    sundae_shores = 0,
    croco_swamp = 0,
    magma_peak = 0,
    cosmic_rift = 0,
    the_void = 0,
    boss = 0, -- <<< world-boss fight track (swaps in during a boss, restores after)
}

-- AMBIENCE beds per biome (meadow birds, beach waves, swamp insects, volcano rumble, cosmic hum,
-- void drone). 0 = silent.
AudioConfig.Ambience = {
    sunny_meadow = 0,
    sundae_shores = 0,
    croco_swamp = 0,
    magma_peak = 0,
    cosmic_rift = 0,
    the_void = 0,
}

-- Global mix defaults (the player's settings scale these live). Crossfade/duck are in seconds/fraction.
AudioConfig.Mix = {
    MusicBase = 0.5, -- base music bus volume (x the player's MusicVolume setting)
    AmbienceBase = 0.6, -- base ambience bus volume (x MusicVolume; shares the music mute)
    SfxBase = 1.0, -- base sfx/stinger bus volume (x SfxVolume)
    UiBase = 0.8, -- base UI-click bus volume (x SfxVolume; shares the sfx mute)
    Crossfade = 1.5, -- s music/ambience crossfade on a zone change
    DuckAmount = 0.55, -- music drops to this fraction briefly under a big stinger
    DuckTime = 0.18, -- s to duck down
    DuckHold = 0.6, -- s before restoring
    StingerCap = 8, -- max concurrent pooled stinger Sounds (perf guard in crowded moments)
}

-- These Audio.Sfx keys route to the UI bus (so the SFX setting/mute governs them); all others -> Sfx.
AudioConfig.UiKeys = {
    click = true,
    open = true,
    close = true,
    tab = true,
    error = true,
    purchase = true,
}

-- Stingers that DUCK the music briefly (big moments). Others play without ducking.
AudioConfig.DuckKeys = {
    catch_rare = true,
    boss_death = true,
    milestone = true,
}

function AudioConfig.MusicFor(biomeId)
    return AudioConfig.Music[biomeId] or AudioConfig.Music.hub or 0
end

function AudioConfig.AmbienceFor(biomeId)
    return AudioConfig.Ambience[biomeId] or 0
end

return AudioConfig
