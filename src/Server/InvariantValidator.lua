-- InvariantValidator: a DEV-ONLY, read-only scanner that checks the SACRED INVARIANTS against
-- LIVE server state and logs any violation LOUDLY with full detail. It turns "I can't see runtime
-- bugs" into "the game shouts the instant an invariant breaks."
--
-- It is server-only, never reachable by a client, never mutates anything, and can NEVER affect
-- gameplay. The periodic auto-scan runs ONLY when the DEV/TEST SIM flag is on (Studio/dev), so a
-- published server pays nothing. Run() can also be invoked on demand from the command bar:
--   require(game.ServerScriptService.Server.InvariantValidator).Run()
--
-- INVARIANTS CHECKED (mirrors the VM0 sacred list):
--   1. Every owned brainrot Id is owned by EXACTLY ONE loaded player (no cross-player DUPE/loss).
--   2. No loaded player's Cash is negative.
--   3. Every IN_TRANSIT id is still owned by exactly one player (a carried unit stays in victim
--      data; an in-transit id owned by nobody = a leak).
--   4. Every TRADE-LOCKED id is owned by a loaded player (a lock on an unowned id is a dangling
--      entry that would wrongly block stealing).
--   5. Each loaded player's global income multiplier is within the configured cap, and prestige is
--      within its cap (sources never run away / double-apply).
--   6. No player's season-score record targets a FUTURE season id (per-season writes stay current).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Monetization)
local RebirthConfig = require(ReplicatedStorage.Shared.RebirthConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local TransitRegistry = require(script.Parent.TransitRegistry)
local TradeLockRegistry = require(script.Parent.TradeLockRegistry)
local Benefits = require(script.Parent.Benefits)
local SeasonService = require(script.Parent.SeasonService)
local DevConfig = require(script.Parent.DevConfig)

local InvariantValidator = {}

local SCAN_INTERVAL = 30 -- s between dev auto-scans (cheap; only runs in SIM/dev)
local EPSILON = 1e-6

-- Runs ONE full invariant scan against live state. Returns an array of violation strings (empty =
-- healthy). Logs each violation as a warning and prints a concise PASS/FAIL summary.
function InvariantValidator.Run()
    local violations = {}
    local function flag(msg)
        table.insert(violations, msg)
    end

    local profiles = ProfileManager.GetAllProfiles()

    -- Build Id -> { ownerName, ... } across every loaded profile (invariant 1 + the basis for 2-4).
    local ownersById = {}
    local loadedPlayers = 0
    for player, profile in pairs(profiles) do
        loadedPlayers += 1
        local data = profile.Data

        -- (2) Cash never negative.
        if type(data.Cash) ~= "number" or data.Cash < 0 then
            flag(
                string.format(
                    "CASH NEGATIVE/INVALID: %s has Cash=%s",
                    player.Name,
                    tostring(data.Cash)
                )
            )
        end

        -- (1) Ownership map.
        for _, unit in ipairs(data.OwnedBrainrots) do
            local list = ownersById[unit.Id]
            if list == nil then
                list = {}
                ownersById[unit.Id] = list
            end
            table.insert(list, player.Name)
        end

        -- (5) Income multiplier + prestige caps.
        local mult = Benefits.GetIncomeMultiplier(player)
        if mult > Monetization.Income.MaxMultiplier + EPSILON then
            flag(
                string.format(
                    "INCOME MULT OVER CAP: %s mult=%.4f > cap=%.4f",
                    player.Name,
                    mult,
                    Monetization.Income.MaxMultiplier
                )
            )
        end
        local prestige = data.PrestigeMultiplier or 1
        if prestige > RebirthConfig.PrestigeCap + EPSILON then
            flag(
                string.format(
                    "PRESTIGE OVER CAP: %s prestige=%.4f > cap=%.4f",
                    player.Name,
                    prestige,
                    RebirthConfig.PrestigeCap
                )
            )
        end

        -- (6) Season score never targets a future season.
        local currentSeason = SeasonService.CurrentId()
        if data.SeasonScore ~= nil and data.SeasonScore.Id > currentSeason then
            flag(
                string.format(
                    "SEASON ID IN FUTURE: %s SeasonScore.Id=%d > current=%d",
                    player.Name,
                    data.SeasonScore.Id,
                    currentSeason
                )
            )
        end
    end

    -- (1) Any Id owned by more than one player is a DUPE -- the worst invariant break.
    for id, owners in pairs(ownersById) do
        if #owners > 1 then
            flag(
                string.format(
                    "DUPLICATE OWNERSHIP: brainrot %s owned by %s",
                    id,
                    table.concat(owners, " + ")
                )
            )
        end
    end

    -- (3) Every in-transit id must still be owned by exactly one loaded player.
    for id in pairs(TransitRegistry.All()) do
        local owners = ownersById[id]
        local n = owners ~= nil and #owners or 0
        if n == 0 then
            flag(
                string.format(
                    "IN_TRANSIT BUT UNOWNED: brainrot %s is carried yet in no inventory (leak).",
                    id
                )
            )
        end
    end

    -- (4) Every trade-locked id must be owned by a loaded player (else it's a dangling lock).
    for id in pairs(TradeLockRegistry.All()) do
        if ownersById[id] == nil then
            flag(
                string.format(
                    "DANGLING TRADE LOCK: brainrot %s is locked but owned by nobody loaded.",
                    id
                )
            )
        end
    end

    -- Report.
    if #violations == 0 then
        print(
            string.format(
                "[Invariants] OK -- %d player(s) scanned, all invariants hold.",
                loadedPlayers
            )
        )
    else
        warn(
            string.format(
                "[Invariants] %d VIOLATION(S) across %d player(s):",
                #violations,
                loadedPlayers
            )
        )
        for _, v in ipairs(violations) do
            warn("   !! " .. v)
        end
    end
    return violations
end

function InvariantValidator.Init()
    -- Periodic scan is DEV-ONLY (SIM flag). A published server never runs the cadence; Run() can
    -- still be called manually from the server command bar for a live spot-check (read-only).
    if not DevConfig.SimMode then
        return
    end
    task.spawn(function()
        while true do
            task.wait(SCAN_INTERVAL)
            if #Players:GetPlayers() > 0 then
                InvariantValidator.Run()
            end
        end
    end)
    print("[Invariants] Dev validator ARMED (SIM mode): scanning every " .. SCAN_INTERVAL .. "s.")
end

return InvariantValidator
