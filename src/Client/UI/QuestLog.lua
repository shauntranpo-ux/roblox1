-- QuestLog (M12.1): the FUNCTIONAL quest panel (via the panel manager + Theme). Tabs for Tutorial /
-- Daily / Weekly / Milestone; each quest shows title, description, a progress bar (current/target), a
-- reward, and a Claim button when complete; daily/weekly show a reset countdown. The client RENDERS
-- server state (GetQuests) and sends CLAIM INTENT only (scope + quest id). Refetches on QuestsUpdate.
-- Styling is the look-pass.

local RunService = game:GetService("RunService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local QuestLog = {}

local player = nil
local remotes = nil
local gui = nil
local list = nil
local tabBar = nil
local currentTab = "Tutorial"
local state = nil
local order = 0

local TABS = { "Tutorial", "Daily", "Weekly", "Milestone" }

local function nextOrder()
    order += 1
    return order
end

local function clearRows()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

local function fmtCountdown(secs)
    secs = math.max(0, math.floor(secs))
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = secs % 60
    if h > 0 then
        return string.format("%dh %dm", h, m)
    elseif m > 0 then
        return string.format("%dm %ds", m, s)
    end
    return string.format("%ds", s)
end

local function doClaim(scope, questId)
    local ok, result = pcall(function()
        return remotes.ClaimQuest:InvokeServer(scope, questId)
    end)
    if ok and type(result) == "table" then
        QuestLog.refresh()
    end
end

-- One quest card: title, desc, progress bar, reward, and a claim/claimed/locked button.
local function questCard(scope, q)
    local card = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 84),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
    }, { Builder.corner(UDim.new(0, 10)), Builder.padding(8) })

    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 0),
        Size = UDim2.new(1, -110, 0, 20),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        RichText = true,
        Text = tostring(q.Title),
        TextColor3 = Theme.Colors.White,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 22),
        Size = UDim2.new(1, -110, 0, 18),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        RichText = true,
        Text = tostring(q.Desc),
        TextColor3 = Theme.Colors.SubText,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = card,
    })

    -- Progress bar.
    local pct = q.Target > 0 and math.clamp(q.Progress / q.Target, 0, 1) or 0
    local barBg = Builder.create("Frame", {
        Position = UDim2.fromOffset(2, 46),
        Size = UDim2.new(1, -110, 0, 16),
        BackgroundColor3 = Theme.Colors.Sand,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Parent = card,
    }, { Builder.corner(UDim.new(1, 0)) })
    Builder.create("Frame", {
        Size = UDim2.fromScale(pct, 1),
        BackgroundColor3 = q.Complete and Theme.Colors.HpFill or Theme.Colors.XpFill,
        BorderSizePixel = 0,
        Parent = barBg,
    }, { Builder.corner(UDim.new(1, 0)) })
    Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = math.floor(q.Progress) .. " / " .. q.Target .. "   (+" .. tostring(q.Reward) .. ")",
        TextColor3 = Theme.Colors.White,
        TextSize = 12,
        ZIndex = 2,
        Parent = barBg,
    })

    -- Claim / state button.
    if q.Claimed then
        Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(96, 56),
            BackgroundTransparency = 1,
            Font = Theme.FontDisplay,
            Text = "✓ Claimed",
            TextColor3 = Theme.Colors.Positive,
            TextSize = 14,
            Parent = card,
        })
    elseif q.Complete then
        Builder.glossButton({
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(96, 56),
            color = Theme.Colors.Positive,
            Text = "Claim",
            maxText = 18,
            Parent = card,
        }, function()
            doClaim(string.lower(scope), q.Id)
        end)
    else
        Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(96, 56),
            BackgroundTransparency = 1,
            Font = Theme.FontBody,
            Text = "In progress",
            TextColor3 = Theme.Colors.SubText,
            TextSize = 13,
            Parent = card,
        })
    end
    card.Parent = list
end

function QuestLog.refresh()
    if gui == nil or not gui.Enabled then
        return
    end
    local ok, result = pcall(function()
        return remotes.GetQuests:InvokeServer()
    end)
    state = (ok and type(result) == "table") and result or nil
    clearRows()
    order = 0
    if state == nil then
        return
    end

    local quests = state[currentTab] or {}
    if currentTab == "Daily" and state.DailyEndsAt ~= nil then
        local label = Builder.create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Font = Theme.FontBody,
            Text = "Resets in " .. fmtCountdown(state.DailyEndsAt - state.Now),
            TextColor3 = Theme.Colors.Gold,
            TextSize = 14,
            LayoutOrder = nextOrder(),
            Parent = list,
        })
        label:SetAttribute("EndsAt", state.DailyEndsAt)
    elseif currentTab == "Weekly" and state.WeeklyEndsAt ~= nil then
        local label = Builder.create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Font = Theme.FontBody,
            Text = "Resets in " .. fmtCountdown(state.WeeklyEndsAt - state.Now),
            TextColor3 = Theme.Colors.Gold,
            TextSize = 14,
            LayoutOrder = nextOrder(),
            Parent = list,
        })
        label:SetAttribute("EndsAt", state.WeeklyEndsAt)
    end

    if #quests == 0 then
        Builder.create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundTransparency = 1,
            Font = Theme.FontBody,
            Text = "Nothing here right now.",
            TextColor3 = Theme.Colors.InkSoft,
            TextSize = 15,
            LayoutOrder = nextOrder(),
            Parent = list,
        })
        return
    end
    for _, q in ipairs(quests) do
        questCard(currentTab, q)
    end
end

local function buildTabs()
    for _, tab in ipairs(TABS) do
        local button = Builder.glossButton({
            Size = UDim2.fromScale(0.24, 1),
            color = Theme.Colors.DarkPill,
            Text = tab,
            maxText = 16,
            Parent = tabBar,
        }, function()
            currentTab = tab
            QuestLog.refresh()
        end)
        button:SetAttribute("Tab", tab)
    end
end

function QuestLog.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("QuestLog", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Quests", function()
        gui.Enabled = false
    end)

    tabBar = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundTransparency = 1,
        LayoutOrder = -1,
        Parent = list,
    }, {
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    buildTabs()

    remotes.QuestsUpdate.OnClientEvent:Connect(function()
        QuestLog.refresh()
    end)

    -- Live reset countdown while the panel is open (cheap; one label).
    RunService.Heartbeat:Connect(function()
        if gui == nil or not gui.Enabled then
            return
        end
        for _, child in ipairs(list:GetChildren()) do
            local endsAt = child:IsA("TextLabel") and child:GetAttribute("EndsAt") or nil
            if endsAt ~= nil then
                child.Text = "Resets in " .. fmtCountdown(endsAt - os.time())
            end
        end
    end)
end

function QuestLog.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        QuestLog.refresh()
    end
end

return QuestLog
