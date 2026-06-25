-- PurchaseService: the secure client -> server purchase flow. The client sends ONLY an
-- item id; the server validates everything against its own catalog and state, and
-- mutates only if every check passes. Nothing from the client is trusted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)

local Remotes = require(script.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)
local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local ProtectionService = require(script.Parent.ProtectionService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)

local PurchaseService = {}

local PURCHASE_COOLDOWN = 0.5 -- seconds; blocks spam / double-spend races
local lastPurchase = {} -- [Player] = os.clock()

-- TRUST BOUNDARY (PurchaseRequest): the client sends ONE thing -- an item id (string). The
-- server resolves the real price/income from its own Catalog, verifies a loaded profile, a free
-- pad, and affordability, then spends + grants atomically. Nothing else from the client is read
-- or trusted (no price, no income, no pad, no cash). Rate-limited per player below.
local function onPurchase(player, itemId)
    -- Rate-limit before doing anything so spamming can't race the economy.
    local now = os.clock()
    local last = lastPurchase[player]
    if last ~= nil and now - last < PURCHASE_COOLDOWN then
        return
    end
    lastPurchase[player] = now

    -- The client sends only an id; resolve the real item from the server catalog.
    if type(itemId) ~= "string" then
        return
    end
    local item = Catalog.Get(itemId)
    if item == nil or item.Buyable == false then
        Remotes.NotifyPlayer(player, "error", "That item is unavailable.")
        return
    end

    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end

    local plot = PlotService.GetPlot(player)
    if plot == nil then
        Remotes.NotifyPlayer(player, "error", "Your base isn't ready yet.")
        return
    end

    -- Need a free pad BEFORE spending (shared authority: excludes owned pads AND pads reserved
    -- for an in-progress steal deposit, so a purchase and a steal never collide on a pad).
    local padIndex = PlotService.FindFreePad(player, profile)
    if padIndex == nil then
        Remotes.NotifyPlayer(player, "error", "No free pads")
        return
    end

    -- Atomic, guarded spend at the SERVER-side price. No yields between the affordability check
    -- and the deduct, so it can't be raced into negative cash. Routes through the single cash
    -- accessor; the client never sends or influences the amount.
    if not ProfileManager.TrySpend(player, item.Price) then
        Remotes.NotifyPlayer(player, "error", "Not enough cash")
        return
    end

    -- Cash purchases are THE mutation source: the factory rolls a server-side mutation.
    local brainrot =
        BrainrotFactory.create(player, item, padIndex, BrainrotFactory.RollFor.Purchase)
    table.insert(profile.Data.OwnedBrainrots, brainrot)

    -- Record the acquire for the later Index (set of roster Ids ever owned).
    profile.Data.Discovered[item.Id] = true

    -- Reuse M1's placement so spawn logic lives in exactly one place.
    BrainrotService.SpawnBrainrot(player, plot, brainrot)
    -- If the buyer's plot is currently protected, the new unit's steal prompt must stay
    -- disabled too (re-applies protection state to the freshly spawned prompt).
    ProtectionService.RefreshPrompts(player)

    -- Refresh replicated display values + the player-list leaderstat. ProfileStore
    -- auto-saves; the deducted cash and new brainrot persist with no manual save.
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)

    Remotes.NotifyPlayer(player, "success", "Bought " .. item.DisplayName .. "!", "buy")

    -- Analytics (pcall-wrapped inside; can't affect gameplay): cash SINK, onboarding funnel
    -- (first purchase, then "hooked" at 3+ units), and a first-Legendary+ tier-up milestone.
    Analytics.economySink(player, item.Price, profile.Data.Cash, Analytics.Tx.Shop, item.Id)
    Analytics.funnelStepOnce(player, Analytics.Funnel.FirstPurchase)
    if #profile.Data.OwnedBrainrots >= 3 then
        Analytics.funnelStepOnce(player, Analytics.Funnel.Hooked)
    end
    if Rarity.Get(item.Rarity).Order >= 4 then
        Analytics.customOnce(player, Analytics.Events.TierUp, Rarity.Get(item.Rarity).Order)
    end
end

function PurchaseService.Init()
    Remotes.PurchaseRequest.OnServerEvent:Connect(onPurchase)
    Players.PlayerRemoving:Connect(function(player)
        lastPurchase[player] = nil
    end)
end

return PurchaseService
