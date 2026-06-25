-- InventoryService: answers the client's "what do I own?" RemoteFunction with a fresh,
-- server-authoritative list. The client never holds the trusted copy -- it asks here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local Remotes = require(script.Parent.Remotes)
local ProfileManager = require(script.Parent.ProfileManager)

local InventoryService = {}

-- Resolves a display name for a stored brainrot type (Catalog for buyables, Config for
-- the free starter, starter as a final fallback for any stale save).
local function displayName(brainrotType)
    local def = Catalog.Get(brainrotType)
        or Config.Brainrots[brainrotType]
        or Config.Brainrots[Config.StarterType]
    return def.Name
end

local function getInventory(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return {}
    end

    local owned = {}
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        table.insert(owned, {
            Name = displayName(brainrot.Type),
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
