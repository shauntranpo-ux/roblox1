# Concentric-Ring Biome Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the world as a TRUE CONCENTRIC-RING bullseye — bases dead center, Sunny Meadow as a ring circling them, Sundae Shores circling the meadow, … out to The Void as the outermost ring — fixing the "only one biome / rings-over-rings" glitch.

**Architecture:** The current map places each biome as a 300×300 square at a different ANGLE and an increasing radius (a spiral/fan), with biomes 360–1560 studs out — far beyond StreamingTargetRadius (640), so 4 of 6 never stream in. Replace that with annular bands defined by `[InnerR, OuterR]` per biome at a single common ring width, built as stacked concentric DISCS (cylinders) so every biome fully surrounds the center 360°. Biome detection switches from tagged box-volumes to DISTANCE-from-center bands. Gates sit on one radial PATH at each ring boundary; the slingshot lands the player at a ring's mid-radius.

**Tech Stack:** Luau, Rojo, Roblox (Cylinder parts for discs, CollectionService tags for gates/spawn/boss, ProximityPrompt gates), StyLua + Selene.

---

## This Repo Has No Luau Unit-Test Harness

Verification is: clean Rojo build + StyLua/Selene clean + an in-Studio playtest. Each task below uses a **green-build gate + a concrete Studio check** instead of unit tests.

**Standard verify (run from `C:\Users\alxnt\roblox1`):**
```bash
stylua src && stylua --check src
selene src
rojo build default.project.json --output "$TEMP/verify.rbxlx" && rm "$TEMP/verify.rbxlx"
```
If `wally install` ever ran, recreate the empty dir first: `mkdir -p Packages`. Work on the **`radial-world-map`** branch (the map lives there). Commit after each task; end messages with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## File Structure

**Modify:**
- `src/Shared/WorldConfig.lua` — replace the `Radial` block + the `biome()` constructor with concentric **ring bands** (`InnerR/OuterR/MidR`), add `RingFor(dist)` + `RingLanding(id)`, bump streaming.
- `src/Server/BiomeService.lua` — `pointBiome` becomes DISTANCE-based (require WorldConfig).
- `src/Server/WorldBuilder.lua` — replace the per-biome square build with concentric **disc grounds** + per-ring annulus decoration/spawn/boss + ring-boundary gates on one path + one radial road.
- `src/Server/SlingshotService.lua` — land at the ring's `RingLanding` point (not a square center).

The tag contract for `BiomeGate`/`SpawnPoint`/`BossArena`/`PlotAnchor`/fixtures/`LeaderboardPillar` is unchanged. `BiomeVolume` is retired (detection is now distance-based — only `BiomeService` read it).

---

## Task 1: WorldConfig — concentric ring bands

**Files:** Modify `src/Shared/WorldConfig.lua`

- [ ] **Step 1: Bump streaming** so the inner rings stream from spawn. Change `WorldConfig.Streaming.TargetRadius = 640` → `900` and `MinRadius = 320` → `450`.

- [ ] **Step 2: Replace the `WorldConfig.Radial` block** (currently ~lines 84-93) with a `Rings` block:

```lua
-- ── CONCENTRIC-RING LAYOUT (bullseye: bases CENTER, each biome a ring around the previous) ────
WorldConfig.Center = Vector3.new(0, 0, 0)
WorldConfig.Rings = {
    PlotRingRadius = 100, -- the central base RING (PlotService MUST use this exact value)
    HubRadius = 170, -- the central plaza disc; the FIRST biome ring starts at this radius
    RingWidth = 150, -- each biome band's radial width (inner..outer)
    GatePathAngleDeg = 0, -- the single radial PATH (degrees) where the gates + the road sit
    DiscStep = 0.05, -- tiny per-ring vertical step (inner rings sit microscopically higher; no z-fight)
}
```

- [ ] **Step 3: Replace the `biome(...)` constructor** (currently ~lines 113-137) so a biome is an annular BAND derived from its tier + the ring width:

