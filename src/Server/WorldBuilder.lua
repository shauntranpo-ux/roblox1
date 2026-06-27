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

-- A blocky BUSH: 2 stacked rounded green cubes (cheap; capped by the caller).
local function bush(parent, pos, leafColor)
    local base = leafColor or P.Grass
    part({
        Size = Vector3.new(5, 3, 5),
        Position = pos + Vector3.new(0, 1.5, 0),
        Color = base,
        Material = Enum.Material.Grass,
    }, parent)
    part({
        Size = Vector3.new(3.5, 2.5, 3.5),
        Position = pos + Vector3.new(1, 3, -0.5),
        Color = base:Lerp(Color3.new(0, 0, 0), 0.12),
        Material = Enum.Material.Grass,
    }, parent)
end

-- ── Forest props (all voxel/blocky, anchored; colliding ones are landmarks, the rest are floor cover) ──

-- A TALL voxel PINE: a slim wood trunk + 3 stacked tapering green cube tiers. Colliding landmark.
local function pine(parent, pos, trunkColor, leafColor)
    local trunkH = S.TreeHeight * 0.5
    part({
        Size = Vector3.new(3, trunkH, 3),
        Position = pos + Vector3.new(0, trunkH / 2, 0),
        Color = trunkColor or P.Wood,
        Material = Enum.Material.Wood,
    }, parent)
    local leaf = leafColor or P.Grass:Lerp(Color3.fromRGB(40, 116, 72), 0.5)
    local tiers = 3
    for t = 0, tiers - 1 do
        local w = (tiers - t) * 3 + 3
        part({
            Size = Vector3.new(w, 4, w),
            Position = pos + Vector3.new(0, trunkH + t * 3 + 2, 0),
            Color = leaf,
            Material = Enum.Material.Grass,
        }, parent)
    end
end

-- A mossy FALLEN LOG: a wood cylinder lying flat (rotated about Y by `rot`). Non-colliding cover detail.
local function fallenLog(parent, pos, rot)
    local len = rng:NextNumber(8, 14)
    local center = pos + Vector3.new(0, 1.2, 0)
    local logPart = part({
        Size = Vector3.new(len, 2.4, 2.4),
        Color = P.Wood:Lerp(Color3.fromRGB(96, 132, 80), 0.25),
        Material = Enum.Material.Wood,
        CanCollide = false,
        CFrame = CFrame.new(center) * CFrame.Angles(0, rot, 0),
    }, parent)
    logPart.Shape = Enum.PartType.Cylinder
    return logPart
end

-- A small FERN: a few thin angled green fronds from one point (cheap non-colliding ground detail).
local function fern(parent, pos)
    local base = Color3.fromRGB(96, 168, 84)
    for _ = 1, 3 do
        local h = rng:NextNumber(3, 5)
        part({
            Size = Vector3.new(0.6, h, 2.4),
            Color = base:Lerp(P.Grass, rng:NextNumber(0, 0.4)),
            Material = Enum.Material.Grass,
            CanCollide = false,
            CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(
                0,
                rng:NextNumber(0, math.pi * 2),
                math.rad(rng:NextNumber(-28, 28))
            ),
        }, parent)
    end
end

-- A MUSHROOM: a short cream stalk + a colored ball cap (non-colliding forest-floor accent).
local function mushroom(parent, pos)
    local capColor = rng:NextNumber(0, 1) < 0.5 and Color3.fromRGB(214, 84, 84)
        or Color3.fromRGB(228, 188, 120)
    part({
        Size = Vector3.new(0.8, 1.6, 0.8),
        Position = pos + Vector3.new(0, 0.8, 0),
        Color = Color3.fromRGB(240, 234, 214),
        Material = Enum.Material.SmoothPlastic,
        CanCollide = false,
    }, parent)
    local cap = part({
        Size = Vector3.new(2.2, 1.2, 2.2),
        Position = pos + Vector3.new(0, 1.8, 0),
        Color = capColor,
        Material = Enum.Material.SmoothPlastic,
        CanCollide = false,
    }, parent)
    cap.Shape = Enum.PartType.Ball
end

