-- BanStore (M13.4): the PERSISTENT, GLOBAL ban list. A single DataStore keyed by the banned userId;
-- the value is { Reason, By, ByName, At, ExpiresAt }. It is SEPARATE from player profiles (a ban must
-- be writable for an OFFLINE user and must never touch their save), so banning can never corrupt a
-- target's data. Any server reads it on join, so a ban enforces CROSS-SERVER. Mirrors the project's
-- DataStore pattern (apiAvailable probe + withRetry + MOCK fallback in unpublished Studio).
--
-- CHOICE (documented): a CUSTOM DataStore ban list, not Players:BanAsync. Rationale -- it is testable
-- in Studio via the MOCK fallback, supports our own timed bans + logging + the in-game admin panel,
-- and keeps one transparent source of truth. Players:BanAsync (which adds alt-account propagation)
-- can be layered on later in AdminService.ban without changing callers.
--
-- TIMED BANS: ExpiresAt = 0 means PERMANENT; otherwise an os.time() expiry. GetBan auto-clears and
-- returns nil once a timed ban has expired, so enforcement and expiry live in one place.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local BanStore = {}

local STORE_NAME = "GlobalBans_v1"
local DS_RETRIES = 3

local usingMock = false
local mock = {} -- [userIdKey] = record
local store = nil

local function withRetry(fn)
    for attempt = 1, DS_RETRIES do
        local ok, res = pcall(fn)
        if ok then
            return true, res
        end
        if attempt < DS_RETRIES then
            task.wait(0.5 * 2 ^ attempt)
        end
    end
    return false, nil
end

local function apiAvailable()
    if not RunService:IsStudio() then
        return true
    end
    local ok = pcall(function()
        DataStoreService:GetDataStore("__ban_probe"):GetAsync("probe")
    end)
    return ok
end

function BanStore.Init()
    usingMock = not apiAvailable()
    if not usingMock then
        store = DataStoreService:GetDataStore(STORE_NAME)
    end
    print(
        usingMock
                and "[Ban] DataStore API unavailable -> MOCK ban list (RESETS when you stop Play)."
            or "[Ban] Using REAL global ban DataStore -> bans persist + enforce cross-server."
    )
end

function BanStore.IsUsingMock()
    return usingMock
end

local function isExpired(record)
    return type(record) == "table"
        and type(record.ExpiresAt) == "number"
        and record.ExpiresAt ~= 0
        and os.time() >= record.ExpiresAt
end

-- Returns the active ban record for `userId`, or nil. A timed ban that has expired is cleared here and
-- reported as not-banned. Read failures return nil (see the fail-open note in AdminService.EnforceBan).
function BanStore.GetBan(userId)
    local key = tostring(userId)
    local record
    if usingMock then
        record = mock[key]
    else
        local ok, value = withRetry(function()
            return store:GetAsync(key)
        end)
        if not ok then
            return nil, false -- (no record, store-was-readable=false)
        end
        record = value
    end
    if type(record) ~= "table" then
        return nil, true
    end
    if isExpired(record) then
        BanStore.ClearBan(userId) -- self-healing: drop an expired timed ban on read
        return nil, true
    end
    return record, true
end

-- Writes/overwrites a ban for `userId`. record = { Reason, By, ByName, At, ExpiresAt }.
function BanStore.SetBan(userId, record)
    local key = tostring(userId)
    if usingMock then
        mock[key] = record
        return true
    end
    local ok = withRetry(function()
        store:SetAsync(key, record)
    end)
    return ok
end

-- Removes any ban for `userId` (idempotent -- safe if none exists).
function BanStore.ClearBan(userId)
    local key = tostring(userId)
    if usingMock then
        mock[key] = nil
        return true
    end
    local ok = withRetry(function()
        store:RemoveAsync(key)
    end)
    return ok
end

return BanStore
