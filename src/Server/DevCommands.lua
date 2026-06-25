-- DevCommands: admin/troubleshooting commands, available TWO ways:
--   1. IN-GAME CHAT (live) -- type "/help", "/resetmoney", "/setcash 1000000", etc. in the chat
--      box. These use Roblox TextChatCommands, so the typed command is intercepted and NEVER shown
--      in anyone's chat (not yours, not other players').
--   2. STUDIO COMMAND BAR (SIM only) -- require(...).SetCash("Name", 1000) etc.
--
-- ============================  SECURITY  ====================================================
-- Chat commands are gated by a SERVER-SIDE allowlist (isAdmin): the place OWNER is always allowed
-- (game.CreatorId for a user-owned place), plus any UserIds you add to ADMIN_IDS, plus anyone in a
-- Studio test. A non-admin who types a command is silently ignored -- the action never runs. The
-- caller's identity comes from the TextSource.UserId, which Roblox sets server-side and a client
-- cannot spoof. Money changes route through the SAME guarded cash accessor as the rest of the game,
-- so they can't break the cash invariants. There is no client RemoteEvent surface here.
-- ===========================================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
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
local Remotes = require(script.Parent.Remotes)

local DevCommands = {}

-- ===========================================================================================
-- Admin allowlist (who may run CHAT commands on a live server). ADD EXTRA ADMIN UserIds HERE.
-- ===========================================================================================
local ADMIN_IDS = {
    -- [123456789] = true,  -- example: paste a Roblox UserId to grant another admin
}

local function isAdmin(userId)
    if RunService:IsStudio() then
        return true -- private test environment
    end
    if ADMIN_IDS[userId] then
        return true
    end
    -- The place owner (for a user-owned experience) is always an admin.
    if game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId then
        return true
    end
    return false
end

-- ===========================================================================================
-- Shared helpers
-- ===========================================================================================
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
-- Raw actions: act on a Player, return (ok, message). NO gating here -- callers gate.
-- ===========================================================================================
local function actSetCash(player, amount)
    amount = tonumber(amount)
    if amount == nil then
        return false, "usage: /setcash <amount>"
    end
    if ProfileManager.GetProfile(player) == nil then
        return false, "your data isn't loaded yet."
    end
    local current = ProfileManager.GetCash(player)
    ProfileManager.AddCash(player, amount - current)
    refresh(player)
    return true, string.format("cash set to %d", math.floor(ProfileManager.GetCash(player)))
end

local function actAddCash(player, amount)
    amount = tonumber(amount)
    if amount == nil then
        return false, "usage: /addcash <amount>"
    end
    if ProfileManager.GetProfile(player) == nil then
        return false, "your data isn't loaded yet."
    end
    ProfileManager.AddCash(player, amount)
    refresh(player)
    return true, string.format("cash now %d", math.floor(ProfileManager.GetCash(player)))
end

local function actResetMoney(player)
    return actSetCash(player, 0)
end

local function actGive(player, brainrotId, rollMutation)
    local def = brainrotId ~= nil and Catalog.Get(brainrotId) or nil
    if def == nil then
        return false, "usage: /give <id>  (try /help for ids)"
    end
    local profile = ProfileManager.GetProfile(player)
    local plot = PlotService.GetPlot(player)
    if profile == nil or plot == nil then
        return false, "not ready."
    end
    local padIndex = PlotService.FindFreePad(player, profile)
    if padIndex == nil then
        return false, "no free pad (/clearbrainrots or free one first)."
    end
    local roll = rollMutation and BrainrotFactory.RollFor.Purchase
        or BrainrotFactory.RollFor.Product
    local unit = BrainrotFactory.create(player, def, padIndex, roll)
    table.insert(profile.Data.OwnedBrainrots, unit)
    profile.Data.Discovered[def.Id] = true
    BrainrotService.SpawnBrainrot(player, plot, unit)
    ProtectionService.RefreshPrompts(player)
    refresh(player)
    return true, string.format("gave %s (mutation=%s)", def.Id, tostring(unit.Mutation))
end

