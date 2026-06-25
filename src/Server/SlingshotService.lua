-- SlingshotService (M-map): server half of the SLINGSHOT. It owns the AUTHORITY (which biome you may be
-- flung to) + the landing point; the client owns the launch PHYSICS on its own character. "get" returns
-- the biome list + per-biome unlock state (for the menu); "launch" validates the destination is unlocked
-- (reusing BiomeService.IsUnlocked -- one unlock authority), rate-limits, and returns the world landing
-- point + flight time. Flinging to a locked biome is refused; even if a hacked client self-flings,
-- BiomeService's rarity ROUTING still gates rewards by unlock (not position), so it is never an exploit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local BiomeConfig = require(ReplicatedStorage.Shared.BiomeConfig)
local SlingshotConfig = require(ReplicatedStorage.Shared.SlingshotConfig)

local BiomeService = require(script.Parent.BiomeService)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)

local SlingshotService = {}

-- The ordered biome list + this player's unlock state, for the menu.
local function listFor(player)
    local out = {}
    for _, b in ipairs(BiomeConfig.Ladder) do
        local worldBiome = WorldConfig.Get(b.BiomeId)
        table.insert(out, {
            BiomeId = b.BiomeId,
            Name = b.Name,
            Tier = worldBiome ~= nil and worldBiome.Tier or 0,
            Unlocked = BiomeService.IsUnlocked(player, b.BiomeId),
        })
    end
    return out
end

local function handleLaunch(player, biomeId)
    if not RateLimiter.check(player, "slingshot", SlingshotConfig.Cooldown) then
        return { Result = "Error", Message = "Reloading the slingshot..." }
    end
    if type(biomeId) ~= "string" or BiomeConfig.Get(biomeId) == nil then
        return { Result = "Error", Message = "Unknown destination." }
    end
    if not BiomeService.IsUnlocked(player, biomeId) then
        return { Result = "Error", Message = "Unlock that biome first!" }
    end
    local worldBiome = WorldConfig.Get(biomeId)
    if worldBiome == nil then
        return { Result = "Error", Message = "That biome has no location." }
    end
    Analytics.custom(player, Analytics.Events.SlingshotLaunch, worldBiome.Tier or 0)
    return {
        Result = "Success",
        -- ELEVATOR: ride the player UP to the chosen LEVEL platform (the world is a vertical stack now;
        -- the old slingshot landed at a ground 'Center'). LevelLanding gives the platform drop-off point.
        Target = WorldConfig.LevelLanding(biomeId)
            + Vector3.new(0, SlingshotConfig.LandingHeight, 0),
        FlightTime = SlingshotConfig.FlightTime,
    }
end

function SlingshotService.Init()
    Remotes.SlingshotAction.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return { Result = "Error", Message = "Invalid request." }
        end
        if payload.Action == "get" then
            return { Result = "Success", Biomes = listFor(player) }
        elseif payload.Action == "launch" then
            return handleLaunch(player, payload.BiomeId)
        end
        return { Result = "Error", Message = "Unknown action." }
    end
end

return SlingshotService
