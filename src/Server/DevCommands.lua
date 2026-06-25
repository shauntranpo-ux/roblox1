-- DevCommands: a SIM-ONLY troubleshooting console you drive from the Studio SERVER command bar.
--
-- SAFETY: every command is gated on DevConfig.SimMode, which is `RunService:IsStudio()`-gated, so on
-- a PUBLISHED server these all no-op with a warning. This is a server module under
-- ServerScriptService -- it is NOT a remote and NOTHING here is reachable by a client. It can never
-- be used to cheat a live game. Money changes route through the SAME guarded cash accessor as the
-- rest of the game, so they can't break the cash invariants.
--
-- HOW TO USE (Studio): press Play, set the command bar dropdown to "Server", then e.g.
--   require(game.ServerScriptService.Server.DevCommands).Help()
--   require(game.ServerScriptService.Server.DevCommands).ResetMoney()
--   require(game.ServerScriptService.Server.DevCommands).SetCash("YourName", 1000000)
--   require(game.ServerScriptService.Server.DevCommands).Give("YourName", "garama")
-- The player argument is optional in a solo test (it defaults to the only player), and accepts
-- either a Player instance or a name string.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)

local DevConfig = require(script.Parent.DevConfig)
local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local ProtectionService = require(script.Parent.ProtectionService)
local RebirthService = require(script.Parent.RebirthService)
local InvariantValidator = require(script.Parent.InvariantValidator)

local DevCommands = {}

-- Every command bails here on a live server.
local function guard()
    if not DevConfig.SimMode then
        warn("[Dev] DevCommands are SIM-only (Studio). They do nothing on a published server.")
        return false
    end
    return true
end

-- Accepts a Player, a name string, or nil (defaults to the only player in a solo test).
local function resolve(p)
    if typeof(p) == "Instance" and p:IsA("Player") then
        return p
    end
    if type(p) == "string" then
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Name:lower() == p:lower() then
                return player
            end
        end
        warn("[Dev] no player named '" .. p .. "'")
        return nil
    end
    local all = Players:GetPlayers()
    if #all == 1 then
        return all[1]
    end
    warn("[Dev] multiple players present -- pass a name, e.g. SetCash('Name', 1000)")
    return nil
end

local function refresh(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
end

-- ===========================================================================================
-- Money
-- ===========================================================================================

-- Sets cash to an exact amount (routes through the guarded accessor, so it stays clamped/valid).
function DevCommands.SetCash(p, amount)
    if not guard() then
        return
    end
    local player = resolve(p)
    if player == nil then
        return
    end
    amount = tonumber(amount) or 0
    local current = ProfileManager.GetCash(player)
    ProfileManager.AddCash(player, amount - current)
    refresh(player)
    print(string.format("[Dev] %s cash set to %d", player.Name, ProfileManager.GetCash(player)))
end

-- Adds (or subtracts, if negative) cash.
function DevCommands.AddCash(p, amount)
    if not guard() then
        return
    end
    local player = resolve(p)
    if player == nil then
        return
    end
    ProfileManager.AddCash(player, tonumber(amount) or 0)
    refresh(player)
    print(string.format("[Dev] %s cash now %d", player.Name, ProfileManager.GetCash(player)))
end

-- Resets cash to 0.
function DevCommands.ResetMoney(p)
    DevCommands.SetCash(p, 0)
end

-- ===========================================================================================
-- Brainrots
-- ===========================================================================================

-- Grants a brainrot by roster Id (see Help() for the list). `rollMutation` true rolls a mutation.
function DevCommands.Give(p, brainrotId, rollMutation)
    if not guard() then
        return
    end
    local player = resolve(p)
    if player == nil then
        return
    end
    local def = Catalog.Get(brainrotId)
    if def == nil then
        warn("[Dev] unknown brainrot id '" .. tostring(brainrotId) .. "' -- try Help() for ids.")
        return
    end
    local profile = ProfileManager.GetProfile(player)
    local plot = PlotService.GetPlot(player)
    if profile == nil or plot == nil then
        warn("[Dev] player not ready.")
        return
    end
    local padIndex = PlotService.FindFreePad(player, profile)
    if padIndex == nil then
        warn("[Dev] no free pad -- ClearBrainrots first or free a pad.")
        return
    end
    local roll = rollMutation and BrainrotFactory.RollFor.Purchase
        or BrainrotFactory.RollFor.Product
    local unit = BrainrotFactory.create(player, def, padIndex, roll)
    table.insert(profile.Data.OwnedBrainrots, unit)
    profile.Data.Discovered[def.Id] = true
    BrainrotService.SpawnBrainrot(player, plot, unit)
    ProtectionService.RefreshPrompts(player)
    refresh(player)
    print(
        string.format(
            "[Dev] gave %s a %s (mutation=%s)",
            player.Name,
            def.Id,
            tostring(unit.Mutation)
        )
    )
end

-- Removes ALL of a player's placed brainrots (despawns + clears the saved list). Destructive.
function DevCommands.ClearBrainrots(p)
    if not guard() then
        return
    end
    local player = resolve(p)
    if player == nil then
        return
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        BrainrotService.RemoveModel(player, unit.Id)
    end
    profile.Data.OwnedBrainrots = {}
    refresh(player)
    print(string.format("[Dev] cleared all brainrots for %s", player.Name))
end

-- ===========================================================================================
-- Progression
-- ===========================================================================================

-- Sets the rebirth count and re-derives the prestige multiplier + attributes.
function DevCommands.SetRebirth(p, count)
    if not guard() then
        return
    end
    local player = resolve(p)
    if player == nil then
        return
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    profile.Data.RebirthCount = math.max(0, math.floor(tonumber(count) or 0))
    RebirthService.SetupPlayer(player, profile)
    print(string.format("[Dev] %s rebirth set to %d", player.Name, profile.Data.RebirthCount))
end

-- ===========================================================================================
-- Troubleshooting
-- ===========================================================================================

-- Runs the sacred-invariant scan now (dupes / negative cash / cap breaks / dangling locks).
function DevCommands.Validate()
    if not guard() then
        return
    end
    InvariantValidator.Run()
end

function DevCommands.Help()
    print([[
[Dev] SIM-only commands -- run from the Studio command bar set to "Server":
  D = require(game.ServerScriptService.Server.DevCommands)

  D.ResetMoney("Name")            cash -> 0
  D.SetCash("Name", 1000000)      set cash to an exact amount
  D.AddCash("Name", -500)         add/subtract cash
  D.Give("Name", "garama")        grant a brainrot by id (3rd arg true = roll a mutation)
  D.ClearBrainrots("Name")        remove every placed brainrot
  D.SetRebirth("Name", 3)         set rebirth count (re-derives prestige)
  D.Validate()                    scan the sacred invariants now

  (the "Name" arg is optional in a solo test -- it defaults to the only player.)

Other SIM hooks live on their own services:
  EventService.ForceEvent("double_weekend", true|false)
  SeasonService.ForceRollover()
  MonetizationService.SimGrantGamepass(player, "DoubleCash")
  MonetizationService.SimFireProduct(player, "CashLarge")
  TutorialService.ResetForTesting(player)

Brainrot ids:]])
    local ids = {}
    for _, item in ipairs(Catalog.Items) do
        table.insert(ids, item.Id)
    end
    print("  " .. table.concat(ids, ", "))
end

return DevCommands
