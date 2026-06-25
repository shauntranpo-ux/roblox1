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
-- M9.4 set perks. Client sends INTENT ONLY (a set Key); server verifies completion + grants once.
Remotes.ClaimSetPerk = nil -- RemoteFunction : client -> server (setKey) -> { Result, Message }
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
-- M9.1 sell. Client sends INTENT ONLY (a unit Id, or a bulk filter); server computes value + sells.
Remotes.SellRequest = nil -- RemoteFunction : client -> server ({ Action, Id?/Mode?, Confirm? }) -> result
-- M9.2 fusion. Client sends INTENT ONLY (the fodder unit Ids + mode); server rolls + fuses.
Remotes.FuseRequest = nil -- RemoteFunction : client -> server ({ FodderIds, Mode? }) -> result
-- M11.1 loadout. Client sends INTENT ONLY (a unit Id + perk slot, or a slot to unequip / "get").
Remotes.LoadoutRequest = nil -- RemoteFunction : client -> server ({ Action, UnitId?, Slot? }) -> result
-- M11.2 evolve. Client sends INTENT ONLY (which unit Id to evolve); server validates + evolves atomically.
Remotes.EvolveRequest = nil -- RemoteFunction : client -> server (unitId) -> { Result, Message, Stage? }
-- M11.3 world bosses. Server -> ALL clients: boss spawn alert, live catch-meter snapshots, defeat/flee
-- broadcasts. The boss fight itself is driven by a server-side ProximityPrompt (no client attack remote
-- -- the client never asserts HP/contribution/death).
Remotes.BossUpdate = nil -- RemoteEvent : server -> clients, { Kind, Name?, Biome?, HP?, Max?, Pos?, TimeLeft?, Damage? } (Kind="hit" is targeted to the attacker)
-- M10.1 wild-catch. WildUpdate streams a player's OWN instanced spawns to them (the client renders +
-- holds + catches); WildCatch is the catch INTENT (a spawn id). Server owns the registry + validation.
Remotes.WildUpdate = nil -- RemoteEvent : server -> owner client, { Kind="spawn"|"move"|"despawn", Id, ... }
Remotes.WildCatch = nil -- RemoteFunction : client -> server (spawnId) -> { Result, Name?/Message? }
-- M10.2 biomes. Client sends INTENT ONLY ({ Action="get"|"unlock", BiomeId? }); server owns zone
-- membership + unlock validation + persistence.
Remotes.BiomeAction = nil -- RemoteFunction : client -> server ({ Action, BiomeId? }) -> { Result, State?/Message }
-- M10.3 shared rare events. Server -> ALL clients: the mystery-spawn alert, position updates, and the
-- caught/escape outcome. The catch itself fires server-side (a ProximityPrompt on the world entity).
Remotes.SharedEvent = nil -- RemoteEvent : server -> ALL clients, { Kind="spawn"|"update"|"caught"|"escape"|"gone", ... }
-- M10.4 nets. Client sends INTENT ONLY ({ Action="get"|"upgrade" }); the server owns the net tier +
-- the effective catch params. (The Pro Net gamepass purchase reuses PromptGamepass.)
Remotes.NetAction = nil -- RemoteFunction : client -> server ({ Action }) -> { Result, State?/Message }
-- M12.1 quests. Client sends CLAIM INTENT only (scope + quest id); the server owns progress + grants.
Remotes.GetQuests = nil -- RemoteFunction : client -> server () -> quest state (tutorial/daily/weekly/milestone)
Remotes.ClaimQuest = nil -- RemoteFunction : client -> server (scope, questId) -> { Result, Message }
Remotes.QuestsUpdate = nil -- RemoteEvent : server -> a client, a ping that quest state changed (refetch)
-- M12.2 free rewards. Client sends CLAIM/SPIN INTENT only (an action string); the server owns all
-- cooldown/streak/spin state + rolls RNG server-side.
Remotes.FreeRewardAction = nil -- RemoteFunction : client -> server (action) -> { Result, State?/Message }
Remotes.FreeRewardUpdate = nil -- RemoteEvent : server -> a client, a ping that free-reward state changed
-- M11.4 seasonal exclusives. Client sends INTENT ONLY ({ Action="get"|"buy", Key? }); server gates by
-- server-time season window + the idempotent claim set.
Remotes.ExclusiveAction = nil -- RemoteFunction : client -> server ({ Action, Key? }) -> { Result, State?/Message }

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
    "ClaimSetPerk",
    "TradeAction",
    "TradeUpdate",
    "GetEvents",
    "ClaimEventReward",
    "EventShopBuy",
    "EventsUpdate",
    "GetSeasons",
    "SeasonsUpdate",
    "SellRequest",
    "FuseRequest",
    "LoadoutRequest",
    "EvolveRequest",
    "BossUpdate",
    "ExclusiveAction",
    "WildUpdate",
    "WildCatch",
    "BiomeAction",
    "SharedEvent",
    "NetAction",
    "GetQuests",
    "ClaimQuest",
    "QuestsUpdate",
    "FreeRewardAction",
    "FreeRewardUpdate",
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

    local claimSetPerk = Instance.new("RemoteFunction")
    claimSetPerk.Name = "ClaimSetPerk"
    claimSetPerk.Parent = folder

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

    local sellRequest = Instance.new("RemoteFunction")
    sellRequest.Name = "SellRequest"
    sellRequest.Parent = folder

    local fuseRequest = Instance.new("RemoteFunction")
    fuseRequest.Name = "FuseRequest"
    fuseRequest.Parent = folder

    local loadoutRequest = Instance.new("RemoteFunction")
    loadoutRequest.Name = "LoadoutRequest"
    loadoutRequest.Parent = folder

    local evolveRequest = Instance.new("RemoteFunction")
    evolveRequest.Name = "EvolveRequest"
    evolveRequest.Parent = folder

    local bossUpdate = Instance.new("RemoteEvent")
    bossUpdate.Name = "BossUpdate"
    bossUpdate.Parent = folder

    local exclusiveAction = Instance.new("RemoteFunction")
    exclusiveAction.Name = "ExclusiveAction"
    exclusiveAction.Parent = folder

    local wildUpdate = Instance.new("RemoteEvent")
    wildUpdate.Name = "WildUpdate"
    wildUpdate.Parent = folder

    local wildCatch = Instance.new("RemoteFunction")
    wildCatch.Name = "WildCatch"
    wildCatch.Parent = folder

    local biomeAction = Instance.new("RemoteFunction")
    biomeAction.Name = "BiomeAction"
    biomeAction.Parent = folder

    local sharedEvent = Instance.new("RemoteEvent")
    sharedEvent.Name = "SharedEvent"
    sharedEvent.Parent = folder

    local netAction = Instance.new("RemoteFunction")
    netAction.Name = "NetAction"
    netAction.Parent = folder

    local getQuests = Instance.new("RemoteFunction")
    getQuests.Name = "GetQuests"
    getQuests.Parent = folder

    local claimQuest = Instance.new("RemoteFunction")
    claimQuest.Name = "ClaimQuest"
    claimQuest.Parent = folder

    local questsUpdate = Instance.new("RemoteEvent")
    questsUpdate.Name = "QuestsUpdate"
    questsUpdate.Parent = folder

    local freeRewardAction = Instance.new("RemoteFunction")
    freeRewardAction.Name = "FreeRewardAction"
    freeRewardAction.Parent = folder

    local freeRewardUpdate = Instance.new("RemoteEvent")
    freeRewardUpdate.Name = "FreeRewardUpdate"
    freeRewardUpdate.Parent = folder

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
    Remotes.ClaimSetPerk = claimSetPerk
    Remotes.TradeAction = tradeAction
    Remotes.TradeUpdate = tradeUpdate
    Remotes.GetEvents = getEvents
    Remotes.ClaimEventReward = claimEventReward
    Remotes.EventShopBuy = eventShopBuy
    Remotes.EventsUpdate = eventsUpdate
    Remotes.GetSeasons = getSeasons
    Remotes.SeasonsUpdate = seasonsUpdate
    Remotes.SellRequest = sellRequest
    Remotes.FuseRequest = fuseRequest
    Remotes.LoadoutRequest = loadoutRequest
    Remotes.EvolveRequest = evolveRequest
    Remotes.BossUpdate = bossUpdate
    Remotes.ExclusiveAction = exclusiveAction
    Remotes.WildUpdate = wildUpdate
    Remotes.WildCatch = wildCatch
    Remotes.BiomeAction = biomeAction
    Remotes.SharedEvent = sharedEvent
    Remotes.NetAction = netAction
    Remotes.GetQuests = getQuests
    Remotes.ClaimQuest = claimQuest
    Remotes.QuestsUpdate = questsUpdate
    Remotes.FreeRewardAction = freeRewardAction
    Remotes.FreeRewardUpdate = freeRewardUpdate
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

-- Broadcasts a shared rare-event state change to EVERY client (mystery alert / position / outcome).
function Remotes.BroadcastSharedEvent(payload)
    if Remotes.SharedEvent ~= nil then
        Remotes.SharedEvent:FireAllClients(payload)
    end
end

-- Broadcasts a world-boss state change to EVERY client (spawn alert / meter snapshot / defeat / flee).
-- payload = { Kind = "spawn"|"update"|"defeat"|"flee"|"gone", Name?, Biome?, Meter?, Max?, Pos?, TimeLeft? }.
function Remotes.BroadcastBoss(payload)
    if Remotes.BossUpdate ~= nil then
        Remotes.BossUpdate:FireAllClients(payload)
    end
end

-- Tells one client a gamepass it can buy is now owned, so the shop flips Buy -> Owned live.
function Remotes.PushMonetizationUpdate(player, passKey, owned)
    if Remotes.MonetizationUpdate ~= nil then
        Remotes.MonetizationUpdate:FireClient(player, { Key = passKey, Owned = owned })
    end
end

return Remotes
