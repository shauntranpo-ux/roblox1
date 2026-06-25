-- TransitRegistry: the server-only set of brainrot Ids that are currently IN_TRANSIT
-- (being carried in a steal). A carried brainrot earns income for NO ONE, so this is the
-- single source IncomeService + PlayerStats consult to skip non-earning units.
--
-- It exists as its own tiny module purely to DECOUPLE: StealService writes it, while
-- IncomeService/PlayerStats only read it -- so income code never has to require StealService
-- (which would create a require cycle). The set is runtime-only and never saved.

local TransitRegistry = {}

local inTransit = {} -- [brainrotId] = true while carried

-- Marks a brainrot in-transit (value = true) or clears it (value = false/nil).
function TransitRegistry.Set(brainrotId, value)
    if value then
        inTransit[brainrotId] = true
    else
        inTransit[brainrotId] = nil
    end
end

function TransitRegistry.Has(brainrotId)
    return inTransit[brainrotId] == true
end

-- Read-only shallow copy of the in-transit set (for the dev invariant validator).
function TransitRegistry.All()
    local copy = {}
    for id in pairs(inTransit) do
        copy[id] = true
    end
    return copy
end

return TransitRegistry
