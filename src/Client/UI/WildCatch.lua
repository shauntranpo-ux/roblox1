-- WildCatch (M10.1): renders the LOCAL player's instanced wild spawns (the server streams them via
-- WildUpdate; only the owner sees their own) + a "Catch" ProximityPrompt (reuses the steal hold
-- indicator), lerps their server-driven movement, shows a catch / "got away" toast, and draws an
-- on-screen direction MARKER for reveal-perk-revealed rare spawns. The client sends catch INTENT only
-- (the spawn id); the server owns the registry + validates + mints. It NEVER spawns a unit.
--
-- TUTORIAL BUBBLE (T3): for the player's first TUTORIAL_CATCHES successful catches a screen-space
-- bubble (lower-center, glossy FredokaOne style) reads "Tap the brainrot to catch it!" whenever a
-- catchable is in range. After TUTORIAL_CATCHES catches the bubble is permanently suppressed.
-- Catch count is tracked locally: each WildUpdate despawn + Caught=true increments catchCount.
--
-- TARGET INDICATOR (T3): the old heavy default Roblox [E] ProximityPrompt card is replaced with a
-- Custom-style prompt (hidden native UI) plus a slim glossy BillboardGui chevron ("▼") above the
-- creature that pulses while in range. The existing name label + rarity color are preserved.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Notifications = require(script.Parent.Notifications)
local Effects = require(script.Parent.Effects)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))

local WildCatch = {}

local TUTORIAL_CATCHES = 3

local remotes = nil
local gui = nil
local models = {} -- [id] = { part, target(Vector3), rarity, revealed, name, marker, chevron }

local catchCount = 0 -- client-local; incremented on each confirmed catch (despawn + Caught=true)
local tutorialBubble = nil -- the ScreenGui bubble frame (created once in mount)
local bubbleScale = nil -- UIScale inside tutorialBubble for pop-in/out animation
local anyInRange = false -- true while at least one CatchPrompt is in range (drives bubble visibility)
local activeChevronId = nil -- id of the model whose chevron is currently the active tap target

-- ── Tutorial bubble construction (created once; shown/hidden based on range + catchCount) ──────
local function makeTutorialBubble(parent)
    local frame = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -220), -- above the TAP button panel
        Size = UDim2.fromOffset(280, 52),
        BackgroundColor3 = Theme.Colors.Accent,
        BackgroundTransparency = 0.22,
        Visible = false,
        Parent = parent,
    }, {
        Builder.corner(Theme.Radius.Card),
        Builder.create("UIStroke", {
            Color = Theme.Colors.White,
            Thickness = 2.5,
            Transparency = 0.1,
        }),
    })
    Builder.glossify(frame, "Default")
    -- UIScale drives the pop-in / pop-out; starts at 0.6 (will be snapped before show).
    local uiScale = Instance.new("UIScale")
    uiScale.Scale = 0.6
    uiScale.Parent = frame
    bubbleScale = uiScale
    local label = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "Tap the brainrot to catch it!",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Parent = frame,
    }, {
        Builder.padding(8),
        Builder.create("UITextSizeConstraint", { MaxTextSize = 20 }),
    })
    Builder.styleText(label, { keepColor = true })
    return frame
end

-- Animate the bubble in (Back ease, ~0.2s) or out (shrink + fade, ~0.15s).
local function bubbleShow(on)
    if tutorialBubble == nil or bubbleScale == nil then
        return
    end
    if on then
        tutorialBubble.Visible = true
        tutorialBubble.BackgroundTransparency = 1
        bubbleScale.Scale = 0.6
        TweenService:Create(
            bubbleScale,
            TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }
        ):Play()
        TweenService:Create(
            tutorialBubble,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.22 }
        ):Play()
    else
        local scaleOut = TweenService:Create(
            bubbleScale,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Scale = 0.7 }
        )
        TweenService:Create(
            tutorialBubble,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()
        scaleOut:Play()
        scaleOut.Completed:Connect(function()
            if tutorialBubble ~= nil then
                tutorialBubble.Visible = false
                tutorialBubble.BackgroundTransparency = 0.22
                bubbleScale.Scale = 0.6
            end
        end)
    end
end

local function refreshTutorialBubble()
    if tutorialBubble == nil then
        return
    end
    local shouldShow = catchCount < TUTORIAL_CATCHES and anyInRange
    -- Guard: only animate when the visible state actually changes.
    local isVisible = tutorialBubble.Visible
    if isVisible == shouldShow then
        return
    end
    bubbleShow(shouldShow)
end

-- Pulse the bubble and/or chevron by scale 1 -> 1.15 -> 1 (~0.12s) to react to a tap.
local function pulseTapReact()
    if tutorialBubble ~= nil and tutorialBubble.Visible and bubbleScale ~= nil then
        local t1 = TweenService:Create(
            bubbleScale,
            TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Scale = 1.15 }
        )
        t1:Play()
        t1.Completed:Connect(function()
            TweenService:Create(
                bubbleScale,
                TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { Scale = 1 }
            ):Play()
        end)
    end
    -- Pulse the active chevron's billboard if one is in range.
    if activeChevronId ~= nil and models[activeChevronId] ~= nil then
        local chevron = models[activeChevronId].chevron
        if chevron ~= nil then
            local label = chevron:FindFirstChildWhichIsA("TextLabel")
            if label ~= nil then
                local base = label.TextSize ~= 0 and label.TextSize or nil
                local curSize = chevron.Size
                local bigSize = UDim2.fromOffset(curSize.X.Offset * 1.15, curSize.Y.Offset * 1.15)
                local t2 = TweenService:Create(
                    chevron,
                    TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { Size = bigSize }
                )
                t2:Play()
                t2.Completed:Connect(function()
                    TweenService
                        :Create(
                            chevron,
                            TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                            { Size = curSize }
                        )
                        :Play()
                end)
                _ = base -- suppress unused warning
            end
        end
    end
