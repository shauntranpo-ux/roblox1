-- RateLimiter: per-player, per-action minimum-interval throttle for client-callable remotes.
-- Defeats spam / race exploits on EVERY remote (not just purchases) -- a flood of requests is
-- silently dropped instead of doing work or racing the economy. Cheap: one timestamp per
-- (player, action key).
--
-- Usage:  if not RateLimiter.check(player, "buy", 0.4) then return end

local RateLimiter = {}

local stamps = {} -- [Player] = { [key] = lastClock }

-- Returns true if this action is allowed now (and records the time); false if it's too soon.
function RateLimiter.check(player, key, minInterval)
    local now = os.clock()
    local perPlayer = stamps[player]
    if perPlayer == nil then
        perPlayer = {}
        stamps[player] = perPlayer
    end
    local last = perPlayer[key]
    if last ~= nil and now - last < minInterval then
        return false
    end
    perPlayer[key] = now
    return true
end

-- Drops a leaving player's timestamps.
function RateLimiter.clear(player)
    stamps[player] = nil
end

return RateLimiter
