-- MonetizationService: the entire Robux money path. Owns gamepass ownership (cached + live),
-- the BENEFIT REGISTRY that applies each perk server-side + idempotently, the SINGLE
-- ProcessReceipt callback for developer products (perfectly idempotent + crash-safe), the
-- premium-brainrot grant, and the prompt plumbing. NOTHING is ever trusted from the client --
-- the client may only REQUEST a Marketplace prompt; Roblox + this server own every outcome.
--
-- ============================  SELF-AUDIT (money path)  =====================================
-- 1. DOUBLE-GRANT / CRASH SAFETY (developer products):
--    * Dedupe is persisted in profile.Data.PurchaseHistory[PurchaseId]. The grant mutation AND
--      the PurchaseId record are written together with NO yields between them (applyReceiptCore
--      -> apply(); PurchaseHistory[id]=true), so ProfileStore persists them atomically. A crash
--      can never leave one without the other.
--    * Already-recorded PurchaseId -> grant nothing, return PurchaseGranted (stops retries).
--    * Profile not loaded / player gone / unknown product / can't place premium unit -> grant
--      nothing, return NotProcessedYet (Roblox safely retries later, even next session).
--    * A receipt re-delivered across a restart is caught by the PERSISTED PurchaseHistory, so it
--      is never granted twice.
-- 2. INCOME-MULTIPLIER DOUBLE-STACK: each multiplier source is keyed (Benefits.SetIncomeSource
--    "gp:<passKey>"). Applying a benefit again (join re-verify OR live PromptFinished) overwrites
--    the same key -> the effective multiplier is recomputed, never accumulated. Pads are likewise
--    recomputed from sources (never incremented in place) except the receipt-deduped product add.
-- 3. ORDERED-DATASTORE writes live in LeaderboardService (floored, clamped, throttled, pcall'd).
-- 4. CLIENT AUTHORITY: the only client inputs are "please prompt pass/product KEY". Ownership is
--    read from MarketplaceService (or SIM), grants flow only through ProcessReceipt / verified
--    ownership. No client value is trusted.
-- ===========================================================================================

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Monetization)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Config = require(ReplicatedStorage.Shared.Config)

local DevConfig = require(script.Parent.DevConfig)
local Benefits = require(script.Parent.Benefits)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local ProtectionService = require(script.Parent.ProtectionService)
local BrainrotService = require(script.Parent.BrainrotService)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local Remotes = require(script.Parent.Remotes)

local MonetizationService = {}

-- Session state (all cleared on leave). None is persisted except via the benefit it drives.
local ownedCache = {} -- [Player] = { [gamePassId] = bool } -- real ownership, checked once per session
local simOwned = {} -- [Player] = { [passKey] = true } -- simulated ownership (SIM mode only)
local gamepassPadBonus = {} -- [Player] = number -- pads from the Extra Pads gamepass (session)
local reinforcedOwners = {} -- [Player] = minSeconds -- Reinforced Lock auto-renew set
local vipPlayers = {} -- [Player] = true -- VIP nametag re-apply on respawn

-- Built from config at Init (only configured, non-zero Ids).
local gamepassByPassId = {} -- [gamePassId] = { Key, Def }
local productByProductId = {} -- [productId] = { Key, Def }

local OWNERSHIP_RETRIES = 3
local RENEW_INTERVAL = 30 -- s between Reinforced Lock top-ups (< MinProtectionSeconds)

-- ===========================================================================================
-- Ownership
-- ===========================================================================================

-- UserOwnsGamePassAsync with pcall + exponential backoff. On persistent failure returns false
-- (we never GRANT on uncertainty). Yields.
local function userOwnsGamepassWithRetry(userId, passId)
    for attempt = 1, OWNERSHIP_RETRIES do
        local ok, result = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
        end)
        if ok then
            return result
        end
        if attempt < OWNERSHIP_RETRIES then
            task.wait(0.5 * 2 ^ attempt) -- 1s, 2s backoff
        end
    end
    return false
end

-- True if the player owns the pass (SIM-aware). Reads cache/sim only -- never hits the web here.
local function ownsPass(player, passKey)
    local gp = Monetization.Gamepasses[passKey]
    if gp == nil then
        return false
    end
    if DevConfig.SimMode then
        local s = simOwned[player]
        return s ~= nil and s[passKey] == true
    end
    local cache = ownedCache[player]
    return gp.Id ~= 0 and cache ~= nil and cache[gp.Id] == true
end

