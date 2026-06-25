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
local Analytics = require(script.Parent.Analytics)
local EventService = require(script.Parent.EventService)

local IncomeService = {}

local PUSH_INTERVAL = 0.1 -- seconds between display refreshes (~10 Hz)
local ANALYTICS_FLUSH = 60 -- seconds between aggregated income economy-source logs (NOT per frame)
local connection = nil
local pushAccum = 0
local flushAccum = 0
local earned = {} -- [Player] = cash earned since the last analytics flush (aggregated, not logged per frame)

-- Logs (and resets) a player's accumulated income as one economy SOURCE event. Called on the
-- throttled flush tick and on leave, so analytics stays well under per-call frequency limits.
function IncomeService.FlushAnalytics(player)
    local amount = earned[player]
    if amount ~= nil and amount > 0 then
        local profile = ProfileManager.GetProfile(player)
        local balance = profile ~= nil and profile.Data.Cash or amount
        Analytics.economySource(player, amount, balance, Analytics.Tx.Gameplay)
        EventService.Signal(player, "EARN_CASH", amount) -- feed "earn N cash" event quests
    end
    earned[player] = nil
end

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

        flushAccum += deltaTime
        local flushNow = flushAccum >= ANALYTICS_FLUSH
        if flushNow then
            flushAccum = 0
        end

        for _, player in ipairs(Players:GetPlayers()) do
            local profile = ProfileManager.GetProfile(player)
            if profile ~= nil then
                -- PERF: base rate is cached (recomputed only on roster/multiplier change), so this
                -- is O(players) per frame, not O(brainrots). The multiplier is read live so a
                -- benefit change (e.g. 2x Cash) takes effect immediately. All cash flows through
                -- the single guarded accessor -> never negative, never NaN/inf.
                -- prestige is a SEPARATE multiplicative axis OUTSIDE the global cap (see RebirthConfig).
                local prestige = profile.Data.PrestigeMultiplier or 1
                local rate = PlayerStats.GetBaseRate(player)
                    * Benefits.GetIncomeMultiplier(player)
                    * prestige
                if rate > 0 then
                    local gained = rate * deltaTime
                    ProfileManager.AddCash(player, gained)
                    earned[player] = (earned[player] or 0) + gained -- aggregate for analytics
                end
                if pushNow then
                    Leaderstats.Update(player, profile)
                    PlayerStats.PushCash(player, profile)
                end
                if flushNow then
                    IncomeService.FlushAnalytics(player)
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
