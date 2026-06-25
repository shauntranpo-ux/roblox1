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

-- A flat circular DISC (a Cylinder rotated so its round faces point up/down) -- ONE part per level
-- platform. `r` = radius, `topY` = the walking surface height, `thickness` = how deep it goes down.
local function disc(r, topY, thickness, color, material, parent)
    local d = part({
        Size = Vector3.new(thickness, r * 2, r * 2),
        Color = color,
        Material = material or Enum.Material.SmoothPlastic,
        CFrame = CFrame.new(0, topY - thickness / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
    }, parent)
    d.Shape = Enum.PartType.Cylinder
    return d
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

-- A real elevator CAR (floor + 3 walls + roof + corner posts + a glowing call panel) at a platform's edge.
-- The call panel carries the "Slingshot" tag so the existing prompt/menu binds to it. `y` = platform top.
local function buildElevatorCar(folder, y)
    local a = math.rad(WorldConfig.Levels.ElevatorAngleDeg)
    local r = WorldConfig.Levels.ElevatorRadius
    local center = Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
    local cf = CFrame.lookAt(center, WorldConfig.Center + Vector3.new(0, y, 0)) -- car faces the platform center
    part(
        { Size = Vector3.new(14, 1, 14), CFrame = cf * CFrame.new(0, 0.5, 0), Color = P.HubStone },
        folder
    )
    part({
        Size = Vector3.new(14, 16, 1),
        CFrame = cf * CFrame.new(0, 8, -6.5),
        Color = P.ShieldCyan,
    }, folder)
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(1, 16, 14),
            CFrame = cf * CFrame.new(sx * 6.5, 8, 0),
            Color = P.HubStone,
        }, folder)
    end
    part(
        { Size = Vector3.new(15, 1, 15), CFrame = cf * CFrame.new(0, 16.5, 0), Color = P.HubStone },
        folder
    )
    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            part({
                Size = Vector3.new(1.5, 17, 1.5),
                CFrame = cf * CFrame.new(sx * 7, 8.5, sz * 7),
                Color = P.Gold,
            }, folder)
        end
    end
    local panel = fixture(
        folder,
        (cf * CFrame.new(0, 0, -6)).Position,
        Vector3.new(4, 6, 1),
        P.Gold,
        "Slingshot",
        "ELEVATOR"
    )
    panel:SetAttribute("LaunchHeight", 26)
    part({
        Size = Vector3.new(4, 6, 0.4),
        CFrame = cf * CFrame.new(0, 9, -6.2),
        Color = P.ShieldCyan,
        Glow = true,
    }, folder)
    return panel
end

-- A vertical SHAFT track (thin glowing rails) running the full stack height at the elevator spot.
local function buildElevatorShaft(folder)
    local a = math.rad(WorldConfig.Levels.ElevatorAngleDeg)
    local r = WorldConfig.Levels.ElevatorRadius
    local topY = WorldConfig.Biomes[#WorldConfig.Biomes].Y
    local pos = Vector3.new(math.cos(a) * r, topY / 2, math.sin(a) * r)
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(1, topY + 20, 1),
            Position = pos + Vector3.new(0, 0, sx * 8),
            Color = P.HubStone,
        }, folder)
    end
end

