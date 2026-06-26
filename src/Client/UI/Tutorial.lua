-- Tutorial: the one-time, almost-wordless first-session onboarding. The server (TutorialService)
-- decides whether to start it (new players only) after the client signals "ready"; this module
-- just renders the beats. Two beats: (A) an arrow + coachmark pointing at the Shop to make the
-- first purchase unmissable, (B) a quick celebration on the first buy. Skippable at any time.
--
-- All connections + instances are tracked in a Janitor and released on finish, so nothing leaks
-- if the player skips, buys, or the flow ends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Janitor = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Janitor"))

local Tutorial = {}

local player = nil
local remotes = nil
local gui = nil
local jan = nil
local active = false
local finished = false
local purchased = false
local card = nil
local cardText = nil
local actionButton = nil

local function teardown()
    if jan ~= nil then
        jan:cleanup()
        jan = nil
    end
    if gui ~= nil then
        gui.Enabled = false
    end
end

local function finish(reason)
    if finished then
        return
    end
    finished = true
    active = false
    if remotes ~= nil then
        remotes.Tutorial:FireServer(reason) -- "done" | "skip" (server only ever sets the flag true)
    end
    teardown()
end

-- Beat B: celebrate the first purchase, then let the player dismiss.
function Tutorial.onPurchase()
    if not active then
        return
    end
    purchased = true
    if cardText ~= nil then
        cardText.Text = "Awesome! More brainrots = more cash. Keep buying!"
    end
    if actionButton ~= nil then
        actionButton.Text = "Got it!"
        actionButton.BackgroundColor3 = Theme.Colors.Positive
    end
end

-- Beat A: arrow toward the Shop button + a short coachmark.
local function start()
    if active or finished then
        return
    end
    active = true
    gui.Enabled = true
    jan = Janitor.new()

    -- Bouncing arrow above the bottom button bar (where Shop lives) -- draws the eye, no precise
    -- anchoring needed so it's robust across aspect ratios.
    local arrow = jan:add(Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.84),
        Size = UDim2.fromScale(0.16, 0.08),
        BackgroundTransparency = 1,
        Font = Theme.FontBold,
        Text = "▼",
        TextColor3 = Theme.Colors.Accent,
        TextScaled = true,
        Parent = gui,
    }))
    local bounce = TweenService:Create(
        arrow,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true),
        { Position = UDim2.fromScale(0.5, 0.88) }
    )
    bounce:Play()
    jan:add(function()
        bounce:Cancel()
    end)

    -- Coachmark card.
    card = jan:add(Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.16),
        Size = UDim2.fromScale(0.86, 0.18),
        BackgroundColor3 = Theme.Colors.Panel,
        BorderSizePixel = 0,
        Parent = gui,
    }, {
        Builder.corner(UDim.new(0, 16)),
        Builder.padding(14),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(520, 200) }),
    }))

    cardText = Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 0.6),
        Font = Theme.FontBold,
        Text = "Your money goes up on its own. Tap Shop and buy your first brainrot!",
        TextColor3 = Theme.Colors.Ink,
        TextScaled = true,
        TextWrapped = true,
        Parent = card,
    }, { Builder.create("UITextSizeConstraint", { MaxTextSize = 22 }) })

    actionButton = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromScale(0.5, 1),
        Size = UDim2.fromScale(0.5, 0.32),
        BackgroundColor3 = Theme.Colors.Disabled,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = "Skip",
        TextColor3 = Theme.Colors.Text,
        TextScaled = true,
        Parent = card,
    }, {
        Builder.corner(UDim.new(0, 12)),
        Builder.create("UITextSizeConstraint", { MaxTextSize = 20 }),
    })

    actionButton.Activated:Connect(function()
        -- Before the first buy this is "Skip"; after it's "Got it!" -- either way the tutorial
        -- ends and is marked complete server-side so it never shows again.
        finish(purchased and "done" or "skip")
    end)
end

function Tutorial.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Tutorial", player:WaitForChild("PlayerGui"), false)
    gui.DisplayOrder = 20

    -- Handshake: tell the server we're listening; it replies "start" (new player) or "none"
    -- (returning) once our profile is loaded. We retry because the profile may still be loading
    -- when we first ask; bounded so a returning player stops quickly. Connecting BEFORE firing
    -- means the reply can never arrive before we listen.
    local answered = false
    remotes.Tutorial.OnClientEvent:Connect(function(action)
        if action == "start" then
            answered = true
            start()
        elseif action == "none" then
            answered = true
        end
    end)
    task.spawn(function()
        for _ = 1, 8 do
            if answered then
                break
            end
            remotes.Tutorial:FireServer("ready")
            task.wait(1)
        end
    end)
end

return Tutorial
