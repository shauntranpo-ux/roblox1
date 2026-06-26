-- WildCatch (M10.1): renders the LOCAL player's instanced wild spawns (the server streams them via
-- WildUpdate; only the owner sees their own) + a "Catch" ProximityPrompt (reuses the steal hold
-- indicator), lerps their server-driven movement, shows a catch / "got away" toast, and draws an
-- on-screen direction MARKER for reveal-perk-revealed rare spawns. The client sends catch INTENT only
-- (the spawn id); the server owns the registry + validates + mints. It NEVER spawns a unit.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Notifications = require(script.Parent.Notifications)
local Effects = require(script.Parent.Effects)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))

local WildCatch = {}

local remotes = nil
local gui = nil
local models = {} -- [id] = { part, target(Vector3), rarity, revealed, marker(TextLabel) }

-- M10.4 CATCH JUICE: a rarity-scaled burst + flash + sound on a successful catch (pooled via
-- Effects; silent/graceful if no sound asset). Captures the creature's screen anchor BEFORE the
-- server despawns it.
local function captureAnchor(model)
    if model == nil or model.part == nil then
        return UDim2.fromScale(0.5, 0.5)
    end
    local camera = Workspace.CurrentCamera
    if camera == nil then
        return UDim2.fromScale(0.5, 0.5)
    end
    local sp = camera:WorldToViewportPoint(model.part.Position)
    local v = camera.ViewportSize
    if sp.Z <= 0 or v.X == 0 then
        return UDim2.fromScale(0.5, 0.4)
    end
    return UDim2.fromScale(math.clamp(sp.X / v.X, 0, 1), math.clamp(sp.Y / v.Y, 0, 1))
end

local function makeModel(payload)
    local part = Instance.new("Part")
    part.Name = "Wild_" .. tostring(payload.Id)
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.new(3, 3, 3)
    part.Color = Rarity.Get(payload.Rarity).Color
    part.Material = Enum.Material.Neon
    part.Transparency = 0.05
    part.CFrame = CFrame.new(payload.Pos)

    -- Oversized invisible hitbox (1.5x the visual part) so small targets are easy to tap on both
    -- PC and mobile. TapInput.tapTargetAt() raycasts against this and reads TapKind/TapTargetId
    -- to confirm the tap hit THIS creature. CanQuery=true so the raycast finds it; CanCollide=false
    -- so it never obstructs the player. Anchored alongside the visual part; both lerp each frame.
    local hitbox = Instance.new("Part")
    hitbox.Name = "TapHitbox"
    hitbox.Anchored = true
    hitbox.CanCollide = false
    hitbox.CanQuery = true
    hitbox.Size = Vector3.new(4.5, 4.5, 4.5) -- 1.5x the 3-stud visual part
    hitbox.Transparency = 1
    hitbox.CFrame = part.CFrame
    hitbox:SetAttribute("TapKind", "catch")
    hitbox:SetAttribute("TapTargetId", tostring(payload.Id))
    hitbox.Parent = part -- parented to part so it moves with it; WildCatch lerps the part each frame

    -- Subtle name label above the creature (replaced the heavy billboard card from earlier).
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.fromScale(4, 1.1)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = false
    billboard.MaxDistance = 140
    billboard.Adornee = part
    billboard.Parent = part
    local nameLabel = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = tostring(payload.Name),
        TextColor3 = Rarity.Get(payload.Rarity).Color,
        TextScaled = true,
        Parent = billboard,
    })
    Builder.styleText(nameLabel, { keepColor = true })

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "CatchPrompt"
    prompt.ActionText = "Tap to Catch"
    prompt.ObjectText = tostring(payload.Name)
    prompt.HoldDuration = 0 -- TAP-TO-PROGRESS: target marker only; catching fills by TAPPING (TapInput)
    prompt.MaxActivationDistance = math.max(4, tonumber(payload.Range) or 12)
    prompt.RequiresLineOfSight = false
    prompt:SetAttribute("Need", tonumber(payload.Need) or 6) -- taps to catch (TapInput shows the meter)
    prompt:SetAttribute("SpawnId", tostring(payload.Id)) -- TapInput reads this as the catch TargetId
    prompt.Parent = part

    part.Parent = Workspace

    local marker = nil
    if payload.Revealed then
        marker = Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(150, 26),
            BackgroundColor3 = Rarity.Get(payload.Rarity).Color,
            BackgroundTransparency = 0.3,
            Text = "★ " .. tostring(payload.Name),
            TextColor3 = Theme.Colors.White,
            TextScaled = true,
            Visible = false,
            Parent = gui,
        }, { Builder.corner(UDim.new(0, 8)) })
        Builder.styleText(marker, { keepColor = true })
    end

    return {
        part = part,
        target = payload.Pos,
        rarity = payload.Rarity,
        revealed = payload.Revealed,
        name = payload.Name,
        marker = marker,
    }
