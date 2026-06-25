-- Remotes: the SINGLE place that creates the network surface. The server builds a
-- "Remotes" folder in ReplicatedStorage at startup; clients WaitForChild it. No other
-- file creates remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

-- Created in Init(); referenced by the server handlers.
Remotes.PurchaseRequest = nil -- RemoteEvent  : client -> server, fires an item id only
Remotes.GetInventory = nil -- RemoteFunction : client -> server, returns owned brainrots
Remotes.Notify = nil -- RemoteEvent  : server -> client, toast { Kind, Message }
Remotes.KillFeed = nil -- RemoteEvent  : server -> ALL clients, steal banner { Thief, Victim, Name, Rarity }
-- M5 monetization. The client may only REQUEST a Marketplace prompt (by config KEY); the
-- server + Roblox own the outcome. Ownership/grants never trust the client.
Remotes.PromptGamepass = nil -- RemoteEvent  : client -> server, requests a gamepass purchase prompt (passKey)
Remotes.PromptProduct = nil -- RemoteEvent  : client -> server, requests a dev-product purchase prompt (productKey)
Remotes.GetMonetization = nil -- RemoteFunction : client -> server, returns { Owned = {key=true}, SimMode = bool }
Remotes.MonetizationUpdate = nil -- RemoteEvent  : server -> client, a gamepass became owned { Key, Owned }
-- M6 onboarding + settings. Client sends INTENT ONLY (tutorial finished/skipped; which prefs).
Remotes.Tutorial = nil -- RemoteEvent  : server -> client "start"; client -> server "done"|"skip"
Remotes.GetSettings = nil -- RemoteFunction : client -> server, returns the saved { Music, SFX, Shake }
Remotes.SaveSettings = nil -- RemoteEvent  : client -> server, saves validated boolean prefs
-- M7 codes + what's-new. Client sends ONLY the typed code string; server validates + grants.
Remotes.RedeemCode = nil -- RemoteFunction : client -> server (code string) -> { Result, Message }
Remotes.WhatsNew = nil -- RemoteEvent  : server -> client, show the changelog once per version
-- M8.1 rebirth + collection index. Client sends INTENT ONLY (rebirth request; milestone id).
Remotes.RequestRebirth = nil -- RemoteFunction : client -> server (no args) -> { Result, Message }
Remotes.GetIndex = nil -- RemoteFunction : client -> server -> { Discovered, Claimed, Score }
Remotes.ClaimIndexReward = nil -- RemoteFunction : client -> server (milestoneId) -> { Result, Message }
-- M8.2 trading. Client sends INTENT ONLY ({ Action, ... }); server owns all session state.
Remotes.TradeAction = nil -- RemoteEvent  : client -> server, { Action, TargetUserId?, BrainrotId?, Amount?, Accept?, Ready? }
Remotes.TradeUpdate = nil -- RemoteEvent  : server -> client, authoritative session snapshot / request / closed
-- M8.4 events. Client sends INTENT ONLY; server owns time/active-state + grants.
Remotes.GetEvents = nil -- RemoteFunction : client -> server -> active events + progress/currency
Remotes.ClaimEventReward = nil -- RemoteFunction : client -> server (eventKey, objId) -> { Result, Message }
Remotes.EventShopBuy = nil -- RemoteFunction : client -> server (eventKey, entryId) -> { Result, Message }
Remotes.EventsUpdate = nil -- RemoteEvent  : server -> ALL clients, "events changed" ping (re-pull)
-- M8.5 seasons. Client renders replicated season state only; server owns time/score/rewards.
Remotes.GetSeasons = nil -- RemoteFunction : client -> server -> season id, countdown, top-N, my rank/score, tiers
Remotes.SeasonsUpdate = nil -- RemoteEvent  : server -> ALL clients, "season rolled over" ping

