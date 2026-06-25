-- Monetization: THE single, ID-driven config for every Robux purchase + the leaderboards.
-- Shared so the client can render shop rows (names/descriptions) and the server can read the
-- IDs/benefits/grants. Paste the numeric Ids you create on the Roblox Creator Dashboard into
-- the `Id` fields below; EVERYTHING is driven from here.
--
-- SAFETY: while an `Id` is still 0 it is treated as UNCONFIGURED -- that pass/product is hidden
-- from the shop (unless you are in SIM mode) and is NEVER granted on a live server. So this
-- file is safe to ship with placeholder 0s; the real paths light up the instant you fill Ids.
--
-- NOTE: every item here is DIRECT and DETERMINISTIC -- you buy exactly what the row says. We
-- sell NOTHING randomized (no loot boxes / gacha), so Roblox's paid-random-item policy does
-- not apply. (PolicyService exists for paid-random compliance; we don't need it.)

local Monetization = {}

-- ===========================================================================================
-- GAMEPASSES (permanent perks). Each maps a gamepass Id to a BENEFIT that hooks an existing
-- system. A benefit's `Type` selects a server-side handler in Benefits/MonetizationService;
-- adding a new pass = a config row here + (if a new Type) one small handler function.
-- ===========================================================================================
Monetization.Gamepasses = {
    DoubleCash = {
        Order = 1,
        Id = 0, -- <<< paste the "2x Cash" gamepass Id here
        Name = "2x Cash",
        Description = "Permanently DOUBLE all of your passive income.",
        Benefit = { Type = "IncomeMultiplier", Multiplier = 2 },
    },
    ExtraPads = {
        Order = 2,
        Id = 0, -- <<< paste the "Extra Pads" gamepass Id here
        Name = "+2 Pads",
        Description = "Unlock 2 extra brainrot pads on your base.",
        Benefit = { Type = "ExtraPads", Pads = 2 },
    },
    ReinforcedLock = {
        Order = 3,
        Id = 0, -- <<< paste the "Reinforced Lock" gamepass Id here
        Name = "Reinforced Lock",
        Description = "Your base stays shielded with auto-renewing protection.",
        Benefit = { Type = "ReinforcedLock", MinProtectionSeconds = 60 },
    },
    VIP = {
        Order = 4,
        Id = 0, -- <<< paste the "VIP" gamepass Id here
        Name = "VIP",
        Description = "A gold VIP tag + faster steals (reduced steal cooldown).",
        Benefit = { Type = "VIP", StealCooldownMult = 0.5 },
    },
}

-- ===========================================================================================
-- DEVELOPER PRODUCTS (consumable, repeatable). Each maps a product Id to a deterministic
-- GRANT. The receipt handler is perfectly idempotent (see MonetizationService.ProcessReceipt),
-- so a given purchase grants EXACTLY once even across retries/restarts.
-- ===========================================================================================
Monetization.Products = {
    CashSmall = {
        Order = 1,
        Id = 0, -- <<< paste the "Cash Pack (Small)" product Id here
        Name = "Cash Pack (Small)",
        Description = "Instantly receive $10K.",
        Grant = { Type = "Cash", Amount = 10000 },
    },
    CashLarge = {
        Order = 2,
        Id = 0, -- <<< paste the "Cash Pack (Large)" product Id here
        Name = "Cash Pack (Large)",
        Description = "Instantly receive $1M.",
        Grant = { Type = "Cash", Amount = 1000000 },
    },
    PadUnlock = {
        Order = 3,
        Id = 0, -- <<< paste the "Instant Pad" product Id here
        Name = "Instant Pad",
        Description = "Permanently unlock 1 extra pad right now.",
        Grant = { Type = "Pads", Pads = 1 },
    },
    -- OPTIONAL premium-brainrot product. Leave Id = 0 to disable it entirely. BrainrotId must
    -- be a roster entry flagged `Premium = true` in Shared/Catalog (purchase-gated, not random).
    PremiumUnit = {
        Order = 4,
        Id = 0, -- <<< paste the "Exclusive Brainrot" product Id here (or leave 0 to disable)
        Name = "Exclusive Brainrot",
        Description = "Instantly own an exclusive, purchase-only unit.",
        Grant = { Type = "Brainrot", BrainrotId = "el_secreto" },
    },
}

-- ===========================================================================================
-- INCOME-MULTIPLIER STACKING RULE (explicit + clamped).
--   Multipliers stack ADDITIVELY as bonuses over a base of 1.0:
--       effective = clamp(1 + SUM(each source's bonus), 1, MaxMultiplier)
--   A "2x" source contributes a bonus of (2 - 1) = 1.0. Every source is keyed (e.g. by its
--   gamepass), so re-applying the SAME source overwrites its entry and can NEVER double-count
--   on rejoin or a repeated live-purchase event. The total is clamped to MaxMultiplier.
-- ===========================================================================================
Monetization.Income = {
    MaxMultiplier = 10, -- hard cap on the combined income multiplier
}

-- ===========================================================================================
-- LEADERBOARDS (global, OrderedDataStore-backed; in-memory fallback in unpublished Studio).
-- ===========================================================================================
Monetization.Leaderboard = {
    RefreshInterval = 60, -- s between throttled board writes/reads (also writes on player leave)
    TopN = 10, -- how many ranked entries each billboard shows
    -- OrderedDataStore values must be NON-NEGATIVE INTEGERS in a safe range. Cash/income can
    -- grow past 2^53 (double-precision integer safety), so every written value is floor()ed and
    -- clamped to [0, MaxValue]. 9e15 sits just under 2^53 (~9.007e15).
    MaxValue = 9000000000000000,
    -- RAREST-COLLECTION score = SUM over the player's Discovered roster Ids of the weight of
    -- that Id's rarity tier. A single positive integer, so "rarest collection" is sortable.
    -- Weights climb ~5x per tier so one Secret outweighs a pile of Commons. Retune freely.
    RarityWeights = {
        Common = 1,
        Rare = 5,
        Epic = 25,
        Legendary = 125,
        Mythic = 625,
        Secret = 3125,
    },
}

return Monetization