-- ===========================================================================================
-- Pads (recomputed from sources -> always idempotent, routed through the M3 setter)
-- ===========================================================================================
local function recomputePads(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    local base = Config.Plots.DefaultUnlockedPads
    local productPads = profile.Data.PadProducts or 0
    local gpPads = gamepassPadBonus[player] or 0
    ProfileManager.SetUnlockedPads(player, base + productPads + gpPads)
end

-- ===========================================================================================
-- VIP nametag (cosmetic, server-built so everyone sees it)
-- ===========================================================================================
local function applyVipTag(player)
    local character = player.Character
    if character == nil then
        return
    end
    local head = character:FindFirstChild("Head")
    if head == nil or head:FindFirstChild("VIPTag") ~= nil then
        return
    end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "VIPTag"
    billboard.Size = UDim2.fromScale(3.6, 1)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = head

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.Text = "VIP"
    label.TextColor3 = Color3.fromRGB(255, 200, 40)
    label.TextStrokeTransparency = 0.35
    label.TextScaled = true
    label.Parent = billboard

    billboard.Parent = head
end

-- ===========================================================================================
-- Benefit registry: one server-side function per benefit Type. Each is IDEMPOTENT -- safe to
-- run on join, on live purchase, and re-run any time without double-applying.
-- ===========================================================================================
local benefitHandlers = {}

benefitHandlers.IncomeMultiplier = function(player, passKey, benefit)
    -- Keyed source -> re-applying overwrites, never double-stacks. bonus = multiplier - 1.
    Benefits.SetIncomeSource(player, "gp:" .. passKey, benefit.Multiplier - 1)
    local profile = ProfileManager.GetProfile(player)
    if profile ~= nil then
        PlayerStats.UpdateIncome(player, profile) -- reflect the boosted rate on the HUD now
    end
end

benefitHandlers.ExtraPads = function(player, _passKey, benefit)
    gamepassPadBonus[player] = benefit.Pads -- overwrite (not add) -> idempotent
    recomputePads(player)
end

benefitHandlers.ReinforcedLock = function(player, _passKey, benefit)
    reinforcedOwners[player] = benefit.MinProtectionSeconds
    ProtectionService.MaintainAtLeast(player, benefit.MinProtectionSeconds)
end

benefitHandlers.VIP = function(player, _passKey, benefit)
    vipPlayers[player] = true
    player:SetAttribute("VIP", true)
    Benefits.SetStealCooldownMult(player, benefit.StealCooldownMult)
    applyVipTag(player)
end

local function applyBenefit(player, passKey, benefit)
    local handler = benefitHandlers[benefit.Type]
    if handler == nil then
        warn("[Monetization] No benefit handler for type: " .. tostring(benefit.Type))
        return
    end
    handler(player, passKey, benefit)
end

-- ===========================================================================================
-- Developer-product receipts (idempotent + crash-safe)
-- ===========================================================================================

-- Validates a grant WITHOUT mutating anything and returns a closure that performs the mutation,
-- or nil if it can't be granted right now (-> NotProcessedYet, retried later). Splitting
-- "can we?" from "do it" keeps the commit step free of any failure surface.
local function prepareGrant(player, profile, grant)
    local t = grant.Type
    if t == "Cash" then
        local amount = grant.Amount
        return function()
            ProfileManager.AddCash(player, amount) -- single guarded cash accessor
        end
    elseif t == "Pads" then
        local pads = grant.Pads
        return function()
            profile.Data.PadProducts += pads
            recomputePads(player)
        end
    elseif t == "Brainrot" then
        local def = Catalog.Get(grant.BrainrotId)
        if def == nil then
            return nil -- misconfigured BrainrotId; retry later rather than grant nothing wrong
        end
        local plot = PlotService.GetPlot(player)
        if plot == nil then
            return nil
        end
        local padIndex = PlotService.FindFreePad(player, profile)
        if padIndex == nil then
            Remotes.NotifyPlayer(
                player,
                "error",
                "Free a pad to receive " .. def.DisplayName .. "!"
            )
            return nil -- no home for it yet; Roblox retries (incl. next session)
        end
        return function()
            local brainrot =
                BrainrotFactory.create(player, def, padIndex, BrainrotFactory.RollFor.Product)
            table.insert(profile.Data.OwnedBrainrots, brainrot)
            profile.Data.Discovered[def.Id] = true
            BrainrotService.SpawnBrainrot(player, plot, brainrot)
            ProtectionService.RefreshPrompts(player)
        end
    end
    return nil
end

-- The shared grant core used by BOTH the real ProcessReceipt and the SIM path, so they are
-- byte-for-byte the same dedupe + grant + record logic. Returns an Enum.ProductPurchaseDecision.
local function applyReceiptCore(player, profile, def, purchaseId)
    -- IDEMPOTENT: already granted this PurchaseId -> grant nothing, stop the retries.
    if profile.Data.PurchaseHistory[purchaseId] then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end

    local apply = prepareGrant(player, profile, def.Grant)
    if apply == nil then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- ===== COMMIT: mutate Data AND record the receipt with NO yields between them. =====
    apply()
    profile.Data.PurchaseHistory[purchaseId] = true
    -- ==================================================================================

    -- Post-commit (not part of the atomic mutation): refresh displays + toast.
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
    Remotes.NotifyPlayer(player, "success", "Purchase complete: " .. def.Name)
    -- Analytics: Robux-driven cash grants as an economy SOURCE (IAP).
    if def.Grant.Type == "Cash" then
        Analytics.economySource(
            player,
            def.Grant.Amount,
            profile.Data.Cash,
            Analytics.Tx.IAP,
            "product:" .. def.Name
        )
    end
    return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- THE single ProcessReceipt callback for the whole game (registering two would drop purchases).
local function processReceipt(receiptInfo)
    local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
    if player == nil then
        return Enum.ProductPurchaseDecision.NotProcessedYet -- not in game; retry later
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return Enum.ProductPurchaseDecision.NotProcessedYet -- profile not loaded; NEVER grant
    end
    local entry = productByProductId[receiptInfo.ProductId]
    if entry == nil then
        return Enum.ProductPurchaseDecision.NotProcessedYet -- unknown product; don't grant blind
    end
    return applyReceiptCore(player, profile, entry.Def, receiptInfo.PurchaseId)
end

-- ===========================================================================================
-- Prompts (client only REQUESTS; outcome owned by Roblox + server)
-- ===========================================================================================
local function simGrantGamepass(player, passKey)
    local gp = Monetization.Gamepasses[passKey]
    if gp == nil then
        return
    end
    simOwned[player] = simOwned[player] or {}
    simOwned[player][passKey] = true
    applyBenefit(player, passKey, gp.Benefit)
    Remotes.PushMonetizationUpdate(player, passKey, true)
    Remotes.NotifyPlayer(player, "success", "[SIM] Granted " .. gp.Name)
end

-- TRUST BOUNDARY (PromptGamepass / PromptProduct): the client sends ONLY a config KEY (string)
-- asking to be SHOWN a purchase prompt. The server never grants here -- ownership is read from
-- MarketplaceService (or SIM) and dev-product grants flow exclusively through ProcessReceipt.
-- Rate-limited so a flood can't spam real Robux prompts.
local function onPromptGamepass(player, passKey)
    if type(passKey) ~= "string" then
        return
    end
    if not RateLimiter.check(player, "promptGamepass", 1) then
        return
    end
    local gp = Monetization.Gamepasses[passKey]
    if gp == nil then
        return
    end
    if ownsPass(player, passKey) then
        Remotes.PushMonetizationUpdate(player, passKey, true) -- already owned; resync the button
        return
    end
    if DevConfig.SimMode then
        simGrantGamepass(player, passKey)
        return
    end
    if gp.Id == 0 then
        Remotes.NotifyPlayer(player, "error", "That pass isn't available yet.")
        return
    end
    pcall(function()
        MarketplaceService:PromptGamePassPurchase(player, gp.Id)
    end)
end

local function onPromptProduct(player, productKey)
    if type(productKey) ~= "string" then
        return
    end
    if not RateLimiter.check(player, "promptProduct", 1) then
        return
    end
    local def = Monetization.Products[productKey]
    if def == nil then
        return
    end
    if DevConfig.SimMode then
        MonetizationService.SimFireProduct(player, productKey)
        return
    end
    if def.Id == 0 then
        Remotes.NotifyPlayer(player, "error", "That item isn't available yet.")
        return
    end
    pcall(function()
        MarketplaceService:PromptProductPurchase(player, def.Id)
    end)
end

local function onPromptGamepassFinished(player, gamePassId, wasPurchased)
    if not wasPurchased then
        return
    end
    local entry = gamepassByPassId[gamePassId]
    if entry == nil then
        return
    end
    local cache = ownedCache[player]
    if cache == nil then
        cache = {}
        ownedCache[player] = cache
    end
    cache[gamePassId] = true
    applyBenefit(player, entry.Key, entry.Def.Benefit) -- idempotent
    Remotes.PushMonetizationUpdate(player, entry.Key, true)
    Remotes.NotifyPlayer(player, "success", "Unlocked " .. entry.Def.Name .. "!")
    Analytics.custom(player, Analytics.Events.GamepassPurchased, gamePassId)
end

-- ===========================================================================================
-- Public API
-- ===========================================================================================

-- Join: verify ownership of every configured pass (cached for the session), apply owned
-- benefits, and recompute pads. Yields (web ownership checks). Call AFTER the profile loads.
function MonetizationService.SetupPlayer(player, _profile)
    ownedCache[player] = ownedCache[player] or {}
    recomputePads(player) -- baseline from default + any persisted pad products

    for passKey, gp in pairs(Monetization.Gamepasses) do
        local owned
        if DevConfig.SimMode then
            owned = ownsPass(player, passKey) -- pre-seeded sim ownership, if any
        elseif gp.Id ~= 0 then
            owned = userOwnsGamepassWithRetry(player.UserId, gp.Id)
            ownedCache[player][gp.Id] = owned
        else
            owned = false
        end
        if owned then
            applyBenefit(player, passKey, gp.Benefit)
        end
    end
end

-- Returns the per-player monetization state the shop renders from (owned map + SIM flag).
function MonetizationService.GetState(player)
    local owned = {}
    for passKey in pairs(Monetization.Gamepasses) do
        owned[passKey] = ownsPass(player, passKey)
    end
    return { Owned = owned, SimMode = DevConfig.SimMode }
end

-- SIM (Studio only): pretend the player owns a gamepass and apply it. Callable from the command
-- bar:  require(game.ServerScriptService.Server.MonetizationService).SimGrantGamepass(game.Players.YOURNAME, "DoubleCash")
function MonetizationService.SimGrantGamepass(player, passKey)
    if not DevConfig.SimMode then
        warn("[Monetization] SimGrantGamepass ignored -- SIM mode is OFF.")
        return
    end
    simGrantGamepass(player, passKey)
end

-- SIM (Studio only): fire a developer-product grant through the REAL receipt codepath. By
-- default uses a STABLE PurchaseId per (player, product), so firing it repeatedly grants EXACTLY
-- once (proves idempotency). Pass { Fresh = true } to simulate a brand-new purchase.
function MonetizationService.SimFireProduct(player, productKey, opts)
    if not DevConfig.SimMode then
        warn("[Monetization] SimFireProduct ignored -- SIM mode is OFF.")
        return
    end
    local def = Monetization.Products[productKey]
    if def == nil then
        warn("[Monetization] SIM: unknown product '" .. tostring(productKey) .. "'")
        return
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    local purchaseId = "SIM-" .. productKey
    if opts ~= nil and opts.Fresh then
        purchaseId = purchaseId .. "-" .. HttpService:GenerateGUID(false)
    end
    local decision = applyReceiptCore(player, profile, def, purchaseId)
    print(
        string.format(
            "[Monetization] SIM product '%s' -> %s (PurchaseId=%s)",
            productKey,
            tostring(decision),
            purchaseId
        )
    )
end

function MonetizationService.ClearPlayer(player)
    ownedCache[player] = nil
    simOwned[player] = nil
    gamepassPadBonus[player] = nil
    reinforcedOwners[player] = nil
    vipPlayers[player] = nil
    Benefits.ClearPlayer(player)
end

function MonetizationService.Init()
    -- Build the Id -> config lookups (configured items only).
    for passKey, gp in pairs(Monetization.Gamepasses) do
        if gp.Id ~= 0 then
            gamepassByPassId[gp.Id] = { Key = passKey, Def = gp }
        end
    end
    for productKey, def in pairs(Monetization.Products) do
        if def.Id ~= 0 then
            productByProductId[def.Id] = { Key = productKey, Def = def }
        end
    end

    -- THE one receipt callback for the whole game.
    MarketplaceService.ProcessReceipt = processReceipt

    -- Live gamepass purchases (real path).
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPromptGamepassFinished)

    -- Client prompt requests + state query.
    Remotes.PromptGamepass.OnServerEvent:Connect(onPromptGamepass)
    Remotes.PromptProduct.OnServerEvent:Connect(onPromptProduct)
    Remotes.GetMonetization.OnServerInvoke = function(player)
        return MonetizationService.GetState(player)
    end

    -- VIP nametag survives respawns.
    local function hookCharacters(player)
        player.CharacterAdded:Connect(function()
            if vipPlayers[player] then
                task.defer(applyVipTag, player)
            end
        end)
    end
    Players.PlayerAdded:Connect(hookCharacters)
    for _, player in ipairs(Players:GetPlayers()) do
        hookCharacters(player)
    end

    -- Reinforced Lock auto-renew: keep owners' shields topped up so they never lapse.
    task.spawn(function()
        while true do
            task.wait(RENEW_INTERVAL)
            for player, minSeconds in pairs(reinforcedOwners) do
                if player.Parent == Players then
                    ProtectionService.MaintainAtLeast(player, minSeconds)
                end
            end
        end
    end)

    if DevConfig.SimMode then
        print(
            "[Monetization] SIM MODE ON (Studio): gamepasses/products are simulated, no Robux spent."
        )
    else
        print("[Monetization] LIVE mode: real MarketplaceService + ProcessReceipt + ownership.")
    end
end

return MonetizationService
