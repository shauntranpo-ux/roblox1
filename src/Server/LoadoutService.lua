-- LoadoutService (M11.1): the per-brainrot SIGNATURE-PERK loadout. You equip OWNED units into N
-- active perk slots; each equipped unit's signature perk applies, scaled server-side. REPLACES the
-- M9.3 generic-role system, reusing its plumbing (the DeployLockRegistry item-lock + the decoupled
-- effect aggregate + the Benefits registry).
--
-- ============================  SELF-AUDIT (loadout path)  ====================================
-- (a) EQUIP TAGS ONLY -- NEVER MOVES/DUPES/LOSES: equipping writes profile.Data.Loadout[slot]=unitId
--     and adds the id to DeployLockRegistry. It NEVER touches OwnedBrainrots -- the unit keeps its
--     pad + income. Unequip just clears the tag + lock.
-- (b) PERKS APPLY EXACTLY ONCE UNDER THE CAP: recompute() is the ONLY apply path -- it Resets the
--     PerkEffects aggregate + clears EVERY slot's Benefits income/luck source, THEN re-applies the
--     live loadout from scratch. So equip / join / rejoin / swap can NEVER double-apply or leave
--     residue; income/luck sources are keyed per slot and clamped to the global cap by the registry.
-- (c) COMBAT PERKS ARE PARAMS ONLY: RAID/DEF perks write to PerkEffects, which StealService READS as
--     difficulty/speed/visibility knobs. The ownership-transfer state machine is untouched.
-- (d) EQUIPPED UNITS ARE LOCKED: the DeployLockRegistry id is consulted by sell + fusion + steal +
--     trade (unchanged from M9.3), so an equipped unit can't be sold/fused/stolen/traded.
-- (e) LEAVE-SAFE: ClearPlayer (BEFORE profile release) unlocks the equipped ids, records LastLeaveTime
--     (for Cold Storage offline accrual), and clears the aggregate; Benefits sources wipe on leave.
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerksConfig = require(ReplicatedStorage.Shared.PerksConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)

local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local PlayerStats = require(script.Parent.PlayerStats)
local PerkEffects = require(script.Parent.PerkEffects)
local PerkRegistry = require(script.Parent.PerkRegistry)
local DeployLockRegistry = require(script.Parent.DeployLockRegistry)
local TransitRegistry = require(script.Parent.TransitRegistry)
local TradeLockRegistry = require(script.Parent.TradeLockRegistry)
local StealService = require(script.Parent.StealService)
local BrainrotService = require(script.Parent.BrainrotService)
local Analytics = require(script.Parent.Analytics)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)

local LoadoutService = {}

local function findEntry(profile, unitId)
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        if unit.Id == unitId then
            return unit
        end
    end
    return nil
end

-- Loadout slots are saved with STRING keys ("1".."N") since DataStore coerces numeric keys to strings.
local function slotKey(slot)
    return tostring(slot)
end

local function isValidSlot(slot)
    return type(slot) == "number" and slot >= 1 and slot <= PerksConfig.SlotCount and slot % 1 == 0
end

-- THE single idempotent apply path. Reset everything, then re-apply the live loadout from scratch.
local function recompute(player, profile)
    PerkEffects.Reset(player)
    for slot = 1, PerksConfig.SlotCount do
        PerkRegistry.ClearSlot(player, slot)
    end
    for slot = 1, PerksConfig.SlotCount do
        local unitId = profile.Data.Loadout[slotKey(slot)]
        if unitId ~= nil then
            local unit = findEntry(profile, unitId)
            if unit ~= nil then
                PerkRegistry.Apply(player, unit, slot)
            end
        end
    end
    PlayerStats.UpdateIncome(player, profile)
    -- Push the aggregated MOVE + DEFENDER-HOLD effects to their authorities.
    StealService.SetMoveMult(player, PerkEffects.MoveMult(player))
    BrainrotService.SetHoldMultiplier(player, PerkEffects.DefenderHoldMult(player))
