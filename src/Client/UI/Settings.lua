-- Settings: a tiny, mobile-friendly preference panel (Music / SFX / Screen Shake), reached from
-- the HUD gear button. Pulls the saved values from the server on mount and writes changes back
-- through SaveSettings (validated server-side). Preferences are presentational only.

local UserInputService = game:GetService("UserInputService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Notifications = require(script.Parent.Notifications)

local Settings = {}

-- M12.4 audio (bool MUTES + 0..1 VOLUME numbers) + M13.6 graphics/HUD/notify toggles. All are
-- presentational PREFERENCES -- they grant nothing; the server validates + persists the same keys.
local DEFAULTS = {
    Music = false,
    SFX = true,
    Shake = true,
    MusicVolume = 0.5,
    SfxVolume = 0.7,
    AmbienceVolume = 0.5,
    ReduceEffects = false,
    ShowKillFeed = true,
    NotifyOptIn = false,
}

local player = nil
local remotes = nil
local gui = nil
local current = {}
local onChanged = nil
local buttons = {} -- [key] = TextButton
local groupContainer = nil -- M13.6: the "Community" group-reward section (rebuilt on re-check)

local function sanitize(data)
    local out = {}
    local t = type(data) == "table" and data or {}
    for key, default in pairs(DEFAULTS) do
        if type(default) == "boolean" then
            out[key] = type(t[key]) == "boolean" and t[key] or default
        else
            local n = tonumber(t[key])
            out[key] = (n ~= nil) and math.clamp(n, 0, 1) or default
        end
    end
    return out
end

local function setVisual(button, on)
    button.Text = on and "ON" or "OFF"
    button.BackgroundColor3 = on and Theme.Colors.Positive or Theme.Colors.Disabled
    button.TextColor3 = on and Theme.Colors.Text or Theme.Colors.SubText
end

local function buildToggle(parent, key, label, order)
    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 62),
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(10) })

    Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(6, 0),
        Size = UDim2.new(1, -120, 1, 0),
        Font = Theme.FontBold,
        Text = label,
        TextColor3 = Theme.Colors.Ink,
        TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local button = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(92, 44),
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        TextSize = 18,
        AutoButtonColor = true,
        Parent = row,
    }, { Builder.corner(UDim.new(0, 10)) })

    setVisual(button, current[key])
    button.Activated:Connect(function()
        current[key] = not current[key]
        setVisual(button, current[key])
        remotes.SaveSettings:FireServer(current)
        if onChanged ~= nil then
            onChanged(current)
        end
    end)

    buttons[key] = button
    row.Parent = parent
end

-- M12.4: a functional volume slider (tap or drag). Applies live; persists on release.
local function buildSlider(parent, key, label, order)
    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 62),
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(10) })
    Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(6, 4),
        Size = UDim2.new(1, -12, 0, 22),
        Font = Theme.FontBold,
        Text = label,
        TextColor3 = Theme.Colors.Ink,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    local valueLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -6, 0, 4),
        Size = UDim2.fromOffset(60, 22),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = "",
        TextColor3 = Theme.Colors.InkSoft,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })
    local track = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 6, 1, -6),
        Size = UDim2.new(1, -12, 0, 14),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BorderSizePixel = 0,
        Parent = row,
    }, { Builder.corner(UDim.new(1, 0)) })
    local fill = Builder.create("Frame", {
        Size = UDim2.fromScale(current[key] or 0.5, 1),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Parent = track,
    }, { Builder.corner(UDim.new(1, 0)) })

    local function paint()
        fill.Size = UDim2.fromScale(current[key], 1)
        valueLabel.Text = math.floor(current[key] * 100 + 0.5) .. "%"
    end
    local function setFromX(px)
        local rel =
            math.clamp((px - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
        current[key] = rel
        paint()
        if onChanged ~= nil then
            onChanged(current) -- live audio feedback while dragging
        end
    end
    paint()

    local dragging = false
    track.InputBegan:Connect(function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if
            dragging
            and (
                input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch
            )
        then
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if
            dragging
            and (
                input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            )
        then
            dragging = false
            remotes.SaveSettings:FireServer(current) -- persist on release (not every frame)
        end
    end)
    row.Parent = parent
end

-- ===========================================================================================
-- M13.6: small section helpers + the Community (group reward) section.
-- ===========================================================================================
local function sectionLabel(parent, text, order)
    Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        Font = Theme.FontBold,
        Text = text,
        TextColor3 = Theme.Colors.Accent,
        TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = order,
        Parent = parent,
    })
end

