-- SetsConfig (M9.4): THE single source of truth for INDEX SET PERKS. Completing a themed SET (every
-- member discovered) grants a PERMANENT passive perk -- the reason to KEEP units, not just sell them.
--
-- COMPLETION BASIS = the player's DISCOVERED set (every roster Id ever owned), NOT currently-owned.
-- So selling / fusing a member AFTER completing a set NEVER revokes the set or its perk (the perk is
-- permanent once claimed). This mirrors the Index milestone rule exactly.
--
-- PREMIUM TRACK: a set may set Premium = true to mark it as a SEPARATE / OPTIONAL track whose members
-- are paywalled (Robux-gated units). NO free set contains a premium member, so premium units can NEVER
-- block a free player from completing the free sets. The premium set simply stays locked until its
-- paywalled member is owned.
--
-- Reward types (each REUSES an existing, guarded grant path -- no new plumbing):
--   { Type = "Cash",      Amount = n }            -> guarded AddCash (one-time)
--   { Type = "Multiplier", Bonus = b }            -> keyed income source "set:<Key>" (permanent,
--                                                     ADDITIVE, under the existing global cap)
--   { Type = "Luck",      Mult = m }              -> keyed luck source "set:<Key>" (permanent,
--                                                     multiplicative; the mutation roll respects it)
--   { Type = "Brainrot",  BrainrotId = "id" }     -> placed on a FREE pad via the factory (claimed
--                                                     ONLY if it actually places -- never dupes/loses)
--
-- Retune EVERYTHING here: which members theme a set, and the reward each grants.

local SetsConfig = {}

SetsConfig.Sets = {
    -- A tiny TEST/onboarding set: the free starter + the two cheapest Commons. Easy to complete in
    -- the first minute, so the set-perk loop is felt immediately.
    {
        Key = "starter_trio",
        Name = "Starter Trio",
        Members = { "tung_sahur", "trippi_troppi", "frigo_camelo" },
        Reward = { Type = "Cash", Amount = 5000 },
    },
    -- The reference's "collect Normals for +0.1x cash": every Common -> a permanent income multiplier.
    {
        Key = "common_crew",
        Name = "Common Crew",
        Members = {
            "tung_sahur",
            "trippi_troppi",
            "frigo_camelo",
            "brr_patapim",
            "boneca_ambalabu",
            "bombombini",
            "trulimero",
        },
        Reward = { Type = "Multiplier", Bonus = 0.1 },
    },
    -- Every Rare -> a permanent LUCK boost (better mutation odds).
    {
        Key = "rare_club",
        Name = "Rare Club",
        Members = { "tralalero", "lirili_larila", "chimpanzini", "burbaloni", "girafa_celestre" },
        Reward = { Type = "Luck", Mult = 1.15 },
    },
    -- Every Epic -> a free Epic brainrot (exercises the safe no-free-pad grant path).
    {
        Key = "epic_squad",
        Name = "Epic Squad",
        Members = {
            "bombardiro",
            "orcalero_orcala",
            "glorbo",
            "rhino_toasterino",
            "ballerina",
            "bananita_dolphinita",
        },
        Reward = { Type = "Brainrot", BrainrotId = "bombardiro" },
    },
    -- A cross-rarity prestige theme (one big unit from the top tiers) -> a strong income multiplier.
    {
        Key = "apex",
        Name = "Apex Predators",
        Members = { "cappuccino_assassino", "graipuss_medussi", "garama" },
        Reward = { Type = "Multiplier", Bonus = 0.35 },
    },
    -- PREMIUM TRACK (separate/optional): requires the paywalled El Secreto. Does NOT block free sets.
    {
        Key = "secret_society",
        Name = "Secret Society",
        Premium = true,
        Members = { "el_secreto" },
        Reward = { Type = "Cash", Amount = 250000 },
    },
}

SetsConfig.ByKey = {}
for _, set in ipairs(SetsConfig.Sets) do
    SetsConfig.ByKey[set.Key] = set
end

return SetsConfig
