# Radial World Map + Slingshot Travel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the world so the player BASES sit in the middle and the six biomes radiate OUTWARD around them in a circle (outer = higher tier = farther), fix the blown-out white lighting, and add a SLINGSHOT that flings the player to a biome chosen from a menu (instead of a long walk / a teleporter).

**Architecture:** The world is regenerated in code by `WorldBuilder` from `WorldConfig`. Today it's a straight corridor (bases in a `+X` row at origin; biomes strung along `-Z`). We move the hub + base ring to the world origin and place each biome as a self-contained square zone at a radial position `center = (cos θ, 0, sin θ) · r`, with the angle stepping 60° per tier and the radius growing per tier — so the biomes encircle the middle and march outward. Gates, roads and signs rotate to face the center; biome ground/volumes stay axis-aligned squares so the existing tag contract (`BiomeVolume`/`SpawnPoint`/`BossArena`/`BiomeGate`) is untouched. Lighting is a value-tune in `Theme.Lighting`. The slingshot is a new server-validated launch: the client picks an unlocked biome, the server (reusing `BiomeService`'s unlock truth) approves + returns the landing point, and the client applies a ballistic velocity to its own character (Roblox owns the local character physics). Unlock is the authority; rewards are already gated by `BiomeService` routing, so flinging can never be an exploit.

**Tech Stack:** Luau, Rojo, Roblox (CollectionService tags, ProximityPrompt, BillboardGui, AssemblyLinearVelocity ballistic launch), StyLua + Selene, ProfileStore (unchanged here).

---

## This Codebase Has No Luau Unit-Test Harness

There is no Lua test runner in this repo. Every milestone is verified by: **(1)** a clean Rojo build, **(2)** StyLua + Selene clean, **(3)** an in-Studio playtest against a written checklist. So each task below replaces "write a failing test" with a **green-build gate + a concrete manual Studio check**. Do not invent a test framework.

**The standard verify (run from `C:\Users\alxnt\roblox1`, every task):**

```bash
# format, then confirm clean
stylua src && stylua --check src
# lint
selene src
# build to a temp file, confirm zero errors, delete it
rojo build default.project.json --output "$TEMP/verify.rbxlx" && rm "$TEMP/verify.rbxlx"
```

PowerShell equivalent for the build line: `rojo build default.project.json --output "$env:TEMP\verify.rbxlx"; Remove-Item "$env:TEMP\verify.rbxlx"`. **If `wally install` was ever run it deletes the empty `Packages/` dir** — recreate it before building: `New-Item -ItemType Directory -Force Packages`.

Expected every time: `stylua --check` prints nothing (exit 0); Selene prints `0 errors, 0 warnings, 0 parse errors`; Rojo prints `Built project to ...`.

**Commit after every task.** Branch first if on `main` (`git checkout -b radial-world-map`). End commit messages with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

---

## File Structure

**Modify:**
- `src/Client/UI/Theme.lua` — `Theme.Lighting` values toned down (de-blowout) + a `Slingshot` accent.
- `src/Shared/WorldConfig.lua` — radial layout: hub/district at origin, per-biome `Center` computed from angle+radius, a `Radial` block, a `Slingshot` pad position.
- `src/Server/WorldBuilder.lua` — build hub at origin, biomes at radial centers, gates/roads/signs facing center, a tagged `Slingshot` fixture, central district ground + ring `PlotAnchor`s.
- `src/Server/PlotService.lua` — plots placed in a central ring (not a `+X` row), facing outward.
- `src/Server/BiomeService.lua` — expose a public `BiomeService.IsUnlocked(player, biomeId)` (slingshot reuses the unlock truth).
- `src/Server/Remotes.lua` — add `SlingshotAction` (RemoteFunction).
- `src/Server/Bootstrap.server.lua` — `start("SlingshotService", SlingshotService.Init)`.
- `src/Client/Client.client.lua` — wire the `Slingshot` remote + panel + Menu button.

**Create:**
- `src/Shared/SlingshotConfig.lua` — launch arc params + the hub pad position.
- `src/Server/SlingshotService.lua` — `SlingshotAction` handler (get list / validated launch).
- `src/Client/UI/Slingshot.lua` — the slingshot menu panel + the ballistic launch.

**Out of scope (separate plan):** the Shop / tab panel UI restyle.

---

## Task 1: De-blowout the lighting

**Why first:** Independent, tiny, and fixes a big part of "looks bad" (the over-exposed near-white world). No layout dependency.

**Files:**
- Modify: `src/Client/UI/Theme.lua:160-185` (the `Theme.Lighting` table)

- [ ] **Step 1: Lower brightness/exposure + tame bloom**

In `src/Client/UI/Theme.lua`, replace the current values inside `Theme.Lighting` (the washed-out cause is `Brightness = 2.4` + `ExposureCompensation = 0.12` + a low bloom `Threshold = 1.1` that blooms every bright/Neon part). Change exactly these lines:

```lua
    Brightness = 1.7,             -- was 2.4 (over-bright)
    ExposureCompensation = 0.0,   -- was 0.12 (pushed everything toward white)
    Ambient = Color3.fromRGB(120, 130, 145),       -- was (140,150,165)
    OutdoorAmbient = Color3.fromRGB(150, 162, 178), -- was (170,180,195)
```

And change the bloom + color-correction lines:

```lua
    Bloom = { Intensity = 0.3, Size = 24, Threshold = 1.6 }, -- was Intensity 0.55, Threshold 1.1
    ColorCorrection = {
        Saturation = 0.16,   -- was 0.18
        Contrast = 0.04,     -- was 0.06
        Brightness = -0.02,  -- was 0.01 (pull the whites down off the clip point)
        TintColor = Color3.fromRGB(255, 252, 245),
    },
```

