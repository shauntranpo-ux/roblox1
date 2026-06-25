-- Catalog: the data-driven shop catalog. THE single source of truth for buyable
-- brainrots, read by both the server (authoritative price/income lookup) and the
-- client (renders whatever is here -- no hardcoded UI rows).
--
-- M2 ships a tiny placeholder set. M3 replaces/expands this table (rarities, the full
-- roster, real icons/models) by editing DATA ONLY -- no service or UI changes needed.
-- Icon / ModelName are reserved for when real art exists.

local Catalog = {}

Catalog.Items = {
    {
        Id = "cappuccino",
        Name = "Cappuccino Assassino",
        Price = 75,
        IncomePerSec = 3,
        Buyable = true,
        ModelName = "CappuccinoAssassino", -- reserved: future Model in ServerStorage/Assets
    },
    {
        Id = "trippi",
        Name = "Trippi Troppi",
        Price = 400,
        IncomePerSec = 12,
        Buyable = true,
        ModelName = "TrippiTroppi",
    },
    {
        Id = "bombardiro",
        Name = "Bombardiro Crocodilo",
        Price = 1500,
        IncomePerSec = 45,
        Buyable = true,
        ModelName = "BombardiroCrocodilo",
    },
}

-- Id -> item lookup, built once so the server can validate a purchase in O(1).
Catalog.ById = {}
for _, item in ipairs(Catalog.Items) do
    Catalog.ById[item.Id] = item
end

function Catalog.Get(id)
    return Catalog.ById[id]
end

return Catalog
