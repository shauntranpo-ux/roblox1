-- DevCommands: admin/troubleshooting commands, available TWO ways:
--   1. IN-GAME CHAT (live) -- type "/help", "/resetmoney", "/setcash 1000000", etc. in the chat
--      box. These use Roblox TextChatCommands, so the typed command is intercepted and NEVER shown
--      in anyone's chat (not yours, not other players').
--   2. STUDIO COMMAND BAR (SIM only) -- require(...).SetCash("Name", 1000) etc.
--
-- ============================  SECURITY  ====================================================
-- Authority is the SINGLE consolidated allowlist in AdminConfig (Studio + place creator + the tiered
-- ID lists) -- isAdmin() just delegates there, and the MODERATION commands forward to AdminService,
-- which re-checks the exact per-command tier SERVER-SIDE. A non-admin who types a command is silently
-- ignored -- the action never runs. The caller's identity comes from TextSource.UserId, which Roblox
-- sets server-side and a client cannot spoof. Money/items route through the SAME guarded accessor +
-- factory the admin panel uses (one impl), so they can't break the economy invariants.
-- ===========================================================================================

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local EvolutionConfig = require(ReplicatedStorage.Shared.EvolutionConfig)

local DevConfig = require(script.Parent.DevConfig)
local AdminConfig = require(script.Parent.AdminConfig)
local AdminService = require(script.Parent.AdminService)
local ProfileManager = require(script.Parent.ProfileManager)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local RebirthService = require(script.Parent.RebirthService)
local InvariantValidator = require(script.Parent.InvariantValidator)
local BossService = require(script.Parent.BossService)
local SeasonService = require(script.Parent.SeasonService)
local ExclusivesService = require(script.Parent.ExclusivesService)
local Remotes = require(script.Parent.Remotes)

local DevCommands = {}

-- ===========================================================================================
-- Authority is the SINGLE, CONSOLIDATED allowlist in AdminConfig (Studio + place creator + the tiered
-- ID lists). There is no separate admin list here -- to grant admins, edit AdminConfig. The self-
-- targeted dev/test commands below need any tier; the moderation commands forward to AdminService,
-- which re-checks the exact per-command tier server-side.
-- ===========================================================================================
local function isAdmin(userId)
    return AdminConfig.IsAdmin(userId)
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
-- These self-targeted economy commands reuse the SAME canonical helpers the admin system uses
-- (AdminService.GrantCash / GiveItem / ClearUnits) -> one cash impl, one give impl, no parallel code.
local function actSetCash(player, amount)
    amount = tonumber(amount)
    if amount == nil then
        return false, "usage: /setcash <amount>"
    end
    if ProfileManager.GetProfile(player) == nil then
        return false, "your data isn't loaded yet."
    end
    AdminService.GrantCash(player, amount - ProfileManager.GetCash(player)) -- delta to reach the target
    return true, string.format("cash set to %d", math.floor(ProfileManager.GetCash(player)))
end

local function actAddCash(player, amount)
    amount = tonumber(amount)
    if amount == nil then
        return false, "usage: /addcash <amount>"
    end
    if AdminService.GrantCash(player, amount) == nil then
        return false, "your data isn't loaded yet."
    end
    return true, string.format("cash now %d", math.floor(ProfileManager.GetCash(player)))
end

local function actResetMoney(player)
    return actSetCash(player, 0)
end

local function actGive(player, brainrotId, rollMutation)
    if brainrotId == nil then
        return false, "usage: /give <id>  (try /help for ids)"
    end
    local granted, message = AdminService.GiveItem(player, brainrotId, rollMutation == true)
    if not granted then
        return false, message
    end
    return true, "gave " .. message
end

local function actClearBrainrots(player)
    return AdminService.ClearUnits(player)
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

-- M11.2: bank XP onto every owned unit so they become evolvable (open the Evolve panel to evolve).
local function actAddXP(player, amount)
    amount = tonumber(amount)
    if amount == nil then
        return false, "usage: /addxp <amount>"
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return false, "not ready."
    end
    local n = 0
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        EvolutionConfig.AddXP(unit, amount)
        n += 1
    end
    refresh(player)
    return true, string.format("added %d XP to %d units -- open Evolve to evolve.", amount, n)
end

-- M11.3: force a world boss to spawn now (go hold its prompt to drain it).
local function actBoss(_player)
    local ok = BossService.ForceSpawn()
    return ok,
        ok and "world boss spawned -- go attack it!"
            or "a boss is already active (or none configured)."
end

-- M11.4: force a season rollover (SIM only) so frozen-season rewards become claimable.
local function actSeason(_player)
    if not DevConfig.SimMode then
        return false, "SIM-only (force rollover is off in production)."
    end
    SeasonService.ForceRollover()
    return true, "forced season rollover -- frozen-season rewards claim on next join / re-join."
end

