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
