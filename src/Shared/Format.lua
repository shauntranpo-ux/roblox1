-- Format: compact number formatting for display. Require-able from client or server.
--
-- Examples:
--   Format.short(950)        -> "950"
--   Format.short(1234)       -> "1.2K"
--   Format.short(3400000)    -> "3.4M"
--   Format.short(1000000000) -> "1B"
-- Rounds to one decimal and strips a trailing ".0".

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function Format.short(value)
    value = tonumber(value) or 0
    local negative = value < 0
    value = math.abs(value)

    local tier = 0
    while value >= 1000 and tier < #SUFFIXES - 1 do
        value = value / 1000
        tier += 1
    end

    local text
    if tier == 0 then
        text = tostring(math.floor(value + 0.5))
    else
        local rounded = math.floor(value * 10 + 0.5) / 10
        -- Rounding can push a value up a tier (e.g. 999.95K -> 1000K -> 1M).
        if rounded >= 1000 and tier < #SUFFIXES - 1 then
            rounded = rounded / 1000
            tier += 1
        end
        if rounded == math.floor(rounded) then
            text = string.format("%d%s", rounded, SUFFIXES[tier + 1])
        else
            text = string.format("%.1f%s", rounded, SUFFIXES[tier + 1])
        end
    end

    if negative then
        text = "-" .. text
    end
    return text
end

return Format
