-- ExclusivesConfig (M11.4): THE single source of truth for SEASONAL EXCLUSIVES -- brainrots,
-- mutations, and cosmetics obtainable ONLY during a given season window and never again (the
-- miss-it-forever hook). Extends the seasons + events-availability + idempotent-claim systems --
-- does NOT fork them.
--
-- ── HOW IT GATES ──────────────────────────────────────────────────────────────────────────────
-- Each exclusive is tied to a SeasonId. Availability derives PURELY from server time
-- (SeasonService.CurrentId(), identical on every server) -> obtainable iff the current season id ==
-- the exclusive's SeasonId, via its defined Source. Roster/mutation entries also carry an
-- `ExclusiveSeason` field so the BRAINROT FACTORY default-DENIES creating them unless the grant is an
-- authorized in-window/earned source (ExclusivesService) -- so NO path (shop/catch/hatch/fusion/boss/
-- trade-as-new-grant) can mint an expired exclusive. Trading an ALREADY-OWNED copy is a MOVE, not a
-- new grant, and is unaffected.
--
-- AUTHORING A REAL SEASON: set an exclusive's `SeasonId` to the actual SeasonService season id of the
-- week you want it live (compute it from the date). The shipped examples use SENTINEL ids (>= 900000)
-- so they are NEVER live in production and are reachable ONLY via the SIM dev-force window for testing.
--
-- SOURCES: "track" (season-track score tier, claimed via SeasonRewardService's idempotent claim),
-- "ranked" (top-N finish, same claim), "shop" (buy with EARNED cash while the window is open),
-- "boss"/"catch" (in-window drop -- FORWARD-COMPAT: gated when those systems exist, dormant otherwise).

local ExclusivesConfig = {}

ExclusivesConfig.InWindowSources = { shop = true, boss = true, catch = true } -- need a LIVE open window

-- Lightweight cosmetics (owned permanently; purely visual/status -- NO power, to stay pay-to-win-free).
ExclusivesConfig.Cosmetics = {
    winter_crown = {
        Id = "winter_crown",
        Name = "Winter Crown",
        Kind = "title",
        Desc = "A frosty Top-10 title flex.",
    },
    ember_aura = {
        Id = "ember_aura",
        Name = "Ember Aura",
        Kind = "aura",
        Desc = "A glowing seasonal base aura.",
    },
}

-- The exclusives. Each: Key (unique; the idempotent-claim id), Kind, SeasonId, Source + its params.
ExclusivesConfig.Exclusives = {
    {
        Key = "s900001_warden",
        Kind = "Brainrot",
        SeasonId = 900001,
        Source = "track",
        TrackScore = 2000, -- earn it by reaching this season-score this season
        Species = "winter_warden",
        DisplayName = "Winter Warden",
    },
    {
        Key = "s900001_frost",
        Kind = "Mutation",
        SeasonId = 900001,
        Source = "shop",
        Price = 2000000, -- buy with EARNED cash while the window is open
        Mutation = "frostbite",
        CarrierSpecies = "winter_warden", -- minted as a Winter Warden carrying the Frostbite mutation
        DisplayName = "Frostbite Warden",
    },
    {
        Key = "s900001_crown",
        Kind = "Cosmetic",
        SeasonId = 900001,
        Source = "ranked",
        RankMax = 10, -- earn it by finishing Top 10 this season
        CosmeticId = "winter_crown",
        DisplayName = "Winter Crown",
    },
    {
        Key = "s900001_aura",
        Kind = "Cosmetic",
        SeasonId = 900001,
        Source = "shop",
        Price = 500000,
        CosmeticId = "ember_aura",
        DisplayName = "Ember Aura",
    },
}

ExclusivesConfig.ByKey = {}
for _, ex in ipairs(ExclusivesConfig.Exclusives) do
    ExclusivesConfig.ByKey[ex.Key] = ex
end

function ExclusivesConfig.Get(key)
    return ExclusivesConfig.ByKey[key]
end

-- Every exclusive tied to a given season id.
function ExclusivesConfig.ForSeason(seasonId)
    local out = {}
    for _, ex in ipairs(ExclusivesConfig.Exclusives) do
        if ex.SeasonId == seasonId then
            table.insert(out, ex)
        end
    end
    return out
end

function ExclusivesConfig.IsInWindowSource(source)
    return ExclusivesConfig.InWindowSources[source] == true
end

return ExclusivesConfig
