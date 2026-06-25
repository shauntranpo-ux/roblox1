-- PerksConfig (M11.1): THE single source of truth for SIGNATURE PERKS. Every brainrot species has
-- ONE unique perk. You equip specific OWNED units into a few active PERK SLOTS; the equipped unit's
-- perk applies its effect, scaled SERVER-SIDE by the holder's rarity (baked into each perk's base) x
-- star x mutation. This REPLACES the M9.3 generic-role system (slots are now per-unit perks).
--
-- ── HOW A PERK IS BUILT ────────────────────────────────────────────────────────────────────
-- Each perk is a config row with an `Effects` table of EFFECT PRIMITIVES. A single generic applier
-- (Server/PerkRegistry) reads those primitives and routes each to the right system. So ADDING A PERK
-- = one row here; no registry surgery. Primitives:
--   Income=frac          -> a capped Benefits income source (+frac of all your cash)
--   Luck=frac            -> a Benefits luck source (x(1+frac); better mutation odds)
--   CooldownReduce=frac  -> your steal cooldown x(1-frac)  [attacker "steal faster"; see note]
--   Reach=studs          -> +deposit reach while carrying (attacker)
--   CarryCount=n         -> carry up to n stolen units at once (attacker; discrete, takes the MAX)
--   CarryEase=0..1       -> ease the carry slowdown toward none (attacker)
--   Invisible=true       -> stealth: the victim isn't alerted while you raid (attacker)
--   DefHold=mult         -> thieves' hold time vs YOUR base x mult (defender)
--   Interrupt=chance     -> chance a steal attempt on you is blocked (defender)
--   Stun=true            -> a thief attempting your base is knocked back + stunned + BLOCKED (defender)
--   Alert=true           -> you're always alerted to raids, even vs stealth (defender)
--   Knockback=studs      -> knockback impulse used by Stun (defender)
--   OfflineFrac=frac     -> earn frac of your income rate while offline (capped accrual on join)
--   Hourglass={Cap,RampSeconds}   -> income ramps the longer you're online this session, to +Cap
--   Battalion={PerUnit,Cap}       -> +PerUnit income per owned brainrot, to +Cap (army bonus)
--   Meltdown={Period,Mult}        -> every Period s an income CRIT pays Mult x one period of income
--   FusionCrit=frac / FusionFailMult=mult -> better fusion crit / fewer fails (M9.2 fusion)
--   MoveMult=frac        -> +frac walkspeed (server-authoritative; reverts on unequip/death/leave)
--   Hunt={...}           -> wild-catch effects (M10) -- DORMANT until M10 lands (guarded no-op)
--
-- NOTE (attacker hold): a ProximityPrompt's hold time is one SHARED, client-driven value on the
-- victim's unit -- the server can't shorten it for one specific thief. So "reduced steal hold" is
-- realized server-authoritatively as a STEAL-COOLDOWN reduction (you steal more often). Defender
-- "longer hold" CAN be done per-victim (their own prompts) and is (DefHold).
--
-- ── STACKING RULE (documented + enforced) ──────────────────────────────────────────────────
-- Two equipped units with the SAME perk, or two different multiplier perks, COMBINE UNDER THE
-- EXISTING GLOBAL INCOME CAP (Monetization.Income.MaxMultiplier):
--   * Income: each equipped perk is its own keyed Benefits source; sources SUM, then the registry
--     clamps 1+sum to the cap. Same-perk twice simply adds twice (still capped) -- no double-count
--     bug because each slot is a distinct key recomputed from scratch on every change.
--   * Luck: each is a Benefits luck SOURCE; the product applies (magnitudes are small).
--   * CarryCount: takes the MAX across equipped (no stacking to absurd numbers).
--   * CooldownReduce / Reach / DefHold: combine (product / sum / product) with hard floors/caps here.
--   * Interrupt: probabilistic OR (1 - prod(1-p)). Booleans (Invisible/Stun/Alert): OR.
-- Magnitudes are recomputed from the live loadout on EVERY change, so equip/join/rejoin/swap can
-- never double-apply.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))

local PerksConfig = {}