-- A modeled hub STRUCTURE for a tagged interactable. Builds a unique look per `tagName`, tags the base
-- block with `tagName` (the contract), floats a label, and returns the tagged block.
local function buildStructure(folder, pos, tagName, label, accent)
    local base = part(
        { Size = Vector3.new(12, 4, 12), Position = pos + Vector3.new(0, 2, 0), Color = P.HubStone },
        folder
    )
    base.Name = tagName
    tag(base, tagName)
    if tagName == "FreeGift" then
        part(
            { Size = Vector3.new(8, 8, 8), Position = pos + Vector3.new(0, 8, 0), Color = accent },
            folder
        )
        part({
            Size = Vector3.new(8.4, 1.6, 1.6),
            Position = pos + Vector3.new(0, 8, 0),
            Color = P.Gold,
            Glow = true,
        }, folder)
        part({
            Size = Vector3.new(1.6, 1.6, 8.4),
            Position = pos + Vector3.new(0, 8, 0),
            Color = P.Gold,
            Glow = true,
        }, folder)
        part({
            Size = Vector3.new(3, 3, 3),
            Position = pos + Vector3.new(0, 12.5, 0),
            Color = P.Gold,
            Glow = true,
        }, folder)
    elseif tagName == "DailyChest" then
        part({
            Size = Vector3.new(9, 5, 6),
            Position = pos + Vector3.new(0, 6.5, 0),
            Color = P.Wood,
            Material = Enum.Material.Wood,
        }, folder)
        part(
            { Size = Vector3.new(9, 3, 6), Position = pos + Vector3.new(0, 10, 0), Color = accent },
            folder
        )
        part({
            Size = Vector3.new(1.5, 3, 1.5),
            Position = pos + Vector3.new(0, 8.5, 3),
            Color = P.Gold,
            Glow = true,
        }, folder)
    elseif tagName == "SpinWheel" then
        part({
            Size = Vector3.new(1.5, 10, 1.5),
            Position = pos + Vector3.new(0, 9, 0),
            Color = P.HubStone,
        }, folder)
        part({
            Size = Vector3.new(12, 12, 1),
            Position = pos + Vector3.new(0, 15, 0),
            Color = accent,
            Glow = true,
        }, folder)
    else
        part({
            Size = Vector3.new(12, 5, 4),
            Position = pos + Vector3.new(0, 4.5, 0),
            Color = P.Wood,
            Material = Enum.Material.Wood,
        }, folder)
        for _, sx in ipairs({ -1, 1 }) do
            for _, sz in ipairs({ -1, 1 }) do
                part({
                    Size = Vector3.new(1, 14, 1),
                    Position = pos + Vector3.new(sx * 6, 7, sz * 6),
                    Color = P.HubStone,
                }, folder)
            end
        end
        part({
            Size = Vector3.new(15, 2, 15),
            Position = pos + Vector3.new(0, 15, 0),
            Color = accent,
        }, folder)
        part({
            Size = Vector3.new(15, 1, 4),
            Position = pos + Vector3.new(0, 14, 7),
            Color = P.RedTrim,
            Glow = true,
        }, folder)
    end
    if label ~= nil then
        worldSign(folder, pos + Vector3.new(0, 0, -8), label, accent)
    end
    return base
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

    -- ELEVATOR CAR on the bottom 'start' level (tagged "Slingshot" -> the client elevator menu lives on it).
    buildElevatorCar(folder, 0)

    -- shop stalls + free-reward blocks (modeled structures), arranged around the plaza.
    buildStructure(folder, c + Vector3.new(-90, 0, -40), "NetShop", "NET SHOP", P.Grass)
    buildStructure(folder, c + Vector3.new(90, 0, -40), "PremiumShop", "PREMIUM", P.Gold)
    buildStructure(folder, c + Vector3.new(-130, 0, 30), "DailyChest", "DAILY", P.RedTrim)
    buildStructure(folder, c + Vector3.new(-110, 0, 50), "FreeGift", "GIFT", P.ShieldCyan)
    buildStructure(folder, c + Vector3.new(130, 0, 30), "SpinWheel", "SPIN", P.Gold)

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

-- A base ENCLOSURE around one plot: a raised floor pad + low walls (3 sides, open front) + corner posts +
-- a header beam. `center` = plot center on the ground, `face` = a CFrame whose -Z points at the open front.
local function buildBaseEnclosure(folder, center, face)
    local W, D, H = 52, 44, 14 -- interior footprint + wall height
    local cf = CFrame.new(center) * (face - face.Position)
    part(
        { Size = Vector3.new(W, 1.5, D), CFrame = cf * CFrame.new(0, 0.75, 0), Color = P.HubStone },
        folder
    )
    part({
        Size = Vector3.new(W, H, 1.5),
        CFrame = cf * CFrame.new(0, H / 2, -D / 2),
        Color = P.ShieldCyan,
    }, folder)
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(1.5, H, D),
            CFrame = cf * CFrame.new(sx * W / 2, H / 2, 0),
            Color = P.ShieldCyan,
        }, folder)
        for _, sz in ipairs({ -1, 1 }) do
            part({
                Size = Vector3.new(2.5, H + 4, 2.5),
                CFrame = cf * CFrame.new(sx * W / 2, (H + 4) / 2, sz * D / 2),
                Color = P.Gold,
            }, folder)
        end
    end
    part({
        Size = Vector3.new(W + 5, 3, 3),
        CFrame = cf * CFrame.new(0, H + 3, D / 2),
        Color = P.Gold,
        Glow = true,
    }, folder)
end

-- ── BASE DISTRICT (PlotAnchor markers on the base RING; ground disc is now built by buildPlatforms) ──
local function buildDistrict(folder)
    local ringR = WorldConfig.Levels.PlotRingRadius
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
        -- Wrap each plot in a 3-sided enclosure; open front faces the hub center.
        local faceCF = CFrame.lookAt(Vector3.new(pos.X, 0, pos.Z), WorldConfig.Center)
        buildBaseEnclosure(folder, pos, faceCF)
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