end

-- ── World-space chevron indicator above a creature (replaces the heavy [E] card) ───────────────
-- Returns the BillboardGui (parented to `part`).
local function makeChevron(part, rarityColor)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "CatchChevron"
    billboard.Size = UDim2.fromOffset(44, 32)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
    billboard.AlwaysOnTop = false
    billboard.MaxDistance = 60
    billboard.Adornee = part
    billboard.Parent = part

    local chevronLabel = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "▼",
        TextColor3 = rarityColor,
        TextScaled = true,
        Parent = billboard,
    })
    Builder.styleText(chevronLabel, { keepColor = true })

    -- Gentle bob: oscillate Y offset so the chevron floats above the creature.
    TweenService:Create(
        billboard,
        TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { StudsOffsetWorldSpace = Vector3.new(0, 5.0, 0) }
    ):Play()

    return billboard
end

-- ── Capture screen-anchor before despawn (for Effects.burst) ────────────────────────────────────
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

    -- Subtle name label above the creature.
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
    -- SUBTLE INDICATOR: suppress the default Roblox [E] card; our chevron + name label are the cue.
    prompt.Style = Enum.ProximityPromptStyle.Custom
    prompt:SetAttribute("Need", tonumber(payload.Need) or 6) -- taps to catch (TapInput shows the meter)
    prompt:SetAttribute("SpawnId", tostring(payload.Id)) -- TapInput reads this as the catch TargetId
    prompt.Parent = part

    -- Floating chevron indicator above the creature (visible at close range; the cue to tap).
    local chevron = makeChevron(part, Rarity.Get(payload.Rarity).Color)

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
        chevron = chevron,
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
                -- Tutorial: increment client-local catch counter on each confirmed catch.
                catchCount += 1
                refreshTutorialBubble()
                -- CHEVRON POP-OUT: quick scale-up + fade before the model is destroyed.
                if model.chevron ~= nil then
                    local chev = model.chevron
                    local bigSize =
                        UDim2.fromOffset(chev.Size.X.Offset * 1.5, chev.Size.Y.Offset * 1.5)
                    TweenService
                        :Create(
                            chev,
                            TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                            { Size = bigSize }
                        )
                        :Play()
                    TweenService
                        :Create(
                            chev,
                            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                            { StudsOffsetWorldSpace = Vector3.new(0, 7, 0) }
                        )
                        :Play()
                end
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

    -- Build the tutorial bubble (hidden initially; shown when in range + catchCount < TUTORIAL_CATCHES).
    tutorialBubble = makeTutorialBubble(gui)

    remotes.WildUpdate.OnClientEvent:Connect(function(payload)
        if typeof(payload) == "table" then
            WildCatch.onUpdate(payload)
        end
    end)

    -- Track CatchPrompt in-range state for the tutorial bubble. PromptShown/Hidden fire on this client.
    -- Also track which spawn is the active tap target so the chevron pulse knows which model to pulse.
    local inRangeCount = 0
    ProximityPromptService.PromptShown:Connect(function(prompt)
        if prompt.Name == "CatchPrompt" then
            inRangeCount += 1
            anyInRange = inRangeCount > 0
            -- Last-shown prompt wins as the active chevron target (mirrors TapInput targeting).
            activeChevronId = prompt:GetAttribute("SpawnId")
            refreshTutorialBubble()
        end
    end)
    ProximityPromptService.PromptHidden:Connect(function(prompt)
        if prompt.Name == "CatchPrompt" then
            inRangeCount = math.max(0, inRangeCount - 1)
            anyInRange = inRangeCount > 0
            if activeChevronId == prompt:GetAttribute("SpawnId") then
                activeChevronId = nil
            end
            refreshTutorialBubble()
        end
    end)

    -- TAP REACT: pulse the bubble + active chevron on each registered catch tap.
    ProximityPromptService.PromptTriggered:Connect(function(prompt)
        if prompt.Name == "CatchPrompt" then
            pulseTapReact()
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