-- ── Loadout sizing + scaling tunables ───────────────────────────────────────────────────────
PerksConfig.SlotCount = 3 -- active perk slots. HOOK: raise this later for a mastery/gamepass slot.
PerksConfig.MaxSlotCount = 6 -- safety ceiling the equip remote validates against (future expansion).
PerksConfig.StarPerLevel = 0.25 -- +25% perk effect per star above 1 (star 3 -> +50%, star 5 -> +100%)
PerksConfig.MutScaleFactor = 0.05 -- mutation contribution: 1 + this*(mutMult-1) (rainbow ~+45%, etc.)
PerksConfig.CooldownFloor = 0.1 -- a thief's steal cooldown can never drop below 10% of base
PerksConfig.InterruptCap = 0.85 -- a defender can never block more than 85% of steal attempts
PerksConfig.BaseWalkSpeed = 16 -- the natural character walkspeed perks scale from (Roblox default)
PerksConfig.OfflineMaxSeconds = 8 * 3600 -- cap offline accrual at 8 hours of away time
PerksConfig.DefaultPerk = "drumline" -- reconcile: any roster entry without an assignment gets this

-- ── Per-species assignment (stamped onto every Catalog entry as `SignaturePerk`) ─────────────
PerksConfig.Assignments = {
    -- COMMON
    tung_sahur = "drumline",
    trippi_troppi = "slippery_catch",
    frigo_camelo = "cold_storage",
    brr_patapim = "deep_roots",
    boneca_ambalabu = "rolling_start",
    bombombini = "dive_bomb",
    trulimero = "lucky_fin",
    -- RARE
    tralalero = "just_do_it",
    lirili_larila = "hourglass",
    chimpanzini = "banana_hoard",
    burbaloni = "hard_shell",
    girafa_celestre = "long_neck",
    -- EPIC
    bombardiro = "carpet_bomb",
    orcalero_orcala = "apex_hunter",
    glorbo = "ripe_rare",
    rhino_toasterino = "stampede",
    ballerina = "graceful_thief",
    bananita_dolphinita = "splash_zone",
    -- LEGENDARY
    cappuccino_assassino = "assassins_mark",
    cocosini_mama = "mothers_blessing",
    la_vacca = "cosmic_forge",
    tortuginni_dragonfruitini = "fortress_shell",
    -- MYTHIC
    sahur_combinasion = "battalion",
    pandaccini = "lucky_panda",
    los_tralaleritos = "feeding_frenzy",
    graipuss_medussi = "krakens_hold",
    -- SECRET
    garama = "twin_titans",
    nuclearo_dinossauro = "meltdown",
    la_grande = "world_eater",
    los_combinasos = "total_domination",
    -- PREMIUM
    el_secreto = "wildcard",
}

