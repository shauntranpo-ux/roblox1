-- TapInput (tap-to-progress): the ONE shared client module behind uncapped tapping for catch/steal/
-- combat. It uses each system's EXISTING ProximityPrompt as the TARGET (PromptShown/Hidden pick the
-- active interaction uniformly), counts every tap LOCALLY with INSTANT juice (no hold bar, no throttle),
-- and flushes the accumulated count to the server every TapConfig.BatchInterval. The server is
-- authoritative on progress + completion (it clamps to a human-max rate); this client is OPTIMISTIC and
-- reconciles to the server's TapUpdate, so it never shows a false completion or sticks at 99%.
--
-- TAP SURFACES (all count once, never double): a big on-screen TAP button (mobile), tap-anywhere on the
-- screen WHILE the tap lands on the target's hitbox (raycast-gated so random mis-taps don't progress),
-- and the prompt's own keybind/touch button (ProximityPromptService.PromptTriggered). Mash any of them.
--
-- HITBOX GATING: screen taps (InputBegan) are raycast through tapTargetAt(screenPos). It walks the hit
-- part's ancestry for a TapHitbox part (named "TapHitbox", carrying TapKind/TapTargetId attributes
-- placed by WildSpawnService + BossService) OR a StealPrompt (steal units use the existing model part).
-- Only fires onTap() when the raycast resolves to the CURRENT active target.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)

local TapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TapConfig"))

local TapInput = {}

local remotes = nil
local gui = nil
local panel = nil -- the bottom tap UI (button + meter), shown only while a target is active
local meterBg = nil
local meterSet = nil -- progressBar setter: meterSet(cur, max, text)
local tapButton = nil
local promptLabel = nil

local current = nil -- { Kind, TargetId, Need } or nil
local pending = 0 -- taps accumulated since the last flush (optimistic)
local serverCount = 0 -- last server-confirmed progress for `current`
local sendAccum = 0
local lastTapSfx = 0
local lastTapBurst = 0 -- throttle the pooled tap particle pop

-- Map a prompt to a (Kind, TargetId, Need). Returns nil for prompts we don't drive.
local function targetForPrompt(prompt)
    local name = prompt.Name
    if name == "CatchPrompt" then
        return {
            Kind = "catch",
            TargetId = prompt:GetAttribute("SpawnId"),
            Need = tonumber(prompt:GetAttribute("Need")) or 6,
        }
    elseif name == "StealPrompt" then
        return {
            Kind = "steal",
            TargetId = prompt:GetAttribute("BrainrotId"),
            Need = TapConfig.StealTaps,
        }
    elseif name == "BossPrompt" then
        return { Kind = "combat", TargetId = "boss", Need = nil }
    end
    return nil
end

local function repaintMeter()
    if current == nil or current.Need == nil then
        if meterBg ~= nil then
            meterBg.Visible = false
        end
        return
    end
    meterBg.Visible = true
    -- optimistic: server-confirmed + locally-pending, but NEVER show full until the server completes.
    local shown = math.min(current.Need - 0.001, serverCount + pending)
    meterSet(shown, current.Need, "") -- animated fill (fast tween) + gloss sweep; no x/y label
end

local function showPanel(on)
    if panel ~= nil then
        panel.Visible = on
    end
end

local function setTarget(t)
    current = t
    pending = 0
    serverCount = 0
    if t ~= nil and promptLabel ~= nil then
        promptLabel.Text = (t.Kind == "combat" and "ATTACK!")
            or (t.Kind == "steal" and "STEAL!")
            or "CATCH!"
    end
    showPanel(t ~= nil)
    repaintMeter()
end

local function clearTarget()
    setTarget(nil)
end

