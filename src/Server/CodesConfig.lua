-- CodesConfig: the data-driven list of redeemable codes. SERVER-ONLY ON PURPOSE -- it lives in
-- ServerScriptService and is NEVER replicated, so exploiters can't dump ReplicatedStorage to
-- read unreleased codes (that would defeat the whole "search for the codes" retention loop and
-- let everyone redeem instantly). The client only ever sends the string it typed; the server
-- validates it here. (The prompt suggested a "Shared" config; server-only is the correct,
-- anti-cheat-consistent choice and is noted in the launch self-audit.)
--
-- ADD / EXPIRE CODES HERE -- this is the ONLY place. Each entry:
--   Code          the string players type (matched case-insensitively, whitespace-trimmed).
--   Reward        a typed reward (reuses existing systems):
--                   { Type = "Cash",     Amount = <n> }                      -- guarded AddCash
--                   { Type = "Boost",    Multiplier = <n>, DurationSeconds = <n> } -- M5 income mult
--                   { Type = "Brainrot", BrainrotId = "<roster id>" }        -- placed on a free pad
--   Active        false to disable WITHOUT deleting (returns "Inactive"). Defaults true.
--   Expiry        optional os.time() after which it returns "Expired".
--   MaxGlobalUses optional cross-server cap (OrderedDataStore/DataStore counter; opt-in). When
--                 the DataStore API is unavailable (Studio mock) this falls back to per-player-once.

local CodesConfig = {}

CodesConfig.List = {
    {
        Code = "LAUNCH",
        Reward = { Type = "Cash", Amount = 2500 },
        Active = true,
    },
    {
        Code = "BOOST2X",
        Reward = { Type = "Boost", Multiplier = 2, DurationSeconds = 600 },
        Active = true,
    },
    {
        Code = "FREEROT",
        Reward = { Type = "Brainrot", BrainrotId = "trippi_troppi" },
        Active = true,
    },
    -- Example of a disabled code (kept for testing the "Inactive" path).
    {
        Code = "OLDCODE",
        Reward = { Type = "Cash", Amount = 500 },
        Active = false,
    },
}

-- Normalizes a raw string the way redemption does: trim surrounding whitespace + UPPER-case.
function CodesConfig.normalize(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        return nil
    end
    return string.upper(trimmed)
end

-- Normalized lookup built once: NORMALIZED code -> entry. Lets redemption match in O(1),
-- case-insensitively, against the canonical form (also stored in RedeemedCodes).
CodesConfig.ByNormalized = {}
for _, entry in ipairs(CodesConfig.List) do
    local key = CodesConfig.normalize(entry.Code)
    if key ~= nil then
        entry.Normalized = key
        CodesConfig.ByNormalized[key] = entry
    end
end

return CodesConfig
