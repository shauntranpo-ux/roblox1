-- BrainrotBillboard: the SINGLE camera-facing 2D sprite/card builder for a brainrot's WORLD look. A
-- BillboardGui always faces every player's camera, so a brainrot reads as a flat "2D brainrot" (the
-- classic look) -- never a 3D block. Shared by PLACED units (BrainrotService), WILD spawns (WildCatch),
-- and SHARED rare events (SharedEventService) so they all use ONE implementation (no fork). Pure
-- Instance construction -> safe to call on the server OR the client. A missing sprite asset falls back
-- to a clean rarity-tinted placeholder card (graceful, never errors), so the game is fully playable
-- before any art is supplied.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))

local BrainrotBillboard = {}

local INK = Color3.fromRGB(20, 16, 30)
local WHITE = Color3.fromRGB(255, 255, 255)

-- The 2D SPRITE asset id for a species: an explicit per-species `SpriteId` override (a world-only
-- image), else the shared `IconId` (the same image used on the UI cards), else 0 -> no art yet, so a
-- rarity-tinted placeholder card is shown. DEV SWAP POINT: paste the decal/image number in the roster.
function BrainrotBillboard.spriteId(def)
    if type(def) ~= "table" then
        return 0
    end
    local s = def.SpriteId
    if type(s) == "number" and s ~= 0 then
        return s
    end
    local i = def.IconId
    if type(i) == "number" and i ~= 0 then
        return i
    end
    return 0
end

-- Attaches a camera-facing 2D billboard to `anchor` (a Part), replacing any prior one. opts:
--   size (UDim2, default 5x6)            -- billboard footprint in studs
--   offset (Vector3, default 0,1.5,0)    -- world-space offset above the anchor
--   maxDistance (number, default 130)    -- render-cull distance (perf)
--   alwaysOnTop (bool, default false)
--   tint (Color3)                        -- placeholder-card fill (defaults to the rarity color)
--   name (string|nil)                    -- placeholder-card label (nil = no text)
--   mutationColor (Color3|nil)           -- a colored outline (mutation read)
--   forcePlaceholder (bool)              -- always the card even if a sprite exists (hidden-identity events)
-- Returns the BillboardGui (named "Art"); it is parented to `anchor`, so destroying the anchor on
-- catch/despawn/leave cleans it up automatically (no leaked GUIs).
function BrainrotBillboard.attach(anchor, def, opts)
    opts = opts or {}
    local existing = anchor:FindFirstChild("Art")
    if existing ~= nil then
        existing:Destroy()
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Art"
    billboard.Size = opts.size or UDim2.fromScale(5, 6)
    billboard.StudsOffsetWorldSpace = opts.offset or Vector3.new(0, 1.5, 0)
    billboard.LightInfluence = 0
    billboard.MaxDistance = opts.maxDistance or 130
    billboard.AlwaysOnTop = opts.alwaysOnTop == true
    billboard.Adornee = anchor
    billboard.Parent = anchor

    local sprite = (opts.forcePlaceholder == true) and 0 or BrainrotBillboard.spriteId(def)
    if sprite ~= 0 then
        -- Real 2D sprite: a flat picture that always faces the camera.
        local image = Instance.new("ImageLabel")
        image.Size = UDim2.fromScale(1, 1)
        image.BackgroundTransparency = 1
        image.Image = "rbxassetid://" .. tostring(sprite)
        image.ScaleType = Enum.ScaleType.Fit
        image.Parent = billboard
        if opts.mutationColor ~= nil then
            local stroke = Instance.new("UIStroke")
            stroke.Color = opts.mutationColor
            stroke.Thickness = 3
            stroke.Transparency = 0.1
            stroke.Parent = image
        end
        return billboard
    end

    -- Placeholder: a rounded tinted card (graceful fallback / hidden-identity mystery). Reads as a flat
    -- "2D brainrot" card, never a 3D cube.
    local tint = opts.tint
        or (type(def) == "table" and def.Rarity ~= nil and Rarity.Get(def.Rarity).Color)
        or Color3.fromRGB(200, 200, 200)
    local card = Instance.new("Frame")
    card.Size = UDim2.fromScale(1, 1)
    card.BackgroundColor3 = tint
    card.BackgroundTransparency = 0.05
    card.BorderSizePixel = 0
    card.Parent = billboard
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = card
    -- Card outline stays INK (the mutation reads via the tinted background); the mutation OUTLINE is on
    -- the sprite/art path only -- matching the original placed-unit placeholder card exactly.
    local stroke = Instance.new("UIStroke")
    stroke.Color = INK
    stroke.Thickness = 3
    stroke.Parent = card

    local gloss = Instance.new("Frame")
    gloss.Size = UDim2.fromScale(1, 0.42)
    gloss.BackgroundColor3 = WHITE
    gloss.BackgroundTransparency = 0.78
    gloss.BorderSizePixel = 0
    gloss.ZIndex = 0
    gloss.Parent = card
    local glossCorner = Instance.new("UICorner")
    glossCorner.CornerRadius = UDim.new(0, 16)
    glossCorner.Parent = gloss

    if opts.name ~= nil then
        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(0.86, 0.86)
        label.Position = UDim2.fromScale(0.07, 0.07)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.FredokaOne
        label.Text = tostring(opts.name)
        label.TextColor3 = WHITE
        label.TextStrokeColor3 = INK
        label.TextStrokeTransparency = 0
        label.TextScaled = true
        label.Parent = card
    end
    return billboard
end

return BrainrotBillboard