```lua
-- Each biome is an ANNULAR RING [InnerR, OuterR] at an increasing radius -> it fully circles the center.
-- `tier` (1 = innermost, the starter meadow) sets the band. MidR is the band's middle (spawn/slingshot).
local function biome(id, name, tier, ground, accent, material, style, open)
    local R = WorldConfig.Rings
    local innerR = R.HubRadius + (tier - 1) * R.RingWidth
    return {
        Id = id,
        Name = name,
        Tier = tier,
        InnerR = innerR,
        OuterR = innerR + R.RingWidth,
        MidR = innerR + R.RingWidth / 2,
        TopY = (tier) * R.DiscStep, -- this ring's ground top Y (inner rings slightly higher)
        GroundColor = ground,
        Accent = accent,
        GroundMaterial = material,
        Style = style,
        Open = open == true,
        TreeCount = 12,
        PropCount = 16,
    }
end
```

The six `biome("sunny_meadow","Sunny Meadow",1,...)` … `biome("the_void","The Void",6,...)` calls (the tier + colors + styles) are UNCHANGED — keep them exactly as they are.

- [ ] **Step 4: Add the ring helpers** right after the `WorldConfig.Get` function (~line 210):

```lua
-- DISTANCE-BASED biome lookup: which ring band contains a horizontal distance from the world center.
-- Inside the hub (below the first ring) -> the starter; beyond the outermost ring -> the last biome.
function WorldConfig.RingFor(dist)
    for _, b in ipairs(WorldConfig.Biomes) do
        if dist >= b.InnerR and dist < b.OuterR then
            return b.Id
        end
    end
    if dist < WorldConfig.Biomes[1].InnerR then
        return WorldConfig.Biomes[1].Id
    end
    return WorldConfig.Biomes[#WorldConfig.Biomes].Id
end

-- The world point the slingshot lands a player at for a ring: its mid-radius, ON the gate/road path.
function WorldConfig.RingLanding(id)
    local b = WorldConfig.Get(id)
    if b == nil then
        return WorldConfig.Center
    end
    local a = math.rad(WorldConfig.Rings.GatePathAngleDeg)
    return Vector3.new(math.cos(a) * b.MidR, b.TopY + 5, math.sin(a) * b.MidR)
end
```

- [ ] **Step 5: Update the LAYOUT comment** at the top of the file (lines 7-12) to describe the bullseye (one sentence: "Bases at the world origin; the six biomes are CONCENTRIC RINGS around them — meadow innermost, void outermost — built as stacked discs; you progress outward through gates on one radial path.").

- [ ] **Step 6: Run the standard verify.** WorldBuilder still reads old fields (`cfg.Center`, `cfg.Angle`, `cfg.Size`, `WorldConfig.Radial`) until Task 3 — but `rojo build` only COMPILES Luau, so it stays green. (Tasks 3-5 remove every old-field read.)

- [ ] **Step 7: Commit** — `git commit -am "feat(world): concentric ring-band biome config"`.

---

## Task 2: BiomeService — distance-based detection

**Files:** Modify `src/Server/BiomeService.lua`

- [ ] **Step 1: Require WorldConfig.** Under the existing `local BiomeConfig = require(ReplicatedStorage.Shared.BiomeConfig)` add:
```lua
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
```

- [ ] **Step 2: Replace `pointBiome` + the now-dead box helpers.** Delete the `inside(part, point)` function (~lines 45-50), the `VOLUME_TAG`/`warnedNoVolumes` locals (~lines 39, 43), and the whole `pointBiome` function (~lines 52-81). Replace `pointBiome` with:

```lua
-- DISTANCE-BASED ring detection: the biome is the concentric ring band the player's horizontal distance
-- from the world center falls in (WorldConfig.RingFor). No tagged volumes -> nothing to mis-tag.
local function pointBiome(point)
    local dist = Vector3.new(point.X, 0, point.Z).Magnitude
    return WorldConfig.RingFor(dist)
end
```

Leave `rootOf`, `isUnlocked`, `highestUnlocked`, `routedBiome`, `RollRarityFor`, `CurrentBiome`, and everything below UNCHANGED — they call `pointBiome` the same way (it never returns nil now, which is fine: `routedBiome`/`CurrentBiome` already `or BiomeConfig.StarterBiome`).

- [ ] **Step 3: Confirm no orphans.** Grep returns nothing:
```bash
grep -nE "VOLUME_TAG|warnedNoVolumes|CollectionService" src/Server/BiomeService.lua
```
If `CollectionService` is now unused, remove its `game:GetService("CollectionService")` line.