end

local function removeModel(id)
    local model = models[id]
    if model == nil then
        return
    end
    if model.part ~= nil then
        model.part:Destroy()
    end
    if model.marker ~= nil then
        model.marker:Destroy()
    end
    models[id] = nil
end

function WildCatch.onUpdate(payload)
    local kind = payload.Kind
    if kind == "spawn" then
        if models[payload.Id] == nil then
            models[payload.Id] = makeModel(payload)
        end
    elseif kind == "move" then
        local model = models[payload.Id]
        if model ~= nil and payload.Pos ~= nil then
            model.target = payload.Pos -- (reveal state is set at spawn; markers track via RenderStepped)
        end
    elseif kind == "despawn" then
        local model = models[payload.Id]
        if model ~= nil then
            if payload.Caught == true then
                -- CATCH JUICE (the tap meter filled + the server minted): rarity-scaled burst + flash +
                -- sound + a "Caught!" toast. Anchor captured before the model is destroyed below.
                local info = Rarity.Get(model.rarity)
                Effects.burst(captureAnchor(model), info.Color, math.min(20, 8 + info.Order * 3))
                Effects.flash(info.Color)
                Effects.playSfx(info.Order >= 4 and "catch_rare" or "catch")
                Notifications.show(
                    "success",
                    "Caught a " .. tostring(model.name or "brainrot") .. "!"
                )
            elseif Rarity.Get(model.rarity).Order >= 4 then
                -- FLEE cue: a rare that escaped uncaught gives a small "got away" sting.
                Effects.playSfx("flee")
                Notifications.show("error", "A rare brainrot got away...")
            end
        end
        removeModel(payload.Id)
    end
end

function WildCatch.mount(context)
    remotes = context.remotes
    local player = context.player or Players.LocalPlayer
    gui = Builder.screenGui("WildCatch", player:WaitForChild("PlayerGui"), true)
    gui.DisplayOrder = 6

    remotes.WildUpdate.OnClientEvent:Connect(function(payload)
        if typeof(payload) == "table" then
            WildCatch.onUpdate(payload)
        end
    end)

    -- Lerp models toward their server position + keep reveal markers pointing at them (screen-edge).
    RunService.RenderStepped:Connect(function(dt)
        local camera = Workspace.CurrentCamera
        for _, model in pairs(models) do
            if model.part ~= nil and model.target ~= nil then
                model.part.CFrame =
                    model.part.CFrame:Lerp(CFrame.new(model.target), math.min(1, dt * 10))
            end
            if model.marker ~= nil and camera ~= nil and model.part ~= nil then
                local screen = camera:WorldToViewportPoint(model.part.Position)
                local v = camera.ViewportSize
                local x = screen.Z <= 0 and (v.X - screen.X) or screen.X
                local y = screen.Z <= 0 and (v.Y - 60) or screen.Y
                model.marker.Position =
                    UDim2.fromOffset(math.clamp(x, 40, v.X - 40), math.clamp(y, 70, v.Y - 50))
                model.marker.Visible = true
            end
        end
    end)
end

return WildCatch
