-- EventService: the LIMITED-TIME EVENTS engine. A generic time-window SCHEDULER + TRANSITION
-- engine (schedule -> active set -> onStart/onEnd fired once per boundary) that ORCHESTRATES
-- existing levers. Built reusable so LEADERBOARD SEASONS (8.5) registers as another scheduled
-- window (see the extension note in recomputeActive).
--
-- ============================  SELF-AUDIT (events)  =========================================
-- TIME AUTHORITY: active-state derives ONLY from os.time() (UTC) vs config timestamps, so every
--   server agrees with no coordination. The client only renders replicated state + countdowns.
-- MODIFIERS APPLY ONCE, REMOVE CLEAN: an event income/luck modifier is a KEYED Benefits source
--   ("event:<key>"). onEventStart sets it for all online players; SetupPlayer sets it for joiners
--   during the window; both idempotent (overwrite same key). onEventEnd sets the source to neutral
--   for all online players + recomputes -> NO permanent residue, no double-stack, under the cap.
-- REWARDS/CURRENCY IDEMPOTENT + SERVER-AUTH: quest claims dedupe via ClaimedEventRewards ("key:obj")
--   with grant+record in the SAME mutation; currency flows through a guarded add/spend (never
--   negative, never client-set); the shop is gated to the window SERVER-SIDE. Brainrot reward with
--   no pad -> refused, NOT recorded. Progress counts only while the event is active at action time.
-- ===========================================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventsConfig = require(ReplicatedStorage.Shared.EventsConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local MutationConfig = require(ReplicatedStorage.Shared.MutationConfig)

local DevConfig = require(script.Parent.DevConfig)
local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local PlayerStats = require(script.Parent.PlayerStats)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local ProtectionService = require(script.Parent.ProtectionService)
local Leaderstats = require(script.Parent.Leaderstats)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)

local EventService = {}

local activeKeys = {} -- [eventKey] = true (currently active)
local forced = {} -- [eventKey] = true (dev-forced active; SIM only)
local graceUntil = {} -- [eventKey] = os.time() rewards remain claimable until (after end)

local function now()
    return os.time()
end

-- ===========================================================================================
-- Active-state (server time + config; forced in SIM)
-- ===========================================================================================
local function isActive(event)
    if forced[event.Key] then
        return true
    end
    if not EventsConfig.IsConfigValid(event) then
        return false
    end
    if event.StartTimestamp == 0 or event.EndTimestamp == 0 then
        return false -- unscheduled (dev-force only)
    end
    local t = now()
    return t >= event.StartTimestamp and t < event.EndTimestamp
end

local function isClaimable(event)
    return isActive(event) or (graceUntil[event.Key] ~= nil and now() < graceUntil[event.Key])
end

-- ===========================================================================================
-- Modifiers (feed the EXISTING benefit registry + luck hook; keyed source = apply-once)
-- ===========================================================================================
local function applyModifiers(player, event)
    local mods = event.Modifiers
    if mods == nil then
        return
    end
    if mods.IncomeMultiplier ~= nil then
        Benefits.SetIncomeSource(player, "event:" .. event.Key, mods.IncomeMultiplier - 1)
    end
    if mods.LuckMultiplier ~= nil then
        Benefits.SetLuckSource(player, "event:" .. event.Key, mods.LuckMultiplier)
    end
    local profile = ProfileManager.GetProfile(player)
    if profile ~= nil then
        PlayerStats.UpdateIncome(player, profile)
    end
end

local function removeModifiers(player, event)
    Benefits.SetIncomeSource(player, "event:" .. event.Key, 0) -- neutral bonus
    Benefits.SetLuckSource(player, "event:" .. event.Key, 1) -- neutral luck
    local profile = ProfileManager.GetProfile(player)
    if profile ~= nil then
        PlayerStats.UpdateIncome(player, profile)
    end
end

-- ===========================================================================================
-- Transitions
-- ===========================================================================================
local function pushUpdatePing()
    if Remotes.EventsUpdate ~= nil then
        Remotes.EventsUpdate:FireAllClients()
    end
end

local function onEventStart(event)
    -- Flip event-only content availability (existing Available flags).
    for _, key in ipairs(event.UnlockedMutationKeys or {}) do
        local m = MutationConfig.ByKey[key]
        if m ~= nil then
            m.Available = true
        end
    end
    -- Apply modifiers to everyone online (idempotent).
    for _, player in ipairs(Players:GetPlayers()) do
        applyModifiers(player, event)
        player:SetAttribute("EventActive", true)
        Analytics.custom(player, "event_start", 1)
    end
    graceUntil[event.Key] = nil
    pushUpdatePing()
end