Leave `ClockTime`, `GeographicLatitude`, `FogEnd`, `Atmosphere`, `SunRays`, `SkyDefault` unchanged.

- [ ] **Step 2: Run the standard verify** — build green, StyLua/Selene clean.

- [ ] **Step 3: Manual Studio check** — Press Play. The ground + hub no longer read as a blown-out white sheet; bright/Neon props still glow but don't smear the whole screen white. (If still too bright, drop `Brightness` to `1.5`; if too flat, raise to `1.9`.)

- [ ] **Step 4: Commit**

```bash
git add src/Client/UI/Theme.lua
git commit -m "fix(lighting): de-blowout the world (lower brightness/exposure, tame bloom)"
```

---

## Task 2: Radial layout config (WorldConfig)

**Why:** All geometry derives from here. After this task the config DESCRIBES a radial world; Task 3 makes the builder render it.

**Files:**
- Modify: `src/Shared/WorldConfig.lua`

- [ ] **Step 1: Add the `Radial` block + move hub/district to the origin**

Replace the `WorldConfig.Hub` and `WorldConfig.District` tables (currently lines ~65-81) with a centered layout, and add a `Radial` block + a `Slingshot` pad position directly above them:

```lua
-- ── RADIAL LAYOUT (bases in the MIDDLE; biomes encircle + march outward) ─────────────────────
WorldConfig.Center = Vector3.new(0, 0, 0)
WorldConfig.Radial = {
    PlotRingRadius = 100, -- the central base RING (PlotService MUST use this exact value)
    HubRadius = 150, -- half-extent of the central plaza (road spokes start here)
    BiomeRadius0 = 360, -- radius of the FIRST (meadow) biome's center
    BiomeRingStep = 240, -- each higher tier sits this much farther out
    AngleStartDeg = 30, -- first biome angle (offset 30 from the plot ring so spokes pass between plots)
    AngleStepDeg = 60, -- 360 / 6 biomes -> evenly around the circle
}

-- ── HUB (central plaza at the world origin; holds the slingshot + fixtures) ───────────────────
WorldConfig.Hub = {
    Center = Vector3.new(0, 0, 0),
    Size = Vector3.new(360, 1, 360), -- square central plaza footprint
    LandmarkHeight = 34,
    SparkleRate = 14,
}

-- The slingshot launch pad sits just off the plaza center (tagged "Slingshot" by WorldBuilder).
WorldConfig.Slingshot = {
    Position = Vector3.new(0, 0, 40), -- relative to Hub.Center
}

-- ── BASE DISTRICT (central ground under the PlotService base RING) ────────────────────────────
WorldConfig.District = {
    GroundSize = Vector3.new(440, 1, 440), -- one central slab covering the plaza + the base ring
}
```

- [ ] **Step 2: Compute each biome's `Center` radially**

Replace the `biome(...)` constructor (currently lines ~86-103) so a biome takes a `tier` (1-6) and computes its radial `Center`:

```lua
-- Each biome is a self-contained AXIS-ALIGNED square zone placed at a radial position. `tier` (1=nearest)
-- drives BOTH its angle (60 deg per tier) and its radius (farther per tier) -> they encircle + expand out.
local function biome(id, name, tier, ground, accent, material, style, open)
    local R = WorldConfig.Radial
    local angle = math.rad(R.AngleStartDeg + (tier - 1) * R.AngleStepDeg)
    local radius = R.BiomeRadius0 + (tier - 1) * R.BiomeRingStep
    return {
        Id = id,
        Name = name,
        Tier = tier,
        Angle = angle, -- radians, from +X (used by the builder to face gates/roads/signs at center)
        Radius = radius,
        Center = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius),
        Size = Vector3.new(300, 1, 300),
        GroundColor = ground,
        Accent = accent,
        GroundMaterial = material,
        Style = style,
        Open = open == true,
        TreeCount = 12,
        PropCount = 16,
        SpawnAreaOffset = Vector3.new(-70, 0, 0), -- left side = wild-spawn area (axis-aligned; fine)
        BossArenaOffset = Vector3.new(70, 0, 0), -- right side = boss clearing
    }
end
```

- [ ] **Step 3: Pass `tier` (1-6) instead of the old `centerZ`**

In the `WorldConfig.Biomes = { ... }` list (lines ~106-167), change each `biome(...)` call's third argument from the old Z coordinate to the tier index. Exactly:

```lua
WorldConfig.Biomes = {
    biome("sunny_meadow",  "Sunny Meadow",  1, P.Grass,              rgb(120, 210, 90),  Enum.Material.Grass,         "meadow", true),
    biome("sundae_shores", "Sundae Shores", 2, P.Sand,               rgb(255, 150, 190), Enum.Material.Sand,          "shores", false),
    biome("croco_swamp",   "Croco Swamp",   3, rgb(86, 120, 78),     rgb(60, 95, 60),    Enum.Material.Grass,         "swamp",  false),
    biome("magma_peak",    "Magma Peak",    4, rgb(54, 48, 58),      rgb(255, 110, 20),  Enum.Material.Slate,         "magma",  false),
    biome("cosmic_rift",   "Cosmic Rift",   5, rgb(96, 78, 170),     rgb(120, 230, 255), Enum.Material.SmoothPlastic, "rift",   false),
    biome("the_void",      "The Void",      6, rgb(46, 36, 86),      rgb(90, 235, 255),  Enum.Material.SmoothPlastic, "void",   false),
}
```

Leave `WorldConfig.ById`, `WorldConfig.Get`, the whole `WorldConfig.Atmosphere` block, and `WorldConfig.AtmosphereFor` exactly as they are (keyed by biome id — layout-independent).

