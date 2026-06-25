-- InventoryService: answers the client's "what do I own?" RemoteFunction with a fresh,
-- server-authoritative list. The client never holds the trusted copy -- it asks here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local TradeConfig = require(ReplicatedStorage.Shared.TradeConfig)
local UnitIncome = require(ReplicatedStorage.Shared.UnitIncome)
local SellConfig = require(ReplicatedStorage.Shared.SellConfig)
local MutationConfig = require(ReplicatedStorage.Shared.MutationConfig)

local Remotes = require(script.Parent.Remotes)
local ProfileManager = require(script.Parent.ProfileManager)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)

local InventoryService = {}

-- Resolves a stored brainrot type (a roster Id) to its roster entry, falling back to the
-- starter so any stale save still renders.
local function resolveDef(brainrotType)
    return Catalog.Get(brainrotType) or Catalog.GetStarter()
end

-- TRUST BOUNDARY (GetInventory): read-only. The client asks "what do I own?"; the server returns
-- a fresh list built from ITS OWN profile data + roster (display fields only). The client never
-- holds the authoritative copy and sends no arguments. Rate-limited to blunt spam.
local function getInventory(player)
    if not RateLimiter.check(player, "inventory", 0.25) then
        return {}
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return {}
    end

    local owned = {}
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        local def = resolveDef(brainrot.Type)
        -- M9.1: server-computed sell value (DISPLAY ONLY -- SellService recomputes on the real sell).
        -- M12.3: LOCKED blocks ALL consumption (single + bulk sell/fuse); FAVORITED is bulk-excluded
        -- (still single-sellable). The Sellable display flag hides the single-sell button on locked.
        local premiumBlock = def.Premium and not SellConfig.AllowSellPremium
        local locked = brainrot.Locked == true
        local sellable = not premiumBlock and not locked
        local sellValue = not premiumBlock
                and SellConfig.ComputeValue(
                    def,
                    MutationConfig.MultiplierFor(brainrot.Mutation),
                    brainrot.Star
                )
            or 0
        table.insert(owned, {
            Id = brainrot.Id, -- unique per-unit Id (the trade picker offers by this)
            Name = def.DisplayName,
            Rarity = def.Rarity, -- rarity key; the client colors it via Shared/Rarity
            IncomePerSec = UnitIncome.effective(brainrot), -- mutation-aware effective income
            Type = brainrot.Type,
            Tradeable = TradeConfig.IsTradeable(def),
            Mutation = brainrot.Mutation, -- mutation key (nil = Normal)
            Star = brainrot.Star or 1, -- M9.2: star level (default 1; income reflects it via the helper)
            Sellable = sellable, -- M9.1: false for premium (protected)
            SellValue = sellValue, -- M9.1: display value (server recomputes on sell)
            EvolutionStage = brainrot.EvolutionStage or 1, -- M11.2: evolution stage (income reflects it)
            XP = brainrot.XP or 0, -- M11.2: banked XP toward the next stage (client compares vs config)
            ExclusiveSeason = def.ExclusiveSeason, -- M11.4: nil unless a seasonal exclusive (badge)
            Favorited = brainrot.Favorited == true, -- M12.3 soft flag (bulk-excluded, filterable)
            Locked = locked, -- M12.3 hard flag (protected from ALL sell/fuse/trade)
            Value = sellValue, -- alias for sorting by value (= sell value)
        })
    end
    return owned
end

-- M12.3: toggle a per-unit FAVORITE / LOCK flag (server-validated INTENT; persisted). A locked unit
-- is hard-protected from every consume path; favorited is bulk-excluded. Cannot toggle a unit you
-- don't own. (Locking only sets a flag -- it never moves/consumes the unit, so no dupe surface.)
local function toggleFlag(player, unitId, flag, value)
    if not RateLimiter.check(player, "invflag", 0.15) then
        return { Result = "Error", Message = "Slow down." }
    end
    if type(unitId) ~= "string" or #unitId == 0 or #unitId > 100 then
        return { Result = "Error", Message = "Invalid unit." }
    end
    if flag ~= "Locked" and flag ~= "Favorited" then
        return { Result = "Error", Message = "Invalid flag." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        if brainrot.Id == unitId then
            brainrot[flag] = value == true
            ProfileManager.ForceSave(player)
            Analytics.custom(player, Analytics.Events.FlagToggle, value and 1 or 0)
            return {
                Result = "Success",
                Locked = brainrot.Locked == true,
                Favorited = brainrot.Favorited == true,
            }
        end
    end
    return { Result = "Error", Message = "You don't own that unit." }
end

function InventoryService.Init()
    Remotes.GetInventory.OnServerInvoke = getInventory
    Remotes.InventoryAction.OnServerInvoke = function(player, action, unitId, value)
        if action == "lock" then
            return toggleFlag(player, unitId, "Locked", value)
        elseif action == "favorite" then
            return toggleFlag(player, unitId, "Favorited", value)
        end
        return { Result = "Error", Message = "Unknown action." }
    end
end

return InventoryService
