-- ReferralStore (M13.1): the durable cross-session "mailbox" that delivers a QUALIFIED referral to an
-- inviter who is OFFLINE (or on another server) when their friend hits the milestone. Keyed by the
-- INVITER's userId; the value is the set of invitee userIds who have qualified. The inviter drains it
-- on their next join and applies any NOT-yet-counted credits (the inviter's PROFILE QualifiedReferrals
-- set is the idempotency ledger, so the mailbox can never double-credit). Mock fallback in Studio.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReferralStore = {}

local STORE_NAME = "ReferralCredits_v1"
local DS_RETRIES = 3

local usingMock = false
local mock = {} -- [inviterKey] = { [inviteeKey] = true }
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
        DataStoreService:GetDataStore("__ref_probe"):GetAsync("probe")
    end)
    return ok
end

function ReferralStore.Init()
    usingMock = not apiAvailable()
    if not usingMock then
        store = DataStoreService:GetDataStore(STORE_NAME)
    end
    print(
        usingMock and "[Referral] DataStore API unavailable -> MOCK referral mailbox."
            or "[Referral] Using REAL referral mailbox DataStore."
    )
end

-- Records that `inviteeId` qualified for `inviterId` (idempotent set-add; survives offline/cross-server).
function ReferralStore.AddPending(inviterId, inviteeId)
    local key = tostring(inviterId)
    local field = tostring(inviteeId)
    if usingMock then
        mock[key] = mock[key] or {}
        mock[key][field] = true
        return
    end
    withRetry(function()
        store:UpdateAsync(key, function(current)
            current = (type(current) == "table") and current or {}
            current[field] = true
            return current
        end)
    end)
end

-- Returns the array of invitee userIds (numbers) currently in `inviterId`'s mailbox.
function ReferralStore.GetPending(inviterId)
    local key = tostring(inviterId)
    local data
    if usingMock then
        data = mock[key]
    else
        local ok, value = withRetry(function()
            return store:GetAsync(key)
        end)
        data = ok and value or nil
    end
    local ids = {}
    if type(data) == "table" then
        for field in pairs(data) do
            local id = tonumber(field)
            if id ~= nil then
                table.insert(ids, id)
            end
        end
    end
    return ids
end

return ReferralStore
