-- TradeService: SAME-SERVER player-to-player trading. The server owns one authoritative
-- TradeSession per trade; clients send INTENT ONLY and never assert trade state or outcomes.
--
-- ====================  SELF-AUDIT (the DUPLICATION INVARIANT is the prime directive)  ======
-- WORST-CASE FAILURE MODE IS A CLEAN NO-OP: every validation failure / cancel / leave / crash
-- path leaves both players with EXACTLY what they had. No path creates or destroys value.
--
-- (a) NO DUPE/LOSS: the swap funnels through ONE synchronous performSwap() with NO yields: each
--     offered unit is table.remove'd from its giver and table.insert'd into the receiver (on a
--     freed/free pad), cash moves via the guarded accessor. There is no instant where a unit is in
--     two inventories or none.
-- (b) NO STALE-SNAPSHOT DUPE: at COMMIT we RE-VALIDATE against LIVE profiles -- each giver still
--     owns every offered Id, none is IN_TRANSIT, all are tradeable + still trade-locked by THIS
--     session, cash <= live balance, net pad capacity holds for both sides. Any mismatch -> no-op.
-- (c) NO SWITCHEROO: ANY offer edit resets BOTH players' Ready+Confirm; a settle delay gates Ready;
--     COMMIT requires BOTH Confirm on the frozen offer. You can never commit an offer the other
--     player didn't see + confirm.
-- (d) NO DOUBLE-COMMIT: session.Committing guard + the byPlayer session clear mean a session
--     commits at most once; confirm-spam can't re-fire it.
-- (e) STEAL/TRADE COLLISION: offered units are LOCKED (TradeLockRegistry) so StealService refuses
--     them; an IN_TRANSIT unit can't be added. One trade per player; an item can't be in two trades.
-- (f) LEAVE/DISCONNECT/DIE MID-TRADE: Bootstrap calls ResolvePlayer BEFORE profile release -> the
--     session cancels (no-op) + all items unlock before anything saves.
-- (g) CROSS-SERVER: forbidden -- both players are looked up in THIS server; profiles are session-
--     locked here, so this server holds authoritative ownership of both and mutates them together.
-- (h) PERSISTENCE: after the in-memory swap (both profiles consistent in memory -- the live source
--     of truth) we force-save BOTH back-to-back. A crash before saves leaves both pre-trade (safe).
--     The only theoretical residual is a crash in the sub-ms window between the two queued saves;
--     this is the standard same-server-trade model and the in-memory state stays consistent.
-- ===========================================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local TradeConfig = require(ReplicatedStorage.Shared.TradeConfig)
local UnitIncome = require(ReplicatedStorage.Shared.UnitIncome)

local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local ProtectionService = require(script.Parent.ProtectionService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local TransitRegistry = require(script.Parent.TransitRegistry)
local TradeLockRegistry = require(script.Parent.TradeLockRegistry)
local StealService = require(script.Parent.StealService)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)
local EventService = require(script.Parent.EventService)
local SeasonService = require(script.Parent.SeasonService)

local TradeService = {}

