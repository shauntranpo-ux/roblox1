-- WorldConfig (VM6): THE single source of truth for the PROCEDURALLY-GENERATED voxel world. The
-- server-side WorldBuilder reads this to generate the hub, the base district, the six contiguous
-- biomes, the connecting roads, and the unlock gates -- all blocky/bright/kid-friendly -- then TAGS
-- everything per the contract so the already-written systems bind. NOTHING here is gameplay logic; it
-- is geometry/visual tuning + the tag/layout contract. Retune freely + regenerate. Validate defensively.
--
-- LAYOUT: the BASE DISTRICT sits at the world origin (PlotService builds plots along +X at z~0). The
-- HUB plaza sits just in front (-Z), covering the spots the existing systems already use (leaderboard
-- stands ~(80,-40), the boss default spawn (0,-140), the shared-event spawn (0,-110)). From the hub a
-- wide road runs -Z through the six biomes in a straight contiguous CORRIDOR (meadow nearest, void
-- farthest), each biome with a physical GATE at its entrance (the starter meadow is open). ONE
-- continuous walkable space -- NO portals.

local WorldConfig = {}

local function rgb(r, g, b)
    return Color3.fromRGB(r, g, b)
end

-- ── Palette (bright/glossy/kid-friendly; the reference hexes) ────────────────────────────────
WorldConfig.Palette = {
    Sky = rgb(41, 182, 246), -- #29B6F6
    Grass = rgb(139, 195, 74), -- #8BC34A
    Dirt = rgb(141, 110, 99), -- #8D6E63
    Sand = rgb(230, 198, 138), -- #E6C68A
    RedTrim = rgb(239, 83, 80), -- #EF5350 path trim
    Water = rgb(41, 182, 246), -- #29B6F6
    Foam = rgb(245, 250, 255),
    ShieldCyan = rgb(79, 195, 247), -- #4FC3F7
    ShieldRim = rgb(255, 255, 255),
    Gold = rgb(255, 193, 7), -- #FFC107
    HubStone = rgb(225, 232, 240),
    PlotBase = rgb(54, 58, 74),
    Wood = rgb(120, 85, 60),
}

-- ── Scale constants (avatar ~5-6 studs) ─────────────────────────────────────────────────────
WorldConfig.Scale = {
    Block = 4, -- terrain block size
    TreeHeight = 26, -- chunky cube tree
    PathWidth = 16, -- WIDE roads (boss-stampede crowds)
    GateWidth = 26, -- wide gates
    WallHeight = 22, -- gate barrier height
    GroundThickness = 6,
    BiomeVolumeHeight = 220, -- how tall the (invisible) zone-detection volume reaches
}

-- ── StreamingEnabled targets (tuned for a large but light world) ────────────────────────────
WorldConfig.Streaming = {
    Enabled = true,
    TargetRadius = 640, -- StreamingTargetRadius
    MinRadius = 320, -- StreamingMinRadius
    Pause = Enum.StreamingPauseMode.ClientPhysicsPause,
}

-- ── Asset id SWAP POINTS (bright defaults until supplied; the skybox lives in Theme.Assets) ──
WorldConfig.Assets = {
    TreeMeshId = 0, -- optional MeshPart tree (0 -> blocky cube tree)
    RockMeshId = 0, -- optional rock mesh (0 -> cube rock)
    HexShieldTextureId = 0, -- honeycomb shield texture (0 -> flat translucent cyan); also Theme.Assets
}

WorldConfig.Seed = 20260625 -- deterministic scatter (same config -> same world)

-- ── HUB (a big plaza in front of the base district; covers the existing fixture spots) ──────
WorldConfig.Hub = {
    Center = Vector3.new(160, 0, -150),
    Size = Vector3.new(440, 1, 260), -- x by z plaza footprint
    LandmarkHeight = 34, -- the central monument (NOT a portal)
    SparkleRate = 14, -- ambient hub sparkle particles (capped)
    RoadExitZ = -280, -- where the road leaves the hub toward the meadow
}

-- ── BASE DISTRICT (ground under the PlotService plots; plus PlotAnchor markers) ──────────────
-- PlotService builds Config.Plots.Count plots along +X at z=0; this just lays polished ground + the
-- contract's PlotAnchor markers under them (PlotService positions the plots itself).
WorldConfig.District = {
    Min = Vector3.new(-60, 0, -30),
    Max = Vector3.new(380, 0, 70),
    PlotAnchorZ = 0,
}

