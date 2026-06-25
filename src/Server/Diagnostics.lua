-- Diagnostics: a boot-time + per-join HEALTH CHECK so runtime problems surface the instant the
-- game is played, instead of hiding until something breaks. Server-only, read-only, side-effect
-- free (it never mutates game state and can never affect gameplay).
--
-- WHAT IT REPORTS:
--   * BOOT: which services started vs failed (with the error), whether the Remotes folder + every
--     expected remote exists, whether each data store is REAL or MOCK, and the DEV/TEST SIM flag
--     state -- with a LOUD warning if SIM is somehow ON while the place is published.
--   * JOIN: whether the joining player's profile loaded and has every template field present
--     (catches a reconciliation gap on an old save). Verbose in Studio/dev; in production it stays
--     quiet and only WARNS when something is actually wrong (cheap -- one cheap pass per join).
--
-- This module is intentionally dependency-light and requires nothing that requires it back.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileManager = require(script.Parent.ProfileManager)
local Remotes = require(script.Parent.Remotes)
local DevConfig = require(script.Parent.DevConfig)
local LeaderboardService = require(script.Parent.LeaderboardService)
local SeasonService = require(script.Parent.SeasonService)

local Diagnostics = {}

-- Verbose (per-join field-by-field) logging only in Studio or dev SIM; production stays quiet
-- and only warns on an actual problem.
local function isVerbose()
    return RunService:IsStudio() or DevConfig.SimMode
end

local function line()
    print("--------------------------------------------------------------")
end

-- Verifies the ReplicatedStorage/Remotes surface. Returns present, total, { missing names }.
local function checkRemotes()
    local folder = ReplicatedStorage:FindFirstChild("Remotes")
    local missing = {}
    local present = 0
    local expected = Remotes.ExpectedNames
    for _, name in ipairs(expected) do
        if folder ~= nil and folder:FindFirstChild(name) ~= nil then
            present += 1
        else
            table.insert(missing, name)
        end
    end
    return folder ~= nil, present, #expected, missing
end

-- Prints the one-time boot health report. `serviceResults` is an array of { Name, Ok, Err }
-- (filled by Bootstrap as it starts each service through a protected runner).
function Diagnostics.bootReport(serviceResults)
    line()
    print("[BRAINROT] BOOT HEALTH CHECK")

    -- Services.
    local started, failed = 0, 0
    for _, r in ipairs(serviceResults) do
        if r.Ok then
            started += 1
        else
            failed += 1
        end
    end
    print(string.format("  Services: %d/%d started", started, started + failed))
    for _, r in ipairs(serviceResults) do
        if not r.Ok then
            warn(string.format("    [X] %s FAILED to start: %s", r.Name, tostring(r.Err)))
        end
    end

    -- Remote surface.
    local folderOk, present, total, missing = checkRemotes()
    if folderOk and #missing == 0 then
        print(string.format("  Remotes: folder OK, %d/%d present", present, total))
    else
        warn(
            string.format(
                "  [X] Remotes: folder=%s, %d/%d present, MISSING: %s",
                tostring(folderOk),
                present,
                total,
                #missing > 0 and table.concat(missing, ", ") or "(none)"
            )
        )
    end

    -- Data stores (REAL persistence vs in-memory MOCK).
    print(
        string.format(
            "  DataStores: Profiles=%s  Leaderboards=%s  Seasons=%s",
            ProfileManager.IsUsingMock() and "MOCK" or "REAL",
            LeaderboardService.IsUsingMock() and "MOCK" or "REAL",
            SeasonService.IsMock() and "MOCK" or "REAL"
        )
    )
    if ProfileManager.IsUsingMock() then
        print("    (MOCK = data RESETS when you stop Play; publish + enable API access to persist)")
    end

    -- SIM flag + the hard production-safety assertion.
    if DevConfig.SimMode then
        if RunService:IsStudio() then
            print("  SIM mode: ON (Studio) -- gamepasses/products simulated, no Robux spent.")
        else
            -- DevConfig gates SimMode on IsStudio(), so this is impossible today; the check exists
            -- so any future regression that lets SIM leak into production screams immediately.
            warn("  [!!!] SIM MODE IS ON IN A PUBLISHED SERVER -- monetization is FAKE. FIX NOW.")
        end
    else
        print("  SIM mode: OFF (live monetization path).")
    end
    line()
end

-- Per-join health line. Confirms the profile loaded and every template field reconciled onto it.
function Diagnostics.playerReport(player, profile)
    if profile == nil then
        warn(
            string.format(
                "[Diag] %s JOIN: profile FAILED to load (player gets no save).",
                player.Name
            )
        )
        return
    end

    local missing = {}
    for _, key in ipairs(ProfileManager.GetTemplateFieldNames()) do
        if profile.Data[key] == nil then
            table.insert(missing, key)
        end
    end

    if #missing > 0 then
        warn(
            string.format(
                "[Diag] %s JOIN: profile loaded but MISSING template fields: %s "
                    .. "(reconciliation gap -- add to PROFILE_TEMPLATE).",
                player.Name,
                table.concat(missing, ", ")
            )
        )
    elseif isVerbose() then
        local total = #ProfileManager.GetTemplateFieldNames()
        print(
            string.format(
                "[Diag] %s JOIN ok: store=%s, fields=%d/%d, cash=%d",
                player.Name,
                ProfileManager.IsUsingMock() and "MOCK" or "REAL",
                total,
                total,
                math.floor(profile.Data.Cash)
            )
        )
    end
end

return Diagnostics