- [ ] **Step 4: Run the standard verify.**

- [ ] **Step 5: Manual Studio check** — Press Play, walk straight out from spawn; the top-left biome chip changes Sunny Meadow → (as you cross radii) Sundae Shores → … (once Task 3-5 build the rings). For now just confirm green build + no boot error.

- [ ] **Step 6: Commit** — `git commit -am "feat(world): distance-based ring biome detection"`.

---

## Task 3: WorldBuilder — concentric disc grounds

**Files:** Modify `src/Server/WorldBuilder.lua`

- [ ] **Step 1: Add a disc helper** right after the `part(...)` helper (~line 68):

```lua
-- A flat circular DISC (a Cylinder rotated so its round faces point up/down). `r` = radius, `topY` = the
-- ground surface height, `thickness` = how deep it goes. Anchored, low-overhead (ONE part per ring).
local function disc(r, topY, thickness, color, material, parent)
    local d = part({
        Size = Vector3.new(thickness, r * 2, r * 2),
        Color = color,
        Material = material,
        CFrame = CFrame.new(0, topY - thickness / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
    }, parent)
    d.Shape = Enum.PartType.Cylinder
    return d
end
```

- [ ] **Step 2: Add `buildRings`** (concentric biome ground, built OUTERMOST first so inner rings render on top, each fully circling the center). Add it just above `buildBiome` (~line 585):

```lua
-- Build the 6 biome rings as stacked concentric DISCS (void largest -> meadow smallest), so each biome
-- shows as a clean circular band around the center. Inner rings sit a hair higher (DiscStep) -> no
-- z-fight, still flat/walkable. ONE disc part per biome (cheap). Returns nothing.
local function buildRings(folder)
    -- outermost (highest tier) first
    for i = #WorldConfig.Biomes, 1, -1 do
        local cfg = WorldConfig.Biomes[i]
        disc(cfg.OuterR, cfg.TopY, S.GroundThickness, cfg.GroundColor, cfg.GroundMaterial, folder)
    end
end
```

- [ ] **Step 3: In `WorldBuilder.Init`, call `buildRings` + drop the per-biome square build.** Find the biome loop in `Init` (currently `for _, cfg in ipairs(WorldConfig.Biomes) do buildBiome(...) buildGate(...) end`). Replace the WHOLE block that builds district/biomes/roads with this order (the new `buildBiomeRing` + `buildRingGates` + `buildRingRoad` come in Tasks 4-5; for THIS task call only `buildRings`):

```lua
    buildDistrict(worldFolder) -- central plaza ground + plot platforms + PlotAnchors (unchanged)
    buildHub(worldFolder)
    buildRings(worldFolder) -- the 6 concentric biome ground discs
    for _, cfg in ipairs(WorldConfig.Biomes) do
        buildBiomeRing(worldFolder, cfg) -- per-ring decoration + spawn + boss + sign (Task 4)
    end
    buildRingGates(worldFolder) -- gates at each ring boundary on the path (Task 5)
    buildRingRoad(worldFolder) -- one radial road through all the gates (Task 5)
    buildIslands(worldFolder)
```

> Until Tasks 4-5 add `buildBiomeRing`/`buildRingGates`/`buildRingRoad`, this won't compile. To keep Task 3 independently green, TEMPORARILY add three empty stubs above `WorldBuilder.Init` and delete them in Tasks 4/5:
```lua
local function buildBiomeRing(_folder, _cfg) end
local function buildRingGates(_folder) end
local function buildRingRoad(_folder) end
```
Also DELETE the old `buildBiome`, `buildGate`, `buildRoads`, and `terrainFeatures` functions in Tasks 4-5 (they read the removed `cfg.Center/Size/Angle`). For Task 3, leave them defined but unreferenced (still compiles) and remove in Task 4.

- [ ] **Step 4: Run the standard verify.**

- [ ] **Step 5: Manual Studio check** — Play, fly up: the ground is now concentric colored rings (green meadow innermost → dark void outermost) circling the central plaza. Walk out: you cross from green to sand to swamp colors. (Gates/decoration come next.)

