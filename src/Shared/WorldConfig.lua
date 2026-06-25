-- WorldConfig (VM6): THE single source of truth for the PROCEDURALLY-GENERATED voxel world. The
-- server-side WorldBuilder reads this to generate the hub, the base district, the six contiguous
-- biomes, the connecting roads, and the unlock gates -- all blocky/bright/kid-friendly -- then TAGS
-- everything per the contract so the already-written systems bind. NOTHING here is gameplay logic; it
-- is geometry/visual tuning + the tag/layout contract. Retune freely + regenerate. Validate defensively.
--
-- LAYOUT: Bases at the world origin; the six biomes are CONCENTRIC RINGS around them (meadow innermost,
-- void outermost), built as stacked discs; you progress outward through gates on one radial path.

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
    TargetRadius = 900, -- StreamingTargetRadius
    MinRadius = 450, -- StreamingMinRadius
    Pause = Enum.StreamingPauseMode.ClientPhysicsPause,
}

-- ── Asset id SWAP POINTS (bright defaults until supplied; the skybox lives in Theme.Assets) ──
WorldConfig.Assets = {
    TreeMeshId = 0, -- optional MeshPart tree (0 -> blocky cube tree)
    RockMeshId = 0, -- optional rock mesh (0 -> cube rock)
    HexShieldTextureId = 0, -- honeycomb shield texture (0 -> flat translucent cyan); also Theme.Assets
}

WorldConfig.Seed = 20260625 -- deterministic scatter (same config -> same world)

-- NEON FIX: true downgrades the old blanket-glow blocks (hub caps, biome scatter, lava/crystals) to
-- solid SmoothPlastic so nothing blinds; only a FEW `Glow` accents (shield rim, mystery block, gate
-- glow) stay neon. Flip to false to restore the old all-neon look.
WorldConfig.ReduceNeon = true

-- TERRAIN FIX: blocky ELEVATION + decoration per biome (capped for perf; same Seed -> same world). Tune
-- height/variation/density here. Hills are merged larger parts scattered AWAY from the flat spawn/arena.
WorldConfig.Terrain = {
    HillCount = 14, -- capped sculpted hills per biome (form + life without exploding part count)
    HillMinSize = 14,
    HillMaxSize = 34,
    HillMinHeight = 4,
    HillMaxHeight = 20, -- max mound height (stepped/gentle -> still walkable around)
    RockCount = 10, -- scattered blocky rocks per biome
    ClearRadius = 62, -- keep this radius around the biome center (spawn) + the arena FLAT
    ColorJitter = 14, -- +/- RGB jitter so surfaces aren't one dead-flat color
    PlotPadColor = rgb(70, 76, 96), -- the clean raised level platform under each base
    PlotPadInset = 8, -- the platform extends this far past the plot footprint (a clean margin)
}
-- ── STACKED-LEVEL LAYOUT (a vertical TOWER: bases on the bottom 'start' platform; each biome a floating
-- disc platform stacked ABOVE the previous with a big height gap; ride the ELEVATOR up to the next level.
-- Meadow = level 1 (ground), Void = the top. "+ add more if needed" = just add biomes; tiers auto-stack) ─
WorldConfig.Center = Vector3.new(0, 0, 0)
WorldConfig.Levels = {
    PlotRingRadius = 100, -- the central base RING on the bottom (start) platform (PlotService uses this)
    PlatformRadius = 160, -- each biome platform's radius (a floating disc)
    LevelHeight = 130, -- vertical gap between consecutive level platforms (lots of height between them)
    PlatformThickness = 8,
    ElevatorAngleDeg = 0, -- the angle (deg) on each platform where the elevator pad + drop-off sit
    ElevatorRadius = 80, -- how far from the platform center the elevator sits
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

-- Each biome is a floating LEVEL PLATFORM stacked vertically. `tier` (1 = the bottom 'start' level, the
-- meadow) sets its height Y. Y = (tier-1) x LevelHeight -> evenly spaced, lots of height between levels.
local function biome(id, name, tier, ground, accent, material, style, open)
    local L = WorldConfig.Levels
    return {
        Id = id,
        Name = name,
        Tier = tier,
        Y = (tier - 1) * L.LevelHeight, -- the platform's TOP surface height (level 1 = ground, y=0)
        Radius = L.PlatformRadius,
        GroundColor = ground,
        Accent = accent,
        GroundMaterial = material,
        Style = style,
        Open = open == true,
        TreeCount = 12,
        PropCount = 16,
    }
end

local P = WorldConfig.Palette
WorldConfig.Biomes = {
    biome(
        "sunny_meadow",
        "Sunny Meadow",
        1,
        P.Grass,
        rgb(120, 210, 90),
        Enum.Material.Grass,
        "meadow",
        true
    ),
    biome(
        "sundae_shores",
        "Sundae Shores",
        2,
        P.Sand,
        rgb(255, 150, 190),
        Enum.Material.Sand,
        "shores",
        false
    ),
    biome(
        "croco_swamp",
        "Croco Swamp",
        3,
        rgb(86, 120, 78),
        rgb(60, 95, 60),
        Enum.Material.Grass,
        "swamp",
        false
    ),
    biome(
        "magma_peak",
        "Magma Peak",
        4,
        rgb(54, 48, 58),
        rgb(255, 110, 20),
        Enum.Material.Slate,
        "magma",
        false
    ),
    biome(
        "cosmic_rift",
        "Cosmic Rift",
        5,
        rgb(96, 78, 170),
        rgb(120, 230, 255),
        Enum.Material.SmoothPlastic,
        "rift",
        false
    ),
    biome(
        "the_void",
        "The Void",
        6,
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

-- HEIGHT-BASED biome lookup: which stacked LEVEL a vertical height falls on (the platform you're on).
-- Below the bottom -> level 1; above the top -> the last biome.
function WorldConfig.LevelFor(y)
    local L = WorldConfig.Levels
    local idx = math.floor(y / L.LevelHeight + 0.5) + 1
    idx = math.clamp(idx, 1, #WorldConfig.Biomes)
    return WorldConfig.Biomes[idx].Id
end

-- Where the ELEVATOR drops the player onto a level platform (just off-center, at the elevator exit).
function WorldConfig.LevelLanding(id)
    local b = WorldConfig.Get(id)
    if b == nil then
        return WorldConfig.Center
    end
    local a = math.rad(WorldConfig.Levels.ElevatorAngleDeg)
    return Vector3.new(math.cos(a) * 36, b.Y + 6, math.sin(a) * 36)
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
