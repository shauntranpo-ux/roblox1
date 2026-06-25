-- CombatConfig (M11.3-combat): THE single source of truth for COLLECTION-POWERED COMBAT. A player's
-- damage to a world boss = the combined POWER of their EQUIPPED brainrot team (the M11.1 loadout),
-- scaled by the SAME per-unit factors as income (rarity via BasePower x star x mutation x evolution),
-- + a per-unit combat-perk bonus, x an attack scalar, + a base tap so an empty loadout still chips in.
-- Server-authoritative (Server/CombatPower is the ONE site). Put EVERY number here.
--
-- POWER FORMULA (per equipped unit):
--   unitPower = BasePower x mutationMult x starMult x evolutionMult
--   BasePower = species `BasePower` if tuned, else species IncomePerSec x IncomeToPower (income already
--               encodes the rarity tier, so rarity is NOT multiplied again -> no double-count).
--   teamPower = SUM over equipped units of unitPower x (1 + perkCombatMod[that unit's perk category])
--   per-attack DAMAGE = teamPower x AttackScalar + BaseTapDamage   (clamped tap rate server-side)
-- All terms are finite sums/products of config values -> bounded, no multiplicative blow-up.

local CombatConfig = {}

CombatConfig.IncomeToPower = 1.0 -- BasePower = species IncomePerSec x this (rarity encoded in income)
CombatConfig.AttackScalar = 0.5 -- per-attack damage = teamPower x this (+ BaseTapDamage)
CombatConfig.BaseTapDamage = 50 -- flat damage per attack so a new / empty / weak loadout still chips in
CombatConfig.AttackInterval = 0.18 -- s: server-enforced MIN gap between a player's attacks (rate cap)

-- Per-unit COMBAT bonus by the equipped unit's signature-perk CATEGORY (M11.1). Offense (RAID) hits
-- hardest; others contribute small or nothing. Applied ONCE per equipped unit (no double-apply), then
-- clamped to MaxPerkMod. Combat perks adjust DAMAGE only -- never ownership transfer.
CombatConfig.PerkCombatMod = {
    RAID = 0.5, -- offense -> the biggest damage boost
    DEF = 0.15,
    HUNT = 0.1,
    MOVE = 0.1,
    ECON = 0.0,
    EARN = 0.0,
}
CombatConfig.MaxPerkMod = 0.5 -- hard cap on a single unit's perk combat bonus (no blow-up)

return CombatConfig
