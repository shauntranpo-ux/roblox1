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
        local sellable = not (def.Premium and not SellConfig.AllowSellPremium)
        local sellValue = sellable
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
        })
    end
    return owned
end

function InventoryService.Init()
    Remotes.GetInventory.OnServerInvoke = getInventory
end

return InventoryService