-- ── The perks (numbers are STARTING POINTS; retune freely) ───────────────────────────────────
PerksConfig.Perks = {
    -- COMMON (modest base)
    drumline = {
        Name = "Drumline",
        Category = "EARN",
        Desc = "+8% cash from all your brainrots.",
        Effects = { Income = 0.08 },
    },
    slippery_catch = {
        Name = "Slippery Catch",
        Category = "HUNT",
        Desc = "+catch range and faster catch on wild brainrots.",
        Effects = { Hunt = { CatchRange = 8, CatchSpeed = 0.25 } },
    },
    cold_storage = {
        Name = "Cold Storage",
        Category = "EARN",
        Desc = "Earn ~10% of your income while offline.",
        Effects = { OfflineFrac = 0.1 },
    },
    deep_roots = {
        Name = "Deep Roots",
        Category = "DEF",
        Desc = "Thieves take longer to steal from your base.",
        Effects = { DefHold = 1.3 },
    },
    rolling_start = {
        Name = "Rolling Start",
        Category = "MOVE",
        Desc = "+10% walkspeed.",
        Effects = { MoveMult = 0.1 },
    },
    dive_bomb = {
        Name = "Dive Bomb",
        Category = "RAID",
        Desc = "Steal faster (-15% steal cooldown).",
        Effects = { CooldownReduce = 0.15 },
    },
    lucky_fin = {
        Name = "Lucky Fin",
        Category = "ECON",
        Desc = "Small + to mutation odds on units you catch.",
        Effects = { Luck = 0.05 },
    },
    -- RARE
    just_do_it = {
        Name = "Just Do It",
        Category = "MOVE",
        Desc = "Big +walkspeed. The signature speed perk.",
        Effects = { MoveMult = 0.28 },
    },
    hourglass = {
        Name = "Hourglass",
        Category = "EARN",
        Desc = "Income ramps the longer you stay online (resets on leave).",
        Effects = { Hourglass = { Cap = 0.5, RampSeconds = 600 } },
    },
    banana_hoard = {
        Name = "Banana Hoard",
        Category = "EARN",
        Desc = "+15% cash from all brainrots.",
        Effects = { Income = 0.15 },
    },
    hard_shell = {
        Name = "Hard Shell",
        Category = "DEF",
        Desc = "Thieves take notably longer to rob you.",
        Effects = { DefHold = 1.8 },
    },
    long_neck = {
        Name = "Long Neck",
        Category = "RAID",
        Desc = "Steal reach increased -- grab from far away.",
        Effects = { Reach = 18 },
    },
    -- EPIC
    carpet_bomb = {
        Name = "Carpet Bomb",
        Category = "RAID",
        Desc = "Carry TWO stolen brainrots at once.",
        Effects = { CarryCount = 2 },
    },
    apex_hunter = {
        Name = "Apex Hunter",
        Category = "HUNT",
        Desc = "Rare wild brainrots spawn more often near you.",
        Effects = { Hunt = { SpawnRate = 0.4 } },
    },
    ripe_rare = {
        Name = "Ripe & Rare",
        Category = "ECON",
        Desc = "Strong + to mutation odds on caught units.",
        Effects = { Luck = 0.3 },
    },
    stampede = {
        Name = "Stampede",
        Category = "DEF",
        Desc = "Thieves who try to rob you get knocked back + stunned.",
        Effects = { Stun = true, Knockback = 60 },
    },
    graceful_thief = {
        Name = "Graceful Thief",
        Category = "RAID",
        Desc = "You're invisible to the victim while stealing.",
        Effects = { Invisible = true },
    },
    splash_zone = {
        Name = "Splash Zone",
        Category = "HUNT",
        Desc = "Wild brainrots near you stop fleeing.",
        Effects = { Hunt = { NoFlee = true } },
    },
    -- LEGENDARY
    assassins_mark = {
        Name = "Assassin's Mark",
        Category = "RAID",
        Desc = "Steal cooldown slashed AND hard to detect while raiding.",
        Effects = { CooldownReduce = 0.5, Invisible = true },
    },
    mothers_blessing = {
        Name = "Mother's Blessing",
        Category = "EARN",
        Desc = "+40% cash from all your brainrots.",
        Effects = { Income = 0.4 },
    },
    cosmic_forge = {
        Name = "Cosmic Forge",
        Category = "ECON",
        Desc = "Big fusion crit chance and your fusions rarely fail.",
        Effects = { FusionCrit = 0.4, FusionFailMult = 0.1 },
    },
    fortress_shell = {
        Name = "Fortress Shell",
        Category = "DEF",
        Desc = "Thieves take dramatically longer, and attempts can be interrupted.",
        Effects = { DefHold = 2.5, Interrupt = 0.25 },
    },
    -- MYTHIC
    battalion = {
        Name = "Battalion",
        Category = "EARN",
        Desc = "+income that scales with how many brainrots you own (capped).",
        Effects = { Battalion = { PerUnit = 0.01, Cap = 0.5 } },
    },
    lucky_panda = {
        Name = "Lucky Panda",
        Category = "ECON",
        Desc = "Big boost to BOTH mutation odds and rare spawn rate.",
        Effects = { Luck = 0.5, Hunt = { SpawnRate = 0.5 } },
    },
    feeding_frenzy = {
        Name = "Feeding Frenzy",
        Category = "RAID",
        Desc = "Carry THREE stolen brainrots and move fast while carrying.",
        Effects = { CarryCount = 3, CarryEase = 0.8 },
    },
    krakens_hold = {
        Name = "Kraken's Hold",
        Category = "DEF",
        Desc = "Your whole base is far harder to steal; thieves stun; you're alerted.",
        Effects = { DefHold = 3.0, Interrupt = 0.5, Stun = true, Alert = true, Knockback = 90 },
    },
    -- SECRET (build-defining)
    twin_titans = {
        Name = "Twin Titans",
        Category = "EARN",
        Desc = "A big income multiplier AND a big luck boost at once.",
        Effects = { Income = 1.0, Luck = 0.5 },
    },
    meltdown = {
        Name = "Meltdown",
        Category = "EARN",
        Desc = "Income crit-ticks pay a massive multiple; raiders trigger a stun-blast.",
        Effects = { Meltdown = { Period = 30, Mult = 5 }, Stun = true, Knockback = 80 },
    },
    world_eater = {
        Name = "World Eater",
        Category = "HUNT",
        Desc = "Dramatically boosts rare/secret spawns and reveals them across the map.",
        Effects = { Hunt = { SpawnRate = 1.0, RareReveal = true } },
    },
    total_domination = {
        Name = "Total Domination",
        Category = "RAID",
        Desc = "Near-instant steals, carry several, invisible while raiding.",
        Effects = { CooldownReduce = 0.8, CarryCount = 3, CarryEase = 1.0, Invisible = true },
    },
    -- PREMIUM (versatile, not a single-axis ceiling-breaker)
    wildcard = {
        Name = "Wildcard",
        Category = "EARN",
        Desc = "A solid simultaneous boost to income, luck, and catch speed.",
        Effects = { Income = 0.25, Luck = 0.2, Hunt = { CatchSpeed = 0.3 } },
    },
}

