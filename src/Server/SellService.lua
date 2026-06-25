-- SellService (M9.1): the economy FLOOR sink. A player sells a collected brainrot for Cash so no
-- unit is ever worthless. SERVER-AUTHORITATIVE: the client sends a unit Id (single) or a filter
-- (bulk) -- NEVER a value; the server reads the unit's REAL Type/Mutation/Star from the profile and
-- computes the value from SellConfig.
--
-- ============================  SELF-AUDIT (sell path)  ======================================
-- (a) NO DUPE / NO LOSS: a unit is removed by table.remove (single) or by rebuilding OwnedBrainrots
--     without the sold ids (bulk). Removal + the guarded AddCash run in ONE synchronous block with
--     NO yields between them, so the unit vanishes EXACTLY once and the grant happens exactly once.
--     A concurrent/spammed sell of the same unit finds it already gone -> clean no-op (never a second
--     grant, never a different unit lost). Single-threaded Luau + the yield-free commit make the
--     critical section atomic.
-- (b) SERVER-COMPUTED VALUE: the client never sends a price; SellConfig.ComputeValue reads the def's
--     buy price + the unit's stored Mutation (+ defensive Star) only.
-- (c) LOCKED UNITS CAN'T SELL: isLocked() consults the SAME item-lock registries steal + trade use
--     (TransitRegistry = in-transit, TradeLockRegistry = in a trade offer). FORWARD-COMPAT: M9.2
--     fusion + M9.3 deploy make units unsellable simply by adding their id to a lock set checked
--     here -- extend isLocked() when those land; this file needs no other change.
-- (d) CASH NEVER NEGATIVE: value is clamped >= 0 in SellConfig and granted only via the guarded
--     ProfileManager.AddCash. Selling only ADDS cash.
-- (e) LEAVE-SAFE: sell is an atomic synchronous request -- there is no lingering session. If the
--     player leaves, GetProfile returns nil after release -> clean no-op; a sell that already
--     committed did so before release. No half-state, no resolve-on-leave needed.
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local MutationConfig = require(ReplicatedStorage.Shared.MutationConfig)
local SellConfig = require(ReplicatedStorage.Shared.SellConfig)
local Format = require(ReplicatedStorage.Shared.Format)

local ProfileManager = require(script.Parent.ProfileManager)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local BrainrotService = require(script.Parent.BrainrotService)
local Analytics = require(script.Parent.Analytics)
local RateLimiter = require(script.Parent.RateLimiter)
local TransitRegistry = require(script.Parent.TransitRegistry)
local TradeLockRegistry = require(script.Parent.TradeLockRegistry)
local Remotes = require(script.Parent.Remotes)

local SellService = {}

-- A unit is unsellable while it is mid-steal (in transit) or offered in a trade. M9.2 (fusion) /
-- M9.3 (deploy) will make units unsellable by adding their id to a lock set -- extend HERE.
local function isLocked(unitId)
    return TransitRegistry.Has(unitId) or TradeLockRegistry.Has(unitId)
end

local function findEntry(profile, unitId)
    for index, unit in ipairs(profile.Data.OwnedBrainrots) do
        if unit.Id == unitId then
            return unit, index
        end
    end
    return nil
end

-- Server-side value of one owned-unit record (reads its real Type/Mutation/Star).
local function valueOf(def, unit)
    return SellConfig.ComputeValue(def, MutationConfig.MultiplierFor(unit.Mutation), unit.Star)
end

local function refreshAfterSell(player, profile)
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
end

