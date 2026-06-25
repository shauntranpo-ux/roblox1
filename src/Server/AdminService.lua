-- AdminService (M13.4): the ONE server-authoritative admin + moderation system. Every admin command
-- -- whether it arrives from the admin PANEL (Remotes.AdminAction) or from an in-chat command
-- (DevCommands forwards to AdminService.dispatch) -- runs through dispatch(), which RE-CHECKS the
-- caller's authority + tier against the locked AdminConfig allowlist SERVER-SIDE, validates the args,
-- executes via the EXISTING systems (guarded cash accessor, brainrot factory, events/boss/season
-- engines, announce broadcast), and LOGS it. A non-admin firing the remote is rejected + logged; the
-- client showing a button means nothing. Authority is NEVER inferred from the client.
--
-- ============================  SELF-AUDIT (admin)  ==========================================
-- (a) AUTHORITY: dispatch() derives the tier from the CALLER (the Player object the remote hands us,
--     which Roblox sets -- un-spoofable) via AdminConfig.Can(caller.UserId, command). Fails closed on
--     unknown command / no tier / insufficient tier -> rejected + logged (admin_denied). A lower tier
--     cannot target an equal/higher admin. The SAME gate guards the chat and the panel (one system).
-- (b) BANS: persisted in the SEPARATE global BanStore (never touches the target's profile -> no save
--     corruption). EnforceBan kicks a banned user on join BEFORE the profile loads; timed bans expire;
--     cross-server because every server reads the store on join.
-- (c) FILTERING: announce text + report reasons go through TextFilter (fail-safe placeholder, never
--     raw). Names are published as the filtered SafeName attribute.
-- (d) DESTRUCTIVE-SAFE + LOGGED: give-item via the factory (no-pad-safe), cash via the guarded
--     accessor (can't break invariants); every action appends to the audit log + Analytics; the panel
--     confirms heavy actions and the server still validates regardless.
-- (e) REPORTS: any player may report; validated, rate-limited + per-session capped, reason filtered,
--     logged. Roblox's built-in report is surfaced (not replaced) by the client.
-- ===========================================================================================

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)

local AdminConfig = require(script.Parent.AdminConfig)
local BanStore = require(script.Parent.BanStore)
local TextFilter = require(script.Parent.TextFilter)
local ProfileManager = require(script.Parent.ProfileManager)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local BrainrotService = require(script.Parent.BrainrotService)
local PlotService = require(script.Parent.PlotService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local ProtectionService = require(script.Parent.ProtectionService)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)
local EventService = require(script.Parent.EventService)
local BossService = require(script.Parent.BossService)
local SeasonService = require(script.Parent.SeasonService)

local AdminService = {}

local REPORT_COOLDOWN = 5 -- s between a player's reports
local REPORT_SESSION_CAP = 8 -- max reports per player per session (anti-harassment-via-spam)
local LOG_MAX = 60 -- audit ring-buffer size

local muted = {} -- [userId] = expiry os.time() (0 = until unmute/leave); nil = not muted
local reportCount = {} -- [Player] = number of reports this session
local recentLog = {} -- ring buffer (newest appended last)
local readFailedWarned = false

-- ===========================================================================================
-- Audit log
-- ===========================================================================================
local function addLog(entry)
    entry.Time = os.time()
    table.insert(recentLog, entry)
    if #recentLog > LOG_MAX then
        table.remove(recentLog, 1)
    end
    -- A durable server-log line (F9 console) in addition to the in-game panel + analytics.
    print(
        string.format(
            "[Admin] %s | %s -> %s | %s",
            tostring(entry.Type),
            tostring(entry.ActorName),
            tostring(entry.TargetName or "-"),
            tostring(entry.Detail or "")
        )
    )
end

-- Newest-first shallow copy for the panel.
local function getLog()
    local out = {}
    for i = #recentLog, 1, -1 do
        table.insert(out, recentLog[i])
    end
    return out
end