local function onEventEnd(event)
    for _, key in ipairs(event.UnlockedMutationKeys or {}) do
        local m = MutationConfig.ByKey[key]
        if m ~= nil then
            m.Available = false -- event-only content can no longer be acquired (owned stays)
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        removeModifiers(player, event) -- LIVE removal: buff gone immediately, no residue
        player:SetAttribute("EventActive", next(activeKeys) ~= nil)
    end
    graceUntil[event.Key] = now() + EventsConfig.GraceWindow
    pushUpdatePing()
end

-- The scheduler tick: compute the active set from server time + config, DIFF vs last, fire each
-- boundary exactly once. (EXTENSION POINT for SEASONS: register a season as another scheduled
-- window here -- compute its current id from time, fire onSeasonStart/End on change.)
local function recomputeActive()
    local newActive = {}
    for _, event in ipairs(EventsConfig.Events) do
        if isActive(event) then
            newActive[event.Key] = true
        end
    end
    for key in pairs(newActive) do
        if not activeKeys[key] then
            onEventStart(EventsConfig.ByKey[key])
        end
    end
    for key in pairs(activeKeys) do
        if not newActive[key] then
            onEventEnd(EventsConfig.ByKey[key])
        end
    end
    activeKeys = newActive
end

-- ===========================================================================================
-- Join setup + cleanup
-- ===========================================================================================
function EventService.SetupPlayer(player, profile)
    -- Apply currently-active modifiers (idempotent) and prune ended+past-grace progress.
    local anyActive = false
    for _, event in ipairs(EventsConfig.Events) do
        if isActive(event) then
            anyActive = true
            applyModifiers(player, event)
        elseif not isClaimable(event) then
            profile.Data.EventProgress[event.Key] = nil -- safe prune of stale event data
        end
    end
    player:SetAttribute("EventActive", anyActive)
end