-- A FLOWER PATCH: a few tiny colored blooms on short green stems (non-colliding color speckle).
local function flowerPatch(parent, pos)
    local petals = {
        Color3.fromRGB(255, 180, 210),
        Color3.fromRGB(255, 224, 120),
        Color3.fromRGB(180, 170, 255),
        Color3.fromRGB(255, 140, 140),
    }
    for _ = 1, math.floor(rng:NextNumber(3, 6)) do
        local off = Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
        local h = rng:NextNumber(1.5, 3)
        part({
            Size = Vector3.new(0.3, h, 0.3),
            Position = pos + off + Vector3.new(0, h / 2, 0),
            Color = Color3.fromRGB(96, 168, 84),
            Material = Enum.Material.Grass,
            CanCollide = false,
        }, parent)
        local bloom = part({
            Size = Vector3.new(1, 1, 1),
            Position = pos + off + Vector3.new(0, h + 0.4, 0),
            Color = petals[math.floor(rng:NextNumber(1, #petals + 0.999))],
            Material = Enum.Material.SmoothPlastic,
            CanCollide = false,
        }, parent)
        bloom.Shape = Enum.PartType.Ball
    end
end

-- A cut STUMP: a short wide wood block + a lighter cut-top cap (colliding low landmark).
local function stump(parent, pos)
    part({
        Size = Vector3.new(4.5, 3, 4.5),
        Position = pos + Vector3.new(0, 1.5, 0),
        Color = P.Wood,
        Material = Enum.Material.Wood,
    }, parent)
    part({
        Size = Vector3.new(4, 0.4, 4),
        Position = pos + Vector3.new(0, 3.2, 0),
        Color = P.Wood:Lerp(Color3.fromRGB(222, 196, 150), 0.6),
        Material = Enum.Material.Wood,
    }, parent)
end

-- A complete framed Fredoka-One world sign: backing board (boardColor) + 4 P.Beam border strips +
-- two P.Beam wood posts reaching the ground + a SurfaceGui text label (white fill, dark stroke).
-- Signature is UNCHANGED so all callers (`buildPlatform`, `fixture`, `buildStructure`) work as-is.
local function worldSign(parent, pos, text, boardColor)
    -- Board dimensions
    local boardW, boardH = 22, 9
    local boardY = pos.Y + 16 -- board centre height above world origin
    -- Soft PASTEL accent board (was a garish fully-saturated slab) -> cohesive cream-accent sign; the
    -- white Fredoka text + dark stroke reads on it, the accent-painted frame + wood posts finish it.
    local accent = boardColor or P.RedTrim
    local boardCol = accent:Lerp(P.Plaster, 0.5)

    -- Solid backing board (the coloured face)
    local board = part({
        Size = Vector3.new(boardW, boardH, 1),
        Position = Vector3.new(pos.X, boardY, pos.Z),
        Color = boardCol,
    }, parent)

    -- 4 accent-painted frame strips around the board face (slightly proud of the board front)
    local fZ = pos.Z + 0.7 -- frame sits 0.7 studs in front of board centre
    -- Top bar
    part({
        Size = Vector3.new(boardW + 2, 1.2, 0.5),
        Position = Vector3.new(pos.X, boardY + boardH / 2 + 0.6, fZ),
        Color = accent,
        Material = Enum.Material.SmoothPlastic,
    }, parent)
    -- Bottom bar
    part({
        Size = Vector3.new(boardW + 2, 1.2, 0.5),
        Position = Vector3.new(pos.X, boardY - boardH / 2 - 0.6, fZ),
        Color = accent,
        Material = Enum.Material.SmoothPlastic,
    }, parent)
    -- Left bar
    part({
        Size = Vector3.new(1.2, boardH + 2, 0.5),
        Position = Vector3.new(pos.X - boardW / 2 - 0.6, boardY, fZ),
        Color = accent,
        Material = Enum.Material.SmoothPlastic,
    }, parent)
    -- Right bar
    part({
        Size = Vector3.new(1.2, boardH + 2, 0.5),
        Position = Vector3.new(pos.X + boardW / 2 + 0.6, boardY, fZ),
        Color = accent,
        Material = Enum.Material.SmoothPlastic,
    }, parent)

    -- Two P.Beam posts from y=0 up to the board bottom (board bottom = boardY - boardH/2)
    local postH = math.max(1, boardY - boardH / 2) -- distance from ground to board bottom
    local postCY = postH / 2 -- post centre
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(2, postH, 2),
            Position = Vector3.new(pos.X + sx * (boardW / 2 - 2), postCY, pos.Z),
            Color = P.Beam,
            Material = Enum.Material.Wood,
        }, parent)
    end

    -- SurfaceGui text on the board front face (FredokaOne, white fill + dark stroke; unchanged)
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
    -- cf's -Z (LookVector) points to the platform centre -> the car FRONT (door) faces the player.
    local cf = CFrame.lookAt(center, WorldConfig.Center + Vector3.new(0, y, 0))

    -- Floor: stone pad + a metal inlay border + a glowing call-disc inset (reads as a real car).
    part(
        { Size = Vector3.new(15, 1, 15), CFrame = cf * CFrame.new(0, 0.5, 0), Color = P.HubStone },
        folder
    )
    part({
        Size = Vector3.new(11, 1.1, 11),
        CFrame = cf * CFrame.new(0, 0.55, 0),
        Color = P.Gold,
        Material = Enum.Material.Metal,
    }, folder)
    part({
        Size = Vector3.new(7.5, 1.2, 7.5),
        CFrame = cf * CFrame.new(0, 0.6, 0),
        Color = P.ShieldCyan,
        Glow = true,
    }, folder)

    -- GLASS back wall (away from centre, +Z) so the open front faces the player; HubStone side walls
    -- with a gold top trim each. Slim, not a heavy box.
    part({
        Size = Vector3.new(14, 16, 0.6),
        CFrame = cf * CFrame.new(0, 8.5, 6.7),
        Color = P.ShieldCyan,
        Transparency = 0.45,
        Material = Enum.Material.Glass,
    }, folder)
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(0.8, 16, 13.4),
            CFrame = cf * CFrame.new(sx * 6.7, 8.5, 0),
            Color = P.HubStone,
        }, folder)
        part({
            Size = Vector3.new(1, 1, 13.4),
            CFrame = cf * CFrame.new(sx * 6.7, 16.2, 0),
            Color = P.Gold,
            Material = Enum.Material.Metal,
        }, folder)
    end

    -- Roof + a glowing beacon on top.
    part({
        Size = Vector3.new(15.6, 1, 15.6),
        CFrame = cf * CFrame.new(0, 17, 0),
        Color = P.HubStone,
    }, folder)
    part({
        Size = Vector3.new(3, 2.4, 3),
        CFrame = cf * CFrame.new(0, 18.7, 0),
        Color = P.Gold,
        Glow = true,
    }, folder)

    -- Slim metal corner posts.
    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            part({
                Size = Vector3.new(1, 17.5, 1),
                CFrame = cf * CFrame.new(sx * 7, 8.75, sz * 7),
                Color = P.Gold,
                Material = Enum.Material.Metal,
            }, folder)
        end
    end

    -- A glowing UP-indicator strip across the front lintel + the call panel pillar (tagged Slingshot).
    part({
        Size = Vector3.new(11, 1.6, 0.4),
        CFrame = cf * CFrame.new(0, 15, -6.7),
        Color = P.ShieldCyan,
        Glow = true,
    }, folder)
    local panel = fixture(
        folder,
        (cf * CFrame.new(5, 3.5, -6.4)).Position,
        Vector3.new(2.6, 6, 0.9),
        P.Gold,
        "Slingshot",
        "ELEVATOR"
    )
    panel:SetAttribute("LaunchHeight", 26)
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
    -- Cobblestone grounding PAD so every stall reads as planted on a plaza pad (esp. the meadow-edge
    -- ones); sits flush on the ground beneath the plinth.
    part({
        Size = Vector3.new(17, 0.5, 17),
        Position = pos + Vector3.new(0, 0.25, 0),
        Color = P.Stone,
        Material = Enum.Material.Cobblestone,
    }, folder)
    -- Stepped stone PEDESTAL base: 3 tiers so every fixture sits on a real plinth.
    -- Tier 1 (widest) = base, tagged with tagName so the game systems bind to it.
    local base = part({
        Size = Vector3.new(14, 3, 14),
        Position = pos + Vector3.new(0, 1.5, 0),
        Color = P.HubStone,
    }, folder)
    base.Name = tagName
    tag(base, tagName)
    -- Tier 2
    part(
        { Size = Vector3.new(12, 2, 12), Position = pos + Vector3.new(0, 4, 0), Color = P.Stone },
        folder
    )
    -- Tier 3 (top stepping-stone)
    part({
        Size = Vector3.new(10, 1.5, 10),
        Position = pos + Vector3.new(0, 5.75, 0),
        Color = P.Plaster,
    }, folder)

    if tagName == "FreeGift" then
        -- Main gift box sitting on the pedestal
        part({
            Size = Vector3.new(8, 8, 8),
            Position = pos + Vector3.new(0, 10.5, 0),
            Color = accent,
        }, folder)
        -- Ribbon bands (two crossing strips)
        part({
            Size = Vector3.new(8.4, 1.6, 1.6),
            Position = pos + Vector3.new(0, 10.5, 0),
            Color = P.Roof,
        }, folder)
        part({
            Size = Vector3.new(1.6, 1.6, 8.4),
            Position = pos + Vector3.new(0, 10.5, 0),
            Color = P.Roof,
        }, folder)
        -- Bow knot on top
        part({
            Size = Vector3.new(3, 2.5, 3),
            Position = pos + Vector3.new(0, 15, 0),
            Color = P.Gold,
        }, folder)
        -- Small side decoration boxes (depth dressing)
        part({
            Size = Vector3.new(4, 4, 4),
            Position = pos + Vector3.new(-7, 7.5, 2),
            Color = P.Grape,
        }, folder)
        part({
            Size = Vector3.new(3, 3, 3),
            Position = pos + Vector3.new(6, 7, -2),
            Color = P.RedTrim,
        }, folder)
        -- Coin scatter
        local coinCF = CFrame.new(pos + Vector3.new(5, 7.5, 4)) * CFrame.Angles(0, 0, math.rad(90))
        local coin =
            part({ Size = Vector3.new(0.8, 2.5, 2.5), CFrame = coinCF, Color = P.Gold }, folder)
        coin.Shape = Enum.PartType.Cylinder
    elseif tagName == "DailyChest" then
        -- Chest body (wood lower half)
        part({
            Size = Vector3.new(10, 6, 7),
            Position = pos + Vector3.new(0, 9, 0),
            Color = P.Wood,
            Material = Enum.Material.Wood,
        }, folder)
        -- Chest lid (accent color arched top)
        part({
            Size = Vector3.new(10, 3.5, 7),
            Position = pos + Vector3.new(0, 13, 0),
            Color = accent,
        }, folder)
        -- Gold lock hasp
        part({
            Size = Vector3.new(1.8, 3.5, 1.8),
            Position = pos + Vector3.new(0, 10.5, 3.6),
            Color = P.Gold,
        }, folder)
        -- Side coin scatter (give depth)
        local coinCF1 = CFrame.new(pos + Vector3.new(-6, 8, 1)) * CFrame.Angles(0, 0, math.rad(90))
        local c1 =
            part({ Size = Vector3.new(0.8, 2.8, 2.8), CFrame = coinCF1, Color = P.Gold }, folder)
        c1.Shape = Enum.PartType.Cylinder
        local coinCF2 = CFrame.new(pos + Vector3.new(6, 8, -1)) * CFrame.Angles(0, 0, math.rad(90))
        local c2 =
            part({ Size = Vector3.new(0.8, 2.2, 2.2), CFrame = coinCF2, Color = P.Gold }, folder)
        c2.Shape = Enum.PartType.Cylinder
        -- Small treasure box beside it
        part({
            Size = Vector3.new(4, 3.5, 4),
            Position = pos + Vector3.new(7, 8, 2),
            Color = P.Beam,
            Material = Enum.Material.Wood,
        }, folder)
    elseif tagName == "SpinWheel" then
        -- A proper VERTICAL prize wheel facing the player (+Z). Wheel centre well above the pedestal.
        local wc = pos + Vector3.new(0, 21, 0)
        -- Two stout wood support LEGS flanking the wheel + a back axle bar between them.
        for _, sx in ipairs({ -1, 1 }) do
            part({
                Size = Vector3.new(2.6, 24, 2.6),
                Position = pos + Vector3.new(sx * 11, 12.5, -1),
                Color = P.Beam,
                Material = Enum.Material.Wood,
            }, folder)
        end
        part({
            Size = Vector3.new(24, 2.4, 2.4),
            Position = wc + Vector3.new(0, 0, -2),
            Color = P.Beam,
            Material = Enum.Material.Wood,
        }, folder)
        -- Outer RIM (a thick dark wood ring behind the face) + the wheel HUB disc (faces +Z, the player).
        local function faceDisc(size, offsetZ, color, mat)
            local d = part({
                Size = size,
                CFrame = CFrame.new(wc + Vector3.new(0, 0, offsetZ))
                    * CFrame.Angles(0, math.rad(90), 0),
                Color = color,
                Material = mat or Enum.Material.SmoothPlastic,
            }, folder)
            d.Shape = Enum.PartType.Cylinder
            return d
        end
        faceDisc(Vector3.new(2.4, 26, 26), -1.4, P.Wood, Enum.Material.Wood) -- rim
        faceDisc(Vector3.new(2.6, 23, 23), 0, P.Plaster) -- wheel face
        -- 8 colored WEDGES radiating on the face (thin blocks rotated about Z, pushed out + proud of face).
        local spokeColors = {
            accent,
            P.RedTrim,
            P.Gold,
            P.Grape,
            P.ShieldCyan,
            P.Plaster,
            P.Roof,
            P.Grass,
        }
        for i = 0, 7 do
            local angle = math.rad(i * 45 + 22.5)
            local wedgeCF = CFrame.new(wc + Vector3.new(0, 0, 1.4))
                * CFrame.Angles(0, 0, angle)
                * CFrame.new(0, 5.4, 0)
            part({
                Size = Vector3.new(7.4, 10.4, 0.5),
                CFrame = wedgeCF,
                Color = spokeColors[i + 1],
                Material = Enum.Material.SmoothPlastic,
            }, folder)
        end
        -- Gold spoke dividers between wedges (thin radial bars) for a crisp segmented look.
        for i = 0, 7 do
            local angle = math.rad(i * 45)
            local barCF = CFrame.new(wc + Vector3.new(0, 0, 1.7))
                * CFrame.Angles(0, 0, angle)
                * CFrame.new(0, 5.6, 0)
            part({
                Size = Vector3.new(0.7, 11.4, 0.5),
                CFrame = barCF,
                Color = P.Gold,
                Material = Enum.Material.Metal,
            }, folder)
        end
        -- Center bolt cap (a small gold disc on the face).
        faceDisc(Vector3.new(1, 4.5, 4.5), 2, P.Gold, Enum.Material.Metal)
        -- Bold POINTER at 12 o'clock: a gold diamond marker pointing down into the wheel.
        part({
            Size = Vector3.new(3.6, 3.6, 1.4),
            CFrame = CFrame.new(wc + Vector3.new(0, 13.5, 1.6)) * CFrame.Angles(0, 0, math.rad(45)),
            Color = P.Gold,
            Material = Enum.Material.Metal,
        }, folder)
    else
        -- STALL KIOSK (NetShop / PremiumShop)
        -- Chunky wood COUNTER: a solid body + an accent front kick-panel + an overhanging stone top lip
        -- (reads as a real shop counter, not a thin slab).
        part({
            Size = Vector3.new(14, 6, 6),
            Position = pos + Vector3.new(0, 7.5, 3.5),
            Color = P.Beam,
            Material = Enum.Material.Wood,
        }, folder)
        part({
            Size = Vector3.new(13, 3.5, 0.6),
            Position = pos + Vector3.new(0, 7, 6.6),
            Color = accent,
            Material = Enum.Material.SmoothPlastic,
        }, folder)
        part({
            Size = Vector3.new(15.5, 1.2, 7.4),
            Position = pos + Vector3.new(0, 10.7, 3.5),
            Color = P.Stone,
            Material = Enum.Material.SmoothPlastic,
        }, folder)
        -- 4 corner posts (bottom at y=6.5 = tier-3 pedestal top; centre = 6.5 + 8 = 14.5)
        for _, sx in ipairs({ -1, 1 }) do
            for _, sz in ipairs({ -1, 1 }) do
                part({
                    Size = Vector3.new(1.5, 16, 1.5),
                    Position = pos + Vector3.new(sx * 6.5, 14.5, sz * 6),
                    Color = P.Beam,
                    Material = Enum.Material.Wood,
                }, folder)
            end
        end
        -- PEAKED canopy: two sloped slabs meeting at a ridge above the posts (better-proportioned, not
        -- oversized) + a ridge beam capping the seam.
        for _, sx in ipairs({ -1, 1 }) do
            local slopeCF = CFrame.new(pos + Vector3.new(sx * 3.6, 23.5, 0))
                * CFrame.Angles(0, 0, sx * math.rad(28))
            part({
                Size = Vector3.new(7.4, 1.2, 15),
                CFrame = slopeCF,
                Color = accent,
                Material = Enum.Material.Fabric,
            }, folder)
        end
        part({
            Size = Vector3.new(1.4, 1.4, 15.5),
            Position = pos + Vector3.new(0, 25.2, 0),
            Color = P.Wood,
            Material = Enum.Material.Wood,
        }, folder)
        -- Scalloped striped VALANCE hanging off the front eave (alternating accent / plaster tabs).
        for i = -3, 3 do
            part({
                Size = Vector3.new(2, 2.2, 0.6),
                Position = pos + Vector3.new(i * 2.1, 20.4, 7.3),
                Color = (i % 2 == 0) and accent or P.Plaster,
                Material = Enum.Material.Fabric,
            }, folder)
        end
        -- Back shelf board
        part({
            Size = Vector3.new(13, 1, 4),
            Position = pos + Vector3.new(0, 14.5, -5.5),
            Color = P.Beam,
            Material = Enum.Material.Wood,
        }, folder)
        -- Hanging product cube on the shelf
        part({
            Size = Vector3.new(3.5, 3.5, 3.5),
            Position = pos + Vector3.new(0, 17, -5.5),
            Color = P.Gold,
        }, folder)
        -- Small framed wood plaque mounted on the canopy front (replaces the giant floating sign).
        -- Frame: a flat P.Beam board slightly proud of the canopy front face
        local plaquePos = pos + Vector3.new(0, 22.5, 7.6)
        local plaqueBoard = part({
            Size = Vector3.new(10, 3.5, 0.6),
            Position = plaquePos,
            Color = P.Beam,
            Material = Enum.Material.Wood,
        }, folder)
        -- Plaque label: a SurfaceGui on the front face of the board (keeps the text, no giant sign post)
        if label ~= nil then
            local sg = Instance.new("SurfaceGui")
            sg.Name = "Sign"
            sg.Face = Enum.NormalId.Front
            sg.CanvasSize = Vector2.new(400, 140)
            sg.Adornee = plaqueBoard
            sg.Parent = plaqueBoard
            local shadow = Instance.new("TextLabel")
            shadow.Size = UDim2.fromScale(1, 1)
            shadow.Position = UDim2.fromOffset(3, 3)
            shadow.BackgroundTransparency = 1
            shadow.Font = Enum.Font.FredokaOne
            shadow.Text = label
            shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
            shadow.TextTransparency = 0.5
            shadow.TextScaled = true
            shadow.Parent = sg
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.fromScale(1, 1)
            lbl.BackgroundTransparency = 1
            lbl.Font = Enum.Font.FredokaOne
            lbl.Text = label
            lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
            lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            lbl.TextStrokeTransparency = 0
            lbl.TextScaled = true
            lbl.Parent = sg
        end
        -- Thin frame border around the plaque (4 P.Beam strips)
        part({
            Size = Vector3.new(10.8, 0.6, 0.4),
            Position = plaquePos + Vector3.new(0, 1.75, 0.1),
            Color = P.Wood,
            Material = Enum.Material.Wood,
        }, folder) -- top bar
        part({
            Size = Vector3.new(10.8, 0.6, 0.4),
            Position = plaquePos + Vector3.new(0, -1.75, 0.1),
            Color = P.Wood,
            Material = Enum.Material.Wood,
        }, folder) -- bottom bar
        for _, sx in ipairs({ -1, 1 }) do
            part({
                Size = Vector3.new(0.6, 3.5, 0.4),
                Position = plaquePos + Vector3.new(sx * 5.4, 0, 0.1),
                Color = P.Wood,
                Material = Enum.Material.Wood,
            }, folder) -- side bars
        end
        -- For stalls the label is rendered on the plaque above; skip the old worldSign call below.
        return base
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

    -- COURTYARD: a warm cobblestone disc (radius 115) instead of a 360x360 white slab, so the green
    -- meadow disc shows as a ring around the plaza. The base ring (r=100) sits right at the courtyard
    -- edge -- deliberate town-square feel. The clay Roof ring is built SLIGHTLY LOWER + larger so it
    -- peeks out only as a thin rim; the cobblestone disc sits ON TOP (else the clay disc, being both
    -- bigger AND higher, floods the entire plaza red -- the old bug).
    disc(119, 0.34, 2, P.Roof, Enum.Material.Slate, folder) -- clay rim (lower, larger -> shows as a ring)
    disc(115, 0.5, S.GroundThickness, P.Stone, Enum.Material.Cobblestone, folder) -- cobblestone ON TOP

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
    buildStructure(folder, c + Vector3.new(-130, 0, 30), "DailyChest", "DAILY", P.Roof)
    buildStructure(folder, c + Vector3.new(-110, 0, 50), "FreeGift", "GIFT", P.Grape)
    buildStructure(folder, c + Vector3.new(130, 0, 30), "SpinWheel", "SPIN", P.Gold)

    -- LeaderboardPillar anchors: INVISIBLE tagged markers (the dark slabs are retired). The VISIBLE
    -- leaderboard displays are the soft scrolling boards built by LeaderboardBillboards as a tidy
    -- grounded plaza row. Tag + "Board" attribute are preserved for the contract (nothing reads the
    -- old slab's size/position, so shrinking it to an invisible anchor is a visual-only change).
    local boards = { "TopCash", "TopIncome", "RarestCollection" }
    for i, key in ipairs(boards) do
        local anchor = part({
            Size = Vector3.new(4, 1, 4),
            Position = c + Vector3.new(-44 + (i - 1) * 44, 0.5, -110),
            Transparency = 1,
            CanCollide = false,
        }, folder)
        anchor.Name = "LeaderboardPillar"
        tag(anchor, "LeaderboardPillar")
        anchor:SetAttribute("Board", key)
    end
end

-- ── DEDICATED LEADERBOARD PLAZA: a raised stone dais in its own alcove off the hub's -X edge, with a
-- stone path leading to it from the plaza. The board STANDS themselves are placed + oriented by
-- LeaderboardBillboards from the SAME WorldConfig.Leaderboard anchor (facing back down the path); this
-- builds the dais, backdrop, banner, and path around them. The corridor is reserved in the foliage +
-- terrain guards so nothing overgrows it. Built axis-via-basis so changing AngleDeg just rotates it.
local function buildLeaderboardPlaza(folder)
    local LB = WorldConfig.Leaderboard
    local a = math.rad(LB.AngleDeg)
    local center = Vector3.new(math.cos(a) * LB.Radius, LB.BaseY, math.sin(a) * LB.Radius)
    -- local basis: +X = along the dais row (tangent); +Z = forward (toward the player / world center).
    local yaw = math.atan2(-math.cos(a), -math.sin(a))
    local baseCF = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
    local function at(lx, ly, lz)
        return baseCF * CFrame.new(lx, ly, lz)
    end
    local L = LB.DaisLength
    local D = LB.DaisDepth

    -- Stepped stone dais (two tiers) -- the raised special platform.
    part({
        Size = Vector3.new(L + 16, 2, D + 12),
        CFrame = at(0, 1, 0),
        Color = P.Stone,
        Material = Enum.Material.Slate,
    }, folder)
    part({
        Size = Vector3.new(L, 2.5, D),
        CFrame = at(0, 3, 0),
        Color = P.Stone:Lerp(P.Plaster, 0.3),
        Material = Enum.Material.SmoothPlastic,
    }, folder)

    -- Tall "hall of fame" BACKDROP behind the boards (far -forward edge) + an eave cap + corner posts.
    part({
        Size = Vector3.new(L + 8, 42, 2),
        CFrame = at(0, 21, -D / 2 - 1),
        Color = P.Plaster,
        Material = Enum.Material.SmoothPlastic,
    }, folder)
    part({
        Size = Vector3.new(L + 12, 2.5, 4),
        CFrame = at(0, 42.5, -D / 2 - 1),
        Color = P.Roof,
        Material = Enum.Material.Slate,
    }, folder)
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(3.5, 46, 3.5),
            CFrame = at(sx * (L / 2 + 3), 23, -D / 2 - 1),
            Color = P.Beam,
            Material = Enum.Material.Wood,
        }, folder)
    end

    -- "LEADERBOARDS" banner near the top of the backdrop, facing FORWARD (toward the player).
    local banner = part({
        Size = Vector3.new(L * 0.5, 10, 1),
        CFrame = at(0, 38, -D / 2 + 0.2),
        Color = P.Grape:Lerp(P.Plaster, 0.35),
    }, folder)
    local bsg = Instance.new("SurfaceGui")
    bsg.Name = "Banner"
    bsg.Face = Enum.NormalId.Front
    bsg.CanvasSize = Vector2.new(520, 96)
    bsg.Adornee = banner
    bsg.Parent = banner
    local btl = Instance.new("TextLabel")
    btl.Size = UDim2.fromScale(1, 1)
    btl.BackgroundTransparency = 1
    btl.Font = Enum.Font.FredokaOne
    btl.Text = "🏆 LEADERBOARDS"
    btl.TextColor3 = Color3.fromRGB(255, 255, 255)
    btl.TextStrokeColor3 = Color3.fromRGB(36, 22, 60)
    btl.TextStrokeTransparency = 0.2
    btl.TextScaled = true
    btl.Parent = bsg

    -- Stone PATH from the dais front toward the plaza (tiles overlay the floor; lamp posts every 2nd tile).
    local pw = LB.PathHalfWidth
    local zStart = D / 2 + 6
    local zEnd = LB.Radius - LB.PathReachRadius
    local tile = 16
    local zi = zStart
    local flip = false
    while zi < zEnd do
        part({
            Size = Vector3.new(pw * 2, 0.6, tile - 2),
            CFrame = at(0, 0.5, zi + tile / 2),
            Color = flip and P.Stone or P.Stone:Lerp(P.Beam, 0.35),
            Material = Enum.Material.Slate,
        }, folder)
        if flip then
            for _, sx in ipairs({ -1, 1 }) do
                part({
                    Size = Vector3.new(1, 7, 1),
                    CFrame = at(sx * (pw + 1.5), 3.5, zi + tile / 2),
                    Color = P.Beam,
                    Material = Enum.Material.Wood,
                }, folder)
                part({
                    Size = Vector3.new(2, 2, 2),
                    CFrame = at(sx * (pw + 1.5), 7.5, zi + tile / 2),
                    Color = P.Gold,
                    Glow = true,
                }, folder)
            end
        end
        flip = not flip
        zi = zi + tile
    end