local function noteLabel(parent, text, order, color)
    Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = text,
        TextColor3 = color or Theme.Colors.InkSoft,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = order,
        Parent = parent,
    })
end

local function actionButton(parent, text, color, order, fn)
    local b = Builder.create("TextButton", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = text,
        TextColor3 = Theme.Colors.Text,
        TextSize = 18,
        LayoutOrder = order,
        Parent = parent,
    }, { Builder.corner(UDim.new(0, 10)) })
    b.Activated:Connect(fn)
    return b
end

-- Re-pulls group state from the server (membership check is server-side) and rebuilds the section.
local function refreshGroup()
    if groupContainer == nil then
        return
    end
    for _, child in ipairs(groupContainer:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
    local ok, result = pcall(function()
        return remotes.GroupAction:InvokeServer({ Action = "get" })
    end)
    local state = (ok and type(result) == "table") and result.State or nil
    if state == nil or not state.Configured then
        return -- group hook not configured -> hide the section entirely
    end

    sectionLabel(groupContainer, "🏷 Community", 1)
    noteLabel(
        groupContainer,
        state.GroupName .. " — reward: " .. tostring(state.RewardSummary),
        2
    )

    -- "claim" re-checks membership server-side; both the claim and re-check buttons use it.
    local function doClaim()
        local okClaim, res = pcall(function()
            return remotes.GroupAction:InvokeServer({ Action = "claim" })
        end)
        if okClaim and type(res) == "table" then
            Notifications.show(res.Result == "Success" and "success" or "info", res.Message or "")
        end
        refreshGroup()
    end

    if state.IsMember then
        if state.RewardType == "perk" then
            noteLabel(groupContainer, "✓ Member perk active!", 3, Theme.Colors.Positive)
        elseif state.Claimed then
            noteLabel(
                groupContainer,
                "✓ Reward claimed -- thanks for being a member!",
                3,
                Theme.Colors.Positive
            )
        else
            actionButton(
                groupContainer,
                "🎁 Claim Group Reward",
                Theme.Colors.Positive,
                4,
                doClaim
            )
        end
    else
        noteLabel(
            groupContainer,
            tostring(state.PromptText) .. "\nFind us: " .. tostring(state.GroupUrl),
            3,
            Theme.Colors.Gold
        )
        actionButton(groupContainer, "🔄 I Joined -- Re-check", Theme.Colors.Accent, 4, doClaim)
    end
end

function Settings.mount(context, opts)
    player = context.player
    remotes = context.remotes
    onChanged = opts and opts.onChanged
    gui = Builder.screenGui("Settings", player:WaitForChild("PlayerGui"), false)

    -- Pull saved prefs (safe fallback to defaults on any failure).
    local ok, saved = pcall(function()
        return remotes.GetSettings:InvokeServer()
    end)
    current = sanitize(ok and saved or nil)

    local list = Builder.panel(gui, "Settings", function()
        gui.Enabled = false
    end)

    -- Audio (M12.4, absorbed here -- one settings panel, not two).
    buildToggle(list, "Music", "Music", 1)
    buildToggle(list, "SFX", "Sound Effects", 2)
    buildToggle(list, "Shake", "Screen Shake", 3)
    buildSlider(list, "MusicVolume", "Music Volume", 4)
    buildSlider(list, "SfxVolume", "SFX Volume", 5)
    buildSlider(list, "AmbienceVolume", "Ambience Volume", 6)
    -- M13.6: graphics / HUD / notification toggles (each persists + applies live, grants nothing).
    buildToggle(list, "ReduceEffects", "Reduce Effects (low-end)", 7)
    buildToggle(list, "ShowKillFeed", "Steal Banners", 8)
    buildToggle(list, "NotifyOptIn", "Notify Me to Return", 9)
    noteLabel(
        list,
        "Get a ping when your daily chest is ready or an event starts. Opt out anytime.",
        10
    )

    -- M13.6: the Community (group reward) section -- rebuilds itself when you tap claim / re-check.
    groupContainer = Builder.create("Frame", {
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 11,
        Parent = list,
    }, {
        Builder.create("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    -- Populated when the panel is first opened (off-thread) so a group network call never stalls boot.

    -- Credits / links.
    sectionLabel(list, "💛 Credits", 20)
    noteLabel(
        list,
        "Thanks for playing! Settings save to your account, change only your own client, and grant nothing.",
        21
    )

    -- Apply the loaded prefs immediately (music/shake/graphics/HUD state).
    if onChanged ~= nil then
        onChanged(current)
    end
end

function Settings.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        task.spawn(refreshGroup) -- refresh the group/membership state on open (off-thread)
    end
end

return Settings
