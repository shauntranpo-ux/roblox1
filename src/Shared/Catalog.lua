-- Catalog: the full, data-driven brainrot ROSTER. THE single source of truth for every
-- brainrot's stats, read by the server (authoritative price/income lookup + validation)
-- and the client (renders shop rows -- no hardcoded UI). Retune the WHOLE economy here
-- without touching any service or UI logic.
--
-- Each entry:
--   Id            stable internal key. Saved in OwnedBrainrots.Type -- NEVER rename/reuse.
--   DisplayName   shown in shop / inventory / world. Placeholder meme text -- swap freely
--                 (names live in DATA so any character can be skinned in seconds).
--   Rarity        a key into Shared/Rarity (drives color + shop grouping/sorting).
--   Price         server-authoritative cost.
--   IncomePerSec  server-authoritative passive income.
--   Buyable       set false to hide from the shop (defaults to true when omitted).
--   ModelName     RESERVED: clone this Model from ServerStorage/Assets once real art exists
--                 (BrainrotService falls back to a tinted placeholder while it is nil).
--   IconId        RESERVED: shop/inventory thumbnail asset id (nil placeholder for now).
--   SoundId       RESERVED: purchase/idle sound asset id (nil placeholder for now).
--
-- ECONOMY CURVE (retune the numbers, keep the SHAPE):
--   Every tier is a sharp jump -- roughly 5x the previous tier's price, and a touch MORE
--   than that in income, so the income/price RATIO improves modestly as you climb (this
--   rewards chasing rarer units). Within a tier, entries step ~2-3x. Approx income/price
--   ratio by tier: Common ~0.02, Rare ~0.028, Epic ~0.036, Legendary ~0.046,
--   Mythic ~0.057, Secret ~0.073.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))

local Catalog = {}

Catalog.Items = {
    -- COMMON -- the early game. The cheapest Common is the free starter (see StarterId).
    {
        Id = "tung_sahur",
        DisplayName = "Tung Tung Tung Sahur",
        Rarity = "Common",
        Price = 50,
        IncomePerSec = 1,
    },
    {
        Id = "trippi_troppi",
        DisplayName = "Trippi Troppi",
        Rarity = "Common",
        Price = 150,
        IncomePerSec = 3,
    },
    {
        Id = "brr_patapim",
        DisplayName = "Brr Brr Patapim",
        Rarity = "Common",
        Price = 400,
        IncomePerSec = 9,
    },
    {
        Id = "bombombini",
        DisplayName = "Bombombini Gusini",
        Rarity = "Common",
        Price = 900,
        IncomePerSec = 22,
    },

    -- RARE
    {
        Id = "tralalero",
        DisplayName = "Tralalero Tralala",
        Rarity = "Rare",
        Price = 5000,
        IncomePerSec = 140,
    },
    {
        Id = "lirili_larila",
        DisplayName = "Lirili Larila",
        Rarity = "Rare",
        Price = 12000,
        IncomePerSec = 350,
    },
    {
        Id = "chimpanzini",
        DisplayName = "Chimpanzini Bananini",
        Rarity = "Rare",
        Price = 25000,
        IncomePerSec = 760,
    },

    -- EPIC
    {
        Id = "bombardiro",
        DisplayName = "Bombardiro Crocodilo",
        Rarity = "Epic",
        Price = 120000,
        IncomePerSec = 4200,
    },
    {
        Id = "glorbo",
        DisplayName = "Glorbo Fruttodrillo",
        Rarity = "Epic",
        Price = 300000,
        IncomePerSec = 10800,
    },
    {
        Id = "ballerina",
        DisplayName = "Ballerina Cappuccina",
        Rarity = "Epic",
        Price = 650000,
        IncomePerSec = 24000,
    },

    -- LEGENDARY
    {
        Id = "cappuccino_assassino",
        DisplayName = "Cappuccino Assassino",
        Rarity = "Legendary",
        Price = 3000000,
        IncomePerSec = 138000,
    },
    {
        Id = "la_vacca",
        DisplayName = "La Vacca Saturno Saturnita",
        Rarity = "Legendary",
        Price = 7500000,
        IncomePerSec = 352000,
    },

    -- MYTHIC
    {
        Id = "sahur_combinasion",
        DisplayName = "Sahur Combinasion",
        Rarity = "Mythic",
        Price = 40000000,
        IncomePerSec = 2250000,
    },
    {
        Id = "los_tralaleritos",
        DisplayName = "Los Tralaleritos",
        Rarity = "Mythic",
        Price = 95000000,
        IncomePerSec = 5500000,
    },

    -- SECRET -- the chase. Astronomical price; best income/price ratio in the game.
    {
        Id = "garama",
        DisplayName = "Garama and Madundung",
        Rarity = "Secret",
        Price = 600000000,
        IncomePerSec = 42000000,
    },
    {
        Id = "la_grande",
        DisplayName = "La Grande Combinasion",
        Rarity = "Secret",
        Price = 1500000000,
        IncomePerSec = 110000000,
    },
}

-- Id -> item lookup, built once so the server validates a purchase in O(1).
Catalog.ById = {}
for _, item in ipairs(Catalog.Items) do
    Catalog.ById[item.Id] = item
end

function Catalog.Get(id)
    return Catalog.ById[id]
end

-- Items sorted for shop display: ascending rarity, then ascending price within a tier.
-- Computed once so the shop renders this directly and ordering stays fully data-driven.
Catalog.Sorted = {}
for _, item in ipairs(Catalog.Items) do
    table.insert(Catalog.Sorted, item)
end
table.sort(Catalog.Sorted, function(a, b)
    local orderA = Rarity.Get(a.Rarity).Order
    local orderB = Rarity.Get(b.Rarity).Order
    if orderA ~= orderB then
        return orderA < orderB
    end
    return a.Price < b.Price
end)

function Catalog.GetSorted()
    return Catalog.Sorted
end

-- The free starter granted to brand-new players: the cheapest entry of the lowest rarity
-- (i.e. the first item once sorted). DERIVED so retuning prices/rarities can never desync
-- the starter from the roster.
Catalog.StarterId = Catalog.Sorted[1].Id

function Catalog.GetStarter()
    return Catalog.ById[Catalog.StarterId]
end

return Catalog
