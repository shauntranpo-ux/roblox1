-- Rarity: the ordered ladder of brainrot rarity tiers. THE single source of truth for
-- each tier's display name, color, and order. The shop, the inventory, and the in-world
-- placeholder visuals all read tier colors from here, so restyling the whole rarity
-- system -- or adding a tier -- is a one-file change.
--
-- RETUNE HERE: edit Rarity.Tiers to change names/colors/order or add a tier.

local Rarity = {}

-- Ascending power order (Order index). Order drives shop grouping/sorting and "how rare"
-- comparisons. Colors are chosen so tiers read at a glance:
--   Common   neutral off-white   Rare   blue        Epic    purple
--   Legendary gold/orange        Mythic pink/red     Secret  electric cyan
-- (Secret uses a distinct, readable cyan as a stand-in for the classic "black" tier so it
--  stays legible as both a part tint and UI text.)
Rarity.Tiers = {
    Common = { DisplayName = "Common", Order = 1, Color = Color3.fromRGB(200, 206, 218) },
    Rare = { DisplayName = "Rare", Order = 2, Color = Color3.fromRGB(70, 140, 255) },
    Epic = { DisplayName = "Epic", Order = 3, Color = Color3.fromRGB(170, 95, 240) },
    Legendary = { DisplayName = "Legendary", Order = 4, Color = Color3.fromRGB(255, 178, 40) },
    Mythic = { DisplayName = "Mythic", Order = 5, Color = Color3.fromRGB(255, 70, 120) },
    Secret = { DisplayName = "Secret", Order = 6, Color = Color3.fromRGB(15, 222, 235) },
}

-- Ascending-ordered array of { Key, DisplayName, Order, Color } for ordered iteration.
Rarity.Ordered = {}
for key, tier in pairs(Rarity.Tiers) do
    table.insert(Rarity.Ordered, {
        Key = key,
        DisplayName = tier.DisplayName,
        Order = tier.Order,
        Color = tier.Color,
    })
end
table.sort(Rarity.Ordered, function(a, b)
    return a.Order < b.Order
end)

-- The lowest tier's key, used as a safe fallback for any unknown rarity key.
local LOWEST_KEY = Rarity.Ordered[1].Key

-- Resolves a rarity key to its tier record. Falls back to the lowest tier so a stale or
-- mistyped key never errors a caller reading .Color / .DisplayName / .Order.
function Rarity.Get(key)
    return Rarity.Tiers[key] or Rarity.Tiers[LOWEST_KEY]
end

return Rarity
