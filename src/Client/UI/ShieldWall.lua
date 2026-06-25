-- ShieldWall (VM-THEME): DRESSES + BINDS UI onto a base shield-wall part the developer hand-builds +
-- TAGS in Studio with "ShieldWall". It builds NO geometry. For each tagged wall part it: applies the
-- shield look (Color / Material / Transparency + a hex honeycomb Texture IF an asset id is supplied),
-- and -- only on the LOCAL player's own wall (the part's OwnerUserId attribute == our UserId) -- adds a
-- BillboardGui shield bar bound to the live protection value (ShieldSeconds / ShieldMax). Guards
-- cleanly: no tagged wall -> no-op; no honeycomb id -> skip the texture; no OwnerUserId -> dress only.
--
-- DEV: tag your base's shield-wall part "ShieldWall" and set its OwnerUserId attribute to the plot's
-- owner (or have PlotService set it) so each client binds the bar to its own base.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local ShieldWall = {}

local TAG = "ShieldWall"

local function attachBar(part)
    local localPlayer = Players.LocalPlayer
    if part:GetAttribute("OwnerUserId") ~= localPlayer.UserId then
        return -- not our wall -> dress only (no bar bound to our shield)
    end
    if part:FindFirstChild("ShieldUI") ~= nil then
        return
    end

    local billboard = Builder.create("BillboardGui", {
        Name = "ShieldUI",
        Size = UDim2.fromScale(6, 1.2),
        StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2, 0),
        AlwaysOnTop = true,
        MaxDistance = 160,
        Adornee = part,
        Parent = part,
    })
    local icon = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromScale(0.18, 1),
        BackgroundTransparency = 1,
        Text = "🛡",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Parent = billboard,
    })
    Builder.styleText(icon, { keepColor = true })
    local _, set = Builder.statBar({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromScale(0.8, 0.7),
        fillTop = Theme.Colors.HpFill,
        fillBottom = Theme.Colors.HpFillDark,
        Parent = billboard,
    })

    local function refresh()
        local cur = localPlayer:GetAttribute("ShieldSeconds") or 0
        local max = localPlayer:GetAttribute("ShieldMax") or Theme.Hud.ShieldDisplayMax
        set(cur, max, math.floor(cur) .. " / " .. math.floor(max))
    end
    refresh()
    localPlayer:GetAttributeChangedSignal("ShieldSeconds"):Connect(refresh)
    localPlayer:GetAttributeChangedSignal("ShieldMax"):Connect(refresh)
end

local function dress(part)
    if not part:IsA("BasePart") then
        return
    end
    pcall(function()
        part.Color = Theme.Colors.XpFill
        part.Material = Enum.Material.ForceField
        part.Transparency = 0.4
        part.CastShadow = false
    end)
    -- Honeycomb hex texture: only if the dev supplied an asset id (else skip cleanly).
    if Theme.Assets.HoneycombTexture ~= 0 and part:FindFirstChild("Honeycomb") == nil then
        for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
            local tex = Instance.new("Texture")
            tex.Name = "Honeycomb"
            tex.Texture = "rbxassetid://" .. tostring(Theme.Assets.HoneycombTexture)
            tex.StudsPerTileU = 4
            tex.StudsPerTileV = 4
            tex.Transparency = 0.2
            tex.Face = face
            tex.Parent = part
        end
    end
    attachBar(part)
end

function ShieldWall.mount(_context)
    for _, part in ipairs(CollectionService:GetTagged(TAG)) do
        dress(part)
    end
    CollectionService:GetInstanceAddedSignal(TAG):Connect(dress)
end

return ShieldWall