end

-- A cozy COTTAGE base around one plot: warm stone floor + cream plaster walls (3 sides + a flanked front
-- DOORWAY) + wood corner beams + a clay eave trim around the OPEN top (top stays open so the player's
-- brainrots are visible + stealable -- never roof it over). `center` = plot center, `face` -Z = open front.
local function buildBaseEnclosure(folder, center, face)
    local W, D, H = 54, 46, 15
    local cf = CFrame.new(center) * (face - face.Position)
    -- raised warm-stone floor (top at y=1 so pads sit ON it, not clipped through)
    part({
        Size = Vector3.new(W, 2, D),
        CFrame = cf * CFrame.new(0, 0, 0),
        Color = P.Stone,
        Material = Enum.Material.Slate,
    }, folder)
    -- cream plaster back + side walls (floor top now y=1; wall centres shifted down by 1 to sit on floor)
    part({
        Size = Vector3.new(W, H, 1.5),
        CFrame = cf * CFrame.new(0, H / 2 + 1, -D / 2),
        Color = P.Plaster,
    }, folder)
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(1.5, H, D),
            CFrame = cf * CFrame.new(sx * W / 2, H / 2 + 1, 0),
            Color = P.Plaster,
        }, folder)
    end
    -- low FRONT walls flanking an open doorway (reads as an entrance, not a sealed box)
    local doorHalf = 9
    local segW = W / 2 - doorHalf
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(segW, H * 0.55, 1.5),
            CFrame = cf * CFrame.new(sx * (doorHalf + segW / 2), H * 0.275 + 1, D / 2),
            Color = P.Plaster,
        }, folder)
    end
    -- wood corner beams (the cottage frame; bottom at y=1 matching the floor top)
    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            part({
                Size = Vector3.new(2.5, H + 5, 2.5),
                CFrame = cf * CFrame.new(sx * W / 2, (H + 5) / 2 + 1, sz * D / 2),
                Color = P.Beam,
                Material = Enum.Material.Wood,
            }, folder)
        end
    end
    -- clay EAVE trim around the open top (a thin perimeter lip; center stays open)
    local eaveY = H + 2
    part({
        Size = Vector3.new(W + 4, 2, 3),
        CFrame = cf * CFrame.new(0, eaveY, -D / 2),
        Color = P.Roof,
        Material = Enum.Material.Slate,
    }, folder)
    part({
        Size = Vector3.new(W + 4, 2, 3),
        CFrame = cf * CFrame.new(0, eaveY, D / 2),
        Color = P.Roof,
        Material = Enum.Material.Slate,
    }, folder)
    for _, sx in ipairs({ -1, 1 }) do
        part({
            Size = Vector3.new(3, 2, D + 4),
            CFrame = cf * CFrame.new(sx * W / 2, eaveY, 0),
            Color = P.Roof,
            Material = Enum.Material.Slate,
        }, folder)
    end
    -- a warm doorway header banner (no glow)
    part({
        Size = Vector3.new(doorHalf * 2 + 4, 3, 2),
        CFrame = cf * CFrame.new(0, H * 0.55 + 3, D / 2),
        Color = P.Roof,
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
            * CFrame.Angles(0, math.rad(180), 0)
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
        Color = Color3.fromRGB(78, 74, 100), -- softer seam-hider (was near-black 38,41,54)
    }, model)

    -- GRID-FIT pads inside the base (40 x 30) so brainrots never overflow, however many unlock. ALL pads
    -- (active + the 2 pre-built expansion pads) get a centered grid slot, so a newly unlocked pad auto-fits.
    local padCount = Config.Plots.PadsPerPlot
    local total = padCount + 2
    local cols = math.min(total, 4)
    local rows = math.ceil(total / cols)
    local cell = 8 -- 6-stud pad + 2-stud gap
    local function makePad(i, expansion)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = (col - (cols - 1) / 2) * cell
        local z = -2 - (row - (rows - 1) / 2) * cell
        -- Pads: Size y=1, centre y=1.5 -> bottom y=1 = sits ON the enclosure floor whose top is y=1
        local pad = part({
            Size = Vector3.new(6, 1, 6),
            Position = Vector3.new(x, 1.5, z),
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
        makePad(i, true)
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
    local rim = part({
        Size = Vector3.new(46, 1, 1.2),
        Position = Vector3.new(0, 17, 9),
        Color = P.ShieldRim,
        -- Glow OFF: a clean solid bright-cyan rim instead of the blown-out neon strip (no white-out).
        Glow = false,
        CanCollide = false,
    }, model)
    rim.Transparency = 0.15

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
    mystery.Transparency = 0.35
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
    for _ = 1, cfg.TreeCount do
        tree(folder, scatter(), P.Wood, cfg.Accent)
    end
    for _ = 1, math.floor(cfg.PropCount * 1.5) do
        bush(folder, scatter(), cfg.GroundColor:Lerp(P.Grass, 0.5))
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

-- ── SUNNY MEADOW foliage: lush, CAPPED cover (tall grass, bushes, hedge rows, voxel tree clusters,
-- rocks) so the first biome feels alive AND gives wild brainrots places to roam + hide. Grass/bushes/
-- hedges are CanCollide=false (walk-through cover -> the spawn area stays walkable); tree clusters +
-- rocks collide but AVOID the spawn cone so spawns still land on valid ground. Tune density in
-- WorldConfig.MeadowFoliage. Anchored + deterministic (seeded rng); re-running Init reproduces it.
local function meadowFoliage(folder, cfg)
    local F = WorldConfig.MeadowFoliage
    local y = cfg.Y
    local rad = cfg.Radius
    local innerR = F.InnerRadius
    local spawnA = math.rad(90)
    local arenaA = math.rad(270)
    local elevA = math.rad(WorldConfig.Levels.ElevatorAngleDeg)
    local elevR = WorldConfig.Levels.ElevatorRadius

    local function angDiff(x, ref)
        local d = (x - ref) % (math.pi * 2)
        if d > math.pi then
            d = d - math.pi * 2
        end
        return math.abs(d)
    end
    -- COLLIDING props (trees/rocks) keep clear of the spawn cone, boss arena, and the elevator car so
    -- spawns + traversal stay clean. Non-colliding cover (grass/bushes/hedges) ignores this.
    local function blockedForColliders(a, r)
        if angDiff(a, spawnA) < math.rad(14) then
            return true
        end
        if angDiff(a, arenaA) < math.rad(34) then
            return true
        end
        if angDiff(a, elevA) < math.rad(20) then
            return true
        end
        local ex, ez = math.cos(elevA) * elevR, math.sin(elevA) * elevR
        local px, pz = math.cos(a) * r, math.sin(a) * r
        if (px - ex) ^ 2 + (pz - ez) ^ 2 < 40 ^ 2 then
            return true
        end
        -- Reserve the dedicated leaderboard alcove + its path corridor (no trees/rocks overgrow it).
        local LB = WorldConfig.Leaderboard
        local lbA = math.rad(LB.AngleDeg)
        if angDiff(a, lbA) < math.rad(LB.ClearHalfAngleDeg) then
            return true
        end
        local lx, lz = math.cos(lbA) * LB.Radius, math.sin(lbA) * LB.Radius
        return (px - lx) ^ 2 + (pz - lz) ^ 2 < LB.ClearRadius ^ 2
    end
    -- A polar point in the meadow ring [innerR, rad-12]; `towardSpawn` biases it to the spawn side.
    local function pick(towardSpawn)
        local a = towardSpawn and (spawnA + rng:NextNumber(-math.rad(60), math.rad(60)))
            or rng:NextNumber(0, math.pi * 2)
        local r = rng:NextNumber(innerR, rad - 12)
        return a, r, Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
    end

    -- (a) Tall grass tufts: cheap non-colliding green blades; dense cover including near the spawn.
    for i = 1, F.GrassTufts do
        local _, _, pos = pick(i % 2 == 0)
        local h = rng:NextNumber(3, 6)
        part({
            Size = Vector3.new(rng:NextNumber(1.5, 3), h, rng:NextNumber(1.5, 3)),
            Position = pos + Vector3.new(0, h / 2, 0),
            Color = P.Grass:Lerp(Color3.fromRGB(184, 226, 120), rng:NextNumber(0, 0.5)),
            Material = Enum.Material.Grass,
            CanCollide = false,
        }, folder)
    end

    -- (b) Bushes: rounded non-colliding cover to hide near/behind (walk-through; 2 cubes each).
    for i = 1, F.Bushes do
        local _, _, pos = pick(i % 2 == 0)
        local base = P.Grass:Lerp(Color3.fromRGB(80, 152, 72), 0.3)
        part({
            Size = Vector3.new(5, 3.5, 5),
            Position = pos + Vector3.new(0, 1.75, 0),
            Color = base,
            Material = Enum.Material.Grass,
            CanCollide = false,
        }, folder)
        part({
            Size = Vector3.new(3.5, 2.5, 3.5),
            Position = pos + Vector3.new(rng:NextNumber(-1.5, 1.5), 3.4, rng:NextNumber(-1.5, 1.5)),
            Color = base:Lerp(Color3.new(0, 0, 0), 0.1),
            Material = Enum.Material.Grass,
            CanCollide = false,
        }, folder)
    end

    -- (c) Hedge rows: low non-colliding green walls (tangent to the ring) -- cover lines to weave around.
    for _ = 1, F.Hedges do
        local a, _, pos = pick(false)
        local seg = math.floor(rng:NextNumber(3, 5))
        local dirA = a + math.rad(90)
        for s = 0, seg - 1 do
            local off = (s - (seg - 1) / 2) * 5
            part({
                Size = Vector3.new(5, 5, 3),
                Position = pos + Vector3.new(math.cos(dirA) * off, 2.5, math.sin(dirA) * off),
                Color = P.Grass:Lerp(Color3.fromRGB(60, 132, 60), 0.4),
                Material = Enum.Material.Grass,
                CanCollide = false,
            }, folder)
        end
    end

    -- (d) Voxel tree CLUSTERS (small forests): colliding landmarks; skip the spawn cone/arena/elevator.
    local clusters = 0
    for _ = 1, F.TreeClusters * 3 do
        if clusters >= F.TreeClusters then
            break
        end
        local a, r, pos = pick(false)
        if not blockedForColliders(a, r) then
            for _ = 1, math.floor(rng:NextNumber(2, 4)) do
                local off = Vector3.new(rng:NextNumber(-7, 7), 0, rng:NextNumber(-7, 7))
                tree(folder, pos + off, P.Wood, P.Grass:Lerp(Color3.fromRGB(122, 202, 92), 0.4))
            end
            clusters += 1
        end
    end

    -- (e) Mossy rocks: colliding accents; skip the spawn cone/arena/elevator.
    local rocks = 0
    for _ = 1, F.Rocks * 2 do
        if rocks >= F.Rocks then
            break
        end
        local a, r, pos = pick(false)
        if not blockedForColliders(a, r) then
            local s = rng:NextNumber(4, 9)
            part({
                Size = Vector3.new(s, s * 0.7, s),
                Position = pos + Vector3.new(0, s * 0.35, 0),
                Color = P.Stone:Lerp(P.Grass, 0.2),
                Material = Enum.Material.Slate,
            }, folder)
            rocks += 1
        end
    end

    -- (f) Tall PINES: colliding conifer landmarks that thicken the canopy; skip the colliding zones.
    local pines = 0
    for _ = 1, (F.PineTrees or 0) * 3 do
        if pines >= (F.PineTrees or 0) then
            break
        end
        local a, r, pos = pick(false)
        if not blockedForColliders(a, r) then
            pine(
                folder,
                pos,
                P.Wood,
                P.Grass:Lerp(Color3.fromRGB(40, 116, 72), rng:NextNumber(0.3, 0.6))
            )
            pines += 1
        end
    end

    -- (g) Cut STUMPS: low colliding wood landmarks scattered among the trees; skip the colliding zones.
    local stumps = 0
    for _ = 1, (F.Stumps or 0) * 3 do
        if stumps >= (F.Stumps or 0) then
            break
        end
        local a, r, pos = pick(false)
        if not blockedForColliders(a, r) then
            stump(folder, pos)
            stumps += 1
        end
    end

    -- (h) Fallen LOGS: non-colliding ground detail (walk-through), anywhere in the ring.
    for _ = 1, (F.FallenLogs or 0) do
        local _, _, pos = pick(false)
        fallenLog(folder, pos, rng:NextNumber(0, math.pi * 2))
    end

    -- (i) FERNS: dense non-colliding fronds covering the forest floor (incl. near spawn for lushness).
    for i = 1, (F.Ferns or 0) do
        local _, _, pos = pick(i % 2 == 0)
        fern(folder, pos)
    end

    -- (j) MUSHROOMS: small non-colliding floor accents clustered near logs/roots.
    for _ = 1, (F.Mushrooms or 0) do
        local _, _, pos = pick(false)
        mushroom(folder, pos)
    end

    -- (k) FLOWER PATCHES: non-colliding color speckle across the meadow floor.
    for i = 1, (F.FlowerPatches or 0) do
        local _, _, pos = pick(i % 2 == 0)
        flowerPatch(folder, pos)
    end
end

-- ── PLATFORM TERRAIN: seeded blocky hills / mounds / stepped blocks per biome style (PROBLEM 1 fix).
-- Scatters capped, anchored, color-jittered mounds across each disc platform using WorldConfig.Terrain
-- numbers. Kept clear of: disc center (hub/spawn), SpawnPoint arc (~90 deg), BossArena (~270 deg), and
-- Elevator position. Uses polar scatter (inside disc edge inset). WALKABLE: blocks are short/stepped,
-- no holes, the disc remains the floor. Every call draws from the module-level seeded `rng` in sequence
-- (same seed -> same world). Tune height, density, and feel in WorldConfig.Terrain.
local function platformTerrain(folder, cfg)
    local T = WorldConfig.Terrain
    local L = WorldConfig.Levels
    local y = cfg.Y
    local rad = cfg.Radius
    local style = cfg.Style

    -- Jitter a base color by +/- T.ColorJitter per channel (deterministic via seeded rng).
    local function jitterColor(base)
        local j = T.ColorJitter
        return Color3.fromRGB(
            math.clamp(math.round(base.R * 255 + rng:NextNumber(-j, j)), 0, 255),
            math.clamp(math.round(base.G * 255 + rng:NextNumber(-j, j)), 0, 255),
            math.clamp(math.round(base.B * 255 + rng:NextNumber(-j, j)), 0, 255)
        )
    end

    -- Angles (radians) of the three clear zones.
    local spawnAngle = math.rad(90) -- SpawnPoint arc is centered here (+/- ~30 deg cleared)
    local arenaAngle = math.rad(270) -- BossArena centered here (+/- ~30 deg cleared)
    local elevAngle = math.rad(L.ElevatorAngleDeg) -- Elevator spot (+/- ~20 deg + radius guard)
    local elevR = L.ElevatorRadius
    local clearR = T.ClearRadius -- radial distance from disc center to keep flat
    -- PLOT FIX: on the BOTTOM platform (tier 1) the player bases ring at PlotRingRadius with enclosures
    -- spanning out to ~r+26. Widen the centre clear zone past the whole base ring so mounds never clip
    -- a base pad (Problem 2: bases sit on clean pads). Upper levels (no bases) keep the small 62 zone.
    if cfg.Tier == 1 then
        clearR = math.max(clearR, L.PlotRingRadius + 45)
    end

    -- Returns true if the polar position (a=angle rad, r=radius) is in a forbidden zone.
    local function isForbidden(a, r)
        -- inside the centre guard (hub / plot ring on level 1, or spawn corridor on all levels)
        if r < clearR then
            return true
        end
        -- angular guards: normalise angle difference into (-pi, pi] and check a 50-deg cone
        local function angDiff(x, ref)
            local d = (x - ref) % (math.pi * 2)
            if d > math.pi then
                d = d - math.pi * 2
            end
            return math.abs(d)
        end
        if angDiff(a, spawnAngle) < math.rad(50) then
            return true
        end -- spawn catchment arc
        if angDiff(a, arenaAngle) < math.rad(35) then
            return true
        end -- boss arena
        -- elevator: guard both the angular slot AND a circle around the car
        if angDiff(a, elevAngle) < math.rad(22) then
            return true
        end
        local ex = math.cos(elevAngle) * elevR
        local ez = math.sin(elevAngle) * elevR
        local px = math.cos(a) * r
        local pz = math.sin(a) * r
        if (px - ex) ^ 2 + (pz - ez) ^ 2 < 36 ^ 2 then
            return true
        end
        -- Keep mounds out of the dedicated leaderboard alcove + path (tier-1 meadow only).
        if cfg.Tier == 1 then
            local LB = WorldConfig.Leaderboard
            local lbAngle = math.rad(LB.AngleDeg)
            local function angDiff2(x, ref)
                local d = (x - ref) % (math.pi * 2)
                if d > math.pi then
                    d = d - math.pi * 2
                end
                return math.abs(d)
            end
            if angDiff2(a, lbAngle) < math.rad(LB.ClearHalfAngleDeg) then
                return true
            end
            local lx = math.cos(lbAngle) * LB.Radius
            local lz = math.sin(lbAngle) * LB.Radius
            if (px - lx) ^ 2 + (pz - lz) ^ 2 < LB.ClearRadius ^ 2 then
                return true
            end
        end
        return false
    end

    -- Per-style height/shape modifiers (feel tuned per biome identity).
    local hillCount = T.HillCount
    local hillMin = T.HillMinSize
    local hillMax = T.HillMaxSize
    local hMin, hMax = T.HillMinHeight, T.HillMaxHeight

    if style == "meadow" then
        -- gentle rolling mounds: short, wide, two-tier stacks
        hMax = math.floor(hMax * 0.55)
        hillMax = hillMax + 6
    elseif style == "shores" then
        -- low flat dunes: very shallow, wide
        hMax = math.floor(hMax * 0.38)
        hillMin = hillMin + 4
    elseif style == "swamp" then
        -- lumpy uneven ground: mixed small blocks, mid height
        hMax = math.floor(hMax * 0.65)
        hillMin = math.max(8, hillMin - 4)
    elseif style == "magma" then
        -- craggy crater feel: taller blocks concentrated toward one side, 2-tier
        hMax = math.floor(hMax * 1.0) -- full height range
        hillCount = hillCount + 2
    elseif style == "rift" or style == "void" then
        -- floating tiered cube clusters: some blocks lifted slightly above the disc
        hMax = math.floor(hMax * 0.7)
    end

    -- Scatter `hillCount` mounds. Each mound = a base block + (if tall enough) a smaller top tier.
    for _ = 1, hillCount do
        -- try up to 8 placements per hill, drop if none valid (keeps loop bounded)
        local placed = false
        for _ = 1, 8 do
            local a = rng:NextNumber(0, math.pi * 2)
            local r = rng:NextNumber(clearR + 4, rad - 24)
            if not isForbidden(a, r) then
                local px = math.cos(a) * r
                local pz = math.sin(a) * r
                local baseW = rng:NextNumber(hillMin, hillMax)
                local baseD = rng:NextNumber(hillMin, hillMax)
                local h = rng:NextNumber(hMin, hMax)
                local baseColor = jitterColor(cfg.GroundColor)
                local accentColor = jitterColor(cfg.Accent)

                -- Style-specific floating offset (rift/void cluster hovers slightly above disc).
                local floatDy = (style == "rift" or style == "void") and rng:NextNumber(0, 6) or 0

                -- Bottom tier: broad base mound sitting on the disc surface.
                part({
                    Size = Vector3.new(baseW, h, baseD),
                    Position = Vector3.new(px, y + h / 2 + floatDy, pz),
                    Color = baseColor,
                    Material = cfg.GroundMaterial,
                }, folder)

                -- Top tier: a smaller accent block on mounds taller than ~8 studs (stepped look).
                if h > 8 then
                    local topW = baseW * rng:NextNumber(0.42, 0.65)
                    local topD = baseD * rng:NextNumber(0.42, 0.65)
                    local topH = rng:NextNumber(hMin, math.max(hMin + 1, h * 0.5))
                    part({
                        Size = Vector3.new(topW, topH, topD),
                        Position = Vector3.new(
                            px + rng:NextNumber(-3, 3),
                            y + h + topH / 2 + floatDy,
                            pz + rng:NextNumber(-3, 3)
                        ),
                        Color = (rng:NextNumber() > 0.5) and accentColor
                            or jitterColor(cfg.GroundColor),
                        Material = cfg.GroundMaterial,
                    }, folder)
                end

                placed = true
                break
            end
        end
        if not placed then
            -- consume the same number of rng calls as a skipped placement would have to keep the
            -- remaining scatter deterministic (4 calls: angle, radius, baseW, baseD hidden from loop)
            rng:NextNumber()
            rng:NextNumber()
            rng:NextNumber()
            rng:NextNumber()
        end
    end

    -- Scatter a handful of blocky accent rocks (smaller, rounder cubes, color-jittered).
    -- Re-uses WorldConfig.Terrain.RockCount. Kept well within the same forbidden zones.
    for _ = 1, T.RockCount do
        local placed = false
        for _ = 1, 6 do
            local a = rng:NextNumber(0, math.pi * 2)
            local r = rng:NextNumber(clearR + 4, rad - 18)
            if not isForbidden(a, r) then
                local s = rng:NextNumber(4, 10)
                part({
                    Size = Vector3.new(s, s * 0.7, s),
                    Position = Vector3.new(math.cos(a) * r, y + s * 0.35, math.sin(a) * r),
                    Color = jitterColor(cfg.Accent),
                    Material = Enum.Material.Slate,
                }, folder)
                placed = true
                break
            end
        end
        if not placed then
            rng:NextNumber()
            rng:NextNumber()
            rng:NextNumber()
        end
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
    -- The first biome (the meadow) skips the generic platformProps, so give it richer CAPPED foliage
    -- cover (forests/bushes/grass/hedges/rocks) for the wild brainrots to roam + hide in.
    if cfg.Style == "meadow" then
        meadowFoliage(folder, cfg)
    end
    -- TERRAIN FIX: add blocky elevation + color-jittered ground to every platform (levels 1..N).
    -- On level 1 the centre guard (clearR=62) naturally keeps hills away from the hub/plot ring.
    -- On upper levels the guard keeps hills away from the spawn arc, boss arena, and elevator.
    platformTerrain(folder, cfg)
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
    buildLeaderboardPlaza(worldFolder) -- the dedicated leaderboard dais + path in its own -X alcove
    buildPlatforms(worldFolder) -- the stacked floating biome platforms (levels 2..N) + per-level decor
    buildElevatorShaft(worldFolder)
    buildIslands(worldFolder)
end

return WorldBuilder