-- Raycast from a screen position into the world and walk the hit part's ancestry to find a tappable
-- target. Returns { Kind, TargetId } matching the current active interaction, or nil if the tap missed.
-- Three cases are recognized:
--   (a) A "TapHitbox" part (CanQuery=true, CanCollide=false) with TapKind + TapTargetId attributes,
--       placed by WildSpawnService (wild catch) and BossService (boss combat).
--   (b) Any ancestor that holds a StealPrompt child (steal units use the existing on-pad model part).
-- The TAP button always counts (it is already gated by `current ~= nil`); this gate is for raw
-- InputBegan taps only, to prevent mashing the background from progressing.
local function tapTargetAt(screenPos)
    local camera = Workspace.CurrentCamera
    if camera == nil or current == nil then
        return nil
    end
    local ray = camera:ViewportPointToRay(screenPos.X, screenPos.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = { camera }
    local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
    if result == nil then
        return nil
    end

    -- Walk the hit instance and its ancestors (up to 8 levels) looking for a hitbox or steal unit.
    local inst = result.Instance
    for _ = 1, 8 do
        if inst == nil or not inst:IsA("Instance") then
            break
        end
        -- (a) TapHitbox: named part with TapKind + TapTargetId attributes.
        if inst.Name == "TapHitbox" then
            local kind = inst:GetAttribute("TapKind")
            local targetId = inst:GetAttribute("TapTargetId")
            if kind == current.Kind and targetId == current.TargetId then
                return { Kind = kind, TargetId = targetId }
            end
            return nil -- hitbox belongs to a different target
        end
        -- (b) StealPrompt on ancestor: steal unit model part.
        if inst:IsA("BasePart") or inst:IsA("Model") then
            local stealPrompt = inst:FindFirstChild("StealPrompt")
            if stealPrompt ~= nil then
                local brainrotId = stealPrompt:GetAttribute("BrainrotId")
                if current.Kind == "steal" and brainrotId == current.TargetId then
                    return { Kind = "steal", TargetId = brainrotId }
                end
                return nil
            end
        end
        inst = inst.Parent
    end
    return nil
end

-- Flush the accumulated taps to the server (the ONE client->server path). Server clamps + applies.
local function flush()
    if current == nil or pending <= 0 or remotes == nil then
        return
    end
    remotes.TapBatch:FireServer({
        Kind = current.Kind,
        TargetId = current.TargetId,
        Taps = pending,
    })
    pending = 0
end

-- Every tap: instant local feedback + accumulate. Juice is pooled/capped + throttled (never a spike).
local function onTap()
    if current == nil then
        return
    end
    pending += 1
    Effects.pop(tapButton, 0.14) -- quick per-tap squash/pulse on the button
    local now = os.clock()
    if now - lastTapSfx >= 0.04 then -- throttle the click sound (taps fire faster than this)
        lastTapSfx = now
        Effects.playSfx("click")
    end
    if now - lastTapBurst >= 0.08 then -- throttled pooled particle pop near the button (capped pool)
        lastTapBurst = now
        Effects.burst(UDim2.fromScale(0.5, 0.86), Theme.Colors.White, 5)
    end
    repaintMeter()
    -- IMMEDIATE FLUSH when this tap tips the optimistic total past the need: don't wait for the next
    -- scheduled batch interval. The debounce would swallow the final taps and the server would never
    -- see enough to cross the threshold -> the meter reads full but completion never fires.
    if current.Need ~= nil and (serverCount + pending) >= current.Need then
        sendAccum = 0
        flush()
    end
end

-- Server reconcile: the authoritative progress for our active interaction (or a completion).
local function onServerUpdate(payload)
    if type(payload) ~= "table" or current == nil then
        return
    end
    if payload.Kind ~= current.Kind or payload.TargetId ~= current.TargetId then
        return -- stale / different target
    end
    serverCount = tonumber(payload.Count) or serverCount
    if payload.Need ~= nil then
        current.Need = tonumber(payload.Need) or current.Need
    end
    if payload.Done == true then
        -- Server completed it (catch mint / steal pickup). The target's prompt will hide as the
        -- world updates; reset the optimistic state so nothing sticks.
        pending = 0
        serverCount = current.Need or serverCount
    elseif payload.Count ~= nil and payload.Need ~= nil then
        local count = tonumber(payload.Count) or 0
        local need = tonumber(payload.Need) or 1
        if count >= need and payload.Done == false then
            -- Server filled the meter but completion failed (e.g. walked out of range). The server
            -- cleared progress; reset client-side so future taps can restart rather than sticking.
            pending = 0
            serverCount = 0
            current.Need = need
        end
    end
    repaintMeter()
end

function TapInput.mount(context)
    remotes = context.remotes
    local player = context.player or Players.LocalPlayer
    gui = Builder.screenGui("TapInput", player:WaitForChild("PlayerGui"), true)
    gui.DisplayOrder = 9

    panel = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -16),
        Size = UDim2.fromOffset(220, 200),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = gui,
    })

    -- rounded progress METER above the button (catch/steal; hidden for combat) -- the single
    -- Builder.progressBar (animated fill + looping gloss sweep). Fast fill tween so it tracks each tap.
    local catchMeter, catchSet = Builder.progressBar({
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0),
        Size = UDim2.fromOffset(210, 18),
        fillTop = Theme.Colors.HpFill,
        fillBottom = Theme.Colors.HpFillDark,
        label = false,
        fillTween = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        Parent = panel,
    })
    catchMeter.Visible = false
    meterBg = catchMeter
    meterSet = catchSet

    -- the big bubbly glossy TAP button (mobile-first; also tap-anywhere works while a target is active):
    -- candy gradient + top sheen + soft shadow + white glow rim + idle pulse + per-tap squash (onTap).
    tapButton = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromScale(0.5, 1),
        Size = UDim2.fromOffset(150, 150),
        BackgroundColor3 = Theme.accentColor("Default"),
        AutoButtonColor = false,
        Font = Theme.FontDisplay,
        Text = "TAP!",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Parent = panel,
    }, {
        Builder.corner(UDim.new(1, 0)),
        Theme.gradient("Default"), -- candy purple top->bottom gradient
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.White, Thickness = 4, Transparency = 0.1 }
        ),
        Builder.create("UITextSizeConstraint", { MaxTextSize = 44 }),
        Builder.padding(8),
        Builder.create("Frame", { -- top gloss sheen (non-interactive, behind the text)
            Name = "Sheen",
            Size = UDim2.fromScale(1, 0.5),
            BackgroundColor3 = Theme.Colors.GlossTop,
            BackgroundTransparency = 0.72,
            BorderSizePixel = 0,
            ZIndex = 0,
        }, { Builder.corner(UDim.new(1, 0)) }),
    })
    Builder.styleText(tapButton, { keepColor = true }) -- white "TAP!" with the dark rim
    Builder.softShadow(tapButton, { radius = UDim.new(1, 0), spread = 16 })
    Builder.pulse(tapButton) -- gentle idle breathing so it invites the tap
    promptLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -158),
        Size = UDim2.fromOffset(220, 26),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = "",
        TextColor3 = Theme.Colors.Gold,
        TextScaled = true,
        Parent = panel,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 22 }) })
    Builder.styleText(promptLabel, { keepColor = true })

    tapButton.Activated:Connect(onTap)

    -- TARGETING: the active prompt (in range) is our interaction. Last shown wins; hiding it clears.
    ProximityPromptService.PromptShown:Connect(function(prompt)
        local t = targetForPrompt(prompt)
        if t ~= nil and t.TargetId ~= nil then
            setTarget(t)
        end
    end)
    ProximityPromptService.PromptHidden:Connect(function(prompt)
        local t = targetForPrompt(prompt)
        if
            t ~= nil
            and current ~= nil
            and t.Kind == current.Kind
            and t.TargetId == current.TargetId
        then
            clearTarget()
        end
    end)
    -- The prompt's own keybind / touch button press counts as a tap (HoldDuration 0 -> instant trigger).
    ProximityPromptService.PromptTriggered:Connect(function(prompt)
        if targetForPrompt(prompt) ~= nil then
            onTap()
        end
    end)

    -- Screen taps (mouse / touch): HITBOX-GATED. Only count when the tap lands on the active target's
    -- model (via tapTargetAt raycast). UI clicks are gameProcessed -> already filtered. The on-screen
    -- TAP button uses Activated (always counts once the panel is shown) and is not re-gated here.
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed or current == nil then
            return
        end
        local isPointer = input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        if not isPointer then
            return
        end
        local screenPos = Vector2.new(input.Position.X, input.Position.Y)
        -- Only register the tap when it lands on the active target's hitbox.
        if tapTargetAt(screenPos) ~= nil then
            onTap()
        end
    end)

    remotes.TapUpdate.OnClientEvent:Connect(onServerUpdate)

    -- Batched flush loop (the ONLY client->server tap path; ~8 Hz).
    RunService.Heartbeat:Connect(function(dt)
        sendAccum += dt
        if sendAccum >= TapConfig.BatchInterval then
            sendAccum = 0
            flush()
        end
    end)
end

return TapInput