-- ── BIOME CORRIDOR (contiguous, escalating outward along -Z; meadow nearest) ────────────────
-- Each: Center (world), Size (x,y,z), the look, the gate (nil = open starter), and the spawn-area /
-- boss-arena anchor offsets (relative to Center). Style drives biome-specific props in WorldBuilder.
local function biome(id, name, centerZ, ground, accent, material, style, open)
    return {
        Id = id,
        Name = name,
        Center = Vector3.new(160, 0, centerZ),
        Size = Vector3.new(300, 1, 300),
        GroundColor = ground,
        Accent = accent,
        GroundMaterial = material,
        Style = style, -- "meadow"|"shores"|"swamp"|"magma"|"rift"|"void"
        Open = open == true, -- the starter meadow has no gate barrier
        TreeCount = 12,
        PropCount = 16,
        SpawnAreaOffset = Vector3.new(-70, 0, 0), -- left side = wild-spawn area
        BossArenaOffset = Vector3.new(70, 0, 0), -- right side = boss clearing
        GateInset = 150, -- the +Z entrance edge = Center.Z + Size.Z/2
    }
end

local P = WorldConfig.Palette
WorldConfig.Biomes = {
    biome(
        "sunny_meadow",
        "Sunny Meadow",
        -440,
        P.Grass,
        rgb(120, 210, 90),
        Enum.Material.Grass,
        "meadow",
        true
    ),
    biome(
        "sundae_shores",
        "Sundae Shores",
        -760,
        P.Sand,
        rgb(255, 150, 190),
        Enum.Material.Sand,
        "shores",
        false
    ),
    biome(
        "croco_swamp",
        "Croco Swamp",
        -1080,
        rgb(86, 120, 78),
        rgb(60, 95, 60),
        Enum.Material.Grass,
        "swamp",
        false
    ),
    biome(
        "magma_peak",
        "Magma Peak",
        -1400,
        rgb(54, 48, 58),
        rgb(255, 110, 20),
        Enum.Material.Slate,
        "magma",
        false
    ),
    biome(
        "cosmic_rift",
        "Cosmic Rift",
        -1720,
        rgb(96, 78, 170),
        rgb(120, 230, 255),
        Enum.Material.SmoothPlastic,
        "rift",
        false
    ),
    biome(
        "the_void",
        "The Void",
        -2040,
        rgb(46, 36, 86),
        rgb(90, 235, 255),
        Enum.Material.SmoothPlastic,
        "void",
        false
    ),
}

WorldConfig.ById = {}
for _, b in ipairs(WorldConfig.Biomes) do
    WorldConfig.ById[b.Id] = b
end

function WorldConfig.Get(id)
    return WorldConfig.ById[id]
end

-- ── PER-BIOME ATMOSPHERE (drives the existing Atmosphere.setZone hook on a biome crossing) ──
-- Shapes match Atmosphere.setZone: { Atmosphere = {<Atmosphere props>}, ColorCorrection = {<props>} }.
-- All BRIGHT/airy; even the Void is wondrous-glowy, never scary.
WorldConfig.Atmosphere = {
    sunny_meadow = {
        Atmosphere = { Density = 0.3, Haze = 1.2, Glare = 0.2, Color = rgb(235, 245, 255) },
        ColorCorrection = { Saturation = 0.15, Brightness = 0.02, TintColor = rgb(255, 255, 250) },
    },
    sundae_shores = {
        Atmosphere = { Density = 0.32, Haze = 1.6, Glare = 0.35, Color = rgb(255, 240, 245) },
        ColorCorrection = { Saturation = 0.2, Brightness = 0.03, TintColor = rgb(255, 246, 250) },
    },
    croco_swamp = {
        Atmosphere = { Density = 0.42, Haze = 2.2, Glare = 0.1, Color = rgb(210, 230, 205) },
        ColorCorrection = { Saturation = 0.1, Brightness = -0.01, TintColor = rgb(238, 250, 235) },
    },
    magma_peak = {
        Atmosphere = { Density = 0.4, Haze = 1.8, Glare = 0.5, Color = rgb(255, 225, 200) },
        ColorCorrection = { Saturation = 0.25, Brightness = 0.02, TintColor = rgb(255, 238, 225) },
    },
    cosmic_rift = {
        Atmosphere = { Density = 0.36, Haze = 1.4, Glare = 0.4, Color = rgb(225, 220, 255) },
        ColorCorrection = { Saturation = 0.3, Brightness = 0.03, TintColor = rgb(240, 235, 255) },
    },
    the_void = {
        Atmosphere = { Density = 0.45, Haze = 1.0, Glare = 0.6, Color = rgb(205, 215, 255) },
        ColorCorrection = { Saturation = 0.35, Brightness = 0.0, TintColor = rgb(225, 235, 255) },
    },
}

function WorldConfig.AtmosphereFor(id)
    return WorldConfig.Atmosphere[id]
end

return WorldConfig