-- ===========================================================================================
-- Single sell
-- ===========================================================================================
local function handleOne(player, payload)
    if type(payload.Id) ~= "string" or #payload.Id == 0 or #payload.Id > 100 then
        return { Result = "Error", Message = "Invalid unit." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    local unit, index = findEntry(profile, payload.Id)
    if unit == nil then
        return { Result = "Error", Message = "You don't own that unit." }
    end
    if isLocked(payload.Id) then
        return { Result = "Locked", Message = "That unit is busy (in a trade or being stolen)." }
    end
    local def = Catalog.Get(unit.Type)
    if def == nil then
        return { Result = "Error", Message = "Unknown unit." }
    end
    if def.Premium and not SellConfig.AllowSellPremium then
        return { Result = "Error", Message = "Premium units can't be sold." }
    end

    local value = valueOf(def, unit)
    if value >= SellConfig.ConfirmThreshold and payload.Confirm ~= true then
        return {
            Result = "Confirm",
            Value = value,
            Count = 1,
            Message = "Sell for $" .. Format.full(value) .. "?",
        }
    end

    -- ===== COMMIT: remove the unit + grant cash, NO yields between. =====
    table.remove(profile.Data.OwnedBrainrots, index)
    ProfileManager.AddCash(player, value)
    -- ===================================================================

    BrainrotService.RemoveModel(player, payload.Id)
    refreshAfterSell(player, profile)
    -- Selling GRANTS cash, so it is a cash SOURCE (faucet). (The brainrot itself is "sunk", but the
    -- AnalyticsEconomyFlowType tracks the CURRENCY -- cash enters the player's balance here.)
    Analytics.economySource(
        player,
        value,
        profile.Data.Cash,
        Analytics.Tx.Sell,
        "sell:" .. unit.Type
    )
    Analytics.custom(player, Analytics.Events.Sell, 1)
    ProfileManager.ForceSave(player)
    Remotes.NotifyPlayer(
        player,
        "success",
        "Sold " .. def.DisplayName .. " for $" .. Format.full(value)
    )
    return {
        Result = "Success",
        Value = value,
        Count = 1,
        Message = "Sold for $" .. Format.full(value),
    }
end

-- ===========================================================================================
-- Bulk sell (filtered, server-validated, one atomic mutation)
-- ===========================================================================================
local function handleBulk(player, payload)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end

    local mode = payload.Mode
    local maxOrder, keep
    if mode == "RarityAtMost" then
        local tier = Rarity.Tiers[payload.Rarity]
        if tier == nil then
            return { Result = "Error", Message = "Invalid rarity." }
        end
        maxOrder = tier.Order
    elseif mode == "Duplicates" then
        keep = math.clamp(math.floor(tonumber(payload.Keep) or 1), 0, 50)
    else
        return { Result = "Error", Message = "Invalid sell filter." }
    end

    -- Enumerate eligible units (NO yields): not locked, not premium, matching the filter, capped.
    local sellIds = {}
    local total, count = 0, 0
    local keptPerType = {}
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        if count >= SellConfig.MaxBulk then
            break
        end
        local def = Catalog.Get(unit.Type)
        if def ~= nil then
            local sellable = not (def.Premium and not SellConfig.AllowSellPremium)
                and not isLocked(unit.Id)
            local doSell = false
            if mode == "RarityAtMost" then
                doSell = sellable and (Rarity.Get(def.Rarity).Order <= maxOrder)
            else -- Duplicates: keep `keep` per Type; unsellable copies still occupy a kept slot.
                local kept = keptPerType[unit.Type] or 0
                if not sellable or kept < keep then
                    keptPerType[unit.Type] = kept + 1 -- this copy stays (kept)
                else
                    doSell = true -- a sellable copy beyond the keep quota
                end
            end
            if doSell then
                sellIds[unit.Id] = true
                total += valueOf(def, unit)
                count += 1
            end
        end
    end

    if count == 0 then
        return { Result = "Empty", Count = 0, Value = 0, Message = "Nothing matches that filter." }
    end
    if total >= SellConfig.ConfirmThreshold and payload.Confirm ~= true then
        return {
            Result = "Confirm",
            Count = count,
            Value = total,
            Message = "Sell " .. count .. " units for $" .. Format.full(total) .. "?",
        }
    end

    -- ===== COMMIT: rebuild OwnedBrainrots without the sold ids + grant the total, NO yields. =====
    local kept = {}
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        if not sellIds[unit.Id] then
            table.insert(kept, unit)
        end
    end
    profile.Data.OwnedBrainrots = kept
    ProfileManager.AddCash(player, total)
    -- ============================================================================================

    for id in pairs(sellIds) do
        BrainrotService.RemoveModel(player, id)
    end
    refreshAfterSell(player, profile)
    Analytics.economySource(player, total, profile.Data.Cash, Analytics.Tx.Sell, "bulk:" .. mode)
    Analytics.custom(player, Analytics.Events.Sell, count)
    ProfileManager.ForceSave(player)
    Remotes.NotifyPlayer(
        player,
        "success",
        "Sold " .. count .. " units for $" .. Format.full(total)
    )
    return {
        Result = "Success",
        Count = count,
        Value = total,
        Message = "Sold " .. count .. " units for $" .. Format.full(total),
    }
end

function SellService.Init()
    Remotes.SellRequest.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return { Result = "Error", Message = "Invalid request." }
        end
        if payload.Action == "one" then
            if not RateLimiter.check(player, "sell", 0.3) then
                return { Result = "Error", Message = "Slow down." }
            end
            return handleOne(player, payload)
        elseif payload.Action == "bulk" then
            if not RateLimiter.check(player, "sellbulk", 1) then
                return { Result = "Error", Message = "Slow down." }
            end
            return handleBulk(player, payload)
        end
        return { Result = "Error", Message = "Unknown action." }
    end
end

return SellService
