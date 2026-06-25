-- WorldStyler (VM-THEME): applies the palette + a consistent voxel finish (Color / Material /
-- CastShadow) to PARTS the developer TAGS in Studio via CollectionService. It creates NO geometry --
-- it only DRESSES what's tagged, so as you build + tag voxel parts they auto-adopt the look. The tag
-- -> finish map lives in Theme.WorldTags (add a tag entry to style a new tag). No-ops cleanly when
-- nothing is tagged. Client-side (local visual only -- changes no server state, no gameplay).
--
-- TAG YOUR PARTS in Studio with the tag names in Theme.WorldTags (Grass / Sand / Path / Water / Wood
-- / Stone). The honeycomb shield-wall texture is applied separately by the shield-wall UI binder.

local CollectionService = game:GetService("CollectionService")

local Theme = require(script.Parent.Theme)

local WorldStyler = {}

local function styleOne(instance, cfg)
    if not instance:IsA("BasePart") then
        return
    end
    pcall(function()
        instance.Color = cfg.Color
        instance.Material = cfg.Material
        if cfg.Transparency ~= nil then
            instance.Transparency = cfg.Transparency
        end
        instance.CastShadow = true
    end)
end

function WorldStyler.mount(_context)
    for tag, cfg in pairs(Theme.WorldTags) do
        -- Style what's already tagged...
        for _, instance in ipairs(CollectionService:GetTagged(tag)) do
            styleOne(instance, cfg)
        end
        -- ...and anything tagged later (as the dev builds + tags more geometry).
        CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
            styleOne(instance, cfg)
        end)
    end
end

return WorldStyler
