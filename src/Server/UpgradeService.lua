-- UpgradeService: the server-authoritative UPGRADES cash sink. Players buy tiered, persisted boosts with
-- cash; each level's effect is pushed through the existing decoupled multiplier channels (Benefits income/
-- luck + two catch attributes read by NetService.EffectiveCatch), all clamped downstream. No dupe surface:
-- buying only spends cash via the atomic ProfileManager.TrySpend and stores an integer level per upgrade.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local Benefits = require(script.Parent.Benefits)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)

local UpgradeService = {}

local function levelOf(profile, key)
    local up = profile.Data.Upgrades
    return (up ~= nil and up[key]) or 0
end

-- Push every upgrade's current effect through the decoupled channels. Idempotent (keyed Benefits sources
-- + attribute writes), so re-applying on rejoin / after each buy can never double-stack.
function UpgradeService.Apply(player, profile)
    profile = profile or ProfileManager.GetProfile(player)
    if profile == nil then
        return
    end
    Benefits.SetIncomeSource(
        player,
        "Upgrades",
        UpgradeConfig.EffectFor("Income", levelOf(profile, "Income"))
    )
    Benefits.SetLuckSource(
        player,
        "Upgrades",
        1 + UpgradeConfig.EffectFor("Luck", levelOf(profile, "Luck"))
    )
    player:SetAttribute(
        "UpgradeHoldReduce",
        UpgradeConfig.EffectFor("CatchSpeed", levelOf(profile, "CatchSpeed"))
    )
    player:SetAttribute(
        "UpgradeRangeAdd",
        UpgradeConfig.EffectFor("CatchRange", levelOf(profile, "CatchRange"))
    )
end

-- Apply on join + republish income/luck readouts with the upgrades active.
function UpgradeService.SetupPlayer(player, profile)
    UpgradeService.Apply(player, profile)
    PlayerStats.UpdateIncome(player, profile)
end

-- The client state snapshot: cash + one row per upgrade (level, effect text, next cost, affordability).
local function getState(player)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    local cash = profile.Data.Cash
    local rows = {}
    for _, key in ipairs(UpgradeConfig.Order) do
        local u = UpgradeConfig.Get(key)
        local level = levelOf(profile, key)
        local nextCost = UpgradeConfig.CostFor(key, level)
        table.insert(rows, {
            Key = key,
            Name = u.Name,
            Icon = u.Icon,
            Desc = u.Desc,
            Level = level,
            MaxLevel = u.MaxLevel,
            Effect = u.Format(level),
            NextCost = nextCost, -- nil = maxed
            CanAfford = nextCost ~= nil and cash >= nextCost,
        })
    end
    return { Result = "Success", State = { Cash = math.floor(cash), Upgrades = rows } }
end

-- Buy the next level of `key`: atomic spend -> increment -> re-apply -> republish -> persist.
local function buy(player, key)
    if not RateLimiter.check(player, "upgrade", 0.15) then
        return { Result = "Error", Message = "Slow down." }
    end
    if type(key) ~= "string" or UpgradeConfig.Get(key) == nil then
        return { Result = "Error", Message = "Unknown upgrade." }
    end
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return { Result = "Error", Message = "Not ready." }
    end
    local level = levelOf(profile, key)
    local cost = UpgradeConfig.CostFor(key, level)
    if cost == nil then
        return { Result = "Error", Message = "Already at max level." }
    end
    if not ProfileManager.TrySpend(player, cost) then
        return { Result = "Error", Message = "Not enough cash." }
    end
    -- ===== committed: cash already deducted atomically; record the level + re-apply (no yields) =====
    profile.Data.Upgrades = profile.Data.Upgrades or {}
    profile.Data.Upgrades[key] = level + 1
    UpgradeService.Apply(player, profile)
    -- ================================================================================================
    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
    ProfileManager.ForceSave(player)
    return getState(player)
end

function UpgradeService.Init()
    Remotes.GetUpgrades.OnServerInvoke = function(player)
        return getState(player)
    end
    Remotes.UpgradeAction.OnServerInvoke = function(player, payload)
        local key = type(payload) == "table" and payload.Key or payload
        return buy(player, key)
    end
end

return UpgradeService
