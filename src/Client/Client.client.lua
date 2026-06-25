-- Client bootstrap: builds the entire HUD / Shop / Inventory / Toast UI in code on
-- spawn and wires it to the server remotes. All UI is generated programmatically --
-- there are no Studio-authored GUI instances anywhere.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.UI
local HUD = require(UI.HUD)
local Shop = require(UI.Shop)
local Inventory = require(UI.Inventory)
local Notifications = require(UI.Notifications)

local player = Players.LocalPlayer

-- The server creates these at startup; wait for them before building anything.
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
    PurchaseRequest = remotesFolder:WaitForChild("PurchaseRequest"),
    GetInventory = remotesFolder:WaitForChild("GetInventory"),
    Notify = remotesFolder:WaitForChild("Notify"),
}

local context = { player = player, remotes = remotes }

Notifications.mount(context)
Shop.mount(context)
Inventory.mount(context)
HUD.mount(context, {
    onShop = Shop.toggle,
    onInventory = Inventory.toggle,
})

-- Server -> client toasts. A successful purchase also refreshes an open Inventory so
-- the new unit shows up immediately.
remotes.Notify.OnClientEvent:Connect(function(payload)
    if typeof(payload) ~= "table" then
        return
    end
    Notifications.show(payload.Kind, payload.Message)
    if payload.Kind == "success" then
        Inventory.refreshIfOpen()
    end
end)
