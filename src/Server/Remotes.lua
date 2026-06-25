-- Remotes: the SINGLE place that creates the network surface. The server builds a
-- "Remotes" folder in ReplicatedStorage at startup; clients WaitForChild it. No other
-- file creates remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

-- Created in Init(); referenced by the server handlers.
Remotes.PurchaseRequest = nil -- RemoteEvent  : client -> server, fires an item id only
Remotes.GetInventory = nil -- RemoteFunction : client -> server, returns owned brainrots
Remotes.Notify = nil -- RemoteEvent  : server -> client, toast { Kind, Message }

local folder = nil

function Remotes.Init()
    if folder ~= nil then
        return
    end

    folder = Instance.new("Folder")
    folder.Name = "Remotes"

    local purchase = Instance.new("RemoteEvent")
    purchase.Name = "PurchaseRequest"
    purchase.Parent = folder

    local getInventory = Instance.new("RemoteFunction")
    getInventory.Name = "GetInventory"
    getInventory.Parent = folder

    local notify = Instance.new("RemoteEvent")
    notify.Name = "Notify"
    notify.Parent = folder

    folder.Parent = ReplicatedStorage

    Remotes.PurchaseRequest = purchase
    Remotes.GetInventory = getInventory
    Remotes.Notify = notify
end

-- Sends a toast to a single player. kind = "success" | "error" | "info".
function Remotes.NotifyPlayer(player, kind, message)
    if Remotes.Notify ~= nil then
        Remotes.Notify:FireClient(player, { Kind = kind, Message = message })
    end
end

return Remotes