-- ===========================================================================================
-- Quest progress (driven by signals the existing services emit)
-- ===========================================================================================
function EventService.Signal(player, signalType, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    for _, event in ipairs(EventsConfig.Events) do
        if isActive(event) and event.Quests ~= nil then -- boundary: only while active NOW
            for _, quest in ipairs(event.Quests) do
                if quest.Type == signalType then
                    profile.Data.EventProgress[event.Key] = profile.Data.EventProgress[event.Key]
                        or {}
                    local prog = profile.Data.EventProgress[event.Key]
                    prog[quest.Id] = math.min(quest.Target, (prog[quest.Id] or 0) + amount)
                end
            end
        end
    end
end

-- ===========================================================================================
-- Guarded event-currency accessor
-- ===========================================================================================
local function addCurrency(profile, currencyId, delta)
    local cur = profile.Data.EventCurrency[currencyId] or 0
    profile.Data.EventCurrency[currencyId] = math.max(0, math.floor(cur + delta))
end

-- ===========================================================================================
-- Reward / shop grant (prepare-then-commit; idempotent claims)
-- ===========================================================================================
local function prepareGrant(player, profile, grant, currencyId)
    if grant.Type == "Cash" then
        return function()
            ProfileManager.AddCash(player, grant.Amount)
        end
    elseif grant.Type == "EventCurrency" then
        return function()
            addCurrency(profile, currencyId, grant.Amount)
        end
    elseif grant.Type == "Brainrot" then
        local def = Catalog.Get(grant.BrainrotId)
        if def == nil then
            return nil
        end
        local plot = PlotService.GetPlot(player)
        if plot == nil or PlotService.FindFreePad(player, profile) == nil then
            return nil
        end
        local padIndex = PlotService.FindFreePad(player, profile)
        return function()
            local unit =
                BrainrotFactory.create(player, def, padIndex, BrainrotFactory.RollFor.Index)
            table.insert(profile.Data.OwnedBrainrots, unit)
            profile.Data.Discovered[def.Id] = true
            BrainrotService.SpawnBrainrot(player, plot, unit)
            ProtectionService.RefreshPrompts(player)
        end
    end
    return nil
end

local function refreshDisplays(player, profile)
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
end

-- Claim a completed quest reward (RemoteFunction). Client sends event key + objective id only.
function EventService.Claim(player, eventKey, objId)
    if not RateLimiter.check(player, "eventclaim", 0.4) then
        return { Result = "Error", Message = "Slow down." }
    end
    if type(eventKey) ~= "string" or type(objId) ~= "string" then
        return { Result = "Error", Message = "Invalid." }
    end
    local event = EventsConfig.ByKey[eventKey]
    if event == nil or not isClaimable(event) then
        return { Result = "Error", Message = "Event not available." }
    end
    local quest = nil
    for _, q in ipairs(event.Quests or {}) do
        if q.Id == objId then
            quest = q
            break
        end
    end
    if quest == nil then
        return { Result = "Error", Message = "Unknown quest." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    local claimKey = eventKey .. ":" .. objId
    if profile.Data.ClaimedEventRewards[claimKey] then
        return { Result = "AlreadyClaimed", Message = "Already claimed." }
    end
    local prog = (profile.Data.EventProgress[eventKey] or {})[objId] or 0
    if prog < quest.Target then
        return { Result = "Locked", Message = "Not completed." }
    end

    local currencyId = event.EventCurrency ~= nil and event.EventCurrency.Id or nil
    local apply = prepareGrant(player, profile, quest.Reward, currencyId)
    if apply == nil then
        return { Result = "Error", Message = "Free a pad first." }
    end
    -- COMMIT: grant + record together (no yields).
    apply()
    profile.Data.ClaimedEventRewards[claimKey] = true

    refreshDisplays(player, profile)
    Analytics.custom(player, Analytics.Events.EventQuestClaim, 1)
    pushUpdatePing()
    return { Result = "Success", Message = "Reward claimed!" }
end

-- Buy from the event shop (RemoteFunction). Gated to the active window SERVER-SIDE.
function EventService.ShopBuy(player, eventKey, entryId)
    if not RateLimiter.check(player, "eventshop", 0.4) then
        return { Result = "Error", Message = "Slow down." }
    end
    if type(eventKey) ~= "string" or type(entryId) ~= "string" then
        return { Result = "Error", Message = "Invalid." }
    end
    local event = EventsConfig.ByKey[eventKey]
    if event == nil or not isActive(event) then -- shop ONLY during the active window
        return { Result = "Error", Message = "Event shop is closed." }
    end
    local entry = nil
    for _, e in ipairs(event.ShopEntries or {}) do
        if e.Id == entryId then
            entry = e
            break
        end
    end
    if entry == nil or event.EventCurrency == nil then
        return { Result = "Error", Message = "Unavailable." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    local currencyId = event.EventCurrency.Id
    local balance = profile.Data.EventCurrency[currencyId] or 0
    if balance < entry.Price then
        return { Result = "Error", Message = "Not enough " .. event.EventCurrency.Name .. "." }
    end
    local apply = prepareGrant(player, profile, entry.Grant, currencyId)
    if apply == nil then
        return { Result = "Error", Message = "Free a pad first." }
    end
    -- COMMIT: spend + grant together (no yields).
    addCurrency(profile, currencyId, -entry.Price)
    apply()

    refreshDisplays(player, profile)
    Analytics.custom(player, Analytics.Events.EventShopBuy, entry.Price)
    pushUpdatePing()
    return { Result = "Success", Message = "Purchased " .. entry.Name .. "!" }
end

-- State the Events UI renders from.
function EventService.GetState(player)
    local profile = ProfileManager.GetProfile(player)
    local result = { Active = {}, Now = now() }
    for _, event in ipairs(EventsConfig.Events) do
        if isClaimable(event) then
            local progress = {}
            local claimed = {}
            if profile ~= nil then
                progress = profile.Data.EventProgress[event.Key] or {}
                for _, q in ipairs(event.Quests or {}) do
                    claimed[q.Id] = profile.Data.ClaimedEventRewards[event.Key .. ":" .. q.Id]
                        == true
                end
            end
            local currency = 0
            if profile ~= nil and event.EventCurrency ~= nil then
                currency = profile.Data.EventCurrency[event.EventCurrency.Id] or 0
            end
            table.insert(result.Active, {
                Key = event.Key,
                Name = event.DisplayName,
                Description = event.Description,
                EndsAt = forced[event.Key] and 0 or event.EndTimestamp,
                IsActive = isActive(event),
                Quests = event.Quests,
                Progress = progress,
                Claimed = claimed,
                Currency = currency,
                CurrencyName = event.EventCurrency ~= nil and event.EventCurrency.Name or nil,
                Shop = isActive(event) and event.ShopEntries or {},
            })
        end
    end
    return result
end

-- ===========================================================================================
-- DEV/TEST force-event (SIM only, production-safe) -- routes through the REAL transitions.
--   require(game.ServerScriptService.Server.EventService).ForceEvent("double_weekend", true)
-- ===========================================================================================
function EventService.ForceEvent(eventKey, active)
    if not DevConfig.SimMode then
        warn("[Events] ForceEvent ignored -- SIM mode is OFF.")
        return
    end
    if EventsConfig.ByKey[eventKey] == nil then
        return
    end
    forced[eventKey] = active and true or nil
    recomputeActive() -- fires the real onStart/onEnd transitions
end

function EventService.Init()
    Remotes.GetEvents.OnServerInvoke = function(player)
        return EventService.GetState(player)
    end
    Remotes.ClaimEventReward.OnServerInvoke = function(player, eventKey, objId)
        return EventService.Claim(player, eventKey, objId)
    end
    Remotes.EventShopBuy.OnServerInvoke = function(player, eventKey, entryId)
        return EventService.ShopBuy(player, eventKey, entryId)
    end

    recomputeActive()
    task.spawn(function()
        while true do
            task.wait(EventsConfig.TickInterval)
            recomputeActive()
        end
    end)
end

return EventService
