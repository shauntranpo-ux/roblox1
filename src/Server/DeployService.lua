-- DeployService (M9.3): a player's brainrots become their ARSENAL. Deploying TAGS an owned unit to a
-- role slot (it stays on its pad and keeps earning) and grants a server-computed buff.
--
-- ============================  SELF-AUDIT (deploy path)  ====================================
-- (a) NEVER MOVES/DUPES/LOSES A UNIT: deploying only writes profile.Data.Deployed[slot] = unitId and
--     adds the id to the DeployLockRegistry. It never touches OwnedBrainrots -- the unit is not
--     moved, copied, or removed (it keeps its pad + income). Unassign just clears the tag + lock.
-- (b) BUFFS APPLY EXACTLY ONCE, UNDER THE CAP: income/luck buffs register as KEYED Benefits sources
--     ("role:<slot>") -- re-applying overwrites the same key, so equip / live / rejoin / swap can
--     never double-stack; the benefit registry clamps the combined income multiplier to the cap.
--     Guardian/Raider steal knobs are single per-player values in RoleEffects, overwritten on
--     re-apply. SetupPlayer re-derives every slot from saved data idempotently on join.
-- (c) GUARDIAN/RAIDER are STEAL DIFFICULTY/SPEED ONLY: they live in RoleEffects and are READ by
--     StealService (a pre-transfer slap roll; carry speed; deposit reach). They NEVER touch the
--     ownership-transfer logic -- the dupe-proof ON_PAD->IN_TRANSIT state machine is unchanged.
-- (d) DEPLOYED UNITS ARE LOCKED: the DeployLockRegistry id is consulted by sell + fusion + steal +
--     trade, so a deployed unit can't be sold/fused/stolen/traded.
-- (e) LEAVE-SAFE: ClearPlayer (runs before profile release) unlocks the deployed ids + clears the
--     RoleEffects; the Benefits role sources are wiped by Benefits.ClearPlayer on leave.
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RolesConfig = require(ReplicatedStorage.Shared.RolesConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)

local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local PlayerStats = require(script.Parent.PlayerStats)
local RoleEffects = require(script.Parent.RoleEffects)
local DeployLockRegistry = require(script.Parent.DeployLockRegistry)
local TransitRegistry = require(script.Parent.TransitRegistry)
local TradeLockRegistry = require(script.Parent.TradeLockRegistry)
local Analytics = require(script.Parent.Analytics)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)

local DeployService = {}

-- One slot per role for now -> the slot name IS the role key (see RolesConfig header for multi-slot).
local function roleOfSlot(slot)
    return slot
end

local function benefitKey(slot)
    return "role:" .. slot
end

local function findEntry(profile, unitId)
    for _, unit in ipairs(profile.Data.OwnedBrainrots) do
        if unit.Id == unitId then
            return unit
        end
    end
    return nil
end

-- Registers a role's buff for the assigned unit (idempotent: keyed Benefits sources overwrite; the
-- RoleEffects values overwrite). Computes magnitudes SERVER-SIDE from the unit's real stats.
local function applyRole(player, slot, unit)
    local effect = RolesConfig.Effect(roleOfSlot(slot), unit)
    local role = roleOfSlot(slot)
    if role == "GUARDIAN" then
        RoleEffects.SetGuardian(player, effect.InterruptChance or 0)
    elseif role == "RAIDER" then
        RoleEffects.SetRaider(player, effect.Strength or 0, effect.DepositBonus or 0)
    elseif role == "LUCKY" then
        Benefits.SetLuckSource(player, benefitKey(slot), effect.LuckMult or 1)
        Benefits.SetIncomeSource(player, benefitKey(slot), effect.IncomeBonus or 0)
    elseif role == "TOTEM" then
        Benefits.SetIncomeSource(player, benefitKey(slot), effect.IncomeBonus or 0)
    end
end

-- Cleanly removes a slot's buff (no residual). The mirror of applyRole.
local function unregisterRole(player, slot)
    local role = roleOfSlot(slot)
    if role == "GUARDIAN" then
        RoleEffects.SetGuardian(player, 0)
    elseif role == "RAIDER" then
        RoleEffects.SetRaider(player, 0, 0)
    elseif role == "LUCKY" then
        Benefits.SetLuckSource(player, benefitKey(slot), 1) -- neutral luck
        Benefits.SetIncomeSource(player, benefitKey(slot), 0) -- neutral income
    elseif role == "TOTEM" then
        Benefits.SetIncomeSource(player, benefitKey(slot), 0)
    end
end

-- Clears a slot: unregister buff, unlock the unit, drop the tag.
local function clearSlot(player, profile, slot)
    local unitId = profile.Data.Deployed[slot]
    if unitId == nil then
        return
    end
    unregisterRole(player, slot)
    DeployLockRegistry.Set(unitId, false)
    profile.Data.Deployed[slot] = nil
end

local function refreshAttr(player, profile)
    local n = 0
    for _ in pairs(profile.Data.Deployed) do
        n += 1
    end
    player:SetAttribute("DeployedCount", n)
end

