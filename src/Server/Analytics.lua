-- Analytics: a thin, FAIL-SAFE wrapper over Roblox's AnalyticsService so post-launch I can see
-- retention, the new-player funnel, and economy health. EVERY call is pcall-wrapped, so analytics
-- can NEVER affect gameplay (a bad arg / throttle / API change is swallowed). All event names,
-- funnel steps, currency, and transaction types live in ONE constants block below.
--
-- API SIGNATURES (verify on the Creator docs; they evolve -- everything here is pcall-guarded):
--   AnalyticsService:LogEconomyEvent(player, flowType: Enum.AnalyticsEconomyFlowType,
--       currencyType: string, amount: number, endingBalance: number, transactionType: string,
--       itemSku: string?)
--   AnalyticsService:LogOnboardingFunnelStepEvent(player, step: number, stepName: string?)
--   AnalyticsService:LogCustomEvent(player, eventName: string, value: number?)
-- Transaction-type strings below mirror Enum.AnalyticsEconomyTransactionType item names; we pass
-- the string (defensive against enum-item drift). flowType uses the enum directly.

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

-- ===== ONE constants block =================================================================
Analytics.Currency = "Cash"

Analytics.Tx = { -- economy transaction-type strings (Enum.AnalyticsEconomyTransactionType names)
    Gameplay = "Gameplay", -- passive income
    Shop = "Shop", -- cash purchases (sink)
    IAP = "IAP", -- Robux dev-product grants
    TimedReward = "TimedReward", -- code rewards / boosts
    Sell = "Sell", -- M9.1 selling a brainrot back for cash (source)
}

Analytics.Events = { -- custom (retention/engagement) event names
    SessionStart = "session_start",
    FirstSteal = "first_steal",
    FirstRobbed = "first_robbed",
    TierUp = "tier_up", -- first Legendary+ owned
    GamepassPurchased = "gamepass_purchased",
    CodeRedeemed = "code_redeemed",
    Rebirth = "rebirth", -- M8.1 prestige reset (value = new rebirth count)
    IndexComplete = "index_complete", -- M8.1 completion milestone claimed
    TradeComplete = "trade_complete", -- M8.2 a two-party swap committed
    MutationRoll = "mutation_roll", -- M8.3 a mutation rolled at acquisition (value = income multiplier)
    EventQuestClaim = "event_quest_claim", -- M8.4 an event quest reward claimed
    EventShopBuy = "event_shop_buy", -- M8.4 an event-shop purchase
    SeasonReward = "season_reward", -- M8.5 end-of-season reward granted (value = total cash)
    Sell = "sell", -- M9.1 a sell committed (value = count of units sold)
    Fusion = "fusion", -- M9.2 a successful fusion (value = result star level)
    FusionCrit = "fusion_crit", -- M9.2 a fusion crit (extra stars)
    FusionFail = "fusion_fail", -- M9.2 a soft-fail (value = fodder lost)
    Deploy = "deploy", -- M9.3 a unit deployed to a role (value = unit rarity order)
    Undeploy = "undeploy", -- M9.3 a unit unassigned from a role
    SetComplete = "set_complete", -- M9.4 a themed-set perk claimed
    PerkEquip = "perk_equip", -- M11.1 a unit equipped to a perk slot (value = holder rarity order)
    PerkUnequip = "perk_unequip", -- M11.1 a unit unequipped from a perk slot
    Evolve = "evolve", -- M11.2 a unit evolved (value = the new evolution stage)
    BossSpawn = "boss_spawn", -- M11.3 a world boss spawned
    BossKill = "boss_kill", -- M11.3 a world boss defeated (value = qualifying participant count)
    BossReward = "boss_reward", -- M11.3 a participant received their boss reward
    BossFlee = "boss_flee", -- M11.3 a world boss left un-beaten (timeout)
    ExclusiveGrant = "exclusive_grant", -- M11.4 a seasonal exclusive granted (brainrot/mutation/cosmetic)
    WildSpawn = "wild_spawn", -- M10.1 a wild brainrot spawned (value = rarity order)
    WildCatch = "wild_catch", -- M10.1 a wild brainrot caught (value = rarity order)
    BiomeEnter = "biome_enter", -- M10.2 a player entered a biome (value = biome order)
    BiomeUnlock = "biome_unlock", -- M10.2 a biome unlocked (value = biome order)
    SharedSpawn = "shared_spawn", -- M10.3 a shared rare event spawned (value = rarity order)
    SharedCatch = "shared_catch", -- M10.3 a shared rare event caught (value = rarity order)
    SharedEscape = "shared_escape", -- M10.3 a shared rare event escaped (value = rarity order)
    NetUpgrade = "net_upgrade", -- M10.4 a net upgraded (value = the new tier)
    BossDamage = "boss_damage", -- M11.3-combat total damage a player dealt to a slain boss (value = damage)
    TutorialStep = "tutorial_step", -- M12.1 a tutorial step completed (value = the new step index)
    QuestClaim = "quest_claim", -- M12.1 a daily/weekly/milestone quest reward claimed
    DailyClaim = "daily_claim", -- M12.2 a daily-streak chest claimed (value = streak length)
    GiftClaim = "gift_claim", -- M12.2 a timed free gift claimed
    Spin = "spin", -- M12.2 a wheel spin (value = the landed segment index)
    MysteryOpen = "mystery_open", -- M12.2 the base mystery block opened
    FlagToggle = "flag_toggle", -- M12.3 a favorite/lock toggled (value = 1 set / 0 cleared)
    MassFuse = "mass_fuse", -- M12.3 a mass-fuse (value = groups fused)
}

