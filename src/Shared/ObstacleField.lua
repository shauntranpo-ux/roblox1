-- ObstacleField: a tiny, data-only keep-out registry shared between world generation and the wild-spawn
-- service. Wild brainrots are SERVER-OWNED data spawns (no physics body), so they can't collide with the
-- world the normal way -- they would drift straight through buildings, trees and bushes. WorldBuilder
-- registers a flat keep-out DISC (x, z, radius) for every solid obstacle it builds; WildSpawnService's
-- confine() then resolves each spawn position OUT of any disc it lands in, so brainrots roam open ground
-- and slide around footprints instead of clipping through them.
--
-- LEVEL-AWARE: the game's level platforms are concentric discs STACKED on the same X-Z axis (confine pins
-- a spawn's Y to its level floor), so a tree on one level shares X-Z with empty space on another. Each
-- disc therefore stores the Y it was built at, and Resolve only considers discs on the SAME level band as
-- the query point -- a meadow brainrot is never shoved by a tree that lives on the lava level above it.
--
-- Pure Lua tables -- no Instances, no physics, no per-frame allocation. Deterministic + server-only.
-- WorldBuilder.Init() calls Clear() before rebuilding so the registry stays in lockstep with the world.

local ObstacleField = {}

-- Each entry: { x, z, y, r } -- a vertical cylinder keep-out on the X-Z plane at level-band y.
local discs = {}
local BAND = 60 -- half-height of a level band; discs farther than this in Y are ignored by Resolve.

function ObstacleField.Clear()
    table.clear(discs)
end

-- Register a keep-out disc centred at (x, z) on the level whose floor is near `y`, with radius r.
function ObstacleField.Add(x, z, y, r)
    if r == nil or r <= 0 then
        return
    end
    discs[#discs + 1] = { x = x, z = z, y = y or 0, r = r }
end

function ObstacleField.Count()
    return #discs
end

-- Resolve a point OUT of every same-level disc it lies inside, returning the adjusted (x, z). If the
-- point is inside a disc, it is pushed radially to that disc's boundary (plus a hair of margin).
-- Overlapping discs are handled by iterating a few passes -- enough to escape clustered footprints
-- without looping forever. A point exactly at a disc centre is nudged along +X first (deterministic).
function ObstacleField.Resolve(x, z, y)
    y = y or 0
    for _ = 1, 4 do
        local moved = false
        for _, d in ipairs(discs) do
            if math.abs(d.y - y) <= BAND then
                local dx, dz = x - d.x, z - d.z
                local distSq = dx * dx + dz * dz
                local r = d.r
                if distSq < r * r then
                    local dist = math.sqrt(distSq)
                    if dist < 1e-4 then
                        dx, dz, dist = 1, 0, 1 -- degenerate: shove along +X
                    end
                    local s = (r + 0.5) / dist
                    x = d.x + dx * s
                    z = d.z + dz * s
                    moved = true
                end
            end
        end
        if not moved then
            break
        end
    end
    return x, z
end

return ObstacleField