- [ ] **Step 4: Run the standard verify.** (No visual change yet — the builder still reads the old field names in Task 3. Build must stay green; `GateInset` is no longer set on biomes, so confirm Task 3 removes every `cfg.GateInset` read.)

- [ ] **Step 5: Commit**

```bash
git add src/Shared/WorldConfig.lua
git commit -m "feat(world): radial layout config (hub at origin, biomes encircle + expand outward)"
```

---

## Task 3: Build the radial world (WorldBuilder)

**Files:**
- Modify: `src/Server/WorldBuilder.lua`

- [ ] **Step 1: Add a radial-math helper + a center-facing CFrame helper**

Near the top of `WorldBuilder.lua`, just under `local function tag(...)` (around line 72), add:

```lua
-- Horizontal unit direction from the world center out to `pos` (defaults +X if `pos` is the center).
local function outwardDir(pos)
    local flat = Vector3.new(pos.X, 0, pos.Z)
    if flat.Magnitude < 0.001 then
        return Vector3.new(1, 0, 0)
    end
    return flat.Unit
end

-- A CFrame at `pos` (at height y) whose -Z faces the world center (so a wall's thin face / a road's
-- length / a sign reads square to the spoke). `pos` is horizontal; `y` sets the height.
local function facingCenter(pos, y)
    return CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), WorldConfig.Center + Vector3.new(0, y, 0))
end
```

- [ ] **Step 2: Hub at origin + the slingshot fixture**

Replace `buildHub(folder)` (lines ~151-284). The plaza is now centered at the origin; the long waterfall/decor positions that referenced `c + Vector3.new(-180, ...)` are pulled in so they stay on the plaza. Add a tagged `Slingshot` launch pad. Full replacement:

```lua
-- ── HUB (central plaza at origin) ────────────────────────────────────────────────────────────
local function buildHub(folder)
    local hub = WorldConfig.Hub
    local c = hub.Center

    part({
        Size = Vector3.new(hub.Size.X, S.GroundThickness, hub.Size.Z),
        Position = c + Vector3.new(0, -S.GroundThickness / 2, 0),
        Color = P.HubStone,
    }, folder)

    -- SpawnLocation (players spawn on the plaza; PlotService then moves them to their base).
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "HubSpawn"
    spawn.Anchored = true
    spawn.Neutral = true
    spawn.Size = Vector3.new(16, 1, 16)
    spawn.Color = P.Gold
    spawn.Material = Enum.Material.SmoothPlastic
    spawn.Position = c + Vector3.new(0, 0.5, 0)
    spawn.TopSurface = Enum.SurfaceType.Smooth
    spawn.Parent = folder

    -- central LANDMARK monument (stacked; NOT a portal).
    part({ Size = Vector3.new(20, 4, 20), Position = c + Vector3.new(0, 2, -70), Color = P.HubStone }, folder)
    part({ Size = Vector3.new(14, 10, 14), Position = c + Vector3.new(0, 9, -70), Color = P.Sand }, folder)
    part({ Size = Vector3.new(8, 12, 8), Position = c + Vector3.new(0, 20, -70), Color = P.RedTrim }, folder)
    part({ Size = Vector3.new(5, 5, 5), Position = c + Vector3.new(0, 29, -70), Color = P.Gold, Neon = true }, folder)

    -- SLINGSHOT launch pad (tagged; the client's Slingshot menu + the prompt live on this).
    local slingPos = c + WorldConfig.Slingshot.Position
    local base = fixture(folder, slingPos, Vector3.new(12, 4, 12), P.ShieldCyan, "Slingshot", "SLINGSHOT")
    -- two Y-fork posts + a neon band, so it reads as a slingshot.
    for _, sx in ipairs({ -1, 1 }) do
        part({ Size = Vector3.new(2, 16, 2), Position = slingPos + Vector3.new(sx * 4, 12, 0), Color = P.Wood, Material = Enum.Material.Wood }, folder)
    end
    part({ Size = Vector3.new(12, 1.5, 1.5), Position = slingPos + Vector3.new(0, 20, 0), Color = P.Gold, Neon = true }, folder)
    base:SetAttribute("LaunchHeight", 24) -- the prompt/launch anchor height (purely cosmetic hint)

    -- shop stalls + free-reward blocks (tagged fixtures), arranged around the plaza.
    fixture(folder, c + Vector3.new(-90, 0, -40), Vector3.new(14, 12, 10), P.Grass, "NetShop", "NET SHOP")
    fixture(folder, c + Vector3.new(90, 0, -40), Vector3.new(14, 12, 10), P.Gold, "PremiumShop", "PREMIUM", true)
    fixture(folder, c + Vector3.new(-130, 0, 30), Vector3.new(8, 8, 8), P.RedTrim, "DailyChest", "DAILY")
    fixture(folder, c + Vector3.new(-110, 0, 50), Vector3.new(8, 8, 8), P.ShieldCyan, "FreeGift", "GIFT")
    fixture(folder, c + Vector3.new(130, 0, 30), Vector3.new(10, 10, 10), P.Gold, "SpinWheel", "SPIN", true)

    local boards = { "TopCash", "TopIncome", "RarestCollection" }
    for i, key in ipairs(boards) do
        local pillar = fixture(folder, c + Vector3.new(-44 + (i - 1) * 44, 0, -110), Vector3.new(8, 16, 8), P.PlotBase, "LeaderboardPillar", nil)
        pillar:SetAttribute("Board", key)
    end
end
```

- [ ] **Step 3: Central district ground + ring `PlotAnchor`s**

