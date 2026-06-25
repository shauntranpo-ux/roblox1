-- AudioManager (M12.4): the ONE client audio system (it absorbs the theme pass's UI-sound helper --
-- Effects.playSfx now delegates here). Owns four SoundGroup BUSES (Music / Ambience / Sfx / UI) whose
-- volumes/mutes come from the player's persisted settings; crossfades MUSIC + AMBIENCE per biome (via
-- the existing CurrentBiome zone hook), swaps to a boss track during a fight, plays POOLED + CAPPED
-- moment stingers (ducking the music under big ones), and degrades GRACEFULLY -- a missing asset id is
-- simply silent, no error. PURE CLIENT-SIDE PRESENTATION: it only reacts to replicated state/events
-- and never touches gameplay/economy/server state.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))
local AudioConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AudioConfig"))

local AudioManager = {}

local initialized = false
local groups = {} -- [name] = SoundGroup
local stingerPool = {}
local stingerIdx = 0
local musicRef = { id = nil, sound = nil }
local ambienceRef = { id = nil, sound = nil }
local currentBiome = "hub"
local bossActive = false
local settings =
    { Music = false, SFX = true, MusicVolume = 0.5, SfxVolume = 0.7, AmbienceVolume = 0.5 }

local function makeGroup(name)
    local g = Instance.new("SoundGroup")
    g.Name = "Bus_" .. name
    g.Volume = 0
    g.Parent = SoundService
    groups[name] = g
    return g
end

-- ── Settings -> bus volumes (live). Music + Ambience share the Music mute; Sfx + UI share the SFX mute.
function AudioManager.applySettings(s)
    if type(s) == "table" then
        for k, v in pairs(s) do
            settings[k] = v
        end
    end
    if not initialized then
        return
    end
    local mix = AudioConfig.Mix
    local musicOn = settings.Music ~= false
    local sfxOn = settings.SFX ~= false
    local mv = tonumber(settings.MusicVolume) or 0.5
    local sv = tonumber(settings.SfxVolume) or 0.7
    local av = tonumber(settings.AmbienceVolume) or 0.5
    groups.Music.Volume = mix.MusicBase * mv * (musicOn and 1 or 0)
    groups.Ambience.Volume = mix.AmbienceBase * av * (musicOn and 1 or 0)
    groups.Sfx.Volume = mix.SfxBase * sv * (sfxOn and 1 or 0)
    groups.UI.Volume = mix.UiBase * sv * (sfxOn and 1 or 0)
end

-- ── Crossfade a looping bed (music/ambience) to a new asset id (0/nil -> fade to silence) ───
local function crossfade(ref, group, newId)
    newId = newId or 0
    if ref.id == newId then
        return
    end
    ref.id = newId
    local old = ref.sound
    ref.sound = nil
    if old ~= nil then
        local fade =
            TweenService:Create(old, TweenInfo.new(AudioConfig.Mix.Crossfade), { Volume = 0 })
        fade.Completed:Once(function()
            old:Destroy()
        end)
        fade:Play()
    end
    if newId ~= 0 then
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://" .. tostring(newId)
        s.Looped = true
        s.Volume = 0
        s.SoundGroup = group
        s.Parent = group
        s:Play() -- if the id is invalid/empty it just won't sound; no error
        TweenService:Create(s, TweenInfo.new(AudioConfig.Mix.Crossfade), { Volume = 1 }):Play()
        ref.sound = s
    end
end

local function duckMusic()
    local s = musicRef.sound
    if s == nil then
        return
    end
    local mix = AudioConfig.Mix
    TweenService:Create(s, TweenInfo.new(mix.DuckTime), { Volume = mix.DuckAmount }):Play()
    task.delay(mix.DuckHold, function()
        if musicRef.sound == s then
            TweenService:Create(s, TweenInfo.new(mix.DuckTime), { Volume = 1 }):Play()
        end
    end)
end

-- ── Zone music + ambience (driven by the CurrentBiome hook) ─────────────────────────────────
function AudioManager.setBiome(biomeId)
    if type(biomeId) ~= "string" then
        return
    end
    currentBiome = biomeId
    if not bossActive then
        crossfade(musicRef, groups.Music, AudioConfig.MusicFor(biomeId))
    end
    crossfade(ambienceRef, groups.Ambience, AudioConfig.AmbienceFor(biomeId))
end

-- Boss fight: swap to the boss track (if one exists -- else KEEP the zone music), restore on end.
function AudioManager.setBoss(on)
    if on == bossActive then
        return
    end
    bossActive = on
    if on then
        local bossId = AudioConfig.Music.boss or 0
        if bossId ~= 0 then
            crossfade(musicRef, groups.Music, bossId)
        end
    else
        crossfade(musicRef, groups.Music, AudioConfig.MusicFor(currentBiome))
    end
end

-- ── Pooled, capped moment stingers (Effects.playSfx delegates here) ─────────────────────────
function AudioManager.playSfx(key)
    if not initialized then
        return
    end
    local id = Audio.Sfx[key]
    if id == nil or id == 0 then
        return -- no asset -> silent, no error
    end
    local isUi = AudioConfig.UiKeys[key] == true
    if isUi and settings.SFX == false then
        return
    end
    stingerIdx = stingerIdx % AudioConfig.Mix.StingerCap + 1
    local sound = stingerPool[stingerIdx] -- recycled (round-robin; cap enforced)
    sound.SoundGroup = isUi and groups.UI or groups.Sfx
    sound.SoundId = "rbxassetid://" .. tostring(id)
    sound:Play()
    if AudioConfig.DuckKeys[key] then
        duckMusic()
    end
end

function AudioManager.mount(context)
    if initialized then
        return
    end
    local player = context.player or Players.LocalPlayer
    makeGroup("Music")
    makeGroup("Ambience")
    makeGroup("Sfx")
    makeGroup("UI")
    for _ = 1, AudioConfig.Mix.StingerCap do
        local s = Instance.new("Sound")
        s.Volume = 1
        s.SoundGroup = groups.Sfx
        s.Parent = groups.Sfx
        table.insert(stingerPool, s)
    end
    initialized = true

    -- Initial settings (saved prefs) so audio reflects them before the Settings panel is opened.
    local ok, saved = pcall(function()
        return context.remotes.GetSettings:InvokeServer()
    end)
    AudioManager.applySettings(ok and saved or nil)

    -- Zone hook: the server publishes CurrentBiome (M10.2); crossfade on change.
    player:GetAttributeChangedSignal("CurrentBiome"):Connect(function()
        local id = player:GetAttribute("CurrentBiome")
        if type(id) == "string" then
            AudioManager.setBiome(id)
        end
    end)
    local startBiome = player:GetAttribute("CurrentBiome")
    AudioManager.setBiome(type(startBiome) == "string" and startBiome or "hub")

    -- Boss track swap (reinforces the alert). Guarded: no boss track -> keeps the zone music.
    if context.remotes.BossUpdate ~= nil then
        context.remotes.BossUpdate.OnClientEvent:Connect(function(payload)
            if type(payload) ~= "table" then
                return
            end
            if payload.Kind == "spawn" then
                AudioManager.setBoss(true)
            elseif payload.Kind == "defeat" or payload.Kind == "flee" or payload.Kind == "gone" then
                AudioManager.setBoss(false)
            end
        end)
    end
end

return AudioManager