-- The per-unit scaling scalar from STAR (level) x MUTATION (multiplier). Read from the unit's real
-- stored stats (server-side). Rarity is already baked into each perk's base magnitude.
function PerksConfig.Scale(unit)
    local star = (type(unit.Star) == "number" and unit.Star >= 1) and math.floor(unit.Star) or 1
    local starScale = 1 + PerksConfig.StarPerLevel * (star - 1)
    local mutMult = MutationConfig.MultiplierFor(unit.Mutation)
    local mutScale = 1 + PerksConfig.MutScaleFactor * (mutMult - 1)
    return starScale * mutScale
end

function PerksConfig.Get(perkKey)
    return PerksConfig.Perks[perkKey]
end

-- The perk a species grants (falls back to the default, so a new roster entry never errors).
function PerksConfig.PerkForType(unitType)
    return PerksConfig.Assignments[unitType] or PerksConfig.DefaultPerk
end

-- A short, human magnitude label for the UI (the dominant scaled effect of the perk on this unit).
function PerksConfig.MagnitudeLabel(perkKey, unit)
    local perk = PerksConfig.Perks[perkKey]
    if perk == nil then
        return ""
    end
    local s = PerksConfig.Scale(unit)
    local e = perk.Effects
    if e.Income ~= nil then
        return string.format("+%d%% cash", math.floor(e.Income * s * 100 + 0.5))
    elseif e.MoveMult ~= nil then
        return string.format("+%d%% speed", math.floor(e.MoveMult * s * 100 + 0.5))
    elseif e.CarryCount ~= nil then
        return "carry " .. e.CarryCount
    elseif e.CooldownReduce ~= nil then
        return string.format("-%d%% cooldown", math.floor(e.CooldownReduce * s * 100 + 0.5))
    elseif e.Reach ~= nil then
        return string.format("+%d reach", math.floor(e.Reach * s + 0.5))
    elseif e.DefHold ~= nil then
        return string.format("x%.1f steal time", 1 + (e.DefHold - 1) * s)
    elseif e.OfflineFrac ~= nil then
        return string.format("%d%% offline", math.floor(e.OfflineFrac * s * 100 + 0.5))
    elseif e.Hourglass ~= nil then
        return string.format("ramp +%d%%", math.floor(e.Hourglass.Cap * s * 100 + 0.5))
    elseif e.Battalion ~= nil then
        return "army bonus"
    elseif e.Meltdown ~= nil then
        return "income crits"
    elseif e.Stun ~= nil then
        return "stun raiders"
    elseif e.Invisible ~= nil then
        return "stealth"
    elseif e.Luck ~= nil then
        return string.format("x%.2f luck", 1 + e.Luck * s)
    elseif e.FusionCrit ~= nil then
        return "fusion crit"
    elseif e.Hunt ~= nil then
        return "wild-catch"
    end
    return perk.Category
end

return PerksConfig
