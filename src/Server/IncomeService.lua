-- IncomeService: the server-authoritative income loop. Runs on Heartbeat with a
-- delta-time accumulator so cash accrues smoothly and -- critically -- keeps accruing
-- while a player is AFK, because it lives entirely on the server. Nothing here trusts
-- or waits on the client.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProfileManager = require(script.Parent.ProfileManager)
local Leaderstats = require(script.Parent.Leaderstats)

local IncomeService = {}

local connection = nil

function IncomeService.Start()
    if connection ~= nil then
        return
    end

    connection = RunService.Heartbeat:Connect(function(deltaTime)
        for _, player in ipairs(Players:GetPlayers()) do
            local profile = ProfileManager.GetProfile(player)
            if profile ~= nil then
                local ratePerSec = 0
                for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
                    ratePerSec += brainrot.IncomePerSec
                end
                if ratePerSec > 0 then
                    profile.Data.Cash += ratePerSec * deltaTime
                end
                Leaderstats.Update(player, profile)
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
