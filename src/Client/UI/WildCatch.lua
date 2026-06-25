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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))

local WildCatch = {}

local remotes = nil
local gui = nil
local models = {} -- [id] = { part, target(Vector3), rarity, revealed, marker(TextLabel) }

local function doCatch(id)
    local ok, result = pcall(function()
        return remotes.WildCatch:InvokeServer(id)
    end)
    if not ok or type(result) ~= "table" then
        return
    end
    if result.Result == "Success" then
        local mut = (result.Mutation ~= nil) and (tostring(result.Mutation) .. " ") or ""
        Notifications.show("success", "Caught a " .. mut .. tostring(result.Name) .. "!")
    elseif result.Message ~= nil then
        Notifications.show("error", tostring(result.Message))
    end
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

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.fromScale(4, 1.1)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
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
    prompt.ActionText = "Catch"
    prompt.ObjectText = tostring(payload.Name)
    prompt.HoldDuration = math.max(0.3, tonumber(payload.Hold) or 1.5)
    prompt.MaxActivationDistance = math.max(4, tonumber(payload.Range) or 12)
    prompt.RequiresLineOfSight = false
    prompt.Parent = part
    prompt.Triggered:Connect(function()
        doCatch(payload.Id)
    end)

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
