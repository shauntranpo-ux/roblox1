-- TapInput (tap-to-progress): the ONE shared client module behind uncapped tapping for catch/steal/
-- combat. It uses each system's EXISTING ProximityPrompt as the TARGET (PromptShown/Hidden pick the
-- active interaction uniformly), counts every tap LOCALLY with INSTANT juice (no hold bar, no throttle),
-- and flushes the accumulated count to the server every TapConfig.BatchInterval. The server is
-- authoritative on progress + completion (it clamps to a human-max rate); this client is OPTIMISTIC and
-- reconciles to the server's TapUpdate, so it never shows a false completion or sticks at 99%.
--
-- TAP SURFACES (all count once, never double): a big on-screen TAP button (mobile), tap-anywhere on the
-- screen (UserInputService, UI clicks are gameProcessed -> filtered), and the prompt's own keybind/touch
-- button (ProximityPromptService.PromptTriggered). Mash any of them as fast as you can.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)

local TapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TapConfig"))

local TapInput = {}

local remotes = nil
local gui = nil
local panel = nil -- the bottom tap UI (button + meter), shown only while a target is active
local meterBg = nil
local meterFill = nil
local tapButton = nil
local promptLabel = nil

local current = nil -- { Kind, TargetId, Need } or nil
local pending = 0 -- taps accumulated since the last flush (optimistic)
local serverCount = 0 -- last server-confirmed progress for `current`
local sendAccum = 0
local lastTapSfx = 0

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
    meterFill.Size = UDim2.fromScale(math.clamp(shown / current.Need, 0, 1), 1)
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
    Effects.pop(tapButton, 0.12)
    local now = os.clock()
    if now - lastTapSfx >= 0.04 then -- throttle the click sound (taps fire faster than this)
        lastTapSfx = now
        Effects.playSfx("click")
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

    -- thin progress meter above the button (catch/steal; hidden for combat)
    meterBg = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0),
        Size = UDim2.fromOffset(200, 16),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.1,
        Visible = false,
        Parent = panel,
    }, {
        Builder.corner(UDim.new(1, 0)),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.White, Thickness = 2, Transparency = 0.3 }
        ),
    })
    meterFill = Builder.create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Parent = meterBg,
    }, { Builder.corner(UDim.new(1, 0)) })

    -- the big TAP button (mobile-first; also tap-anywhere works while a target is active)
    tapButton = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromScale(0.5, 1),
        Size = UDim2.fromOffset(150, 150),
        BackgroundColor3 = Theme.Colors.Accent,
        AutoButtonColor = false,
        Font = Theme.FontDisplay,
        Text = "TAP!",
        TextColor3 = Theme.Colors.White,
        TextScaled = true,
        Parent = panel,
    }, {
        Builder.corner(UDim.new(1, 0)),
        Builder.create(
            "UIStroke",
            { Color = Theme.Colors.Outline, Thickness = 4, Transparency = 0.1 }
        ),
        Builder.create("UITextSizeConstraint", { MaxTextSize = 44 }),
        Builder.padding(8),
    })
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

    -- Tap-anywhere on the screen (mouse / touch) while a target is active. UI clicks are gameProcessed,
    -- so the TAP button (and other GUI) never double-counts here.
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed or current == nil then
            return
        end
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
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
