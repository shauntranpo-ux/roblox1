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
local Effects = require(UI.Effects)
local Settings = require(UI.Settings)
local Tutorial = require(UI.Tutorial)

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

Effects.mount(context) -- mount first so settings can apply music/shake immediately
Notifications.mount(context)
KillFeed.mount(context)
Shop.mount(context)
Inventory.mount(context)
Settings.mount(context, { onChanged = Effects.applySettings })
Tutorial.mount(context)
HUD.mount(context, {
    onShop = Shop.toggle,
    onInventory = Inventory.toggle,
    onSettings = Settings.toggle,
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
    -- Juice: the optional Cue maps a server event to a presentational effect (no authority).
    local cue = payload.Cue
    if cue == "buy" then
        Effects.playSfx("buy")
        Effects.burst(UDim2.fromScale(0.5, 0.12), Color3.fromRGB(120, 220, 150), 10)
        Effects.pop(HUD.getCashPill())
        Tutorial.onPurchase()
    elseif cue == "deposit" then
        Effects.playSfx("deposit")
        Effects.flash(Color3.fromRGB(120, 220, 150))
        Effects.shake(0.6)
    elseif cue == "robbed" then
        Effects.playSfx("robbed")
        Effects.flash(Color3.fromRGB(230, 90, 90))
        Effects.shake(0.9)
    end
end)

-- Server -> all clients: the kill-feed banner shown to everyone when a steal lands. If WE are
-- the thief, add a small "you stole one" cue.
remotes.KillFeed.OnClientEvent:Connect(function(payload)
    KillFeed.show(payload)
    if typeof(payload) == "table" and payload.Thief == player.Name then
        Effects.playSfx("steal")
    end
end)

-- Juice: celebrate cash milestones (1K, 10K, 100K, ...) as the player crosses each.
local nextMilestone = 1000
player:GetAttributeChangedSignal("Cash"):Connect(function()
    local cash = player:GetAttribute("Cash") or 0
    if cash >= nextMilestone then
        Effects.milestone()
        while cash >= nextMilestone do
            nextMilestone *= 10
        end
    end
end)

-- Server -> client: a gamepass this player can buy became owned -> flip its shop button live.
remotes.MonetizationUpdate.OnClientEvent:Connect(function(payload)
    if typeof(payload) == "table" then
        Shop.applyMonetizationUpdate(payload)
    end
end)
