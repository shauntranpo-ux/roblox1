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
local Codes = require(UI.Codes)
local Announce = require(UI.Announce)
local Menu = require(UI.Menu)
local Rebirth = require(UI.Rebirth)
local Index = require(UI.Index)
local Trade = require(UI.Trade)
local Events = require(UI.Events)
local Seasons = require(UI.Seasons)
local Fusion = require(UI.Fusion)
local PanelManager = require(UI.PanelManager)
local ClickFX = require(UI.ClickFX)

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
    Tutorial = remotesFolder:WaitForChild("Tutorial"),
    GetSettings = remotesFolder:WaitForChild("GetSettings"),
    SaveSettings = remotesFolder:WaitForChild("SaveSettings"),
    RedeemCode = remotesFolder:WaitForChild("RedeemCode"),
    WhatsNew = remotesFolder:WaitForChild("WhatsNew"),
    RequestRebirth = remotesFolder:WaitForChild("RequestRebirth"),
    GetIndex = remotesFolder:WaitForChild("GetIndex"),
    ClaimIndexReward = remotesFolder:WaitForChild("ClaimIndexReward"),
    TradeAction = remotesFolder:WaitForChild("TradeAction"),
    TradeUpdate = remotesFolder:WaitForChild("TradeUpdate"),
    GetEvents = remotesFolder:WaitForChild("GetEvents"),
    ClaimEventReward = remotesFolder:WaitForChild("ClaimEventReward"),
    EventShopBuy = remotesFolder:WaitForChild("EventShopBuy"),
    EventsUpdate = remotesFolder:WaitForChild("EventsUpdate"),
    GetSeasons = remotesFolder:WaitForChild("GetSeasons"),
    SeasonsUpdate = remotesFolder:WaitForChild("SeasonsUpdate"),
    SellRequest = remotesFolder:WaitForChild("SellRequest"),
    FuseRequest = remotesFolder:WaitForChild("FuseRequest"),
}

local context = { player = player, remotes = remotes }

-- Mount each UI module independently so a failure in one (e.g. a juice module) can NEVER
-- cascade and leave the player with no HUD. Each error is logged, the rest still build.
local function safeMount(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        warn("[Client] " .. name .. " failed to mount: " .. tostring(err))
    end
end

safeMount("PanelManager", function() -- the single panel authority + shared scrim (built first)
    PanelManager.init(context)
end)
safeMount("Effects", function() -- first, so settings can apply music/shake immediately
    Effects.mount(context)
end)
safeMount("ClickFX", function() -- global bubble-pop ripple + click sound on every press
    ClickFX.mount(context)
end)
safeMount("Notifications", function()
    Notifications.mount(context)
end)
safeMount("KillFeed", function()
    KillFeed.mount(context)
end)
safeMount("Shop", function()
    Shop.mount(context)
end)
safeMount("Inventory", function()
    Inventory.mount(context)
end)
safeMount("Settings", function()
    Settings.mount(context, { onChanged = Effects.applySettings })
end)
safeMount("Tutorial", function()
    Tutorial.mount(context)
end)
safeMount("Codes", function()
    Codes.mount(context)
end)
safeMount("Announce", function()
    Announce.mount(context)
end)
safeMount("Rebirth", function()
    Rebirth.mount(context)
end)
safeMount("Index", function()
    Index.mount(context)
end)
safeMount("Trade", function()
    Trade.mount(context)
end)
safeMount("Events", function()
    Events.mount(context)
end)
safeMount("Seasons", function()
    Seasons.mount(context)
end)
safeMount("Fusion", function()
    Fusion.mount(context)
end)
safeMount("Menu", function()
    Menu.mount(context)
    -- Menu list entries OPEN their panel through the manager (the Menu closes itself first).
    Menu.addButton("🔨 Fusion", function()
        PanelManager.open("Fusion")
    end)
    Menu.addButton("🏆 Seasons", function()
        PanelManager.open("Seasons")
    end)
    Menu.addButton("🎉 Events", function()
        PanelManager.open("Events")
    end)
    Menu.addButton("🤝 Trade", function()
        PanelManager.open("Trade")
    end)
    Menu.addButton("⭐ Rebirth", function()
        PanelManager.open("Rebirth")
    end)
    Menu.addButton("🎁 Codes", function()
        PanelManager.open("Codes")
    end)
    Menu.addButton("⚙ Settings", function()
        PanelManager.open("Settings")
    end)
end)
safeMount("HUD", function()
    -- HUD nav buttons TOGGLE through the manager (tap again to close).
    HUD.mount(context, {
        onShop = function()
            PanelManager.toggle("Shop")
        end,
        onInventory = function()
            PanelManager.toggle("Inventory")
        end,
        onIndex = function()
            PanelManager.toggle("Index")
        end,
        onMenu = function()
            PanelManager.toggle("Menu")
        end,
    })
end)

-- Register every primary panel with the manager AFTER each has mounted its ScreenGui, so the
-- manager is the sole authority over open/close (at most one open) and applies the glass styling.
safeMount("PanelManager registry", function()
    PanelManager.register("Shop", Shop.toggle)
    PanelManager.register("Inventory", Inventory.toggle)
    PanelManager.register("Menu", Menu.toggle)
    PanelManager.register("Seasons", Seasons.toggle)
    PanelManager.register("Events", Events.toggle)
    PanelManager.register("Trade", Trade.toggle)
    PanelManager.register("Rebirth", Rebirth.toggle)
    PanelManager.register("Index", Index.toggle)
    PanelManager.register("Codes", Codes.toggle)
    PanelManager.register("Settings", Settings.toggle)
    PanelManager.register("Fusion", Fusion.toggle)
end)

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

-- Server -> client: show the "What's New" card once per version bump (drives return visits).
remotes.WhatsNew.OnClientEvent:Connect(function()
    Announce.showWhatsNew()
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
