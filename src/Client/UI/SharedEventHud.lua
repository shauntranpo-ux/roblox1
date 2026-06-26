-- SharedEventHud (M10.3): the server-wide MYSTERY-spawn alert + on-screen marker + outcome, driven by
-- SharedEvent broadcasts. The client renders ONLY -- it never spawns the entity or names the winner;
-- the catch fires from the server-owned model's ProximityPrompt. Hidden identity until the win. Drama
-- (a flash/sound) scales with the hidden tier without revealing it. Reuses Banner + Effects (pooled).
-- FUNCTIONAL drama; full reveal juice comes in M10.4.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Banner = require(script.Parent.Banner)
local Effects = require(script.Parent.Effects)
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))

local SharedEventHud = {}

local gui = nil
local marker = nil
local markerPos = nil
local active = false

function SharedEventHud.onUpdate(payload)
    local kind = payload.Kind
    if kind == "spawn" then
        local where = tostring(payload.Biome or "the world")
        Banner.show("A <hl>MYSTERY BRAINROT</hl> appeared in " .. where .. "!", 6)
        markerPos = payload.Pos
        active = true
        if marker ~= nil then
            marker.Visible = true
        end
        -- Drama scales the flash/sound with the (hidden) tier -- reveals nothing about identity.
        local drama = tonumber(payload.Drama) or 1
        if drama >= 2 then
            Effects.flash(Theme.Colors.Gold)
        end
        Effects.playSfx("milestone")
    elseif kind == "update" then
        if payload.Pos ~= nil then
            markerPos = payload.Pos
        end
    elseif kind == "caught" then
        Banner.show(
            "<hl>"
                .. tostring(payload.Winner)
                .. "</hl> caught the "
                .. tostring(payload.Name)
                .. "!",
            5
        )
        -- The WINNER (only) gets the big capture juice (the catch fired server-side, so they don't go
        -- through the instanced catch path). Everyone else just sees the banner.
        if payload.Winner == Players.LocalPlayer.DisplayName then
            local color = (payload.Rarity ~= nil) and Rarity.Get(payload.Rarity).Color
                or Theme.Colors.Gold
            Effects.burst(UDim2.fromScale(0.5, 0.4), color, 20)
            Effects.flash(color)
            Effects.playSfx("catch_rare")
        end
        active = false
        markerPos = nil
        if marker ~= nil then
            marker.Visible = false
        end
    elseif kind == "escape" then
        Banner.show("The mystery brainrot <hl>got away</hl>...", 4)
        active = false
        markerPos = nil
        if marker ~= nil then
            marker.Visible = false
        end
    elseif kind == "gone" then
        active = false
        markerPos = nil
        if marker ~= nil then
            marker.Visible = false
        end
    end
end

function SharedEventHud.mount(context)
    local player = context.player
    gui = Builder.screenGui("SharedEventHud", player:WaitForChild("PlayerGui"), true)
    gui.DisplayOrder = 8

    marker = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(170, 28),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.2,
        Text = "▾ MYSTERY",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Visible = false,
        Parent = gui,
    }, {
        Builder.corner(UDim.new(1, 0)),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.Accent, Thickness = 2, Transparency = 0.3 }
        ),
    })
    Builder.styleText(marker, { keepColor = true })

    context.remotes.SharedEvent.OnClientEvent:Connect(function(payload)
        if typeof(payload) == "table" then
            SharedEventHud.onUpdate(payload)
        end
    end)

    RunService.RenderStepped:Connect(function()
        if not active or markerPos == nil or marker == nil then
            return
        end
        local camera = Workspace.CurrentCamera
        if camera == nil then
            return
        end
        local screen = camera:WorldToViewportPoint(markerPos)
        local v = camera.ViewportSize
        local x = screen.Z <= 0 and (v.X - screen.X) or screen.X
        local y = screen.Z <= 0 and (v.Y - 60) or screen.Y
        marker.Position = UDim2.fromOffset(math.clamp(x, 40, v.X - 40), math.clamp(y, 70, v.Y - 50))
        marker.Visible = true
    end)
end

return SharedEventHud