- [ ] **Step 6: Commit** — `git commit -am "feat(world): concentric biome ground discs"`.

---

## Task 4: WorldBuilder — per-ring decoration, spawn, boss, sign

**Files:** Modify `src/Server/WorldBuilder.lua`

- [ ] **Step 1: Delete** the old `terrainFeatures`, `buildBiome` functions and the `buildBiomeRing` stub from Task 3.

- [ ] **Step 2: Add a polar helper + `buildBiomeRing`.** Place where `buildBiome` was. It scatters props/hills in the ANNULUS (avoiding the gate path), and tags one `SpawnPoint` + one `BossArena` in the ring, plus a name sign at the ring's inner edge on the path:

```lua
-- A world point at (radius, angleDeg) on the ground, at this ring's top height.
local function polar(radius, angleDeg, y)
    local a = math.rad(angleDeg)
    return Vector3.new(math.cos(a) * radius, y or 0, math.sin(a) * radius)
end

local function jitterColor(base, amount)
    local function j(v)
        return math.clamp(v * 255 + rng:NextInteger(-amount, amount), 0, 255)
    end
    return Color3.fromRGB(j(base.R), j(base.G), j(base.B))
end

-- Decoration + tagged spawn/boss + sign for ONE biome ring. Spawn sits OFF the gate path (so it stays
-- open), the boss arena opposite it; hills/props scatter in the annulus, clear of the path + spawn.
local function buildBiomeRing(folder, cfg)
    local T = WorldConfig.Terrain
    local pathA = WorldConfig.Rings.GatePathAngleDeg
    local spawnA = pathA + 90 -- spawn area 90 deg off the path
    local arenaA = pathA - 90 -- boss arena opposite
    local y = cfg.TopY

    -- wild SpawnPoint markers (a few, in the spawn arc at mid-radius)
    for k = -1, 1 do
        local sp = part({
            Size = Vector3.new(2, 1, 2),
            Position = polar(cfg.MidR, spawnA + k * 8, y + 1),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        sp.Name = "SpawnPoint_" .. cfg.Id .. "_" .. (k + 2)
        tag(sp, "SpawnPoint")
        sp:SetAttribute("Biome", cfg.Id)
    end

    -- a flat boss-arena clearing + tagged center
    local arenaPos = polar(cfg.MidR, arenaA, y)
    part({
        Size = Vector3.new(64, 1, 64),
        Position = arenaPos + Vector3.new(0, 0.2, 0),
        Color = cfg.GroundColor:Lerp(P.Sand, 0.35),
    }, folder)
    local arena = part({
        Size = Vector3.new(4, 1, 4),
        Position = arenaPos + Vector3.new(0, 1, 0),
        Transparency = 1,
        CanCollide = false,
    }, folder)
    arena.Name = "BossArena_" .. cfg.Id
    tag(arena, "BossArena")
    arena:SetAttribute("Biome", cfg.Id)

    -- biome name sign at the ring's inner edge, on the path (greets you as you cross the gate)
    worldSign(folder, polar(cfg.InnerR + 12, pathA, y), string.upper(cfg.Name), cfg.Accent)

    -- HILLS + props scattered around the ring (capped), kept clear of the path + spawn + arena.
    local clearPath = 40 -- keep this many degrees of arc around the path clear
    for _ = 1, cfg.TreeCount + T.HillCount do
        local ang = rng:NextNumber(0, 360)
        local rad = rng:NextNumber(cfg.InnerR + 18, cfg.OuterR - 18)
        local pos = polar(rad, ang, y)
        local dToPath = math.abs(((ang - pathA + 180) % 360) - 180)
        if dToPath > clearPath and (pos - arenaPos).Magnitude > 40 then
            local h = rng:NextNumber(T.HillMinHeight, T.HillMaxHeight)
            local w = rng:NextNumber(T.HillMinSize, T.HillMaxSize)
            part({
                Size = Vector3.new(w, h, w),
                Position = pos + Vector3.new(0, h / 2, 0),
                Color = jitterColor(cfg.GroundColor, T.ColorJitter),
                Material = cfg.GroundMaterial,
            }, folder)
        end
    end
end
```