end

local function refreshAttr(player, profile)
    local n = 0
    for slot = 1, PerksConfig.SlotCount do
        local unitId = profile.Data.Loadout[slotKey(slot)]
        player:SetAttribute("PerkSlot" .. slot, unitId or "")
        if unitId ~= nil then
            n += 1
        end
    end
    player:SetAttribute("PerkSlotsUsed", n)
end

-- The loadout the UI renders (slot -> equipped unit + its perk + scaled magnitude).
local function buildLoadout(profile)
    local slots = {}
    for slot = 1, PerksConfig.SlotCount do
        local entry = { Slot = slot }
        local unitId = profile.Data.Loadout[slotKey(slot)]
        if unitId ~= nil then
            local unit = findEntry(profile, unitId)
            if unit ~= nil then
                local def = Catalog.Get(unit.Type)
                local perkKey = PerksConfig.PerkForType(unit.Type)
                local perk = PerksConfig.Get(perkKey)
                entry.UnitId = unitId
                entry.UnitName = def ~= nil and def.DisplayName or unit.Type
                entry.Rarity = def ~= nil and def.Rarity or "Common"
                entry.Star = unit.Star or 1
                entry.Mutation = unit.Mutation
                entry.PerkName = perk ~= nil and perk.Name or perkKey
                entry.PerkDesc = perk ~= nil and perk.Desc or ""
                entry.Category = perk ~= nil and perk.Category or ""
                entry.Magnitude = PerksConfig.MagnitudeLabel(perkKey, unit)
            end
        end
        table.insert(slots, entry)
    end
    return { Slots = slots, SlotCount = PerksConfig.SlotCount }
end

