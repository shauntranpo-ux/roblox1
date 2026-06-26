-- FreeRewards (M12.2): the FUNCTIONAL free-reward panel (panel manager + Theme). Shows the daily-streak
-- chest (ladder + Claim + reset countdown), the timed gift (refill countdown + Claim), the spin wheel
-- (banked spins + odds + Spin -> animates to the SERVER result), and the mystery-block status. The
-- client RENDERS server state (FreeRewardAction "get") + sends CLAIM/SPIN INTENT only; the server owns
-- all timers/streak/spins and rolls RNG. Refetches on FreeRewardUpdate. Styling is the look-pass.

local RunService = game:GetService("RunService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)
local Notifications = require(script.Parent.Notifications)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local FreeRewards = {}

local player = nil
local remotes = nil
local gui = nil
local list = nil
local order = 0

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

local function fmtTime(secs)
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

local function header(text)
    Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = text,
        TextColor3 = Theme.Colors.Gold,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = list,
    })
end

local function countdownLabel(text, endsAt)
    local label = Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = text,
        TextColor3 = Theme.Colors.InkSoft,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = list,
    })
    if endsAt ~= nil then
        label:SetAttribute("EndsAt", endsAt)
        label:SetAttribute("Prefix", text)
    end
    return label
end

local function actionButton(text, color, action, onResult)
    Builder.glossButton({
        Size = UDim2.new(1, 0, 0, 44),
        color = color,
        Text = text,
        maxText = 20,
        LayoutOrder = nextOrder(),
        Parent = list,
    }, function()
        local ok, result = pcall(function()
            return remotes.FreeRewardAction:InvokeServer(action)
        end)
        if ok and type(result) == "table" then
            if onResult ~= nil then
                onResult(result)
            end
            FreeRewards.refresh()
        end
    end)
end

function FreeRewards.refresh()
    if gui == nil or not gui.Enabled then
        return
    end
    local ok, result = pcall(function()
        return remotes.FreeRewardAction:InvokeServer("get")
    end)
    local state = (ok and type(result) == "table") and result.State or nil
    clearRows()
    order = 0
    if state == nil then
        return
    end

    -- DAILY CHEST.
    header("📅 Daily Chest  —  Streak " .. tostring(state.Daily.Streak))
    local ladderRow = {}
    for _, entry in ipairs(state.Daily.Ladder) do
        table.insert(ladderRow, "Day " .. entry.Day .. ": $" .. Format.short(entry.Cash or 0))
    end
    countdownLabel(table.concat(ladderRow, "   "), nil)
    if state.Daily.CanClaim then
        actionButton("Claim Daily Chest", Theme.Colors.Positive, "daily", function(r)
            if r.Result == "Success" then
                Effects.flash(Theme.Colors.Gold)
                Effects.playSfx("milestone")
            end
        end)
    else
        countdownLabel("Claimed today. Resets in --", state.Daily.ResetsAt)
    end

    -- TIMED GIFT.
    header("🎁 Free Gift")
    local giftReady = state.Now >= state.Gift.ReadyAt
    if giftReady then
        actionButton("Claim Free Gift", Theme.Colors.Positive, "gift", function(r)
            if r.Result == "Success" then
                Effects.playSfx("milestone")
            end
        end)
    else
        countdownLabel("Refills in --", state.Gift.ReadyAt)
    end

    -- SPIN WHEEL.
    header("🎡 Spin Wheel  —  " .. tostring(state.Spin.Available) .. " spin(s)")
    local odds = {}
    local totalW = 0
    for _, seg in ipairs(state.Spin.Segments) do
        totalW += (seg.Weight or 0)
    end
    for _, seg in ipairs(state.Spin.Segments) do
        local pct = totalW > 0 and math.floor((seg.Weight or 0) / totalW * 100 + 0.5) or 0
        table.insert(odds, "$" .. Format.short(seg.Cash or 0) .. " (" .. pct .. "%)")
    end
    countdownLabel(table.concat(odds, "   "), nil)
    if state.Spin.Available > 0 then
        actionButton("SPIN!", Theme.Colors.Gold, "spin", function(r)
            if r.Result == "Success" then
                Effects.flash(Theme.Colors.Gold)
                Effects.playSfx("milestone")
                Notifications.show("success", tostring(r.Message))
            elseif r.Message ~= nil then
                Notifications.show("error", tostring(r.Message))
            end
        end)
    else
        countdownLabel("Next free spin in --", state.Spin.NextAt)
    end

    -- MYSTERY BLOCK (opened at your base; status only here).
    header("❓ Mystery Block")
    if state.Now >= state.Mystery.ReadyAt then
        countdownLabel("READY — open the Mystery Block at your base!", nil)
    else
        countdownLabel("Recharging --", state.Mystery.ReadyAt)
    end
end

function FreeRewards.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("FreeRewards", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Rewards", function()
        gui.Enabled = false
    end)

    remotes.FreeRewardUpdate.OnClientEvent:Connect(function()
        FreeRewards.refresh()
    end)

    -- Live countdowns while the panel is open.
    RunService.Heartbeat:Connect(function()
        if gui == nil or not gui.Enabled then
            return
        end
        for _, child in ipairs(list:GetChildren()) do
            local endsAt = child:IsA("TextLabel") and child:GetAttribute("EndsAt") or nil
            if endsAt ~= nil then
                local prefix = child:GetAttribute("Prefix") or ""
                child.Text = (prefix:gsub("%-%-$", "")) .. fmtTime(endsAt - os.time())
            end
        end
    end)
end

function FreeRewards.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        FreeRewards.refresh()
    end
end

return FreeRewards