- [ ] **Step 3: Run the standard verify.** (`buildRingGates`/`buildRingRoad` are still stubs from Task 3 — keep those two stubs for now.)

- [ ] **Step 4: Manual Studio check** — Play, walk a ring: name signs greet you, hills dot the band (not on the straight path out), spawn brainrots appear, a boss can spawn in the arena. Confirm the path outward (angle 0) stays clear/walkable.

- [ ] **Step 5: Commit** — `git commit -am "feat(world): per-ring decoration, spawn, boss, sign"`.

---

## Task 5: WorldBuilder — ring gates + the radial road

**Files:** Modify `src/Server/WorldBuilder.lua`

- [ ] **Step 1: Delete** the old `buildGate` + `buildRoads` functions and the `buildRingGates`/`buildRingRoad` stubs.

- [ ] **Step 2: Add `buildRingGates`** — a gate ARCH straddling the path at each non-starter ring's inner edge (the boundary you cross to enter it). Tags `BiomeGate` + `TargetBiome` (Biomes.lua opens it per-player on unlock; rarity routing is the real reward gate, so no full wall is needed):

```lua
-- A gate at each ring boundary, straddling the radial PATH. The barrier (tagged) blocks the path until
-- the player unlocks that biome; off-path the rings are an open continuous disc (routing gates rewards).
local function buildRingGates(folder)
    local pathA = WorldConfig.Rings.GatePathAngleDeg
    local w, h = S.GateWidth, S.WallHeight
    for _, cfg in ipairs(WorldConfig.Biomes) do
        if not cfg.Open then
            local pos = polar(cfg.InnerR, pathA, cfg.TopY)
            -- face the gate ALONG the path (its thin axis blocks outward travel)
            local cf = CFrame.lookAt(
                Vector3.new(pos.X, cfg.TopY + h / 2, pos.Z),
                WorldConfig.Center + Vector3.new(0, cfg.TopY + h / 2, 0)
            )
            local barrier = part({ Size = Vector3.new(w, h, 4), CFrame = cf, Color = P.RedTrim }, folder)
            barrier.Name = "Gate_" .. cfg.Id
            tag(barrier, "BiomeGate")
            barrier:SetAttribute("TargetBiome", cfg.Id)
            barrier:SetAttribute("Biome", cfg.Id)
            part({
                Size = Vector3.new(w + 4, 2, 5),
                CFrame = cf * CFrame.new(0, h / 2 + 1, 0),
                Color = P.Gold,
                Glow = true,
            }, folder)
            for _, sx in ipairs({ -1, 1 }) do
                part({
                    Size = Vector3.new(3, h + 4, 3),
                    CFrame = cf * CFrame.new(sx * w / 2, 2, 0),
                    Color = P.Wood,
                    Material = Enum.Material.Wood,
                }, folder)
            end
        end
    end
end
```

- [ ] **Step 3: Add `buildRingRoad`** — one straight road from the hub edge out through all the gates to the void's outer edge:

```lua
-- ONE radial road from the hub out to the world's edge, along the gate PATH (passes through every gate).
local function buildRingRoad(folder)
    local pathA = WorldConfig.Rings.GatePathAngleDeg
    local startR = WorldConfig.Rings.HubRadius - 20
    local endR = WorldConfig.Biomes[#WorldConfig.Biomes].OuterR
    local length = endR - startR
    local midR = (startR + endR) / 2
    local mid = polar(midR, pathA, 0.3)
    local cf = CFrame.lookAt(Vector3.new(mid.X, 0.3, mid.Z), WorldConfig.Center + Vector3.new(0, 0.3, 0))
    part({ Size = Vector3.new(S.PathWidth + 8, 0.6, length), CFrame = cf, Color = P.Sand }, folder)
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(2, 0.8, length),
            CFrame = cf * CFrame.new(sx * (S.PathWidth / 2 + 5), 0.1, 0),
            Color = P.RedTrim,
        }, folder)
    end
end
```

- [ ] **Step 4: Confirm no orphans** — grep returns nothing:
```bash
grep -nE "cfg\.Center|cfg\.Angle|cfg\.Size|WorldConfig\.Radial|outwardDir|facingCenter|buildBiome\b" src/Server/WorldBuilder.lua
```
(`outwardDir`/`facingCenter` were only used by the deleted spoke build — remove them if now unused; Selene will flag them.)