-- ===========================================================================================
-- Mute (server-authoritative via each TextChannel's ShouldDeliverCallback)
-- ===========================================================================================
local function isMuted(userId)
    local expiry = muted[userId]
    if expiry == nil then
        return false
    end
    if expiry ~= 0 and os.time() >= expiry then
        muted[userId] = nil -- timed mute lapsed
        return false
    end
    return true
end

-- Installs the "drop messages from muted senders" gate on a channel (idempotent per channel).
local function hookChannel(channel)
    if not channel:IsA("TextChannel") then
        return
    end
    channel.ShouldDeliverCallback = function(message, _target)
        local src = message.TextSource
        if src ~= nil and isMuted(src.UserId) then
            return false -- muted: deliver to nobody
        end
        return true
    end
end

-- ===========================================================================================
-- Canonical admin economy ops (THE single give/cash/clear impl; DevCommands reuses these too).
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

-- Adds `delta` cash to a target through the GUARDED accessor (clamped >=0, NaN/inf-safe). Returns the
-- new balance, or nil if not ready.
function AdminService.GrantCash(target, delta)
    if ProfileManager.GetProfile(target) == nil then
        return nil
    end
    local newBalance = ProfileManager.AddCash(target, delta)
    refresh(target)
    return newBalance
end

-- Gives a catalog unit to a target via the FACTORY, no-pad-safe. Returns (ok, message).
function AdminService.GiveItem(target, brainrotId, rollMutation)
    local def = brainrotId ~= nil and Catalog.Get(brainrotId) or nil
    if def == nil then
        return false, "unknown item id"
    end
    local profile = ProfileManager.GetProfile(target)
    local plot = PlotService.GetPlot(target)
    if profile == nil or plot == nil then
        return false, "target not ready"
    end
    local padIndex = PlotService.FindFreePad(target, profile)
    if padIndex == nil then
        return false, "target has no free pad" -- no-pad-safe: nothing is created
    end
    local roll = rollMutation and BrainrotFactory.RollFor.Purchase
        or BrainrotFactory.RollFor.Product
    local unit = BrainrotFactory.create(target, def, padIndex, roll, true) -- allowExclusive for support
    if unit == nil then
        return false, "couldn't create unit"
    end
    table.insert(profile.Data.OwnedBrainrots, unit)
    profile.Data.Discovered[def.Id] = true
    BrainrotService.SpawnBrainrot(target, plot, unit)
    ProtectionService.RefreshPrompts(target)
    refresh(target)
    return true, def.Id
end

-- Clears a target's PLACED units (support action; does NOT touch cash). Returns (ok, message).
function AdminService.ClearUnits(target)
    local profile = ProfileManager.GetProfile(target)
    if profile == nil then
        return false, "target not ready"
    end
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        BrainrotService.RemoveModel(target, unit.Id)
    end
    profile.Data.OwnedBrainrots = {}
    refresh(target)
    return true, "cleared placed units"
end

-- ===========================================================================================
-- Ban enforcement (called FIRST on join, before the profile loads)
-- ===========================================================================================
local function formatBanMessage(record)
    local msg = "You are banned. Reason: " .. tostring(record.Reason or "violation")
    if type(record.ExpiresAt) == "number" and record.ExpiresAt ~= 0 then
        local mins = math.max(1, math.floor((record.ExpiresAt - os.time()) / 60))
        msg = msg .. string.format(" (expires in ~%d min)", mins)
    else
        msg = msg .. " (permanent)"
    end
    return msg
end

-- Returns true if `player` is banned (and has been kicked). Reads the global store (yields). Runs
-- before any profile load, so a kicked player's save is never touched. On a STORE READ FAILURE this
-- fails OPEN (admits) rather than locking every player out during a DataStore outage -- documented:
-- we cannot tell "banned" from "not banned" on a failed read, so blocking all joins is unacceptable.
function AdminService.EnforceBan(player)
    local record, readable = BanStore.GetBan(player.UserId)
    if record ~= nil then
        addLog({
            Type = "ban_enforced",
            ActorName = "SERVER",
            ActorId = 0,
            TargetName = player.Name,
            TargetId = player.UserId,
            Detail = tostring(record.Reason),
        })
        player:Kick(formatBanMessage(record))
        return true
    end
    if not readable and not readFailedWarned then
        readFailedWarned = true
        warn(
            "[Admin] ban store read failed -> admitting (fail-open). Bans may not enforce right now."
        )
    end
    return false
end

-- ===========================================================================================
-- Command dispatch -- the single authority gate for EVERY admin action
-- ===========================================================================================
local function resolveTarget(userId)
    if type(userId) ~= "number" then
        return nil
    end
    return Players:GetPlayerByUserId(userId)
end

-- Stops a lower (or equal) tier from moderating an equal/higher admin.
local function outranks(callerId, targetUserId)
    return AdminConfig.RankOf(callerId) > AdminConfig.RankOf(targetUserId)
end

local function err(message)
    return { Result = "Error", Message = message }
end

local function ok(message)
    return { Result = "Success", Message = message }
end

-- The command handlers. Each receives (caller, tier, payload) and assumes authority was ALREADY
-- verified by dispatch(). Returns a result table.
local handlers = {}

function handlers.get(caller)
    local players = {}
    for _, p in ipairs(Players:GetPlayers()) do
        table.insert(players, {
            UserId = p.UserId,
            Name = TextFilter.NameFor(p),
            Tier = AdminConfig.GetTier(p.UserId),
            Muted = isMuted(p.UserId),
        })
    end
    return {
        Result = "Success",
        State = {
            Tier = AdminConfig.GetTier(caller.UserId),
            Players = players,
            Log = getLog(),
            MockBans = BanStore.IsUsingMock(),
        },
    }
end

function handlers.kick(caller, _tier, payload)
    local target = resolveTarget(payload.TargetUserId)
    if target == nil then
        return err("player not in this server")
    end
    if not outranks(caller.UserId, target.UserId) then
        return err("can't target an equal/higher admin")
    end
    local _, reason =
        TextFilter.FilterForBroadcast(payload.Reason or "Kicked by an admin", caller.UserId)
    target:Kick(reason)
    return ok("kicked " .. target.Name)
end

function handlers.ban(caller, _tier, payload)
    local userId = payload.TargetUserId
    if type(userId) ~= "number" then
        return err("invalid target")
    end
    if userId == caller.UserId then
        return err("you can't ban yourself")
    end
    if AdminConfig.RankOf(userId) >= AdminConfig.RankOf(caller.UserId) then
        return err("can't ban an equal/higher admin")
    end
    local minutes = tonumber(payload.Minutes) or 0
    local expiresAt = minutes > 0 and (os.time() + math.floor(minutes) * 60) or 0
    local _, reason =
        TextFilter.FilterForBroadcast(payload.Reason or "Banned by an admin", caller.UserId)
    local record = {
        Reason = reason,
        By = caller.UserId,
        ByName = TextFilter.NameFor(caller),
        At = os.time(),
        ExpiresAt = expiresAt,
    }
    if not BanStore.SetBan(userId, record) then
        return err("ban store write failed -- try again")
    end
    -- Kick the target now if they're in THIS server (other servers enforce on their next join).
    local target = resolveTarget(userId)
    if target ~= nil then
        target:Kick(formatBanMessage(record))
    end
    Analytics.custom(caller, Analytics.Events.AdminBan, minutes)
    return ok((expiresAt == 0 and "permanently banned " or "temp-banned ") .. tostring(userId))
end

function handlers.unban(_caller, _tier, payload)
    local userId = payload.TargetUserId
    if type(userId) ~= "number" then
        return err("invalid target")
    end
    if not BanStore.ClearBan(userId) then
        return err("unban store write failed -- try again")
    end
    return ok("unbanned " .. tostring(userId))
end

function handlers.mute(caller, _tier, payload)
    local target = resolveTarget(payload.TargetUserId)
    if target == nil then
        return err("player not in this server")
    end
    if not outranks(caller.UserId, target.UserId) then
        return err("can't target an equal/higher admin")
    end
    local minutes = tonumber(payload.Minutes) or 0
    muted[target.UserId] = minutes > 0 and (os.time() + math.floor(minutes) * 60) or 0
    Analytics.custom(caller, Analytics.Events.AdminMute, minutes)
    return ok("muted " .. target.Name)
end

function handlers.unmute(_caller, _tier, payload)
    local userId = payload.TargetUserId
    if type(userId) ~= "number" then
        return err("invalid target")
    end
    muted[userId] = nil
    return ok("unmuted " .. tostring(userId))
end

function handlers.givecash(_caller, _tier, payload)
    local target = resolveTarget(payload.TargetUserId)
    if target == nil then
        return err("player not in this server")
    end
    local amount = tonumber(payload.Amount)
    if amount == nil then
        return err("invalid amount")
    end
    local newBalance = AdminService.GrantCash(target, amount)
    if newBalance == nil then
        return err("target not ready")
    end
    return ok(
        ("gave $%d to %s (now $%d)"):format(math.floor(amount), target.Name, math.floor(newBalance))
    )
end

function handlers.give(_caller, _tier, payload)
    local target = resolveTarget(payload.TargetUserId)
    if target == nil then
        return err("player not in this server")
    end
    if type(payload.BrainrotId) ~= "string" then
        return err("invalid item id")
    end
    local granted, message =
        AdminService.GiveItem(target, payload.BrainrotId, payload.Mutation == true)
    if not granted then
        return err(message)
    end
    return ok("gave " .. message .. " to " .. target.Name)
end

function handlers.clear(caller, _tier, payload)
    local target = resolveTarget(payload.TargetUserId)
    if target == nil then
        return err("player not in this server")
    end
    if not outranks(caller.UserId, target.UserId) and target ~= caller then
        return err("can't target an equal/higher admin")
    end
    local cleared, message = AdminService.ClearUnits(target)
    if not cleared then
        return err(message)
    end
    return ok(message .. " for " .. target.Name)
end

local function teleportTo(mover, anchor)
    if mover.Character == nil or anchor.Character == nil then
        return false
    end
    local anchorRoot = anchor.Character:FindFirstChild("HumanoidRootPart")
    local moverRoot = mover.Character:FindFirstChild("HumanoidRootPart")
    if anchorRoot == nil or moverRoot == nil then
        return false
    end
    mover.Character:PivotTo(anchorRoot.CFrame * CFrame.new(0, 0, 4)) -- just behind the anchor
    return true
end

function handlers.tp(caller, _tier, payload)
    local target = resolveTarget(payload.TargetUserId)
    if target == nil then
        return err("player not in this server")
    end
    if not teleportTo(caller, target) then
        return err("couldn't teleport (characters not ready)")
    end
    return ok("teleported to " .. target.Name)
end

function handlers.bring(caller, _tier, payload)
    local target = resolveTarget(payload.TargetUserId)
    if target == nil then
        return err("player not in this server")
    end
    if not outranks(caller.UserId, target.UserId) then
        return err("can't target an equal/higher admin")
    end
    if not teleportTo(target, caller) then
        return err("couldn't bring (characters not ready)")
    end
    return ok("brought " .. target.Name)
end

function handlers.announce(caller, _tier, payload)
    if type(payload.Text) ~= "string" then
        return err("nothing to announce")
    end
    -- FILTER admin free text before it is broadcast to everyone (fail-safe placeholder, never raw).
    local filtered, safe = TextFilter.FilterForBroadcast(payload.Text, caller.UserId)
    if not filtered then
        return err("that message couldn't be posted")
    end
    Remotes.BroadcastAdmin({ Text = safe, From = TextFilter.NameFor(caller) })
    return ok("announced to the server")
end

function handlers.boss(caller)
    local spawned = BossService.ForceSpawn() -- live-capable; reuses the real spawn path
    Analytics.custom(caller, Analytics.Events.AdminAction, 1)
    return spawned and ok("world boss spawned")
        or err("a boss is already active (or none configured)")
end

function handlers.event(_caller, _tier, payload)
    if type(payload.Key) ~= "string" then
        return err("invalid event key")
    end
    -- Reuses the real transition path. ForceEvent is SIM-gated (it warns + no-ops on a live server),
    -- so this works in Studio/SIM for testing and is safely inert in production.
    EventService.ForceEvent(payload.Key, payload.Active ~= false)
    return ok("event force requested: " .. payload.Key .. " (SIM/Studio only)")
end

function handlers.season()
    -- Irreversible -> Owner only (enforced by AdminConfig). SIM-gated in SeasonService.
    SeasonService.ForceRollover()
    return ok("season rollover requested (SIM/Studio only)")
end

-- THE gate. Called by both the panel remote and the chat layer. Verifies authority server-side,
-- runs the handler, logs the outcome. `caller` is the Player from the remote (un-spoofable identity).
function AdminService.dispatch(caller, command, payload)
    if typeof(caller) ~= "Instance" or not caller:IsA("Player") then
        return err("invalid caller")
    end
    if type(command) ~= "string" then
        return err("invalid command")
    end
    payload = type(payload) == "table" and payload or {}

    if not RateLimiter.check(caller, "admin", 0.25) then
        return err("slow down")
    end

    -- ===== AUTHORITY: re-checked here on EVERY command, server-side, against the locked allowlist.
    if not AdminConfig.Can(caller.UserId, command) then
        addLog({
            Type = "denied",
            ActorName = TextFilter.NameFor(caller),
            ActorId = caller.UserId,
            TargetName = nil,
            TargetId = payload.TargetUserId,
            Detail = command,
        })
        warn(
            string.format(
                "[Admin] DENIED: %s (%d) tried '%s' without authority.",
                caller.Name,
                caller.UserId,
                command
            )
        )
        Analytics.custom(caller, Analytics.Events.AdminDenied, 1)
        return err("not authorized")
    end

    local handler = handlers[command]
    if handler == nil then
        return err("unknown command")
    end
    local tier = AdminConfig.GetTier(caller.UserId)
    local result = handler(caller, tier, payload)

    -- Log every AUTHORIZED action (success or a handled failure) for the audit trail.
    if command ~= "get" then
        local target = resolveTarget(payload.TargetUserId)
        addLog({
            Type = command,
            ActorName = TextFilter.NameFor(caller),
            ActorId = caller.UserId,
            Tier = tier,
            TargetName = target ~= nil and target.Name
                or (payload.TargetUserId and tostring(payload.TargetUserId) or nil),
            TargetId = payload.TargetUserId,
            Detail = (result and result.Message) or "",
        })
        Analytics.custom(caller, Analytics.Events.AdminAction, 1)
    end
    return result
end

-- ===========================================================================================
-- Player REPORT flow (any player; NO admin tier required). Validated + rate-limited + filtered + logged.
-- ===========================================================================================
function AdminService.HandleReport(reporter, targetUserId, reason)
    if not RateLimiter.check(reporter, "report", REPORT_COOLDOWN) then
        return err("you're reporting too fast")
    end
    if (reportCount[reporter] or 0) >= REPORT_SESSION_CAP then
        return err("report limit reached for this session")
    end
    if type(targetUserId) ~= "number" then
        return err("invalid player")
    end
    if targetUserId == reporter.UserId then
        return err("you can't report yourself")
    end
    local target = resolveTarget(targetUserId)
    local targetName = target ~= nil and target.Name or ("User" .. tostring(targetUserId))

    -- FILTER the reporter's free-text reason before it is ever shown to an admin (fail-safe placeholder).
    local _, safeReason = TextFilter.FilterForBroadcast(reason or "", reporter.UserId)

    reportCount[reporter] = (reportCount[reporter] or 0) + 1
    addLog({
        Type = "report",
        ActorName = TextFilter.NameFor(reporter),
        ActorId = reporter.UserId,
        TargetName = targetName,
        TargetId = targetUserId,
        Detail = safeReason,
    })
    Analytics.custom(reporter, Analytics.Events.PlayerReport, 1)
    return ok("Report submitted. Thanks for helping keep the game safe!")
end

-- ===========================================================================================
-- Lifecycle
-- ===========================================================================================
-- Publishes the filtered SafeName (off-thread; names route through it) + the player's OWN admin tier
-- (so the client knows whether to surface the admin panel button -- the allowlist stays server-only).
function AdminService.SetupPlayer(player)
    task.spawn(TextFilter.PublishName, player)
    local tier = AdminConfig.GetTier(player.UserId)
    if tier ~= nil then
        player:SetAttribute("AdminTier", tier)
    end
end

function AdminService.ClearPlayer(player)
    reportCount[player] = nil
    muted[player.UserId] = nil -- session mute clears on leave (a ban is what persists)
end

function AdminService.Init()
    -- Server-authoritative MUTE: gate every chat channel (existing + future). WaitForChild covers the
    -- TextChannels folder not existing the instant we Init; nil means legacy chat (no TextChannel mute).
    local channels = TextChatService:WaitForChild("TextChannels", 10)
    if channels ~= nil then
        for _, channel in ipairs(channels:GetChildren()) do
            hookChannel(channel)
        end
        channels.ChildAdded:Connect(hookChannel)
    else
        warn("[Admin] no TextChannels folder -> chat mute is unavailable (legacy chat?).")
    end

    -- Admin PANEL + chat both dispatch through here; the panel remote is admin-gated by dispatch().
    Remotes.AdminAction.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Command) ~= "string" then
            return err("invalid request")
        end
        return AdminService.dispatch(player, payload.Command, payload)
    end

    -- REPORT remote is open to ALL players (no tier); the handler validates + rate-limits + filters.
    Remotes.ReportPlayer.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" then
            return err("invalid request")
        end
        return AdminService.HandleReport(player, payload.TargetUserId, payload.Reason)
    end
end

return AdminService