Replace `buildDistrict(folder)` (lines ~287-310) so the ground is one central slab and the `PlotAnchor` markers sit on the base ring (matching PlotService's ring in Task 4 — same radius + angle formula):

```lua
-- ── BASE DISTRICT (central ground slab + PlotAnchor markers on the base RING) ─────────────────
local function buildDistrict(folder)
    local d = WorldConfig.District
    part({
        Size = Vector3.new(d.GroundSize.X, S.GroundThickness, d.GroundSize.Z),
        Position = Vector3.new(0, -S.GroundThickness / 2, 0),
        Color = P.Grass,
        Material = Enum.Material.Grass,
    }, folder)

    -- PlotAnchor markers, one per plot, on the central ring (PlotService positions the plots themselves;
    -- this MUST use the same radius + angle so the markers line up under the bases).
    local ringR = WorldConfig.Radial.PlotRingRadius
    for index = 1, Config.Plots.Count do
        local angle = math.rad((index - 1) * (360 / Config.Plots.Count))
        local anchor = part({
            Size = Vector3.new(2, 1, 2),
            Position = Vector3.new(math.cos(angle) * ringR, 0.5, math.sin(angle) * ringR),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        anchor.Name = "PlotAnchor" .. index
        tag(anchor, "PlotAnchor")
        anchor:SetAttribute("PlotIndex", index)
    end
end
```

- [ ] **Step 4: Biome ground/volume stay axis-aligned; sign faces center**

In `buildBiome(folder, cfg)` (lines ~576-631) the ground slab, the `BiomeVolume`, the `SpawnPoint`s, and the `BossArena` are unchanged (they read `cfg.Center` + `cfg.Size` + the offsets — all still valid). Only the **sign** moved (the old `cfg.GateInset` field is gone). Replace the single sign line:

```lua
    -- biome name sign at the inner (center-facing) edge of the biome.
    local innerEdge = outwardDir(cfg.Center) * (cfg.Radius - cfg.Size.Z / 2)
    local sign = worldSign(folder, innerEdge + Vector3.new(0, 0, 0), string.upper(cfg.Name), cfg.Accent)
    sign.CFrame = facingCenter(innerEdge, sign.Position.Y) + Vector3.new(0, sign.Position.Y - innerEdge.Y, 0)
```

> Note: `worldSign` returns the board part and posts the sign at the given XZ. The reassignment rotates the board to face the center. If the helper's vertical offset fights this, simpler-and-acceptable: leave `worldSign(folder, innerEdge, ...)` without the rotation line — the sign still sits at the entrance, just axis-aligned. Prefer the rotation; fall back if the board ends up underground.

- [ ] **Step 5: Gates face the center, at the inner edge**

Replace `buildGate(folder, cfg)` (lines ~634-674) so the gate sits on the inner edge facing the hub:

```lua
-- ── GATES (a center-facing barrier at each non-starter biome's inner edge) ────────────────────
local function buildGate(folder, cfg)
    if cfg.Open then
        return
    end
    local dir = outwardDir(cfg.Center)
    local entrance = dir * (cfg.Radius - cfg.Size.Z / 2) -- inner edge, on the spoke
    local w, h = S.GateWidth, S.WallHeight
    local cf = facingCenter(entrance, h / 2) -- -Z faces center; the 4-thick face blocks the spoke

    -- left + right wing walls flanking the opening (always solid).
    local wingW = (cfg.Size.X - w) / 2
    for _, sx in ipairs({ -1, 1 }) do
        part({ Size = Vector3.new(wingW, h, 4), CFrame = cf * CFrame.new(sx * (w / 2 + wingW / 2), 0, 0), Color = P.Dirt }, folder)
    end

    -- the GATE barrier (BiomeService/Biomes.lua opens this per-player on unlock).
    local barrier = part({ Size = Vector3.new(w, h, 4), CFrame = cf, Color = P.RedTrim }, folder)
    barrier.Name = "Gate_" .. cfg.Id
    tag(barrier, "BiomeGate")
    barrier:SetAttribute("TargetBiome", cfg.Id)
    barrier:SetAttribute("Biome", cfg.Id)

    part({ Size = Vector3.new(w + 4, 2, 5), CFrame = cf * CFrame.new(0, h / 2 + 1, 0), Color = P.Gold, Neon = true }, folder)
    for _, sx in ipairs({ -1, 1 }) do
        part({ Size = Vector3.new(3, h + 4, 3), CFrame = cf * CFrame.new(sx * w / 2, 2, 0), Color = P.Wood, Material = Enum.Material.Wood }, folder)
    end
end
```

- [ ] **Step 6: Roads become spokes from the hub to each gate**

Replace `buildRoads(folder)` (lines ~677-697) so one spoke runs out to each biome's inner edge:

```lua
-- ── ROADS (a spoke from the central plaza out to each biome's inner edge) ─────────────────────
local function buildRoads(folder)
    local hubR = WorldConfig.Radial.HubRadius
    for _, cfg in ipairs(WorldConfig.Biomes) do
        local dir = outwardDir(cfg.Center)
        local innerDist = cfg.Radius - cfg.Size.Z / 2
        local length = innerDist - hubR
        if length > 0 then
            local mid = dir * (hubR + length / 2)
            local cf = facingCenter(mid, 0.1) -- -Z toward center => the Z extent (length) runs along the spoke
            part({ Size = Vector3.new(S.PathWidth + 8, 0.6, length), CFrame = cf, Color = P.Sand }, folder)
            for _, sx in ipairs({ -1, 1 }) do
                part({ Size = Vector3.new(2, 0.8, length), CFrame = cf * CFrame.new(sx * (S.PathWidth / 2 + 5), 0.1, 0), Color = P.RedTrim }, folder)
            end
        end
    end
end
```

- [ ] **Step 7: Confirm no orphan references**

Grep the file for the removed fields and confirm zero matches: `cfg.GateInset`, `hub.RoadExitZ`, `d.Min`, `d.Max`, `d.PlotAnchorZ`. (`buildIslands`, `biomeProps`, `configureStreaming`, `buildPlotTemplate`, `WorldBuilder.Init` are unchanged.)

```bash
grep -nE "GateInset|RoadExitZ|d\.Min|d\.Max|PlotAnchorZ" src/Server/WorldBuilder.lua
```

Expected: no output.

- [ ] **Step 8: Run the standard verify.**

- [ ] **Step 9: Manual Studio check** — Press Play. From above (free-cam / zoom out): the plaza is centered at origin, biome zones sit around it like spokes on a wheel, each farther out by tier (meadow nearest, void farthest), a road runs from the plaza to each biome, gates sit at the inner edge facing in, and a "SLINGSHOT" pad stands on the plaza. Bases will look wrong until Task 4 (still a `+X` row) — that's expected.

- [ ] **Step 10: Commit**

```bash
git add src/Server/WorldBuilder.lua
git commit -m "feat(world): build radial world (hub center, biome spokes, center-facing gates/roads, slingshot pad)"
```

---

## Task 4: Bases in a central ring (PlotService)

**Files:**
- Modify: `src/Server/PlotService.lua`

- [ ] **Step 1: Place plots on the central ring, facing outward**

In `PlotService.Init` (lines ~101-130), replace the per-plot origin computation. Add the ring radius constant near the other locals (under `local PAD_SIZE = ...`, line ~16): `local PLOT_RING_RADIUS = 100 -- MUST match WorldConfig.Radial.PlotRingRadius`. Then change the loop body:

```lua
    for index = 1, Config.Plots.Count do
        -- central RING: evenly spaced around the origin, each base's front (+Z) facing OUTWARD toward
        -- the biomes. lookAt(pos, center) points -Z at the center, so +Z (the template's pad/shield
        -- front) faces away from the middle. Plot-internal pad lookup is by instance, so rotation is safe.
        local angle = math.rad((index - 1) * (360 / Config.Plots.Count))
        local pos = Vector3.new(math.cos(angle) * PLOT_RING_RADIUS, 0, math.sin(angle) * PLOT_RING_RADIUS)
        local origin = CFrame.lookAt(pos, Vector3.new(0, 0, 0))
        local model = buildPlot(index, origin)
        model.Parent = plotsFolder

        local pads = {}
        for padIndex = 1, Config.Plots.PadsPerPlot do
            pads[padIndex] = model:FindFirstChild("Pad" .. padIndex, true)
        end

        plots[index] = {
            Index = index,
            Model = model,
            Pads = pads,
            Owner = nil,
            Origin = origin,
            SpawnCFrame = origin * CFrame.new(0, 6, 14), -- on the outward (front) side of the base
        }
    end
```

- [ ] **Step 2: Run the standard verify.**

- [ ] **Step 3: Manual Studio check** — Press Play. You spawn on the central plaza; your base is one of 6 in a ring around the middle, fronts facing out. Walk onto a pad and buy a unit (Shop → Brainrots) → it places on a pad correctly (proves rotated plots didn't break pad lookup). Walk off the front toward a biome road. Trigger a steal between two test players if convenient → deposit still works (proves pad world-positions are correct under rotation).

- [ ] **Step 4: Commit**

```bash
git add src/Server/PlotService.lua
git commit -m "feat(world): bases in a central ring facing outward"
```

---

## Task 5: Slingshot config + unlock accessor

**Files:**
- Create: `src/Shared/SlingshotConfig.lua`
- Modify: `src/Server/BiomeService.lua`

- [ ] **Step 1: Create `SlingshotConfig`**

```lua
-- src/Shared/SlingshotConfig.lua
-- SlingshotConfig (M-map): tunables for the SLINGSHOT travel mechanic. The slingshot flings the player
-- on a ballistic arc to a chosen UNLOCKED biome instead of a long walk (NOT a teleport). The server
-- validates the destination is unlocked + returns the landing point; the client applies the launch to
-- its OWN character (Roblox owns local character physics). Pure config -- no gameplay/economy state.

local SlingshotConfig = {}

SlingshotConfig.FlightTime = 1.7 -- seconds the arc takes to reach the target (drives the launch velocity)
SlingshotConfig.Cooldown = 3 -- seconds between launches (server-enforced, anti-spam)
SlingshotConfig.LandingHeight = 6 -- studs above the biome ground center to aim for (land ON the ground)
SlingshotConfig.MaxFlightTime = 4 -- safety clamp so a far biome can't compute an absurd velocity

return SlingshotConfig
```

- [ ] **Step 2: Expose the unlock truth from BiomeService**

`BiomeService` already has a local `isUnlocked(profile, biomeId)`. Add a PUBLIC wrapper so `SlingshotService` reuses the exact same truth (do NOT duplicate the rule). Add this just above `function BiomeService.Init()` (around line 204):

```lua
-- Public unlock check (the slingshot reuses this so there is ONE unlock authority). Returns false if the
-- profile isn't loaded. The starter biome is always unlocked.
function BiomeService.IsUnlocked(player, biomeId)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return false
    end
    return isUnlocked(profile, biomeId)
end
```

- [ ] **Step 3: Run the standard verify.** (No behavior change yet; just build green.)

- [ ] **Step 4: Commit**

```bash
git add src/Shared/SlingshotConfig.lua src/Server/BiomeService.lua
git commit -m "feat(slingshot): config + public BiomeService.IsUnlocked accessor"
```

---

## Task 6: SlingshotAction remote

**Files:**
- Modify: `src/Server/Remotes.lua`

- [ ] **Step 1: Declare it**

After the `GroupAction` declaration (added in M13.6), add:

```lua
-- Slingshot travel. Client sends INTENT only ({ Action="get"|"launch", BiomeId? }); the server checks
-- the destination is unlocked + returns the landing point. The client applies the arc to its own char.
Remotes.SlingshotAction = nil -- RemoteFunction : client -> server -> { Result, Biomes?/Target?/FlightTime?/Message }
```

- [ ] **Step 2: Add to `ExpectedNames`** — append `"SlingshotAction",` to the `Remotes.ExpectedNames` list (after `"GroupAction"`).

- [ ] **Step 3: Create it in `Init`** — after the `groupAction` creation block:

```lua
    local slingshotAction = Instance.new("RemoteFunction")
    slingshotAction.Name = "SlingshotAction"
    slingshotAction.Parent = folder
```

- [ ] **Step 4: Assign it** — after `Remotes.GroupAction = groupAction`:

```lua
    Remotes.SlingshotAction = slingshotAction
```

- [ ] **Step 5: Run the standard verify.** The boot diagnostic verifies the remote surface against `ExpectedNames`, so a green build + (later) a clean boot proves the four edits are in sync.

- [ ] **Step 6: Commit**

```bash
git add src/Server/Remotes.lua
git commit -m "feat(slingshot): add SlingshotAction remote"
```

---

## Task 7: SlingshotService (server)

**Files:**
- Create: `src/Server/SlingshotService.lua`
- Modify: `src/Server/Bootstrap.server.lua`

- [ ] **Step 1: Create the service**

```lua
-- src/Server/SlingshotService.lua
-- SlingshotService (M-map): server half of the SLINGSHOT. It owns the AUTHORITY (which biome you may be
-- flung to) + the landing point; the client owns the launch PHYSICS on its own character. "get" returns
-- the biome list + per-biome unlock state (for the menu); "launch" validates the destination is unlocked
-- (reusing BiomeService.IsUnlocked -- one unlock authority), rate-limits, and returns the world landing
-- point + flight time. Flinging to a locked biome is refused; even if a hacked client self-flings,
-- BiomeService's rarity ROUTING still gates rewards by unlock (not position), so it is never an exploit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local BiomeConfig = require(ReplicatedStorage.Shared.BiomeConfig)
local SlingshotConfig = require(ReplicatedStorage.Shared.SlingshotConfig)

local BiomeService = require(script.Parent.BiomeService)
local RateLimiter = require(script.Parent.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)

local SlingshotService = {}

-- The ordered biome list + this player's unlock state, for the menu.
local function listFor(player)
    local out = {}
    for _, b in ipairs(BiomeConfig.Ladder) do
        table.insert(out, {
            BiomeId = b.BiomeId,
            Name = b.Name,
            Tier = WorldConfig.Get(b.BiomeId) ~= nil and WorldConfig.Get(b.BiomeId).Tier or 0,
            Unlocked = BiomeService.IsUnlocked(player, b.BiomeId),
        })
    end
    return out
end

local function handleLaunch(player, biomeId)
    if not RateLimiter.check(player, "slingshot", SlingshotConfig.Cooldown) then
        return { Result = "Error", Message = "Reloading the slingshot..." }
    end
    if type(biomeId) ~= "string" or BiomeConfig.Get(biomeId) == nil then
        return { Result = "Error", Message = "Unknown destination." }
    end
    if not BiomeService.IsUnlocked(player, biomeId) then
        return { Result = "Error", Message = "Unlock that biome first!" }
    end
    local worldBiome = WorldConfig.Get(biomeId)
    if worldBiome == nil then
        return { Result = "Error", Message = "That biome has no location." }
    end
    Analytics.custom(player, Analytics.Events.SlingshotLaunch, worldBiome.Tier or 0)
    return {
        Result = "Success",
        Target = worldBiome.Center + Vector3.new(0, SlingshotConfig.LandingHeight, 0),
        FlightTime = SlingshotConfig.FlightTime,
    }
end

function SlingshotService.Init()
    Remotes.SlingshotAction.OnServerInvoke = function(player, payload)
        if type(payload) ~= "table" or type(payload.Action) ~= "string" then
            return { Result = "Error", Message = "Invalid request." }
        end
        if payload.Action == "get" then
            return { Result = "Success", Biomes = listFor(player) }
        elseif payload.Action == "launch" then
            return handleLaunch(player, payload.BiomeId)
        end
        return { Result = "Error", Message = "Unknown action." }
    end
end

return SlingshotService
```

- [ ] **Step 2: Add the analytics constant**

In `src/Server/Analytics.lua`, in the `Analytics.Events` table (after the M13.6 entries), add:

```lua
    SlingshotLaunch = "slingshot_launch", -- a player launched to a biome via the slingshot (value=tier)
```

- [ ] **Step 3: Wire Bootstrap**

In `src/Server/Bootstrap.server.lua`, require it near the other M-additions (after `NotificationService`):

```lua
local SlingshotService = require(script.Parent.SlingshotService)
```

And start it next to the other remote-binding services (after `start("GroupRewardService", GroupRewardService.Init)`):

```lua
start("SlingshotService", SlingshotService.Init)
```

- [ ] **Step 4: Run the standard verify.**

- [ ] **Step 5: Manual Studio check** — Press Play, open the F9 dev console; no `[Bootstrap] SlingshotService failed` warning, and the boot diagnostic reports the remote surface matches (no drift warning for `SlingshotAction`).

- [ ] **Step 6: Commit**

```bash
git add src/Server/SlingshotService.lua src/Server/Analytics.lua src/Server/Bootstrap.server.lua
git commit -m "feat(slingshot): server validation + landing-point service"
```

---

## Task 8: Slingshot menu + launch (client)

**Files:**
- Create: `src/Client/UI/Slingshot.lua`
- Modify: `src/Client/UI/Theme.lua` (accent), `src/Client/Client.client.lua` (wire)

- [ ] **Step 1: Add a Theme accent**

In `src/Client/UI/Theme.lua`, in `Theme.Accents`, after the `Report` entry, add:

```lua
    Slingshot = { Top = Color3.fromRGB(120, 230, 200), Bottom = Color3.fromRGB(40, 170, 150) }, -- launch teal
```

- [ ] **Step 2: Create the panel + the ballistic launch**

```lua
-- src/Client/UI/Slingshot.lua
-- Slingshot (M-map): the FUNCTIONAL travel menu. Lists the biomes (+ unlock state from the server); tap
-- an unlocked one -> the server validates + returns the landing point -> we fling THIS character on a
-- ballistic arc to it (Roblox owns the local character, so the launch is applied client-side). Locked
-- biomes are shown but refused. Client sends INTENT only; the server owns the unlock authority.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Notifications = require(script.Parent.Notifications)

local Slingshot = {}

local player, remotes = nil, nil
local gui, list = nil, nil
local order = 0

local function nextOrder()
    order += 1
    return order
end

local function clear()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

local function label(text, color, size)
    return Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, size or 24),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = text,
        TextColor3 = color or Theme.Colors.Text,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = list,
    })
end

local function rowButton(text, color, fn)
    Builder.glossButton({
        Size = UDim2.new(1, 0, 0, 44),
        color = color,
        Text = text,
        maxText = 18,
        LayoutOrder = nextOrder(),
        Parent = list,
    }, fn)
end

-- Fling the local character to `target` (Vector3) so it ARRIVES there in `flightTime` seconds. Standard
-- projectile solve: v = horizontalGap/T for X/Z, and v_y = dy/T + 0.5*g*T (g = Workspace.Gravity).
local function fling(target, flightTime)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root == nil then
        return false
    end
    local g = Workspace.Gravity
    local t = math.clamp(flightTime or 1.7, 0.5, 4)
    local p0 = root.Position
    local vy = (target.Y - p0.Y) / t + 0.5 * g * t
    local v = Vector3.new((target.X - p0.X) / t, vy, (target.Z - p0.Z) / t)
    -- a tiny upward nudge so the launch clears the slingshot frame, then apply the arc velocity.
    root.CFrame = root.CFrame + Vector3.new(0, 3, 0)
    root.AssemblyLinearVelocity = v
    return true
end

local function doLaunch(biomeId)
    local ok, result = pcall(function()
        return remotes.SlingshotAction:InvokeServer({ Action = "launch", BiomeId = biomeId })
    end)
    if not ok or type(result) ~= "table" then
        Notifications.show("error", "Slingshot jammed -- try again.")
        return
    end
    if result.Result ~= "Success" then
        Notifications.show("info", result.Message or "Can't launch there.")
        return
    end
    gui.Enabled = false
    if fling(result.Target, result.FlightTime) then
        Notifications.show("success", "Launching!")
    else
        Notifications.show("error", "Couldn't launch (no character).")
    end
end

function Slingshot.refresh()
    if gui == nil or not gui.Enabled then
        return
    end
    clear()
    order = 0
    label("Pick where to launch:", Theme.Colors.Gold, 28)
    local ok, result = pcall(function()
        return remotes.SlingshotAction:InvokeServer({ Action = "get" })
    end)
    local biomes = (ok and type(result) == "table") and result.Biomes or nil
    if biomes == nil then
        label("Couldn't load destinations.", Theme.Colors.Danger, 30)
        return
    end
    for _, b in ipairs(biomes) do
        if b.Unlocked then
            rowButton("🎯  " .. b.Name, Theme.Colors.Positive, function()
                doLaunch(b.BiomeId)
            end)
        else
            rowButton("🔒  " .. b.Name .. " (locked)", Theme.Colors.DarkPill, function()
                Notifications.show("info", "Unlock " .. b.Name .. " by walking through its gate first.")
            end)
        end
    end
end

function Slingshot.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Slingshot", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Slingshot", function()
        gui.Enabled = false
    end)
end

function Slingshot.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        Slingshot.refresh()
    end
end

return Slingshot
```

- [ ] **Step 3: Wire the client**

In `src/Client/Client.client.lua`:

(a) require it with the other UI modules (after `local Admin = require(UI.Admin)`):

```lua
local Slingshot = require(UI.Slingshot)
```

(b) add the remote to the `remotes` table (after `GroupAction = ...`):

```lua
    SlingshotAction = remotesFolder:WaitForChild("SlingshotAction"),
```

(c) safe-mount it (after the `Admin` safeMount):

```lua
safeMount("Slingshot", function()
    Slingshot.mount(context)
end)
```

(d) add a Menu button (in the `Menu` safeMount block, after the `🚩 Report` button):

```lua
    Menu.addButton("🎯 Slingshot", function()
        PanelManager.open("Slingshot")
    end)
```

(e) register the panel (in the `PanelManager registry` safeMount, after `PanelManager.register("Admin", Admin.toggleAdmin)`):

```lua
    PanelManager.register("Slingshot", Slingshot.toggle)
```

- [ ] **Step 4: Open the slingshot from its world pad (ProximityPrompt)**

Still in `Client.client.lua`, after the registry safeMount, add a block that puts an "Open Slingshot" prompt on the tagged `Slingshot` fixture and opens the panel when triggered:

```lua
-- The hub Slingshot fixture opens the launch menu (in addition to the Menu button).
do
    local CollectionService = game:GetService("CollectionService")
    local ProximityPromptService = game:GetService("ProximityPromptService")
    local function dressSlingshot(inst)
        if not inst:IsA("BasePart") or inst:FindFirstChild("SlingshotPrompt") then
            return
        end
        local prompt = Instance.new("ProximityPrompt")
        prompt.Name = "SlingshotPrompt"
        prompt.ActionText = "Launch"
        prompt.ObjectText = "Slingshot"
        prompt.HoldDuration = 0.2
        prompt.MaxActivationDistance = 16
        prompt.RequiresLineOfSight = false
        prompt.Parent = inst
    end
    for _, inst in ipairs(CollectionService:GetTagged("Slingshot")) do
        dressSlingshot(inst)
    end
    CollectionService:GetInstanceAddedSignal("Slingshot"):Connect(dressSlingshot)
    ProximityPromptService.PromptTriggered:Connect(function(prompt)
        if prompt.Name == "SlingshotPrompt" then
            PanelManager.open("Slingshot")
        end
    end)
end
```

- [ ] **Step 5: Run the standard verify.**

- [ ] **Step 6: Manual Studio check (2 things)**
  1. Open the menu via ≡ Menu → 🎯 Slingshot AND by walking to the hub slingshot pad and pressing the Launch prompt. The list shows all 6 biomes; only `Sunny Meadow` is tappable (unlocked); the rest show 🔒.
  2. Tap `Sunny Meadow` → you are flung on an arc and land in/near the meadow zone (not in the void, not through the floor). Tap a locked biome → a "unlock first" notice, no launch. (Tune `SlingshotConfig.FlightTime`/`LandingHeight` if you overshoot/undershoot or land too hard.)

- [ ] **Step 7: Commit**

```bash
git add src/Client/UI/Slingshot.lua src/Client/UI/Theme.lua src/Client/Client.client.lua
git commit -m "feat(slingshot): launch menu + ballistic fling + hub prompt"
```

---

## Task 9: Full integration verify + tuning pass

**Files:** none new (tuning only, in `WorldConfig.Radial`, `SlingshotConfig`, `Theme.Lighting`).

- [ ] **Step 1: Run the standard verify** one more time on the whole tree.

- [ ] **Step 2: Full playtest checklist (in Studio, ideally a 2-player Local Server)**
  - Spawn is on the central plaza; bases ring the middle; biomes spoke outward, farther by tier; lighting is not blown-out.
  - Walk a road out to `Sunny Meadow` → the biome label/banner shows on entry (proves the `BiomeVolume` tags still resolve at the new radial positions).
  - Buy a unit; it places on a pad. Steal/deposit between the two players still works (rotated plots safe).
  - Walk into a locked gate → solid; unlock it (earn/`/setcash` then hold the gate prompt) → it opens and you can pass (proves gates rebuilt with correct tags + collision).
  - Slingshot: launch to an unlocked biome → land there; locked → refused; spam the button → the 3s cooldown blocks it ("Reloading...").
  - Leaderboard pillars + NetShop/Premium/Daily/Gift/Spin fixtures are present on the plaza (tags intact).
  - F9 console: no service-start failures, no remote-surface drift, no `[Biomes] No 'BiomeVolume' volumes` warning.

- [ ] **Step 3: Tune to taste** — adjust `WorldConfig.Radial.BiomeRingStep` (spread biomes out/in), `PlotRingRadius` (base ring size), `SlingshotConfig.FlightTime`/`LandingHeight` (arc feel + landing accuracy), and `Theme.Lighting.Brightness` (final brightness). Re-verify + commit any tuning.

- [ ] **Step 4: Commit (if tuned)**

```bash
git add -A
git commit -m "chore(world): radial layout + slingshot tuning pass"
```

- [ ] **Step 5: Finish the branch** — Use **superpowers:finishing-a-development-branch** to review the full diff and merge/PR.

---

## Self-Review (against the request)

**1. Spec coverage**
- "Fix the map / bases in the middle" → Task 4 (central base ring) + Task 3 (hub/district at origin).
- "Biomes surround the middle and expand in a circle outward" → Task 2 (radial `Center` = angle 60°/tier + radius growing per tier) + Task 3 (renders spokes/gates/roads outward).
- "Travel further for outer rings → a slingshot instead of a teleporter" → Tasks 5-8 (config + server authority + menu + ballistic fling; explicitly NOT a teleport).
- "Looks really bad / washed out" → Task 1 (lighting de-blowout).
- UI restyle (Shop/tabs) → intentionally deferred to a separate plan per the agreed scope.

**2. Placeholder scan** — every code step shows the actual code (full new files for the 3 created files; exact old→new for edits). No TBD/TODO. The one soft spot (the sign-rotation reassignment in Task 3 Step 4) has an explicit documented fallback.

**3. Type/name consistency** — `WorldConfig.Radial.PlotRingRadius` (100) is duplicated as `PLOT_RING_RADIUS` in PlotService and used in WorldBuilder's `PlotAnchor` loop (all 100, called out as "must match"). Biome records expose `Tier`/`Angle`/`Radius`/`Center`, consumed consistently by WorldBuilder (`outwardDir`, `facingCenter`, gate/road math) and SlingshotService (`worldBiome.Center`, `.Tier`). `SlingshotAction` is declared/listed/created/assigned (Task 6) and consumed identically server (`SlingshotService`) + client (`remotes.SlingshotAction`). `Analytics.Events.SlingshotLaunch` is added (Task 7) before it's read. `BiomeService.IsUnlocked` is defined (Task 5) before SlingshotService calls it.

**Known cross-system note (not a blocker):** `LeaderboardBillboards.lua` builds its own stands at a hardcoded `FIRST_STAND = (80,0,-40)`, which now lands on the central plaza — still visible, just not auto-aligned with the new pillars. Repositioning those is cosmetic and out of this plan's scope.