- [ ] **Step 5: Run the standard verify.**

- [ ] **Step 6: Manual Studio check** — Play: a road runs straight out through gated arches at each ring boundary. A locked gate is solid on the path; unlock it (`/setcash` then hold its prompt) → it opens + you walk through to the next ring. Off-path you can roam the open ring disc.

- [ ] **Step 7: Commit** — `git commit -am "feat(world): ring-boundary gates + radial road"`.

---

## Task 6: SlingshotService — land in the right ring

**Files:** Modify `src/Server/SlingshotService.lua`

- [ ] **Step 1: Land at the ring's path point.** In `handleLaunch`, the success return currently uses `worldBiome.Center + Vector3.new(0, SlingshotConfig.LandingHeight, 0)`. Replace that `Target` with the ring landing:

```lua
    return {
        Result = "Success",
        Target = WorldConfig.RingLanding(biomeId) + Vector3.new(0, SlingshotConfig.LandingHeight, 0),
        FlightTime = SlingshotConfig.FlightTime,
    }
```
(`WorldConfig` is already required in this file; `RingLanding` was added in Task 1. The `worldBiome.Tier` analytics line above still works.)

- [ ] **Step 2: Run the standard verify.**

- [ ] **Step 3: Manual Studio check** — open the Slingshot menu, launch to an unlocked ring → you arc and land ON that ring (its mid-radius on the path), not at the world origin.

- [ ] **Step 4: Commit** — `git commit -am "feat(slingshot): land at the ring mid-radius"`.

---

## Task 7: Integration verify + playtest

- [ ] **Step 1: Standard verify** on the whole tree (green).

- [ ] **Step 2: Full Studio playtest:**
  - Fly up → a clean BULLSEYE: central plaza + plot ring, then 6 concentric colored biome rings out to the void.
  - Walk straight out → the biome chip steps Sunny Meadow → Sundae Shores → Croco Swamp → … as you cross each radius (proves distance detection + rings line up).
  - Each ring fully circles you (360°), distinct color/material, with hills + a name sign + spawns; the path stays open.
  - A locked gate blocks the path; unlock → pass. Off-path you roam the open disc but locked biomes still give only your unlocked rarities (routing).
  - Slingshot → lands you in the chosen ring.
  - F9: no `BiomeVolume` warning, no service errors, no remote drift.

- [ ] **Step 3: Tune to taste** — `WorldConfig.Rings.RingWidth` (band thickness), `HubRadius`, `Streaming.TargetRadius`, `Terrain` density. Re-verify + commit if changed.

- [ ] **Step 4: Finish the branch** — use **superpowers:finishing-a-development-branch**.

---

## Self-Review (against the request)

**Spec coverage:**
- "Base in middle, biome circling it, then another biome circling that, and so on" → Task 1 (ring bands `InnerR/OuterR` per tier) + Task 3 (concentric discs, void→meadow). ✓
- "Only one biome / map glitches" → Task 1 streaming bump (640→900) + the rings now SURROUND spawn (meadow at 170-320 all around) so you immediately see meadow+shores+swamp; distance detection (Task 2) makes every band live. ✓
- "Add the biomes" → all 6 rings build, are distinct (color/material/decoration/sign), reachable by road (Task 5) or slingshot (Task 6). ✓

**Placeholder scan:** every code step is complete. The only "stub" is the explicitly-temporary Task 3 compile bridge, deleted in Tasks 4-5.

**Type consistency:** biome fields `InnerR/OuterR/MidR/TopY/Tier` are defined in Task 1 and consumed identically in Tasks 3-6; `RingFor`/`RingLanding`/`disc`/`polar`/`buildRings`/`buildBiomeRing`/`buildRingGates`/`buildRingRoad` names match across tasks. `WorldConfig.Rings.GatePathAngleDeg` is the single source for the path angle (used by gates, road, spawn/arena offsets, landing).

**Note (cross-system):** `BiomeVolume` is retired (only `BiomeService` read it). The hard-coded leaderboard stands (`LeaderboardBillboards` `FIRST_STAND`) still sit near origin on the plaza — cosmetic, out of scope.