-- Per-STYLE flavor decoration scattered on a level PLATFORM (center (0, cfg.Y, 0), within cfg.Radius).
-- Cheap + capped; the old per-prop Neon is dropped to plain SmoothPlastic (only emitters glow now).
local function platformProps(folder, cfg)
    local y = cfg.Y
    local rad = cfg.Radius
    local function scatter()
        local a = rng:NextNumber(0, math.pi * 2)
        local r = rng:NextNumber(18, rad - 18)
        return Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
    end
    for _ = 1, cfg.TreeCount do
        tree(folder, scatter(), P.Wood, cfg.Accent)
    end
    local style = cfg.Style
    if style == "meadow" then
        for _ = 1, cfg.PropCount do
            part({
                Size = Vector3.new(2, 2, 2),
                Position = scatter() + Vector3.new(0, 1, 0),
                Color = (rng:NextNumber() > 0.5) and P.Gold or P.RedTrim,
            }, folder)
        end
    elseif style == "shores" then
        for i = -1, 1 do
            part({
                Size = Vector3.new(8, 1, 8),
                Position = Vector3.new(i * 40, y + 6, rad * 0.4),
                Color = (i == 0) and P.RedTrim or P.ShieldCyan,
            }, folder) -- umbrella tops
            part({
                Size = Vector3.new(1, 12, 1),
                Position = Vector3.new(i * 40, y + 1, rad * 0.4),
                Color = P.Foam,
            }, folder)
        end
    elseif style == "swamp" then
        for _ = 1, cfg.PropCount do
            part({
                Size = Vector3.new(6, 0.4, 6),
                Position = scatter() + Vector3.new(0, 1, 0),
                Color = Color3.fromRGB(70, 130, 70),
            }, folder) -- lily pad
        end
        local motes = part({
            Size = Vector3.new(2, 2, 2),
            Position = Vector3.new(0, y + 8, 0),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        emitter(motes, Color3.fromRGB(180, 255, 120), 12) -- fireflies
    elseif style == "magma" then
        for _ = 1, cfg.PropCount do
            part({
                Size = Vector3.new(rng:NextNumber(8, 18), 0.6, rng:NextNumber(8, 18)),
                Position = scatter() + Vector3.new(0, 0.4, 0),
                Color = cfg.Accent,
            }, folder) -- lava pool (solid color, not blinding)
        end
        local embers = part({
            Size = Vector3.new(2, 2, 2),
            Position = Vector3.new(0, y + 10, 0),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        emitter(embers, Color3.fromRGB(255, 140, 40), 16)
    elseif style == "rift" then
        for _ = 1, cfg.PropCount do
            part({
                Size = Vector3.new(3, 10, 3),
                Position = scatter() + Vector3.new(0, 6, 0),
                Color = cfg.Accent,
            }, folder) -- crystal
        end
    elseif style == "void" then
        for _ = 1, cfg.PropCount do
            part({
                Size = Vector3.new(
                    rng:NextNumber(3, 6),
                    rng:NextNumber(14, 28),
                    rng:NextNumber(3, 6)
                ),
                Position = scatter() + Vector3.new(0, 12, 0),
                Color = cfg.Accent,
            }, folder) -- monolith
        end
        local glow = part({
            Size = Vector3.new(2, 2, 2),
            Position = Vector3.new(0, y + 16, 0),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        emitter(glow, Color3.fromRGB(120, 235, 255), 18, 1.2)
    end
end

-- ── ONE LEVEL PLATFORM: decoration + tagged spawn/boss + name sign + (upper levels) an ELEVATOR pad.
-- The platform center is (0, cfg.Y, 0); spawn/boss/sign are forward-compat tags (gameplay spawns track
-- the player). Level 1 (the bottom 'start' platform) is the hub/district ground, so it skips the scatter.
local function buildPlatform(folder, cfg)
    local L = WorldConfig.Levels
    local y = cfg.Y
    local rad = cfg.Radius
    local function onDisc(angleDeg, r, dy)
        local a = math.rad(angleDeg)
        return Vector3.new(math.cos(a) * r, y + (dy or 0), math.sin(a) * r)
    end

    for k = -1, 1 do
        local sp = part({
            Size = Vector3.new(2, 1, 2),
            Position = onDisc(90 + k * 14, rad * 0.55, 1),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        sp.Name = "SpawnPoint_" .. cfg.Id .. "_" .. (k + 2)
        tag(sp, "SpawnPoint")
        sp:SetAttribute("Biome", cfg.Id)
    end

    local arenaPos = onDisc(270, rad * 0.5, 0)
    part({
        Size = Vector3.new(56, 1, 56),
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

    worldSign(folder, onDisc(L.ElevatorAngleDeg, 52, 0), string.upper(cfg.Name), cfg.Accent)

    if cfg.Tier > 1 then
        platformProps(folder, cfg) -- level 1 = the hub; upper levels get the biome flavor scatter
        buildElevatorCar(folder, cfg.Y)
    end
end

-- ── Build all the stacked LEVEL platforms (floating discs at increasing height). Every level,
-- including the bottom 'start' platform, is now a uniform 300-radius disc.
local function buildPlatforms(folder)
    for _, cfg in ipairs(WorldConfig.Biomes) do
        disc(
            cfg.Radius,
            cfg.Y,
            WorldConfig.Levels.PlatformThickness,
            cfg.GroundColor,
            cfg.GroundMaterial,
            folder
        )
        buildPlatform(folder, cfg)
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
    buildDistrict(worldFolder) -- the bottom 'start' platform ground + plot ring (level 1, the meadow)
    buildHub(worldFolder) -- central plaza + fixtures + the bottom-level ELEVATOR on level 1
    buildPlatforms(worldFolder) -- the stacked floating biome platforms (levels 2..N) + per-level decor
    buildElevatorShaft(worldFolder)
    buildIslands(worldFolder)
end

return WorldBuilder