-- Every remote name this module creates -- the SINGLE list the boot diagnostic verifies the
-- ReplicatedStorage/Remotes surface against. Keep in sync with Init() below AND the client's
-- `remotes` table (Client.client.lua); a drift here is exactly what the diagnostic catches.
Remotes.ExpectedNames = {
    "PurchaseRequest",
    "GetInventory",
    "Notify",
    "KillFeed",
    "PromptGamepass",
    "PromptProduct",
    "GetMonetization",
    "MonetizationUpdate",
    "Tutorial",
    "GetSettings",
    "SaveSettings",
    "RedeemCode",
    "WhatsNew",
    "RequestRebirth",
    "GetIndex",
    "ClaimIndexReward",
    "TradeAction",
    "TradeUpdate",
    "GetEvents",
    "ClaimEventReward",
    "EventShopBuy",
    "EventsUpdate",
    "GetSeasons",
    "SeasonsUpdate",
}

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

    local killFeed = Instance.new("RemoteEvent")
    killFeed.Name = "KillFeed"
    killFeed.Parent = folder

    local promptGamepass = Instance.new("RemoteEvent")
    promptGamepass.Name = "PromptGamepass"
    promptGamepass.Parent = folder

    local promptProduct = Instance.new("RemoteEvent")
    promptProduct.Name = "PromptProduct"
    promptProduct.Parent = folder

    local getMonetization = Instance.new("RemoteFunction")
    getMonetization.Name = "GetMonetization"
    getMonetization.Parent = folder

    local monetizationUpdate = Instance.new("RemoteEvent")
    monetizationUpdate.Name = "MonetizationUpdate"
    monetizationUpdate.Parent = folder

    local tutorial = Instance.new("RemoteEvent")
    tutorial.Name = "Tutorial"
    tutorial.Parent = folder

    local getSettings = Instance.new("RemoteFunction")
    getSettings.Name = "GetSettings"
    getSettings.Parent = folder

    local saveSettings = Instance.new("RemoteEvent")
    saveSettings.Name = "SaveSettings"
    saveSettings.Parent = folder

    local redeemCode = Instance.new("RemoteFunction")
    redeemCode.Name = "RedeemCode"
    redeemCode.Parent = folder

    local whatsNew = Instance.new("RemoteEvent")
    whatsNew.Name = "WhatsNew"
    whatsNew.Parent = folder

    local requestRebirth = Instance.new("RemoteFunction")
    requestRebirth.Name = "RequestRebirth"
    requestRebirth.Parent = folder

    local getIndex = Instance.new("RemoteFunction")
    getIndex.Name = "GetIndex"
    getIndex.Parent = folder

    local claimIndexReward = Instance.new("RemoteFunction")
    claimIndexReward.Name = "ClaimIndexReward"
    claimIndexReward.Parent = folder

    local tradeAction = Instance.new("RemoteEvent")
    tradeAction.Name = "TradeAction"
    tradeAction.Parent = folder

    local tradeUpdate = Instance.new("RemoteEvent")
    tradeUpdate.Name = "TradeUpdate"
    tradeUpdate.Parent = folder

    local getEvents = Instance.new("RemoteFunction")
    getEvents.Name = "GetEvents"
    getEvents.Parent = folder

    local claimEventReward = Instance.new("RemoteFunction")
    claimEventReward.Name = "ClaimEventReward"
    claimEventReward.Parent = folder

    local eventShopBuy = Instance.new("RemoteFunction")
    eventShopBuy.Name = "EventShopBuy"
    eventShopBuy.Parent = folder

    local eventsUpdate = Instance.new("RemoteEvent")
    eventsUpdate.Name = "EventsUpdate"
    eventsUpdate.Parent = folder

    local getSeasons = Instance.new("RemoteFunction")
    getSeasons.Name = "GetSeasons"
    getSeasons.Parent = folder

    local seasonsUpdate = Instance.new("RemoteEvent")
    seasonsUpdate.Name = "SeasonsUpdate"
    seasonsUpdate.Parent = folder

    folder.Parent = ReplicatedStorage

    Remotes.PurchaseRequest = purchase
    Remotes.GetInventory = getInventory
    Remotes.Notify = notify
    Remotes.KillFeed = killFeed
    Remotes.PromptGamepass = promptGamepass
    Remotes.PromptProduct = promptProduct
    Remotes.GetMonetization = getMonetization
    Remotes.MonetizationUpdate = monetizationUpdate
    Remotes.Tutorial = tutorial
    Remotes.GetSettings = getSettings
    Remotes.SaveSettings = saveSettings
    Remotes.RedeemCode = redeemCode
    Remotes.WhatsNew = whatsNew
    Remotes.RequestRebirth = requestRebirth
    Remotes.GetIndex = getIndex
    Remotes.ClaimIndexReward = claimIndexReward
    Remotes.TradeAction = tradeAction
    Remotes.TradeUpdate = tradeUpdate
    Remotes.GetEvents = getEvents
    Remotes.ClaimEventReward = claimEventReward
    Remotes.EventShopBuy = eventShopBuy
    Remotes.EventsUpdate = eventsUpdate
    Remotes.GetSeasons = getSeasons
    Remotes.SeasonsUpdate = seasonsUpdate
end

-- Sends a toast to a single player. kind = "success" | "error" | "info". Optional `cue` is a
-- short juice key the client maps to an effect (e.g. "buy", "deposit", "robbed") -- purely
-- presentational; it carries no authority.
function Remotes.NotifyPlayer(player, kind, message, cue)
    if Remotes.Notify ~= nil then
        Remotes.Notify:FireClient(player, { Kind = kind, Message = message, Cue = cue })
    end
end

-- Tells one client to begin the first-session onboarding flow (server decides who/when).
function Remotes.StartTutorial(player)
    if Remotes.Tutorial ~= nil then
        Remotes.Tutorial:FireClient(player, "start")
    end
end

-- Tells one client to show the "What's New" card (server decides, once per version bump).
function Remotes.FireWhatsNew(player)
    if Remotes.WhatsNew ~= nil then
        Remotes.WhatsNew:FireClient(player)
    end
end

-- Broadcasts a steal to EVERY client for the kill-feed banner. payload =
-- { Thief, Victim, Name, Rarity } (Rarity is a key the client colors via Shared/Rarity).
function Remotes.BroadcastKillFeed(payload)
    if Remotes.KillFeed ~= nil then
        Remotes.KillFeed:FireAllClients(payload)
    end
end

-- Tells one client a gamepass it can buy is now owned, so the shop flips Buy -> Owned live.
function Remotes.PushMonetizationUpdate(player, passKey, owned)
    if Remotes.MonetizationUpdate ~= nil then
        Remotes.MonetizationUpdate:FireClient(player, { Key = passKey, Owned = owned })
    end
end

return Remotes
