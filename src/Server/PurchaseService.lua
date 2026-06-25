-- PurchaseService: the secure client -> server purchase flow. The client sends ONLY an
-- item id; the server validates everything against its own catalog and state, and
-- mutates only if every check passes. Nothing from the client is trusted.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local Remotes = require(script.Parent.Remotes)
local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)

local PurchaseService = {}

local PURCHASE_COOLDOWN = 0.5 -- seconds; blocks spam / double-spend races
local lastPurchase = {} -- [Player] = os.clock()

-- Finds the lowest free PadIndex on the player's plot that actually has a pad part.
local function findFreePad(player, profile)
    local pads = PlotService.GetPads(player)
    local used = {}
    for _, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        used[brainrot.PadIndex] = true
    end
    for index = 1, Config.Plots.PadsPerPlot do
        if pads[index] ~= nil and not used[index] then
            return index
        end
    end
    return nil
end

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

    -- Affordability is checked against server truth, using the server-side price.
    if profile.Data.Cash < item.Price then
        Remotes.NotifyPlayer(player, "error", "Not enough cash")
        return
    end

    local padIndex = findFreePad(player, profile)
    if padIndex == nil then
        Remotes.NotifyPlayer(player, "error", "No free pads")
        return
    end

    -- All checks passed -- mutate state once.
    profile.Data.Cash -= item.Price
    local brainrot = {
        Id = HttpService:GenerateGUID(false),
        Type = item.Id,
        IncomePerSec = item.IncomePerSec,
        PadIndex = padIndex,
    }
    table.insert(profile.Data.OwnedBrainrots, brainrot)

    -- Reuse M1's placement so spawn logic lives in exactly one place.
    BrainrotService.SpawnBrainrot(player, plot, brainrot)

    -- Refresh replicated display values + the player-list leaderstat. ProfileStore
    -- auto-saves; the deducted cash and new brainrot persist with no manual save.
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)

    Remotes.NotifyPlayer(player, "success", "Bought " .. item.Name .. "!")
end

function PurchaseService.Init()
    Remotes.PurchaseRequest.OnServerEvent:Connect(onPurchase)
    Players.PlayerRemoving:Connect(function(player)
        lastPurchase[player] = nil
    end)
end

return PurchaseService
