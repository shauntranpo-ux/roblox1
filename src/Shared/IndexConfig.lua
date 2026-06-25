-- IndexConfig: the Collection Index completion milestones + their rewards. Data-driven; retune
-- here. Rewards reuse existing grant paths:
--   { Type = "Cash",       Amount = n }            -> guarded AddCash
--   { Type = "Multiplier", Bonus = b }             -> a keyed completion income source (ADDITIVE,
--                                                      under the existing global cap), Id-keyed so
--                                                      claiming once is permanent + idempotent
--   { Type = "Brainrot",   BrainrotId = "id" }     -> placed on a free pad via the factory
--
-- PREMIUM/LIMITED units are NOT required for free completion (IncludePremiumInCompletion = false)
-- so paywalled units never block a free player from 100%. (A separate premium track could be added
-- later via the same ClaimedIndexRewards pattern.)

local IndexConfig = {}

IndexConfig.IncludePremiumInCompletion = false

-- Milestone types:
--   Rarity     -> discovered EVERY (non-premium) roster Id of `Rarity`.
--   Total      -> discovered at least `Count` distinct roster Ids.
--   FullRoster -> discovered every (non-premium) roster Id.
IndexConfig.Milestones = {
    {
        Id = "total_3",
        Name = "Getting Started",
        Type = "Total",
        Count = 3,
        Reward = { Type = "Cash", Amount = 5000 },
    },
    {
        Id = "rarity_Common",
        Name = "Common Complete",
        Type = "Rarity",
        Rarity = "Common",
        Reward = { Type = "Cash", Amount = 25000 },
    },
    {
        Id = "total_8",
        Name = "Collector",
        Type = "Total",
        Count = 8,
        Reward = { Type = "Multiplier", Bonus = 0.1 },
    },
    {
        Id = "rarity_Rare",
        Name = "Rare Complete",
        Type = "Rarity",
        Rarity = "Rare",
        Reward = { Type = "Cash", Amount = 250000 },
    },
    {
        Id = "rarity_Epic",
        Name = "Epic Complete",
        Type = "Rarity",
        Rarity = "Epic",
        Reward = { Type = "Multiplier", Bonus = 0.15 },
    },
    {
        Id = "rarity_Legendary",
        Name = "Legendary Complete",
        Type = "Rarity",
        Rarity = "Legendary",
        Reward = { Type = "Multiplier", Bonus = 0.25 },
    },
    {
        Id = "rarity_Mythic",
        Name = "Mythic Complete",
        Type = "Rarity",
        Rarity = "Mythic",
        Reward = { Type = "Multiplier", Bonus = 0.4 },
    },
    {
        Id = "rarity_Secret",
        Name = "Secret Complete",
        Type = "Rarity",
        Rarity = "Secret",
        Reward = { Type = "Multiplier", Bonus = 0.6 },
    },
    {
        Id = "full_roster",
        Name = "Gotta Own 'Em All",
        Type = "FullRoster",
        Reward = { Type = "Multiplier", Bonus = 1.0 },
    },
}

IndexConfig.ById = {}
for _, m in ipairs(IndexConfig.Milestones) do
    IndexConfig.ById[m.Id] = m
end

return IndexConfig
