-- WorldBuilder (VM6): PROCEDURALLY GENERATES the entire voxel world IN CODE on server start -- a hub,
-- the base district + a polished plot TEMPLATE, six contiguous biomes, the connecting roads, and the
-- unlock gates -- all blocky/bright/kid-friendly, fully Anchored, low part count, and TAGGED per the
-- contract so the already-written systems bind. Idempotent (clears a dedicated World folder + the
-- template, then rebuilds deterministically -> no duplicates on restart). Sets StreamingEnabled.
-- Generates GEOMETRY + TAGS + the spawn only -- it changes NO gameplay/economy/security logic; the
-- existing systems read the world via the EXACT tag contract. (Lighting/sky/sparkles + the per-zone
-- atmosphere swap are owned by the client VM-THEME Atmosphere module + the M10.2 zone hook.)
--
-- ============================  SELF-AUDIT (world build)  =====================================
-- (a) EFFICIENT + ANCHORED + IDEMPOTENT: big merged slabs (one long road, one ground slab per region,
--     2-part cube trees) + capped scatter; everything Anchored; Init clears the "World" folder + the
--     ServerStorage template + any default Baseplate/Spawn, then rebuilds from a SEEDED RNG -> the same
--     config yields the same world and a restart never duplicates. StreamingEnabled ON + tuned.
-- (b) EXACT TAG CONTRACT: BiomeVolume(+Biome), BiomeGate(+TargetBiome the client reads, +Biome the
--     contract), SpawnPoint(+Biome), BossArena(+Biome), the PlotTemplate model (Pad1..PadN named for
--     PlotService + tagged Pad/PadIndex, ShieldWall, ShieldBarAnchor, NameplateAnchor, MysteryBlock),
--     PlotAnchor markers, and the hub fixtures (NetShop/PremiumShop/DailyChest/FreeGift/SpinWheel/
--     LeaderboardPillar). Built before PlotService.Init so it clones the template.
-- (c) NO GAMEPLAY CHANGE: only Instances + tags + StreamingEnabled + a SpawnLocation. Reads WorldConfig
--     (biome ids/layout/palette) + Config.Plots only, to place + name geometry correctly.
-- (d) ONE CONTINUOUS WALKABLE WORLD, NO PORTALS: a straight road connects hub -> meadow -> ... -> void;
--     gates are physical CanCollide barriers (M10.2 opens them per-player on unlock). Flush roads.
-- (e) GRACEFUL: missing mesh/texture ids -> bright cube defaults; absent tag-reading systems -> the
--     tagged world is still correct and binds when they run. No GUIs leak (cleared with the folder).
-- (f) BRIGHT/KID-FRIENDLY incl. a wondrous (never scary) Void.
-- ===========================================================================================

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Config = require(ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

local P = WorldConfig.Palette
local S = WorldConfig.Scale
local WORLD_FOLDER = "World"

local rng = Random.new(WorldConfig.Seed)
local worldFolder = nil

-- ── Core part helper (Anchored, smooth, low-overhead) ───────────────────────────────────────
local function part(props, parent)
    local p = Instance.new("Part")
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Size = props.Size
    p.Color = props.Color or Color3.fromRGB(235, 235, 235)
    -- NEON FIX: `Glow` is a FEW intentional accents that always glow; `Neon` is the old blanket glow that
    -- WorldConfig.ReduceNeon downgrades to solid SmoothPlastic (kept bright via the color, just not blinding).
    local glow = props.Glow == true or (props.Neon == true and not WorldConfig.ReduceNeon)
    p.Material = glow and Enum.Material.Neon or (props.Material or Enum.Material.SmoothPlastic)
    p.CFrame = props.CFrame or CFrame.new(props.Position or Vector3.zero)
    if props.Transparency ~= nil then
        p.Transparency = props.Transparency
    end
    if props.CanCollide ~= nil then
        p.CanCollide = props.CanCollide
    end
    if props.Shape ~= nil then
        p.Shape = props.Shape
    end
    p.Parent = parent or worldFolder
    return p
end

local function tag(instance, name)
    CollectionService:AddTag(instance, name)
end

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

-- A blocky 2-part cube tree (trunk + leaf cube). Capped by the caller.
local function tree(parent, pos, trunkColor, leafColor)
    local trunkH = S.TreeHeight * 0.45
    part({
        Size = Vector3.new(4, trunkH, 4),
        Position = pos + Vector3.new(0, trunkH / 2, 0),
        Color = trunkColor or P.Wood,
        Material = Enum.Material.Wood,
    }, parent)
    local leaf = S.TreeHeight * 0.6
    part({
        Size = Vector3.new(leaf, leaf, leaf),
        Position = pos + Vector3.new(0, trunkH + leaf / 2 - 2, 0),
        Color = leafColor or P.Grass,
        Material = Enum.Material.Grass,
    }, parent)
end

-- A Fredoka-One world sign (white fill + black stroke + soft shadow) on a posted board.
local function worldSign(parent, pos, text, boardColor)
    part({
        Size = Vector3.new(2, 12, 2),
        Position = pos + Vector3.new(0, 6, 0),
        Color = P.Wood,
        Material = Enum.Material.Wood,
    }, parent)
    local board = part({
        Size = Vector3.new(22, 9, 1),
        Position = pos + Vector3.new(0, 16, 0),
        Color = boardColor or P.RedTrim,
    }, parent)
    local sg = Instance.new("SurfaceGui")
    sg.Name = "Sign"
    sg.Face = Enum.NormalId.Front
    sg.CanvasSize = Vector2.new(440, 180)
    sg.Adornee = board
    sg.Parent = board
    local shadow = Instance.new("TextLabel")
    shadow.Size = UDim2.fromScale(1, 1)
    shadow.Position = UDim2.fromOffset(4, 4)
    shadow.BackgroundTransparency = 1
    shadow.Font = Enum.Font.FredokaOne
    shadow.Text = text
    shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
    shadow.TextTransparency = 0.5
    shadow.TextScaled = true
    shadow.Parent = sg
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.FredokaOne
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0
    label.TextScaled = true
    label.Parent = sg
    return board
end

-- A tagged hub fixture block (stall/chest/etc.) with a name sign.
local function fixture(parent, pos, size, color, tagName, label, neon)
    local block = part({
        Size = size,
        Position = pos + Vector3.new(0, size.Y / 2, 0),
        Color = color,
        Neon = neon,
    }, parent)
    block.Name = tagName
    tag(block, tagName)
    if label ~= nil then
        worldSign(parent, pos, label, color)
    end
    return block
end

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
    part(
        { Size = Vector3.new(20, 4, 20), Position = c + Vector3.new(0, 2, -70), Color = P.HubStone },
        folder
    )
    part(
        { Size = Vector3.new(14, 10, 14), Position = c + Vector3.new(0, 9, -70), Color = P.Sand },
        folder
    )
    part(
        { Size = Vector3.new(8, 12, 8), Position = c + Vector3.new(0, 20, -70), Color = P.RedTrim },
        folder
    )
    part({
        Size = Vector3.new(5, 5, 5),
        Position = c + Vector3.new(0, 29, -70),
        Color = P.Gold,
        Neon = true,
    }, folder)

    -- SLINGSHOT launch pad (tagged; the client's Slingshot menu + the prompt live on this).
    local slingPos = c + WorldConfig.Slingshot.Position
    local base =
        fixture(folder, slingPos, Vector3.new(12, 4, 12), P.ShieldCyan, "Slingshot", "SLINGSHOT")
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(2, 16, 2),
            Position = slingPos + Vector3.new(sx * 4, 12, 0),
            Color = P.Wood,
            Material = Enum.Material.Wood,
        }, folder)
    end
    part({
        Size = Vector3.new(12, 1.5, 1.5),
        Position = slingPos + Vector3.new(0, 20, 0),
        Color = P.Gold,
        Neon = true,
    }, folder)
    base:SetAttribute("LaunchHeight", 24)

    -- shop stalls + free-reward blocks (tagged fixtures), arranged around the plaza.
    fixture(
        folder,
        c + Vector3.new(-90, 0, -40),
        Vector3.new(14, 12, 10),
        P.Grass,
        "NetShop",
        "NET SHOP"
    )
    fixture(
        folder,
        c + Vector3.new(90, 0, -40),
        Vector3.new(14, 12, 10),
        P.Gold,
        "PremiumShop",
        "PREMIUM",
        true
    )
    fixture(
        folder,
        c + Vector3.new(-130, 0, 30),
        Vector3.new(8, 8, 8),
        P.RedTrim,
        "DailyChest",
        "DAILY"
    )
    fixture(
        folder,
        c + Vector3.new(-110, 0, 50),
        Vector3.new(8, 8, 8),
        P.ShieldCyan,
        "FreeGift",
        "GIFT"
    )
    fixture(
        folder,
        c + Vector3.new(130, 0, 30),
        Vector3.new(10, 10, 10),
        P.Gold,
        "SpinWheel",
        "SPIN",
        true
    )

    local boards = { "TopCash", "TopIncome", "RarestCollection" }
    for i, key in ipairs(boards) do
        local pillar = fixture(
            folder,
            c + Vector3.new(-44 + (i - 1) * 44, 0, -110),
            Vector3.new(8, 16, 8),
            P.PlotBase,
            "LeaderboardPillar",
            nil
        )
        pillar:SetAttribute("Board", key)
    end
