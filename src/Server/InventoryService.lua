-- InventoryService: answers the client's "what do I own?" RemoteFunction with a fresh,
-- server-authoritative list. The client never holds the trusted copy -- it asks here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)

local Remotes = require(script.Parent.Remotes)
local ProfileManager = require(script.Parent.ProfileManager)

local InventoryService = {}

-- Resolves a stored brainrot type (a roster Id) to its roster entry, falling back to the
-- starter so any stale save still renders.
local function resolveDef(brainrotType)
    return Catalog.Get(brainrotType) or Catalog.GetStarter()
end

local function getInventory(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return {}
    end

    local owned = {}
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        local def = resolveDef(brainrot.Type)
        table.insert(owned, {
            Name = def.DisplayName,
            Rarity = def.Rarity, -- rarity key; the client colors it via Shared/Rarity
            IncomePerSec = brainrot.IncomePerSec,
            Type = brainrot.Type,
        })
    end
    return owned
end

function InventoryService.Init()
    Remotes.GetInventory.OnServerInvoke = getInventory
end

return InventoryService
