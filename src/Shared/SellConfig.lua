-- SellConfig: THE single source of truth for SELLING (M9.1 -- the economy FLOOR sink so no collected
-- brainrot is ever worthless). Every tunable number lives here; retune the whole sell economy in
-- this one file. Selling is server-authoritative -- the client only ever sends unit Id(s); the
-- server reads the unit's REAL Type/Mutation/Star from the profile and computes the value via
-- ComputeValue below. Cash is granted through the guarded accessor only.
--
-- VALUE FORMULA (per unit):
--   value = floor( species BUY price
--                  * RarityMultiplier[rarity]   -- extra per-rarity knob (default 1 = no-op)
--                  * mutationFactor             -- the per-unit mutation multiplier (Shiny/Golden/...)
--                  * star                       -- the M9.2 STAR field, read DEFENSIVELY (default 1)
--                  * SellRatio[rarity] )        -- the refund fraction of buy value (< 1)
--
-- The `star` term means the upcoming M9.2 star system slots in with NO change here (units without a
-- Star field just use 1). DEPLOYED (M9.3) / FUSING (M9.2) units must be UNSELLABLE -- that is handled
-- by the shared item-lock set in SellService.isLocked (those milestones just add to it), NOT here.

local SellConfig = {}

-- The refund fraction of buy value. < 1 so selling is always a net loss vs buying (a real sink).
-- Per-rarity overridable; falls back to DefaultSellRatio when a rarity is absent.
SellConfig.DefaultSellRatio = 0.3
SellConfig.SellRatio = {
    Common = 0.35,
    Rare = 0.32,
    Epic = 0.3,
    Legendary = 0.28,
    Mythic = 0.26,
    Secret = 0.25,
}

-- Extra per-rarity multiplier baked into the value (default 1 = pure buy-price-based refund). Raise
-- a tier here if you want rarer units to refund disproportionately more/less than their price implies.
SellConfig.RarityMultiplier = {
    Common = 1,
    Rare = 1,
    Epic = 1,
    Legendary = 1,
    Mythic = 1,
    Secret = 1,
}

-- A single sell whose value is >= this requires the client to send Confirm = true (so a fat-finger
-- can't dump a valuable unit). Bulk sells use the same threshold on the TOTAL.
SellConfig.ConfirmThreshold = 1000000

-- Hard cap on how many units one bulk-sell call can remove (keeps a single op bounded + cheap).
SellConfig.MaxBulk = 250

-- Premium / Robux-paid units are NOT sellable by default (protect paid value, like trading). Flip to
-- true to allow it. (Premium units have Price 0 anyway, so they would refund 0.)
SellConfig.AllowSellPremium = false

-- Currency hook: Cash now (the guarded accessor). A future secondary currency would be wired here +
-- in SellService.grant; left as a documented hook -- DO NOT add a currency this milestone.
SellConfig.Currency = "Cash"

-- Computes a unit's sell value from its roster def + resolved mutation factor + star. Pure: the
-- caller resolves the mutation factor (via the canonical mutation config) and reads star defensively.
function SellConfig.ComputeValue(def, mutationFactor, star)
    if def == nil then
        return 0
    end
    local price = type(def.Price) == "number" and def.Price or 0
    local rarityMult = SellConfig.RarityMultiplier[def.Rarity] or 1
    local ratio = SellConfig.SellRatio[def.Rarity] or SellConfig.DefaultSellRatio
    mutationFactor = (type(mutationFactor) == "number" and mutationFactor > 0) and mutationFactor
        or 1
    star = (type(star) == "number" and star > 0) and star or 1
    local value = price * rarityMult * mutationFactor * star * ratio
    if value ~= value or value == math.huge then -- NaN / inf guard
        return 0
    end
    return math.max(0, math.floor(value))
end

return SellConfig
