-- Client bootstrap: builds the entire HUD / Shop / Inventory / Toast UI in code on
-- spawn and wires it to the server remotes. All UI is generated programmatically --
-- there are no Studio-authored GUI instances anywhere.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local UI = script.Parent.UI
local HUD = require(UI.HUD)
local Shop = require(UI.Shop)
local Inventory = require(UI.Inventory)
local Notifications = require(UI.Notifications)
local KillFeed = require(UI.KillFeed)

local player = Players.LocalPlayer

-- The server creates these at startup; wait for them before building anything.
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
    PurchaseRequest = remotesFolder:WaitForChild("PurchaseRequest"),
    GetInventory = remotesFolder:WaitForChild("GetInventory"),
    Notify = remotesFolder:WaitForChild("Notify"),
    KillFeed = remotesFolder:WaitForChild("KillFeed"),
    PromptGamepass = remotesFolder:WaitForChild("PromptGamepass"),
    PromptProduct = remotesFolder:WaitForChild("PromptProduct"),
    GetMonetization = remotesFolder:WaitForChild("GetMonetization"),
    MonetizationUpdate = remotesFolder:WaitForChild("MonetizationUpdate"),
}

local context = { player = player, remotes = remotes }

Notifications.mount(context)
KillFeed.mount(context)
Shop.mount(context)
Inventory.mount(context)
HUD.mount(context, {
    onShop = Shop.toggle,
    onInventory = Inventory.toggle,
})

-- Hide the "Hold to steal" prompt on the LOCAL player's OWN brainrots (you can't steal your
-- own -- the server rejects it regardless). Cosmetic only: we keep re-asserting Enabled=false
-- so a server re-enable (e.g. when this plot's protection expires) can't re-show it to us.
local function hideOwnPrompt(prompt)
    if not prompt:IsA("ProximityPrompt") or prompt.Name ~= "StealPrompt" then
        return
    end
    if prompt:GetAttribute("OwnerUserId") ~= player.UserId then
        return
    end
    prompt.Enabled = false
    prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
        if prompt.Enabled then
            prompt.Enabled = false
        end
    end)
end

Workspace.DescendantAdded:Connect(hideOwnPrompt)
for _, descendant in ipairs(Workspace:GetDescendants()) do
    hideOwnPrompt(descendant)
end

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

-- Server -> all clients: the kill-feed banner shown to everyone when a steal lands.
remotes.KillFeed.OnClientEvent:Connect(function(payload)
    KillFeed.show(payload)
end)

-- Server -> client: a gamepass this player can buy became owned -> flip its shop button live.
remotes.MonetizationUpdate.OnClientEvent:Connect(function(payload)
    if typeof(payload) == "table" then
        Shop.applyMonetizationUpdate(payload)
    end
end)