local byPlayer = {} -- [Player] = session (active OR requester of a REQUESTED session)
local pendingTo = {} -- [Player] = session (a REQUESTED session awaiting THIS player's response)
local lastTradeTime = {} -- [Player] = os.clock() of last completed trade (cooldown)

-- ===========================================================================================
-- Helpers
-- ===========================================================================================
local function offerFor(session, player)
    return session.A == player and session.OfferA or session.OfferB
end
local function other(session, player)
    return session.A == player and session.B or session.A
end

local function findOwned(profile, brainrotId)
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        if unit.Id == brainrotId then
            return unit
        end
    end
    return nil
end

local function inOffer(offer, brainrotId)
    for _, id in ipairs(offer.Items) do
        if id == brainrotId then
            return true
        end
    end
    return false
end

-- ANY offer edit resets both Ready + Confirm (anti-switcheroo) and restarts the settle timer.
local function resetFlags(session)
    session.ReadyA = false
    session.ReadyB = false
    session.ConfirmA = false
    session.ConfirmB = false
    session.LastEdit = os.clock()
    session.LastActivity = os.clock()
end

local function unlockOffer(offer)
    for _, id in ipairs(offer.Items) do
        TradeLockRegistry.Set(id, false)
    end
end

-- Tears a session down (cancel/decline/leave/complete). Unlocks all items + clears registries.
-- `notify` is an optional reason sent to both still-present players.
local function endSession(session, notify)
    unlockOffer(session.OfferA)
    unlockOffer(session.OfferB)
    if byPlayer[session.A] == session then
        byPlayer[session.A] = nil
    end
    if byPlayer[session.B] == session then
        byPlayer[session.B] = nil
    end
    if pendingTo[session.B] == session then
        pendingTo[session.B] = nil
    end
    session.Ended = true
    for _, p in ipairs({ session.A, session.B }) do
        if p.Parent == Players and Remotes.TradeUpdate ~= nil then
            Remotes.TradeUpdate:FireClient(p, { Kind = "closed", Reason = notify })
        end
    end
end

-- ===========================================================================================
-- Snapshot replication (the authoritative state both clients render)
-- ===========================================================================================
local function itemize(ownerProfile, offer)
    local arr = {}
    if ownerProfile == nil then
        return arr
    end
    for _, id in ipairs(offer.Items) do
        local unit = findOwned(ownerProfile, id)
        if unit ~= nil then
            local def = Catalog.Get(unit.Type)
            table.insert(arr, {
                Id = id,
                Name = def ~= nil and def.DisplayName or unit.Type,
                Rarity = def ~= nil and def.Rarity or "Common",
                IncomePerSec = UnitIncome.effective(unit), -- mutation-aware so players can value it
                Mutation = unit.Mutation,
            })
        end
    end
    return arr
end

local function pushUpdate(session)
    if session.State ~= "ACTIVE" then
        return
    end
    local now = os.clock()
    local settleRemaining = math.max(0, TradeConfig.SettleDelay - (now - session.LastEdit))
    local profA = ProfileManager.GetProfile(session.A)
    local profB = ProfileManager.GetProfile(session.B)

    local function snapshotFor(viewer)
        local mine = offerFor(session, viewer)
        local theirs = offerFor(session, other(session, viewer))
        local myProfile = viewer == session.A and profA or profB
        local theirProfile = viewer == session.A and profB or profA
        local myReady = viewer == session.A and session.ReadyA or session.ReadyB
        local theirReady = viewer == session.A and session.ReadyB or session.ReadyA
        local myConfirm = viewer == session.A and session.ConfirmA or session.ConfirmB
        local theirConfirm = viewer == session.A and session.ConfirmB or session.ConfirmA
        return {
            Kind = "update",
            Active = true,
            Partner = other(session, viewer).Name,
            You = {
                Items = itemize(myProfile, mine),
                Cash = mine.Cash,
                Ready = myReady,
                Confirm = myConfirm,
            },
            Them = {
                Items = itemize(theirProfile, theirs),
                Cash = theirs.Cash,
                Ready = theirReady,
                Confirm = theirConfirm,
            },
            BothReady = session.ReadyA and session.ReadyB,
            SettleRemaining = settleRemaining,
            CashEnabled = TradeConfig.CashTradingEnabled,
        }
    end

    if session.A.Parent == Players then
        Remotes.TradeUpdate:FireClient(session.A, snapshotFor(session.A))
    end
    if session.B.Parent == Players then
        Remotes.TradeUpdate:FireClient(session.B, snapshotFor(session.B))
    end
end

-- ===========================================================================================
-- The atomic two-party swap
-- ===========================================================================================
local function collect(profile, offer)
    local units = {}
    for _, id in ipairs(offer.Items) do
        local unit = findOwned(profile, id)
        if unit ~= nil then
            table.insert(units, unit)
        end
    end
    return units
end

-- Re-validates the entire trade against LIVE profile state. Returns ok, reason.
local function revalidate(session)
    local profA = ProfileManager.GetProfile(session.A)
    local profB = ProfileManager.GetProfile(session.B)
    if profA == nil or profB == nil then
        return false, "A player isn't ready."
    end
    if StealService.IsBusy(session.A) or StealService.IsBusy(session.B) then
        return false, "A player is mid-steal."
    end

    local function checkSide(profile, offer)
        for _, id in ipairs(offer.Items) do
            local unit = findOwned(profile, id)
            if unit == nil then
                return false, "An offered item is no longer owned."
            end
            if TransitRegistry.Has(id) or not TradeLockRegistry.Has(id) then
                return false, "An offered item is unavailable."
            end
            if not TradeConfig.IsTradeable(Catalog.Get(unit.Type)) then
                return false, "An offered item isn't tradeable."
            end
        end
        if offer.Cash > 0 and profile.Data.Cash < offer.Cash then
            return false, "Not enough cash."
        end
        return true
    end

    local okA, reasonA = checkSide(profA, session.OfferA)
    if not okA then
        return false, reasonA
    end
    local okB, reasonB = checkSide(profB, session.OfferB)
    if not okB then
        return false, reasonB
    end

    -- Net pad capacity for BOTH sides: free + given - received >= 0.
    local freeA = PlotService.CountFreePads(session.A, profA)
    local freeB = PlotService.CountFreePads(session.B, profB)
    if freeA + #session.OfferA.Items - #session.OfferB.Items < 0 then
        return false, "You don't have enough pads."
    end
    if freeB + #session.OfferB.Items - #session.OfferA.Items < 0 then
        return false, "Partner doesn't have enough pads."
    end
    return true
end

local function appendHistory(profile, partnerName, gave, received)
    local entry = { Partner = partnerName, Gave = gave, Received = received, When = os.time() }
    table.insert(profile.Data.TradeHistory, entry)
    while #profile.Data.TradeHistory > TradeConfig.MaxHistory do
        table.remove(profile.Data.TradeHistory, 1)
    end
end

-- ONE synchronous mutation, NO yields. Moves units + cash both ways.
local function performSwap(session)
    local A, B = session.A, session.B
    local profA = ProfileManager.GetProfile(A)
    local profB = ProfileManager.GetProfile(B)
    local plotA = PlotService.GetPlot(A)
    local plotB = PlotService.GetPlot(B)

    local aToB = collect(profA, session.OfferA)
    local bToA = collect(profB, session.OfferB)

    local function moveUnits(units, fromProfile, fromPlayer, toProfile, toPlayer, toPlot)
        -- remove from giver (frees their pads + despawns models) -- no yields
        for _, unit in ipairs(units) do
            for i, u in ipairs(fromProfile.Data.OwnedBrainrots) do
                if u.Id == unit.Id then
                    table.remove(fromProfile.Data.OwnedBrainrots, i)
                    break
                end
            end
            BrainrotService.RemoveModel(fromPlayer, unit.Id)
        end
        -- add to receiver on a free pad each (freed pads above are available now)
        for _, unit in ipairs(units) do
            local padIndex = PlotService.FindFreePad(toPlayer, toProfile)
            if padIndex ~= nil then
                unit.PadIndex = padIndex
                table.insert(toProfile.Data.OwnedBrainrots, unit)
                toProfile.Data.Discovered[unit.Type] = true
                -- The unit's Mutation field travels UNCHANGED with the moved record; the receiver
                -- now owns it, so they discover that mutation.
                if unit.Mutation ~= nil then
                    toProfile.Data.MutationsDiscovered[unit.Mutation] = true
                end
                if toPlot ~= nil then
                    BrainrotService.SpawnBrainrot(toPlayer, toPlot, unit)
                end
            end
        end
    end

    -- record what moved (for history) BEFORE mutation references change
    local function describe(units)
        local list = {}
        for _, u in ipairs(units) do
            table.insert(list, { Id = u.Id, Type = u.Type })
        end
        return list
    end
    local gaveA, gaveB = describe(aToB), describe(bToA)
    local cashA, cashB = session.OfferA.Cash, session.OfferB.Cash

    moveUnits(aToB, profA, A, profB, B, plotB)
    moveUnits(bToA, profB, B, profA, A, plotA)
    ProfileManager.AddCash(A, cashB - cashA)
    ProfileManager.AddCash(B, cashA - cashB)

    -- ----- end of the no-yield mutation -----

    PlayerStats.PushCash(A, profA)
    PlayerStats.PushCash(B, profB)
    PlayerStats.UpdateIncome(A, profA)
    PlayerStats.UpdateIncome(B, profB)
    Leaderstats.Update(A, profA)
    Leaderstats.Update(B, profB)
    ProtectionService.RefreshPrompts(A)
    ProtectionService.RefreshPrompts(B)

    appendHistory(profA, B.Name, gaveA, gaveB)
    appendHistory(profB, A.Name, gaveB, gaveA)

    Analytics.custom(A, Analytics.Events.TradeComplete, #gaveA + #gaveB)
    Analytics.custom(B, Analytics.Events.TradeComplete, #gaveA + #gaveB)
    EventService.Signal(A, "COMPLETE_TRADES", 1)
    EventService.Signal(B, "COMPLETE_TRADES", 1)
    SeasonService.Signal(A, "TRADE", 1)
    SeasonService.Signal(B, "TRADE", 1)

    -- Persist both as close together as possible (in-memory state is already consistent).
    ProfileManager.ForceSave(A)
    ProfileManager.ForceSave(B)
end

local function commit(session)
    if session.Committing then
        return
    end
    session.Committing = true
    local ok, reason = revalidate(session)
    if not ok then
        endSession(session, reason or "Trade failed.")
        return
    end
    performSwap(session)
    lastTradeTime[session.A] = os.clock()
    lastTradeTime[session.B] = os.clock()
    -- Success closes the session (items already moved + unlocked).
    endSession(session, "Trade complete!")
end

-- ===========================================================================================
-- Action handlers (one INTENT-only remote, validated per action)
-- ===========================================================================================
local function handleRequest(player, targetUserId)
    if type(targetUserId) ~= "number" then
        return
    end
    if byPlayer[player] ~= nil then
        Remotes.NotifyPlayer(player, "error", "You're already in a trade.")
        return
    end
    local target = Players:GetPlayerByUserId(targetUserId)
    if target == nil or target == player then
        return
    end
    if byPlayer[target] ~= nil or pendingTo[target] ~= nil then
        Remotes.NotifyPlayer(player, "error", "They're busy.")
        return
    end
    local now = os.clock()
    if lastTradeTime[player] ~= nil and now - lastTradeTime[player] < TradeConfig.TradeCooldown then
        Remotes.NotifyPlayer(player, "error", "Trade is on cooldown.")
        return
    end
    if ProfileManager.GetProfile(player) == nil or ProfileManager.GetProfile(target) == nil then
        return
    end

    local session = {
        Id = tostring(player.UserId) .. "_" .. tostring(target.UserId),
        A = player,
        B = target,
        State = "REQUESTED",
        OfferA = { Items = {}, Cash = 0 },
        OfferB = { Items = {}, Cash = 0 },
        ReadyA = false,
        ReadyB = false,
        ConfirmA = false,
        ConfirmB = false,
        LastEdit = now,
        LastActivity = now,
        Created = now,
        Committing = false,
    }
    byPlayer[player] = session
    pendingTo[target] = session
    Remotes.TradeUpdate:FireClient(
        target,
        { Kind = "request", FromName = player.Name, FromUserId = player.UserId }
    )
    Remotes.NotifyPlayer(player, "info", "Trade request sent to " .. target.Name .. ".")
end

local function handleRespond(player, accept)
    local session = pendingTo[player]
    if session == nil then
        return
    end
    pendingTo[player] = nil
    if not accept then
        endSession(session, "Trade declined.")
        return
    end
    session.State = "ACTIVE"
    session.LastActivity = os.clock()
    byPlayer[player] = session
    pushUpdate(session)
end

local function activeSessionFor(player)
    local session = byPlayer[player]
    if session ~= nil and session.State == "ACTIVE" and not session.Committing then
        return session
    end
    return nil
end

local function handleAddItem(player, brainrotId)
    if type(brainrotId) ~= "string" then
        return
    end
    local session = activeSessionFor(player)
    if session == nil then
        return
    end
    local offer = offerFor(session, player)
    if #offer.Items >= TradeConfig.MaxItemsPerSide or inOffer(offer, brainrotId) then
        return
    end
    local profile = ProfileManager.GetProfile(player)
    local unit = profile ~= nil and findOwned(profile, brainrotId) or nil
    if unit == nil then
        return
    end
    if TransitRegistry.Has(brainrotId) or TradeLockRegistry.Has(brainrotId) then
        Remotes.NotifyPlayer(player, "error", "That unit is busy.")
        return
    end
    if not TradeConfig.IsTradeable(Catalog.Get(unit.Type)) then
        Remotes.NotifyPlayer(player, "error", "That unit can't be traded.")
        return
    end
    table.insert(offer.Items, brainrotId)
    TradeLockRegistry.Set(brainrotId, true)
    resetFlags(session)
    pushUpdate(session)
end

local function handleRemoveItem(player, brainrotId)
    if type(brainrotId) ~= "string" then
        return
    end
    local session = activeSessionFor(player)
    if session == nil then
        return
    end
    local offer = offerFor(session, player)
    for i, id in ipairs(offer.Items) do
        if id == brainrotId then
            table.remove(offer.Items, i)
            TradeLockRegistry.Set(brainrotId, false)
            resetFlags(session)
            pushUpdate(session)
            return
        end
    end
end

local function handleSetCash(player, amount)
    if not TradeConfig.CashTradingEnabled then
        return
    end
    if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
        return
    end
    local session = activeSessionFor(player)
    if session == nil then
        return
    end
    amount = math.min(math.floor(amount), TradeConfig.MaxCashPerTrade)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil or amount > profile.Data.Cash then
        Remotes.NotifyPlayer(player, "error", "You don't have that much cash.")
        return
    end
    offerFor(session, player).Cash = amount
    resetFlags(session)
    pushUpdate(session)
end

local function handleReady(player, ready)
    local session = activeSessionFor(player)
    if session == nil then
        return
    end
    if ready and (os.clock() - session.LastEdit) < TradeConfig.SettleDelay then
        return -- settle delay not elapsed
    end
    if session.A == player then
        session.ReadyA = ready
        if not ready then
            session.ConfirmA = false
        end
    else
        session.ReadyB = ready
        if not ready then
            session.ConfirmB = false
        end
    end
    session.LastActivity = os.clock()
    pushUpdate(session)
end

local function handleConfirm(player)
    local session = activeSessionFor(player)
    if session == nil then
        return
    end
    if not (session.ReadyA and session.ReadyB) then
        return -- both must be Ready before Confirm
    end
    if session.A == player then
        session.ConfirmA = true
    else
        session.ConfirmB = true
    end
    session.LastActivity = os.clock()
    pushUpdate(session)
    if session.ConfirmA and session.ConfirmB then
        commit(session)
    end
end

local function handleCancel(player)
    local session = byPlayer[player]
    if session == nil then
        return
    end
    endSession(session, "Trade cancelled.")
end

-- ===========================================================================================
-- Public API
-- ===========================================================================================

-- True if the player is in any trade (requested or active). Used by RebirthService to block.
function TradeService.IsTrading(player)
    return byPlayer[player] ~= nil
end

-- Cancels any trade the player is in (called from Bootstrap BEFORE their profile is released).
function TradeService.ResolvePlayer(player)
    local session = byPlayer[player]
    if session ~= nil then
        endSession(session, "A player left.")
    end
    if pendingTo[player] ~= nil then
        endSession(pendingTo[player], "Trade declined.")
    end
end

function TradeService.ClearPlayer(player)
    lastTradeTime[player] = nil
end

function TradeService.Init()
    Remotes.TradeAction.OnServerEvent:Connect(function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return
        end
        if not RateLimiter.check(player, "trade", 0.15) then
            return
        end
        local action = payload.Action
        if action == "request" then
            handleRequest(player, payload.TargetUserId)
        elseif action == "respond" then
            handleRespond(player, payload.Accept == true)
        elseif action == "additem" then
            handleAddItem(player, payload.BrainrotId)
        elseif action == "removeitem" then
            handleRemoveItem(player, payload.BrainrotId)
        elseif action == "setcash" then
            handleSetCash(player, payload.Amount)
        elseif action == "ready" then
            handleReady(player, payload.Ready == true)
        elseif action == "confirm" then
            handleConfirm(player)
        elseif action == "cancel" then
            handleCancel(player)
        end
    end)

    -- Timeout sweep: drop stale requests + idle sessions.
    task.spawn(function()
        while true do
            task.wait(1)
            local now = os.clock()
            local seen = {}
            for _, session in pairs(byPlayer) do
                if not seen[session] and not session.Ended then
                    seen[session] = true
                    if
                        session.State == "REQUESTED"
                        and now - session.Created > TradeConfig.RequestTimeout
                    then
                        endSession(session, "Trade request timed out.")
                    elseif
                        session.State == "ACTIVE"
                        and now - session.LastActivity > TradeConfig.SessionTimeout
                    then
                        endSession(session, "Trade timed out.")
                    end
                end
            end
        end
    end)
end

return TradeService