end

-- ── BASE DISTRICT (central ground slab + PlotAnchor markers on the base RING) ─────────────────
local function buildDistrict(folder)
    local d = WorldConfig.District
    part({
        Size = Vector3.new(d.GroundSize.X, S.GroundThickness, d.GroundSize.Z),
        Position = Vector3.new(0, -S.GroundThickness / 2, 0),
        Color = P.Grass,
        Material = Enum.Material.Grass,
    }, folder)

    local ringR = WorldConfig.Radial.PlotRingRadius
    local T = WorldConfig.Terrain
    for index = 1, Config.Plots.Count do
        local angle = math.rad((index - 1) * (360 / Config.Plots.Count))
        local pos = Vector3.new(math.cos(angle) * ringR, 0, math.sin(angle) * ringR)
        -- PLOT FIX: a clean, raised, LEVEL platform under each base (sized to the 40x30 plot + a margin,
        -- rotated to face center like the plot) so every base reads as its own distinct, separated pad.
        part({
            Size = Vector3.new(40 + T.PlotPadInset * 2, 3, 30 + T.PlotPadInset * 2),
            CFrame = CFrame.lookAt(pos + Vector3.new(0, -1, 0), Vector3.new(0, -1, 0)),
            Color = T.PlotPadColor,
        }, folder)
        local anchor = part({
            Size = Vector3.new(2, 1, 2),
            Position = pos + Vector3.new(0, 0.5, 0),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        anchor.Name = "PlotAnchor" .. index
        tag(anchor, "PlotAnchor")
        anchor:SetAttribute("PlotIndex", index)
    end
end

-- ── PLOT TEMPLATE -> ServerStorage/Assets (PlotService clones it; reads Pad1..PadN by name) ──
local function buildPlotTemplate()
    local assets = ServerStorage:FindFirstChild("Assets")
    if assets == nil then
        assets = Instance.new("Folder")
        assets.Name = "Assets"
        assets.Parent = ServerStorage
    end
    local existing = assets:FindFirstChild(Config.Plots.TemplateName)
    if existing ~= nil then
        existing:Destroy() -- idempotent: never stack duplicate templates
    end

    local model = Instance.new("Model")
    model.Name = Config.Plots.TemplateName -- "PlotTemplate"
    tag(model, "PlotTemplate")

    -- dark tiered platform (PrimaryPart = Base, so PlotService:PivotTo positions it cleanly)
    local base = part(
        { Size = Vector3.new(40, 2, 30), Position = Vector3.new(0, 0, 0), Color = P.PlotBase },
        model
    )
    base.Name = "Base"
    model.PrimaryPart = base
    part({
        Size = Vector3.new(46, 1, 36),
        Position = Vector3.new(0, -1.5, 0),
        Color = Color3.fromRGB(38, 41, 54),
    }, model)

    local padCount = Config.Plots.PadsPerPlot
    local spacing = Config.Plots.PadSpacing
    local function makePad(i, expansion)
        local x = (i - (padCount + 1) / 2) * spacing
        local pad = part({
            Size = Vector3.new(6, 1, 6),
            Position = Vector3.new(x, 1.5, -3),
            Color = expansion and Color3.fromRGB(90, 96, 110) or P.Grass,
            Transparency = expansion and 0.45 or 0,
        }, model)
        pad.Name = "Pad" .. i
        tag(pad, "Pad")
        pad:SetAttribute("PadIndex", i)
        if expansion then
            pad:SetAttribute("Expansion", true)
        end
    end
    for i = 1, padCount do
        makePad(i, false)
    end
    for i = padCount + 1, padCount + 2 do
        makePad(i, true) -- hidden expansion pads (ready if PadsPerPlot grows later)
    end

    -- translucent cyan SHIELD WALL (hex look + glowing rim) at the front; ShieldWall.lua dresses it
    local wall = part({
        Size = Vector3.new(46, 18, 1),
        Position = Vector3.new(0, 8, 9),
        Color = P.ShieldCyan,
        Material = Enum.Material.Glass,
        Transparency = 0.55,
        CanCollide = false,
    }, model)
    wall.Name = "ShieldWall"
    tag(wall, "ShieldWall")
    part({
        Size = Vector3.new(46, 1, 1.2),
        Position = Vector3.new(0, 17, 9),
        Color = P.ShieldRim,
        Glow = true, -- intentional accent: the shield-wall rim stays a subtle glow
        CanCollide = false,
    }, model)

    local barAnchor = part({
        Size = Vector3.new(1, 1, 1),
        Position = Vector3.new(0, 20, 9),
        Transparency = 1,
        CanCollide = false,
    }, model)
    barAnchor.Name = "ShieldBarAnchor"
    tag(barAnchor, "ShieldBarAnchor")

    local nameAnchor = part({
        Size = Vector3.new(1, 1, 1),
        Position = Vector3.new(0, 24, 0),
        Transparency = 1,
        CanCollide = false,
    }, model)
    nameAnchor.Name = "NameplateAnchor"
    tag(nameAnchor, "NameplateAnchor")

    local mystery = part({
        Size = Vector3.new(5, 5, 5),
        Position = Vector3.new(16, 3, -3),
        Color = P.Gold,
        Glow = true, -- intentional accent: the mystery reward block stays a subtle glow
    }, model)
    mystery.Name = "MysteryBlock"
    tag(mystery, "MysteryBlock")

    model.Parent = assets
end

-- ── BIOME-SPECIFIC props (capped; bright, kid-friendly) ─────────────────────────────────────
local function emitter(host, color, rate, size)
    local pe = Instance.new("ParticleEmitter")
    pe.Color = ColorSequence.new(color)
    pe.Rate = rate
    pe.Lifetime = NumberRange.new(2, 4)
    pe.Speed = NumberRange.new(1, 3)
    pe.Size = NumberSequence.new(size or 0.6)
    pe.Transparency = NumberSequence.new(0.3)
    pe.LightEmission = 1
    pe.Parent = host
end

local function biomeProps(folder, cfg)
    local c = cfg.Center
    local half = cfg.Size.X / 2
    local function scatterPos()
        return c
            + Vector3.new(
                rng:NextNumber(-half + 20, half - 20),
                0,
                rng:NextNumber(-half + 20, half - 20)
            )
    end
    -- cube trees (capped)
    for _ = 1, cfg.TreeCount do
        tree(folder, scatterPos(), P.Wood, cfg.Accent)
    end
    local style = cfg.Style
    if style == "meadow" then
        part({
            Size = Vector3.new(14, 1, cfg.Size.Z - 40),
            Position = c + Vector3.new(-110, 0.1, 0),
            Color = P.Water,
            Transparency = 0.2,
        }, folder) -- stream
        for _ = 1, cfg.PropCount do
            local pos = scatterPos()
            part({
                Size = Vector3.new(2, 2, 2),
                Position = pos + Vector3.new(0, 1, 0),
                Color = (rng:NextNumber() > 0.5) and P.Gold or P.RedTrim,
                Neon = true,
            }, folder)
        end
    elseif style == "shores" then
        part({
            Size = Vector3.new(cfg.Size.X, 1, 80),
            Position = c + Vector3.new(0, 0.1, -110),
            Color = P.Water,
            Transparency = 0.15,
        }, folder) -- sea
        part({
            Size = Vector3.new(30, 1, 60),
            Position = c + Vector3.new(0, 1, -70),
            Color = P.Wood,
            Material = Enum.Material.Wood,
        }, folder) -- dock
        for i = -1, 1 do
            part({
                Size = Vector3.new(8, 1, 8),
                Position = c + Vector3.new(i * 40, 6, 40),
                Color = (i == 0) and P.RedTrim or P.ShieldCyan,
                Material = Enum.Material.SmoothPlastic,
            }, folder) -- umbrella tops
            part({
                Size = Vector3.new(1, 12, 1),
                Position = c + Vector3.new(i * 40, 1, 40),
                Color = P.Foam,
            }, folder)
        end
    elseif style == "swamp" then
        part({
            Size = Vector3.new(cfg.Size.X - 30, 1, cfg.Size.Z - 30),
            Position = c + Vector3.new(0, 0.2, 0),
            Color = Color3.fromRGB(60, 95, 70),
            Transparency = 0.25,
        }, folder) -- murky water film
        for _ = 1, cfg.PropCount do
            local pos = scatterPos()
            part({
                Size = Vector3.new(6, 0.4, 6),
                Position = pos + Vector3.new(0, 1, 0),
                Color = Color3.fromRGB(70, 130, 70),
            }, folder) -- lily pad
        end
        local motes = part({
            Size = Vector3.new(2, 2, 2),
            Position = c + Vector3.new(0, 8, 0),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        emitter(motes, Color3.fromRGB(180, 255, 120), 12) -- fireflies
    elseif style == "magma" then
        for _ = 1, cfg.PropCount do
            local pos = scatterPos()
            part({
                Size = Vector3.new(rng:NextNumber(8, 18), 0.6, rng:NextNumber(8, 18)),
                Position = pos + Vector3.new(0, 0.4, 0),
                Color = cfg.Accent,
                Neon = true,
            }, folder) -- lava pool
        end
        -- crater ring
        for a = 0, 5 do
            local ang = a / 6 * math.pi * 2
            part({
                Size = Vector3.new(10, 8, 10),
                Position = c + Vector3.new(math.cos(ang) * 40, 4, math.sin(ang) * 40),
                Color = Color3.fromRGB(40, 36, 44),
            }, folder)
        end
        local embers = part({
            Size = Vector3.new(2, 2, 2),
            Position = c + Vector3.new(0, 10, 0),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        emitter(embers, Color3.fromRGB(255, 140, 40), 16)
    elseif style == "rift" then
        for _ = 1, cfg.PropCount do
            local pos = scatterPos()
            part({
                Size = Vector3.new(rng:NextNumber(10, 20), 4, rng:NextNumber(10, 20)),
                Position = pos + Vector3.new(0, rng:NextNumber(10, 28), 0),
                Color = cfg.GroundColor,
                CanCollide = true,
            }, folder) -- floating cube island
            part({
                Size = Vector3.new(3, 10, 3),
                Position = pos + Vector3.new(0, 6, 0),
                Color = cfg.Accent,
                Neon = true,
                Shape = Enum.PartType.Block,
            }, folder) -- crystal
        end
    elseif style == "void" then
        for _ = 1, cfg.PropCount do
            local pos = scatterPos()
            part({
                Size = Vector3.new(
                    rng:NextNumber(3, 6),
                    rng:NextNumber(18, 34),
                    rng:NextNumber(3, 6)
                ),
                Position = pos + Vector3.new(0, 14, 0),
                Color = cfg.Accent,
                Neon = true,
            }, folder) -- glowing monolith
        end
        local glow = part({
            Size = Vector3.new(2, 2, 2),
            Position = c + Vector3.new(0, 16, 0),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        emitter(glow, Color3.fromRGB(120, 235, 255), 18, 1.2)
    end
end

-- ── TERRAIN: blocky ELEVATION + rocks per biome (Problem 1 fix) ──────────────────────────────
-- Slightly jitters an RGB color so big surfaces aren't one dead-flat shade.
local function jitterColor(base, amount)
    local function j(v)
        return math.clamp(v * 255 + rng:NextInteger(-amount, amount), 0, 255)
    end
    return Color3.fromRGB(j(base.R), j(base.G), j(base.B))
end

-- Scatters capped sculpted HILLS (stepped/tiered larger blocks) + rocks across a biome, kept AWAY from
-- the flat spawn center + the boss arena + the inner gate entrance (those stay open + walkable). Voxel,
-- efficient (a bounded number of larger parts), deterministic (seeded). Gives the land form + life.
local function terrainFeatures(folder, cfg)
    local T = WorldConfig.Terrain
    local c = cfg.Center
    local half = cfg.Size.X / 2
    local arena = c + cfg.BossArenaOffset
    local spawnArea = c + cfg.SpawnAreaOffset
    local outward = outwardDir(c)
    local function placeable(pos)
        return (pos - c).Magnitude > T.ClearRadius -- keep the spawn center flat
            and (pos - arena).Magnitude > 46 -- keep the boss arena open
            and (pos - spawnArea).Magnitude > 40 -- keep the wild-spawn area flat
            and (pos - c):Dot(outward) > -12 -- bias outward so the inner gate entrance stays clear
    end
    local function scatterPos(margin)
        return c
            + Vector3.new(
                rng:NextNumber(-half + margin, half - margin),
                0,
                rng:NextNumber(-half + margin, half - margin)
            )
    end
    for _ = 1, T.HillCount do
        local pos = scatterPos(16)
        if placeable(pos) then
            local w = rng:NextNumber(T.HillMinSize, T.HillMaxSize)
            local d = rng:NextNumber(T.HillMinSize, T.HillMaxSize)
            local h = rng:NextNumber(T.HillMinHeight, T.HillMaxHeight)
            part({
                Size = Vector3.new(w, h, d),
                Position = pos + Vector3.new(0, h / 2 - 1, 0),
                Color = jitterColor(cfg.GroundColor, T.ColorJitter),
                Material = cfg.GroundMaterial,
            }, folder)
            if h > 11 then -- a stacked smaller cap -> a stepped/tiered mound (still walkable around)
                part({
                    Size = Vector3.new(w * 0.6, h * 0.5, d * 0.6),
                    Position = pos + Vector3.new(0, h - 1, 0),
                    Color = jitterColor(cfg.GroundColor, T.ColorJitter),
                    Material = cfg.GroundMaterial,
                }, folder)
            end
        end
    end
    for _ = 1, T.RockCount do
        local pos = scatterPos(12)
        if placeable(pos) then
            local s = rng:NextNumber(3, 8)
            part({
                Size = Vector3.new(s, s * 0.8, s),
                Position = pos + Vector3.new(0, s * 0.4, 0),
                Color = jitterColor(P.Dirt, T.ColorJitter),
            }, folder)
        end
    end
end

-- ── ONE BIOME (ground + invisible zone VOLUME + spawn points + boss arena + sign + props) ───
local function buildBiome(folder, cfg)
    local c = cfg.Center
    -- ground slab (top at y=0)
    part({
        Size = Vector3.new(cfg.Size.X, S.GroundThickness, cfg.Size.Z),
        Position = c + Vector3.new(0, -S.GroundThickness / 2, 0),
        Color = cfg.GroundColor,
        Material = cfg.GroundMaterial,
    }, folder)

    -- invisible BiomeVolume (the M10.2 zone-detection box; reaches high)
    local volume = part({
        Size = Vector3.new(cfg.Size.X, S.BiomeVolumeHeight, cfg.Size.Z),
        Position = c + Vector3.new(0, S.BiomeVolumeHeight / 2 - 2, 0),
        Transparency = 1,
        CanCollide = false,
    }, folder)
    volume.Name = "BiomeVolume_" .. cfg.Id
    tag(volume, "BiomeVolume")
    volume:SetAttribute("Biome", cfg.Id)

    -- wild SpawnPoint markers (a few, in the spawn area)
    for i = -1, 1 do
        local sp = part({
            Size = Vector3.new(2, 1, 2),
            Position = c + cfg.SpawnAreaOffset + Vector3.new(i * 20, 1, 0),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        sp.Name = "SpawnPoint_" .. cfg.Id .. "_" .. (i + 2)
        tag(sp, "SpawnPoint")
        sp:SetAttribute("Biome", cfg.Id)
    end

    -- BossArena clearing + tagged center
    local arenaPos = c + cfg.BossArenaOffset
    part({
        Size = Vector3.new(70, 1, 70),
        Position = arenaPos + Vector3.new(0, 0.15, 0),
        Color = cfg.GroundColor:Lerp(P.Sand, 0.4),
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

    -- biome name sign on the spoke, just inside the gate (toward the center).
    local signPos = outwardDir(cfg.Center) * (cfg.Radius - cfg.Size.Z / 2 - 24)
    worldSign(folder, signPos, string.upper(cfg.Name), cfg.Accent)

    terrainFeatures(folder, cfg) -- Problem 1: blocky elevation + rocks (keeps spawn/arena/entrance clear)
    biomeProps(folder, cfg)
end

-- ── GATES (a center-facing barrier at each non-starter biome's inner edge) ────────────────────
local function buildGate(folder, cfg)
    if cfg.Open then
        return
    end
    local dir = outwardDir(cfg.Center)
    local entrance = dir * (cfg.Radius - cfg.Size.Z / 2)
    local w, h = S.GateWidth, S.WallHeight
    local cf = facingCenter(entrance, h / 2)

    local wingW = (cfg.Size.X - w) / 2
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(wingW, h, 4),
            CFrame = cf * CFrame.new(sx * (w / 2 + wingW / 2), 0, 0),
            Color = P.Dirt,
        }, folder)
    end

    local barrier = part({ Size = Vector3.new(w, h, 4), CFrame = cf, Color = P.RedTrim }, folder)
    barrier.Name = "Gate_" .. cfg.Id
    tag(barrier, "BiomeGate")
    barrier:SetAttribute("TargetBiome", cfg.Id)
    barrier:SetAttribute("Biome", cfg.Id)

    part({
        Size = Vector3.new(w + 4, 2, 5),
        CFrame = cf * CFrame.new(0, h / 2 + 1, 0),
        Color = P.Gold,
        Glow = true, -- intentional accent: a subtle gate glow
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

-- ── ROADS (a spoke from the central plaza out to each biome's inner edge) ─────────────────────
local function buildRoads(folder)
    local hubR = WorldConfig.Radial.HubRadius
    for _, cfg in ipairs(WorldConfig.Biomes) do
        local dir = outwardDir(cfg.Center)
        local innerDist = cfg.Radius - cfg.Size.Z / 2
        local length = innerDist - hubR
        if length > 0 then
            local mid = dir * (hubR + length / 2)
            local cf = facingCenter(mid, 0.1)
            part(
                { Size = Vector3.new(S.PathWidth + 8, 0.6, length), CFrame = cf, Color = P.Sand },
                folder
            )
            for _, sx in ipairs({ -1, 1 }) do
                part({
                    Size = Vector3.new(2, 0.8, length),
                    CFrame = cf * CFrame.new(sx * (S.PathWidth / 2 + 5), 0.1, 0),
                    Color = P.RedTrim,
                }, folder)
            end
        end
    end
end

-- ── Floating grass-cube ISLANDS (distant skyline dressing) ──────────────────────────────────
local function buildIslands(folder)
    for _ = 1, 12 do
        local pos = Vector3.new(
            rng:NextNumber(-400, 720),
            rng:NextNumber(120, 230),
            rng:NextNumber(-2200, 200)
        )
        local s = rng:NextNumber(20, 32)
        part({
            Size = Vector3.new(s, s * 0.5, s),
            Position = pos,
            Color = P.Grass,
            Material = Enum.Material.Grass,
            CanCollide = false,
        }, folder)
        part({
            Size = Vector3.new(s * 0.8, s * 0.4, s * 0.8),
            Position = pos - Vector3.new(0, s * 0.4, 0),
            Color = P.Dirt,
            CanCollide = false,
        }, folder)
    end
end

-- ── Streaming ───────────────────────────────────────────────────────────────────────────────
local function configureStreaming()
    local st = WorldConfig.Streaming
    pcall(function()
        Workspace.StreamingEnabled = st.Enabled
        Workspace.StreamingTargetRadius = st.TargetRadius
        Workspace.StreamingMinRadius = st.MinRadius
        Workspace.StreamingPauseMode = st.Pause
    end)
end

-- Remove any default Studio Baseplate/Spawn so our generated ground is the floor.
local function clearDefaults()
    for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
        local existing = Workspace:FindFirstChild(name)
        if existing ~= nil then
            existing:Destroy()
        end
    end
end

function WorldBuilder.Init()
    -- IDEMPOTENT: clear the world folder (+ the template is cleared in buildPlotTemplate) then rebuild.
    local old = Workspace:FindFirstChild(WORLD_FOLDER)
    if old ~= nil then
        old:Destroy()
    end
    clearDefaults()
    rng = Random.new(WorldConfig.Seed) -- reset -> deterministic

    worldFolder = Instance.new("Folder")
    worldFolder.Name = WORLD_FOLDER
    worldFolder.Parent = Workspace

    configureStreaming()
    buildPlotTemplate() -- into ServerStorage/Assets BEFORE PlotService.Init clones it
    buildDistrict(worldFolder)
    buildHub(worldFolder)
    buildRoads(worldFolder)
    for _, cfg in ipairs(WorldConfig.Biomes) do
        buildBiome(worldFolder, cfg)
        buildGate(worldFolder, cfg)
    end
    buildIslands(worldFolder)
end

return WorldBuilder
