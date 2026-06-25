-- TutorialService: drives the one-time, first-session onboarding flow.
--
-- TRUST BOUNDARY (Tutorial): the client may only send "ready" (I've mounted, am I new?),
-- "done", or "skip". It can grant NOTHING -- the server owns the saved TutorialDone flag and only
-- ever sets it true. The client drives the "ready" handshake so the server's "start" signal can
-- never be fired before the client is listening (no lost-event race). Rate-limited + idempotent.

local Remotes = require(script.Parent.Remotes)
local ProfileManager = require(script.Parent.ProfileManager)
local RateLimiter = require(script.Parent.RateLimiter)
local DevConfig = require(script.Parent.DevConfig)

local TutorialService = {}

local function onClientEvent(player, action)
    if type(action) ~= "string" then
        return
    end
    if not RateLimiter.check(player, "tutorial", 0.5) then
        return
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    if action == "ready" then
        -- Client is listening + the profile is loaded -> give a DEFINITIVE answer so the client
        -- stops its retry loop: "start" for brand-new players, "none" for returning players.
        if profile.Data.TutorialDone then
            Remotes.Tutorial:FireClient(player, "none")
        else
            Remotes.StartTutorial(player)
        end
    elseif action == "done" or action == "skip" then
        profile.Data.TutorialDone = true -- runs once ever; returning players never see it again
    end
end

-- DEV/TEST (SIM only, Studio): reset a player's tutorial so it re-runs. Command bar:
--   require(game.ServerScriptService.Server.TutorialService).ResetForTesting(game.Players.YOURNAME)
function TutorialService.ResetForTesting(player)
    if not DevConfig.SimMode then
        warn("[Tutorial] ResetForTesting ignored -- SIM mode is OFF.")
        return
    end
    local profile = ProfileManager.GetProfile(player)
    if profile ~= nil then
        profile.Data.TutorialDone = false
        Remotes.StartTutorial(player)
    end
end

function TutorialService.Init()
    Remotes.Tutorial.OnServerEvent:Connect(onClientEvent)
end

return TutorialService
