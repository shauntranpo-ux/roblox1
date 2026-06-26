-- TapService (tap-to-progress): the ONE shared server module behind UNCAPPED TAPPING for catch/steal/
-- combat. It owns the single new client->server path (Remotes.TapBatch), the per-player ANTI-CHEAT token
-- bucket, and the generic per-player progress FILL for catch/steal. It NEVER trusts a raw client count:
-- every batch is clamped to a generous human-max rate, then VALIDATED + completed by the home system
-- (whose atomic transfers/rewards are UNCHANGED). Combat applies validated taps as damage directly.
--
-- ============================  SELF-AUDIT (tap security)  ====================================
-- (a) THE FEEL IS UNCAPPED CLIENT-SIDE; this module is the SERVER reconciler -- it bounds PROGRESS, not
--     the player's tapping. (b) TOKEN BUCKET: tokens refill at HumanMaxRate (cap BurstCap); a batch can
--     spend at most floor(tokens) -> an auto-clicker claiming thousands is clamped to human-possible
--     progress and can NEVER instant-complete. (c) The raw client `Taps` is used ONLY as an upper bound
--     on what the bucket allows; the APPLIED count is always the validated one. (d) Completion is decided
--     HERE/in the home system (server), never by the client; the existing atomic ops fire exactly once.
-- (e) Oversized/malformed payloads + firehose intervals are rejected at the boundary; one remote only.
-- ===========================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TapConfig = require(ReplicatedStorage.Shared.TapConfig)

local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)
local WildSpawnService = require(script.Parent.WildSpawnService)
local StealService = require(script.Parent.StealService)
local BossService = require(script.Parent.BossService)

local TapService = {}

local bucket = {} -- [Player] = { tokens, last } anti-cheat token bucket
local progress = {} -- [Player] = { Kind, TargetId, Count } the player's ONE active catch/steal fill

-- Refills + spends the player's token bucket, returning how many of `claimed` taps are ALLOWED (the
-- sustained rate is bounded to HumanMaxRate, bursts to BurstCap). This is the whole anti-cheat clamp.
local function clampTaps(player, claimed)
    local now = os.clock()
    local b = bucket[player]
    if b == nil then
        b = { tokens = TapConfig.BurstCap, last = now }
        bucket[player] = b
    end
    b.tokens = math.min(TapConfig.BurstCap, b.tokens + (now - b.last) * TapConfig.HumanMaxRate)
    b.last = now
    local allowed = math.floor(b.tokens)
    local validated = math.clamp(claimed, 0, allowed)
    b.tokens -= validated
    return validated
end

local function push(player, kind, targetId, count, need, done)
    Remotes.PushTap(player, {
        Kind = kind,
        TargetId = targetId,
        Count = count,
        Need = need,
        Done = done == true,
    })
end

local function handleBatch(player, payload)
    if type(payload) ~= "table" then
        return
    end
    local kind = payload.Kind
    local claimed = tonumber(payload.Taps)
    -- BOUNDARY: shape + magnitude. An oversized claim is rejected OUTRIGHT (not just clamped).
    if type(kind) ~= "string" then
        return
    end
    if
        claimed == nil
        or claimed ~= claimed
        or claimed <= 0
        or claimed > TapConfig.MaxTapsPerBatch
    then
        return
    end
    local targetId = payload.TargetId
    if kind ~= "combat" and (type(targetId) ~= "string" or #targetId == 0 or #targetId > 64) then
        return
    end
    -- ANTI-FIREHOSE: a single client cannot send batches faster than MinBatchInterval.
    if not RateLimiter.check(player, "tapbatch", TapConfig.MinBatchInterval) then
        return
    end
    local taps = clampTaps(player, claimed)
    if taps <= 0 then
        return -- bucket empty (exploiter spamming) -> no progress
    end

    -- COMBAT: each validated tap is one server-computed damage hit (no fill meter; HP is the meter).
    if kind == "combat" then
        BossService.TapAttack(player, taps)
        return
    end

    -- CATCH / STEAL: a progress FILL. Track ONE active interaction per player; a new target resets it.
    local cur = progress[player]
    if cur == nil or cur.Kind ~= kind or cur.TargetId ~= targetId then
        cur = { Kind = kind, TargetId = targetId, Count = 0 }
        progress[player] = cur
    end

    local ok, need
    if kind == "catch" then
        ok, need = WildSpawnService.TapValidate(player, targetId)
    elseif kind == "steal" then
        ok, need = StealService.TapValidate(player, targetId)
    else
        progress[player] = nil
        return -- unknown kind
    end

    if not ok then
        -- target gone / out of range / ineligible (e.g. a creature fled) -> reset the fill cleanly.
        progress[player] = nil
        push(player, kind, targetId, 0, need or 0, false)
        return
    end

    cur.Count += taps
    if cur.Count >= need then
        progress[player] = nil
        local done, failReason
        if kind == "catch" then
            done, failReason = WildSpawnService.TapComplete(player, targetId)
        else
            done, failReason = StealService.TapComplete(player, targetId)
        end
        -- If completion failed (out of range, pad full, etc.) notify the player with a clear reason
        -- instead of silently resetting to zero with a full-looking meter.
        if not done and failReason ~= nil then
            Remotes.NotifyPlayer(player, "error", failReason)
        end
        push(player, kind, targetId, need, need, done) -- server decides completion, not the client
    else
        push(player, kind, targetId, cur.Count, need, false)
    end
end

-- Drops a leaving player's bucket + active fill (called from Bootstrap before profile release).
function TapService.ClearPlayer(player)
    bucket[player] = nil
    progress[player] = nil
end

function TapService.Init()
    Remotes.TapBatch.OnServerEvent:Connect(handleBatch)
end

return TapService