Analytics.Funnel = { -- new-player onboarding funnel steps { stepNumber, stepName }
    Spawn = { 1, "spawn" },
    SawStarter = { 2, "saw_starter" },
    FirstPurchase = { 3, "first_purchase" },
    Hooked = { 4, "hooked" }, -- owns 3+ brainrots
}
-- ===========================================================================================

-- Per-player session guards so "once" events (funnel steps, firsts) fire at most once per session.
local fired = {} -- [Player] = { [key] = true }

local function once(player, key)
    local perPlayer = fired[player]
    if perPlayer == nil then
        perPlayer = {}
        fired[player] = perPlayer
    end
    if perPlayer[key] then
        return false
    end
    perPlayer[key] = true
    return true
end

local function safeNumber(n)
    n = tonumber(n) or 0
    if n ~= n or n == math.huge or n == -math.huge then
        return 0
    end
    return math.floor(n)
end

-- Economy SOURCE (faucet): income, code/IAP grants. Skipped for non-positive amounts.
function Analytics.economySource(player, amount, endingBalance, transactionType, itemSku)
    amount = safeNumber(amount)
    if amount <= 0 then
        return
    end
    pcall(function()
        AnalyticsService:LogEconomyEvent(
            player,
            Enum.AnalyticsEconomyFlowType.Source,
            Analytics.Currency,
            amount,
            safeNumber(endingBalance),
            transactionType,
            itemSku
        )
    end)
end

-- Economy SINK (drain): cash purchases.
function Analytics.economySink(player, amount, endingBalance, transactionType, itemSku)
    amount = safeNumber(amount)
    if amount <= 0 then
        return
    end
    pcall(function()
        AnalyticsService:LogEconomyEvent(
            player,
            Enum.AnalyticsEconomyFlowType.Sink,
            Analytics.Currency,
            amount,
            safeNumber(endingBalance),
            transactionType,
            itemSku
        )
    end)
end

-- New-player onboarding funnel step (fires at most once per session per step).
function Analytics.funnelStepOnce(player, stepPair)
    if not once(player, "funnel_" .. stepPair[2]) then
        return
    end
    pcall(function()
        AnalyticsService:LogOnboardingFunnelStepEvent(player, stepPair[1], stepPair[2])
    end)
end

-- Custom event (every call).
function Analytics.custom(player, eventName, value)
    pcall(function()
        AnalyticsService:LogCustomEvent(player, eventName, value)
    end)
end

-- Custom event, at most once per session (for "first X" milestones).
function Analytics.customOnce(player, eventName, value)
    if not once(player, "custom_" .. eventName) then
        return
    end
    Analytics.custom(player, eventName, value)
end

function Analytics.clearPlayer(player)
    fired[player] = nil
end

return Analytics