-- ===========================================================================================
-- Handlers (INTENT ONLY: a unit Id + a slot)
-- ===========================================================================================
local function handleEquip(player, unitId, slot)
    if type(unitId) ~= "string" or #unitId == 0 or #unitId > 100 then
        return { Result = "Error", Message = "Invalid unit." }
    end
    if not isValidSlot(slot) then
        return { Result = "Error", Message = "Invalid slot." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    local unit = findEntry(profile, unitId)
    if unit == nil then
        return { Result = "Error", Message = "You don't own that unit." }
    end
    if TransitRegistry.Has(unitId) or TradeLockRegistry.Has(unitId) then
        return { Result = "Error", Message = "That unit is busy (in a trade or being stolen)." }
    end
    -- One unit, one slot: reject if it's already equipped in another slot.
    for s = 1, PerksConfig.SlotCount do
        if profile.Data.Loadout[slotKey(s)] == unitId then
            if s == slot then
                return { Result = "Error", Message = "Already in that slot." }
            end
            return { Result = "Error", Message = "That unit is already equipped." }
        end
    end

    -- SWAP: unequip the slot's old occupant first (atomic -- no yields), then equip the new.
    local oldId = profile.Data.Loadout[slotKey(slot)]
    if oldId ~= nil then
        DeployLockRegistry.Set(oldId, false)
    end
    profile.Data.Loadout[slotKey(slot)] = unitId
    DeployLockRegistry.Set(unitId, true)
    recompute(player, profile)
    refreshAttr(player, profile)

    -- Log the equip with the holder's rarity order as the value (which rarities get used as perks).
    local def = Catalog.Get(unit.Type)
    Analytics.custom(
        player,
        Analytics.Events.PerkEquip,
        def ~= nil and Rarity.Get(def.Rarity).Order or 1
    )
    ProfileManager.ForceSave(player)
    return {
        Result = "Success",
        Loadout = buildLoadout(profile),
        Message = "Equipped " .. PerksConfig.Get(PerksConfig.PerkForType(unit.Type)).Name .. ".",
    }
end

local function handleUnequip(player, slot)
    if not isValidSlot(slot) then
        return { Result = "Error", Message = "Invalid slot." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    local unitId = profile.Data.Loadout[slotKey(slot)]
    if unitId == nil then
        return { Result = "Error", Message = "That slot is empty." }
    end
    DeployLockRegistry.Set(unitId, false)
    profile.Data.Loadout[slotKey(slot)] = nil
    recompute(player, profile)
    refreshAttr(player, profile)
    Analytics.custom(player, Analytics.Events.PerkUnequip, 1)
    ProfileManager.ForceSave(player)
    return {
        Result = "Success",
        Loadout = buildLoadout(profile),
        Message = "Unequipped.",
    }
end

-- ===========================================================================================
-- Lifecycle
-- ===========================================================================================

-- One-time Cold Storage offline grant on join (after recompute, so OfflineFrac is known).
local function grantOffline(player, profile)
    local frac = PerkEffects.OfflineFrac(player)
    if frac <= 0 then
        return
    end
    local lastLeave = profile.Data.LastLeaveTime
    if type(lastLeave) ~= "number" or lastLeave <= 0 then
        return
    end
    local away = math.clamp(os.time() - lastLeave, 0, PerksConfig.OfflineMaxSeconds)
    if away <= 0 then
        return
    end
    local prestige = profile.Data.PrestigeMultiplier or 1
    local rate = PlayerStats.GetBaseRate(player) * Benefits.GetIncomeMultiplier(player) * prestige
    local amount = math.floor(rate * frac * away)
    if amount > 0 then
        ProfileManager.AddCash(player, amount)
        PlayerStats.PushCash(player, profile)
        Remotes.NotifyPlayer(
            player,
            "success",
            "Cold Storage earned you $" .. amount .. " while away!"
        )
    end
end

-- On join: reconcile the loadout, drop slots whose unit isn't owned, re-lock equipped units, apply
-- perks idempotently, then grant offline earnings. Legacy M9.3 `Deployed` (role-typed) is ignored.
function LoadoutService.SetupPlayer(player, profile)
    profile.Data.Loadout = profile.Data.Loadout or {}
    for key, unitId in pairs(profile.Data.Loadout) do
        local slot = tonumber(key)
        if slot == nil or not isValidSlot(slot) or findEntry(profile, unitId) == nil then
            profile.Data.Loadout[key] = nil -- bad slot or unit no longer owned -> auto-unequip
        else
            DeployLockRegistry.Set(unitId, true)
        end
    end
    recompute(player, profile)
    refreshAttr(player, profile)
    grantOffline(player, profile)
end

-- On leave (BEFORE profile release): unlock equipped units, stamp LastLeaveTime (Cold Storage), clear
-- the aggregate. Benefits perk sources are wiped by Benefits.ClearPlayer (MonetizationService).
function LoadoutService.ClearPlayer(player)
    local profile = ProfileManager.GetProfile(player)
    if profile ~= nil then
        if profile.Data.Loadout ~= nil then
            for _, unitId in pairs(profile.Data.Loadout) do
                DeployLockRegistry.Set(unitId, false)
            end
        end
        profile.Data.LastLeaveTime = os.time()
    end
    PerkEffects.ClearPlayer(player)
end

function LoadoutService.GetLoadout(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Slots = {}, SlotCount = PerksConfig.SlotCount }
    end
    return buildLoadout(profile)
end

function LoadoutService.Init()
    Remotes.LoadoutRequest.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return { Result = "Error", Message = "Invalid request." }
        end
        if not RateLimiter.check(player, "loadout", 0.3) then
            return { Result = "Error", Message = "Slow down." }
        end
        if payload.Action == "equip" then
            return handleEquip(player, payload.UnitId, payload.Slot)
        elseif payload.Action == "unequip" then
            return handleUnequip(player, payload.Slot)
        elseif payload.Action == "get" then
            return { Result = "Success", Loadout = LoadoutService.GetLoadout(player) }
        end
        return { Result = "Error", Message = "Unknown action." }
    end
end

return LoadoutService