local function actClearBrainrots(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return false, "not ready."
    end
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        BrainrotService.RemoveModel(player, unit.Id)
    end
    profile.Data.OwnedBrainrots = {}
    refresh(player)
    return true, "cleared all placed brainrots."
end

local function actSetRebirth(player, count)
    count = tonumber(count)
    if count == nil then
        return false, "usage: /setrebirth <count>"
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return false, "not ready."
    end
    profile.Data.RebirthCount = math.max(0, math.floor(count))
    RebirthService.SetupPlayer(player, profile)
    return true, string.format("rebirth set to %d", profile.Data.RebirthCount)
end

local function actValidate()
    InvariantValidator.Run()
    return true, "invariant scan printed to the server log (press F9 for the dev console)."
end

-- ===========================================================================================
-- Chat command layer (live, allowlisted, hidden from chat via TextChatCommands)
-- ===========================================================================================
local HELP_LINE = "[Admin] /setcash N · /addcash N · /resetmoney · /give <id> [m] · "
    .. "/clearbrainrots · /setrebirth N · /validate · /help"

local function actHelp()
    return true, HELP_LINE
end

-- alias -> function(player, args) -> (ok, message). Self-targeted (acts on the caller).
local chatHandlers = {
    ["/help"] = function(_player, _args)
        return actHelp()
    end,
    ["/setcash"] = function(player, args)
        return actSetCash(player, args[1])
    end,
    ["/addcash"] = function(player, args)
        return actAddCash(player, args[1])
    end,
    ["/resetmoney"] = function(player, _args)
        return actResetMoney(player)
    end,
    ["/give"] = function(player, args)
        return actGive(player, args[1], args[2] ~= nil)
    end,
    ["/clearbrainrots"] = function(player, _args)
        return actClearBrainrots(player)
    end,
    ["/setrebirth"] = function(player, args)
        return actSetRebirth(player, args[1])
    end,
    ["/validate"] = function(_player, _args)
        return actValidate()
    end,
}

-- Splits the raw command text into args, dropping the leading alias token.
local function parseArgs(text)
    local parts = {}
    for token in string.gmatch(text, "%S+") do
        table.insert(parts, token)
    end
    table.remove(parts, 1)
    return parts
end

local initialized = false

-- Registers the chat commands. Called once from Bootstrap. Commands typed in chat are intercepted
-- by TextChatService and never displayed to anyone, and only allowlisted callers run an action.
function DevCommands.Init()
    if initialized then
        return
    end
    initialized = true

    if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
        warn("[Admin] Legacy chat detected -- in-chat admin commands require TextChatService.")
        return
    end

    for alias, handler in pairs(chatHandlers) do
        local command = Instance.new("TextChatCommand")
        command.Name = "Admin" .. (alias:gsub("/", "_"))
        command.PrimaryAlias = alias
        command.AutocompleteVisible = false -- don't advertise the command in chat autocomplete
        command.Parent = TextChatService
        command.Triggered:Connect(function(textSource, unfilteredText)
            if textSource == nil then
                return
            end
            local player = Players:GetPlayerByUserId(textSource.UserId)
            -- Silently ignore non-admins: the action never runs, no hint that the command exists.
            if player == nil or not isAdmin(player.UserId) then
                return
            end
            local ok, message = handler(player, parseArgs(unfilteredText))
            Remotes.NotifyPlayer(
                player,
                ok and "success" or "error",
                "[Admin] " .. tostring(message)
            )
        end)
    end
    print("[Admin] in-chat commands registered (allowlisted, hidden from chat).")
end

-- ===========================================================================================
-- Studio command-bar API (SIM only). require(game.ServerScriptService.Server.DevCommands).Help()
-- ===========================================================================================
local function guard()
    if not DevConfig.SimMode then
        warn("[Dev] command-bar API is SIM-only; in a live game use the in-chat commands.")
        return false
    end
    return true
end

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
    warn("[Dev] multiple players present -- pass a name.")
    return nil
end

local function runBar(p, fn, ...)
    if not guard() then
        return
    end
    local player = resolve(p)
    if player == nil then
        return
    end
    local _ok, message = fn(player, ...)
    print("[Dev] " .. tostring(message))
end

function DevCommands.SetCash(p, amount)
    runBar(p, actSetCash, amount)
end
function DevCommands.AddCash(p, amount)
    runBar(p, actAddCash, amount)
end
function DevCommands.ResetMoney(p)
    runBar(p, actResetMoney)
end
function DevCommands.Give(p, brainrotId, rollMutation)
    runBar(p, actGive, brainrotId, rollMutation)
end
function DevCommands.ClearBrainrots(p)
    runBar(p, actClearBrainrots)
end
function DevCommands.SetRebirth(p, count)
    runBar(p, actSetRebirth, count)
end
function DevCommands.Validate()
    if not guard() then
        return
    end
    InvariantValidator.Run()
end

function DevCommands.Help()
    print([[
[Dev] In-game CHAT commands (live, allowlisted, hidden from chat): type in the chat box:
  /help  /setcash N  /addcash N  /resetmoney  /give <id> [m]  /clearbrainrots  /setrebirth N  /validate

Studio command-bar API (SIM only), command bar set to "Server":
  D = require(game.ServerScriptService.Server.DevCommands)
  D.ResetMoney("Name") · D.SetCash("Name", 1e6) · D.Give("Name", "garama") · D.Validate()

Other SIM hooks:
  EventService.ForceEvent("double_weekend", true) · SeasonService.ForceRollover()
  MonetizationService.SimGrantGamepass(player, "DoubleCash")

Brainrot ids:]])
    local ids = {}
    for _, item in ipairs(Catalog.Items) do
        table.insert(ids, item.Id)
    end
    print("  " .. table.concat(ids, ", "))
end

return DevCommands
