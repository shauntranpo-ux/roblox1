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
local SeasonService = require(script.Parent.SeasonService)
local PerkEffects = require(script.Parent.PerkEffects)
local GameSignals = require(script.Parent.GameSignals) -- M12.1 quest observation bus
local Remotes = require(script.Parent.Remotes)

local IncomeService = {}

local PUSH_INTERVAL = 0.1 -- seconds between display refreshes (~10 Hz)
local ANALYTICS_FLUSH = 60 -- seconds between aggregated income economy-source logs (NOT per frame)
local connection = nil
local pushAccum = 0
local flushAccum = 0
local earned = {} -- [Player] = cash earned since the last analytics flush (aggregated, not logged per frame)
local sessionStart = {} -- [Player] = os.clock when first seen this session (M11.1 Hourglass ramp)
local meltdownAccum = {} -- [Player] = seconds toward the next Meltdown income crit (M11.1)

-- Logs (and resets) a player's accumulated income as one economy SOURCE event. Called on the
-- throttled flush tick and on leave, so analytics stays well under per-call frequency limits.
function IncomeService.FlushAnalytics(player)
    local amount = earned[player]
    if amount ~= nil and amount > 0 then
        local profile = ProfileManager.GetProfile(player)
        local balance = profile ~= nil and profile.Data.Cash or amount
        Analytics.economySource(player, amount, balance, Analytics.Tx.Gameplay)
        EventService.Signal(player, "EARN_CASH", amount) -- feed "earn N cash" event quests
        SeasonService.Signal(player, "EARN_CASH", amount) -- feed season points
        GameSignals.fire(player, "earn_cash", amount) -- M12.1 quests (earn + cash_reached); pure emit
    end
    earned[player] = nil
end

function IncomeService.Start()
    if connection ~= nil then
        return
    end

    -- Drop per-session perk state on leave (Hourglass session ramp + Meltdown timer).
    Players.PlayerRemoving:Connect(function(player)
        sessionStart[player] = nil
        meltdownAccum[player] = nil
    end)

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

        local now = os.clock()
        for _, player in ipairs(Players:GetPlayers()) do
            local profile = ProfileManager.GetProfile(player)
            if profile ~= nil then
                if sessionStart[player] == nil then
                    sessionStart[player] = now
                end

                -- M11.1 SPECIAL-INCOME perks (Hourglass online ramp + Battalion army bonus) -> ONE
                -- capped Benefits source, refreshed on the throttled tick. Routing through Benefits
                -- keeps them UNDER the global income cap and idempotent (recompute-from-scratch each
                -- tick); the accrual below reads the live multiplier so they take effect immediately.
                if pushNow then
                    local bonus = 0
                    local hg = PerkEffects.GetHourglass(player)
                    if hg ~= nil then
                        local elapsed = now - (sessionStart[player] or now)
                        bonus += math.clamp((elapsed / hg.RampSeconds) * hg.Cap, 0, hg.Cap)
                    end
                    local bat = PerkEffects.GetBattalion(player)
                    if bat ~= nil then
                        bonus += math.min(bat.Cap, bat.PerUnit * #profile.Data.OwnedBrainrots)
                    end
                    Benefits.SetIncomeSource(player, "perk:special", bonus)
                end

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

                -- M11.1 MELTDOWN perk: every Period seconds an income CRIT pays Mult x one period of
                -- income (a one-shot bonus through the guarded accessor; never affects the transfer).
                local md = PerkEffects.GetMeltdown(player)
                if md ~= nil then
                    meltdownAccum[player] = (meltdownAccum[player] or 0) + deltaTime
                    if meltdownAccum[player] >= md.Period then
                        meltdownAccum[player] = 0
                        local bonus = math.floor(rate * md.Period * (md.Mult - 1))
                        if bonus > 0 then
                            ProfileManager.AddCash(player, bonus)
                            earned[player] = (earned[player] or 0) + bonus
                            Remotes.NotifyPlayer(
                                player,
                                "success",
                                "MELTDOWN! Income crit +$" .. bonus .. "!",
                                "buy"
                            )
                        end
                    end
                elseif meltdownAccum[player] ~= nil then
                    meltdownAccum[player] = nil
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