-- M11.4: seasonal-exclusive testing. list / start <key> (open window) / end / grant <key>.
local function actExcl(player, sub, key)
    sub = (type(sub) == "string") and sub:lower() or "list"
    if sub == "list" then
        return true, "exclusives: " .. table.concat(ExclusivesService.ListKeys(), "  |  ")
    elseif sub == "start" then
        return ExclusivesService.DevForceWindow(key)
    elseif sub == "end" then
        return ExclusivesService.DevClearWindow()
    elseif sub == "grant" then
        return ExclusivesService.DevGrant(player, key)
    end
    return false, "usage: /excl list | start <key> | end | grant <key>"
end

-- ===========================================================================================
-- Chat command layer (live, allowlisted, hidden from chat via TextChatCommands)
-- ===========================================================================================
local HELP_LINE = "[Admin] /setcash N · /addcash N · /resetmoney · /give <id> [m] · "
    .. "/clearbrainrots · /setrebirth N · /addxp N · /boss · /season · "
    .. "/excl list|start <key>|end|grant <key> · /validate · /help  ||  MOD: "
    .. "/kick <name> [reason] · /ban <name> [min] [reason] · /unban <id> · "
    .. "/mute <name> [min] · /unmute <name> · /announce <text>"

local function actHelp()
    return true, HELP_LINE
end

-- Finds an in-server player by (case-insensitive) name, or nil.
local function resolveByName(name)
    if type(name) ~= "string" then
        return nil
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == name:lower() then
            return p
        end
    end
    return nil
end

-- Concatenates args[startIdx..] back into a single string (for reasons / announce text).
local function joinFrom(args, startIdx)
    local parts = {}
    for i = startIdx, #args do
        parts[#parts + 1] = args[i]
    end
    return table.concat(parts, " ")
end

-- Forwards a MODERATION command to the one authoritative dispatcher. AdminService re-checks the exact
-- per-command tier server-side, so a Mod typing an Admin-only command is rejected there (not here).
local function forward(player, command, payload)
    local result = AdminService.dispatch(player, command, payload)
    return result.Result == "Success", result.Message
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
    ["/addxp"] = function(player, args)
        return actAddXP(player, args[1])
    end,
    ["/boss"] = function(_player, _args)
        return actBoss()
    end,
    ["/season"] = function(_player, _args)
        return actSeason()
    end,
    ["/excl"] = function(player, args)
        return actExcl(player, args[1], args[2])
    end,
    -- Moderation: forwarded to AdminService.dispatch (which enforces the per-command tier server-side).
    ["/kick"] = function(player, args)
        local target = resolveByName(args[1])
        if target == nil then
            return false, "no player named '" .. tostring(args[1]) .. "' here."
        end
        return forward(player, "kick", { TargetUserId = target.UserId, Reason = joinFrom(args, 2) })
    end,
    ["/ban"] = function(player, args)
        local target = resolveByName(args[1])
        if target == nil then
            return false,
                "no '" .. tostring(args[1]) .. "' here (use the panel to ban an offline id)."
        end
        return forward(player, "ban", {
            TargetUserId = target.UserId,
            Minutes = tonumber(args[2]) or 0,
            Reason = joinFrom(args, 3),
        })
    end,
    ["/unban"] = function(player, args)
        local id = tonumber(args[1])
        if id == nil then
            return false, "usage: /unban <userId>"
        end
        return forward(player, "unban", { TargetUserId = id })
    end,
    ["/mute"] = function(player, args)
        local target = resolveByName(args[1])
        if target == nil then
            return false, "no player named '" .. tostring(args[1]) .. "' here."
        end
        return forward(
            player,
            "mute",
            { TargetUserId = target.UserId, Minutes = tonumber(args[2]) or 0 }
        )
    end,
    ["/unmute"] = function(player, args)
        local target = resolveByName(args[1])
        if target == nil then
            return false, "no player named '" .. tostring(args[1]) .. "' here."
        end
        return forward(player, "unmute", { TargetUserId = target.UserId })
    end,
    ["/announce"] = function(player, args)
        return forward(player, "announce", { Text = joinFrom(args, 1) })
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
  ENDGAME TEST: /addxp N (evolution)  /boss (spawn a Titan)  /season (force rollover, SIM)
  /excl list  /excl start <key>  /excl end  /excl grant <key>   (seasonal exclusives, SIM)

  TEST FLOW (endgame): equip perks in Loadout · /addxp 999999 then evolve in Evolve · /boss then hold
  the Titan prompt · /excl start s900001_aura then buy it in Exclusives · /excl end -> can't buy it now
  · /excl grant s900001_warden -> own a Season exclusive forever (try trading it 2-player).

Studio command-bar API (SIM only), command bar set to "Server":
  D = require(game.ServerScriptService.Server.DevCommands)
  D.ResetMoney("Name") · D.SetCash("Name", 1e6) · D.Give("Name", "garama") · D.Validate()

Other SIM hooks:
  EventService.ForceEvent("double_weekend", true) · SeasonService.ForceRollover()
  BossService.ForceSpawn() · ExclusivesService.DevForceWindow("s900001_aura")
  MonetizationService.SimGrantGamepass(player, "DoubleCash")

Brainrot ids:]])
    local ids = {}
    for _, item in ipairs(Catalog.Items) do
        table.insert(ids, item.Id)
    end
    print("  " .. table.concat(ids, ", "))
end

return DevCommands