-- The loadout the UI renders (slot -> assigned unit + effect label).
local function buildLoadout(profile)
    local out = {}
    for _, slot in ipairs(RolesConfig.Slots) do
        local role = RolesConfig.Roles[slot]
        local entry = { Slot = slot, Name = role.Name, Desc = role.Desc }
        local unitId = profile.Data.Deployed[slot]
        if unitId ~= nil then
            local unit = findEntry(profile, unitId)
            if unit ~= nil then
                local def = Catalog.Get(unit.Type)
                entry.UnitId = unitId
                entry.UnitName = def ~= nil and def.DisplayName or unit.Type
                entry.Rarity = def ~= nil and def.Rarity or "Common"
                entry.Star = unit.Star or 1
                entry.Mutation = unit.Mutation
                entry.Effect = RolesConfig.Effect(roleOfSlot(slot), unit).Label
            end
        end
        table.insert(out, entry)
    end
    return out
end

-- ===========================================================================================
-- Handlers (INTENT ONLY: a unit Id + a slot)
-- ===========================================================================================
local function handleAssign(player, unitId, slot)
    if type(unitId) ~= "string" or #unitId == 0 or #unitId > 100 then
        return { Result = "Error", Message = "Invalid unit." }
    end
    if type(slot) ~= "string" or RolesConfig.Roles[slot] == nil then
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
    -- Already deployed in another (or this) slot? One role per unit.
    for s, id in pairs(profile.Data.Deployed) do
        if id == unitId then
            if s == slot then
                return { Result = "Error", Message = "Already in that slot." }
            end
            return { Result = "Error", Message = "That unit is already deployed elsewhere." }
        end
    end

    -- Swap: clear the old occupant of this slot first (atomic -- no yields), then assign the new.
    clearSlot(player, profile, slot)
    profile.Data.Deployed[slot] = unitId
    DeployLockRegistry.Set(unitId, true)
    applyRole(player, slot, unit)

    PlayerStats.UpdateIncome(player, profile)
    refreshAttr(player, profile)
    -- Log the deploy with the unit's rarity order as the value (so I can see which rarities get used).
    local def = Catalog.Get(unit.Type)
    Analytics.custom(
        player,
        Analytics.Events.Deploy,
        def ~= nil and Rarity.Get(def.Rarity).Order or 1
    )
    ProfileManager.ForceSave(player)
    return {
        Result = "Success",
        Loadout = buildLoadout(profile),
        Message = "Deployed to " .. RolesConfig.Roles[slot].Name .. ".",
    }
end

local function handleUnassign(player, slot)
    if type(slot) ~= "string" or RolesConfig.Roles[slot] == nil then
        return { Result = "Error", Message = "Invalid slot." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready yet." }
    end
    if profile.Data.Deployed[slot] == nil then
        return { Result = "Error", Message = "That slot is empty." }
    end
    clearSlot(player, profile, slot)
    PlayerStats.UpdateIncome(player, profile)
    refreshAttr(player, profile)
    Analytics.custom(player, Analytics.Events.Undeploy, 1)
    ProfileManager.ForceSave(player)
    return {
        Result = "Success",
        Loadout = buildLoadout(profile),
        Message = "Unassigned " .. RolesConfig.Roles[slot].Name .. ".",
    }
end

-- ===========================================================================================
-- Lifecycle
-- ===========================================================================================

-- On join: re-derive every deployed slot from saved data idempotently (re-lock + re-register). Drops
-- a slot whose unit is no longer owned (defensive auto-unassign) or whose slot config was removed.
function DeployService.SetupPlayer(player, profile)
    profile.Data.Deployed = profile.Data.Deployed or {}
    for slot, unitId in pairs(profile.Data.Deployed) do
        if RolesConfig.Roles[slot] == nil then
            profile.Data.Deployed[slot] = nil
        else
            local unit = findEntry(profile, unitId)
            if unit == nil then
                profile.Data.Deployed[slot] = nil -- deployed unit no longer owned -> auto-unassign
            else
                DeployLockRegistry.Set(unitId, true)
                applyRole(player, slot, unit)
            end
        end
    end
    PlayerStats.UpdateIncome(player, profile)
    refreshAttr(player, profile)
end

-- On leave (BEFORE profile release): release the runtime deploy locks + RoleEffects. The Benefits
-- role income/luck sources are wiped by Benefits.ClearPlayer (MonetizationService.ClearPlayer).
function DeployService.ClearPlayer(player)
    local profile = ProfileManager.GetProfile(player)
    if profile ~= nil and profile.Data.Deployed ~= nil then
        for _, unitId in pairs(profile.Data.Deployed) do
            DeployLockRegistry.Set(unitId, false)
        end
    end
    RoleEffects.ClearPlayer(player)
end

function DeployService.GetLoadout(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return {}
    end
    return buildLoadout(profile)
end

function DeployService.Init()
    Remotes.DeployRequest.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return { Result = "Error", Message = "Invalid request." }
        end
        if not RateLimiter.check(player, "deploy", 0.3) then
            return { Result = "Error", Message = "Slow down." }
        end
        if payload.Action == "assign" then
            return handleAssign(player, payload.UnitId, payload.Slot)
        elseif payload.Action == "unassign" then
            return handleUnassign(player, payload.Slot)
        elseif payload.Action == "get" then
            return { Result = "Success", Loadout = DeployService.GetLoadout(player) }
        end
        return { Result = "Error", Message = "Unknown action." }
    end
end

return DeployService
