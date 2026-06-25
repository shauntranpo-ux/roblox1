-- IncomeService: the server-authoritative income loop. Runs on Heartbeat with a
-- delta-time accumulator so cash accrues smoothly and -- critically -- keeps accruing
-- while a player is AFK, because it lives entirely on the server. Nothing here trusts
-- or waits on the client.
--
-- Cash is summed every frame for accuracy, but the replicated display values
-- (leaderstats IntValue + HUD attributes) are refreshed at a throttled rate to keep
-- network traffic light.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProfileManager = require(script.Parent.ProfileManager)
local Leaderstats = require(script.Parent.Leaderstats)
local PlayerStats = require(script.Parent.PlayerStats)
local Benefits = require(script.Parent.Benefits)

local IncomeService = {}

local PUSH_INTERVAL = 0.1 -- seconds between display refreshes (~10 Hz)
local connection = nil
local pushAccum = 0

function IncomeService.Start()
    if connection ~= nil then
        return
    end

    connection = RunService.Heartbeat:Connect(function(deltaTime)
        pushAccum += deltaTime
        local pushNow = pushAccum >= PUSH_INTERVAL
        if pushNow then
            pushAccum = 0
        end

        for _, player in ipairs(Players:GetPlayers()) do
            local profile = ProfileManager.GetProfile(player)
            if profile ~= nil then
                -- PERF: base rate is cached (recomputed only on roster/multiplier change), so this
                -- is O(players) per frame, not O(brainrots). The multiplier is read live so a
                -- benefit change (e.g. 2x Cash) takes effect immediately. All cash flows through
                -- the single guarded accessor -> never negative, never NaN/inf.
                local rate = PlayerStats.GetBaseRate(player) * Benefits.GetIncomeMultiplier(player)
                if rate > 0 then
                    ProfileManager.AddCash(player, rate * deltaTime)
                end
                if pushNow then
                    Leaderstats.Update(player, profile)
                    PlayerStats.PushCash(player, profile)
                end
            end
        end
    end)
end

function IncomeService.Stop()
    if connection ~= nil then
        connection:Disconnect()
        connection = nil
    end
end

return IncomeService
