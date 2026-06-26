-- Admin (M13.4): the functional moderation UI -- TWO panels in one module.
--   * REPORT  (everyone): pick an in-server player + a reason -> submit. The server validates, rate-
--     limits, FILTERS the reason, and logs it. A note points to Roblox's built-in report too.
--   * ADMIN   (gated): only surfaced when the SERVER has stamped an AdminTier attribute on us. A player
--     list with per-player actions (kick/ban/mute/give/teleport/clear), an ops section (announce / force
--     boss/event/season), and the recent action + report LOG. The client sends INTENT ONLY -- the server
--     re-verifies authority + tier on EVERY action, so a non-admin who somehow fires the remote is
--     rejected. Destructive actions confirm here, and the server still validates regardless.

local Players = game:GetService("Players")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Notifications = require(script.Parent.Notifications)

local Admin = {}

local player, remotes = nil, nil
local adminGui, adminList, confirmModal = nil, nil, nil
local reportGui, reportList = nil, nil
local order = 0

local selectedUser = nil -- { UserId, Name } currently being managed (admin) / reported
local giveMutation = false -- admin give-item: roll a mutation?

local function nextOrder()
    order += 1
    return order
end

local function clear(listFrame)
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

local function label(parent, text, color, size, font)
    return Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, size or 22),
        BackgroundTransparency = 1,
        Font = font or Theme.FontBody,
        Text = text,
        TextColor3 = color or Theme.Colors.Ink,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = parent,
    })
end

local function rowButton(parent, text, color, fn)
    return Builder.glossButton({
        Size = UDim2.new(1, 0, 0, 40),
        color = color,
        Text = text,
        maxText = 17,
        LayoutOrder = nextOrder(),
        Parent = parent,
    }, fn)
end

local function inputBox(parent, placeholder)
    return Builder.create("TextBox", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 0.1,
        Font = Theme.FontBody,
        PlaceholderText = placeholder,
        Text = "",
        TextColor3 = Theme.Colors.White,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        LayoutOrder = nextOrder(),
        Parent = parent,
    }, { Builder.corner(UDim.new(0, 8)), Builder.padding(8) })
end

-- ── confirm-then helper (destructive actions) ───────────────────────────────────────────────
local function confirmThen(message, fn)
    confirmModal:FindFirstChild("Msg").Text = message
    confirmModal.Visible = true
    local yes = confirmModal:FindFirstChild("Yes")
    yes.Activated:Once(function()
        confirmModal.Visible = false
        fn()
    end)
end

-- ── server calls (client sends INTENT only; the server owns authority) ───────────────────────
local function adminInvoke(payload)
    local okCall, result = pcall(function()
        return remotes.AdminAction:InvokeServer(payload)
    end)
    if okCall and type(result) == "table" then
        return result
    end
    return { Result = "Error", Message = "request failed" }
end

local function doAction(command, extra)
    local payload = { Command = command }
    if selectedUser ~= nil then
        payload.TargetUserId = selectedUser.UserId
    end
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            payload[k] = v
        end
    end
    local result = adminInvoke(payload)
    Notifications.show(
        result.Result == "Success" and "success" or "error",
        result.Message or "done"
    )
    Admin.refreshAdmin()
end

-- ===========================================================================================
-- ADMIN panel render
-- ===========================================================================================
local function renderActions(state)
    label(adminList, "Managing: " .. selectedUser.Name, Theme.Colors.Gold, 26, Theme.FontDisplay)

    local reasonBox = inputBox(adminList, "reason (kick/ban)")
    local minutesBox = inputBox(adminList, "minutes (0 = permanent / until unmute)")
    local amountBox = inputBox(adminList, "$ amount (give cash)")
    local idBox = inputBox(adminList, "brainrot id (give item)")

    rowButton(adminList, "👢 Kick", Theme.Colors.Danger, function()
        confirmThen("Kick " .. selectedUser.Name .. "?", function()
            doAction("kick", { Reason = reasonBox.Text })
        end)
    end)
    rowButton(adminList, "🔨 Ban", Theme.Colors.Danger, function()
        confirmThen(
            "BAN "
                .. selectedUser.Name
                .. "?\n("
                .. (tonumber(minutesBox.Text) and (minutesBox.Text .. " min") or "permanent")
                .. ")",
            function()
                doAction(
                    "ban",
                    { Reason = reasonBox.Text, Minutes = tonumber(minutesBox.Text) or 0 }
                )
            end
        )
    end)
    rowButton(adminList, "🔇 Mute", Theme.Colors.DarkPill, function()
        doAction("mute", { Minutes = tonumber(minutesBox.Text) or 0 })
    end)
    rowButton(adminList, "🔊 Unmute", Theme.Colors.DarkPill, function()
        doAction("unmute")
    end)
    rowButton(adminList, "💰 Give Cash", Theme.Colors.Positive, function()
        local amount = tonumber(amountBox.Text)
        if amount == nil then
            Notifications.show("error", "enter a $ amount")
            return
        end
        doAction("givecash", { Amount = amount })
    end)
    rowButton(
        adminList,
        "🧠 Give Item  (mutation: " .. (giveMutation and "ON" or "off") .. ")",
        Theme.Colors.Accent,
        function()
            if idBox.Text == "" then
                Notifications.show("error", "enter a brainrot id")
                return
            end
            doAction("give", { BrainrotId = idBox.Text, Mutation = giveMutation })
        end
    )
    rowButton(
        adminList,
        giveMutation and "🎲 Mutation roll: ON" or "🎲 Mutation roll: off",
        Theme.Colors.DarkPill,
        function()
            giveMutation = not giveMutation
            Admin.refreshAdmin()
        end
    )
    rowButton(adminList, "🏃 Teleport To", Theme.Colors.Sky or Theme.Colors.DarkPill, function()
        doAction("tp")
    end)
    rowButton(adminList, "🧲 Bring", Theme.Colors.Sky or Theme.Colors.DarkPill, function()
        doAction("bring")
    end)
    rowButton(adminList, "🧹 Clear Placed Units", Theme.Colors.Danger, function()
        confirmThen("Clear " .. selectedUser.Name .. "'s placed units?", function()
            doAction("clear")
        end)
    end)
    rowButton(adminList, "← Back", Theme.Colors.DarkPill, function()
        selectedUser = nil
        Admin.refreshAdmin()
    end)
    local _ = state
end

local function renderOps(state)
    label(adminList, "Server Ops", Theme.Colors.Ink, 26, Theme.FontDisplay)
    if state.MockBans then
        label(
            adminList,
            "⚠ MOCK ban store (Studio) — bans reset when you stop. Real bans need a PUBLISHED place.",
            Theme.Colors.Gold,
            34
        )
    end
    local announceBox = inputBox(adminList, "announcement text")
    rowButton(adminList, "📣 Announce", Theme.Colors.Accent, function()
        if announceBox.Text == "" then
            Notifications.show("error", "type a message")
            return
        end
        local result = adminInvoke({ Command = "announce", Text = announceBox.Text })
        Notifications.show(
            result.Result == "Success" and "success" or "error",
            result.Message or ""
        )
        announceBox.Text = ""
    end)
    rowButton(adminList, "👹 Spawn World Boss", Theme.Colors.Danger, function()
        local result = adminInvoke({ Command = "boss" })
        Notifications.show(
            result.Result == "Success" and "success" or "error",
            result.Message or ""
        )
    end)
    local eventBox = inputBox(adminList, "event key (force; SIM/Studio)")
    rowButton(adminList, "🎉 Force Event", Theme.Colors.DarkPill, function()
        if eventBox.Text == "" then
            Notifications.show("error", "enter an event key")
            return
        end
        local result = adminInvoke({ Command = "event", Key = eventBox.Text, Active = true })
        Notifications.show(
            result.Result == "Success" and "success" or "error",
            result.Message or ""
        )
    end)
    rowButton(adminList, "🏁 Force Season Rollover", Theme.Colors.DarkPill, function()
        confirmThen("Force a season rollover? (SIM/Studio only)", function()
            local result = adminInvoke({ Command = "season" })
            Notifications.show(
                result.Result == "Success" and "success" or "error",
                result.Message or ""
            )
        end)
    end)
end

local function timeAgo(t)
    local d = os.time() - (tonumber(t) or os.time())
    if d < 60 then
        return d .. "s"
    elseif d < 3600 then
        return math.floor(d / 60) .. "m"
    end
    return math.floor(d / 3600) .. "h"
end

local function renderLog(state)
    label(adminList, "Recent Actions & Reports", Theme.Colors.Ink, 26, Theme.FontDisplay)
    if #state.Log == 0 then
        label(adminList, "(nothing yet)", Theme.Colors.InkSoft, 30)
        return
    end
    local shown = 0
    for _, entry in ipairs(state.Log) do
        if shown >= 18 then
            break
        end
        shown += 1
        local color = entry.Type == "report" and Theme.Colors.Gold
            or (entry.Type == "denied" and Theme.Colors.Danger or Theme.Colors.InkSoft)
        local line = string.format(
            "[%s] %s → %s : %s  (%s ago)",
            tostring(entry.Type),
            tostring(entry.ActorName),
            tostring(entry.TargetName or "-"),
            tostring(entry.Detail or ""),
            timeAgo(entry.Time)
        )
        label(adminList, line, color, 40)
    end
end

function Admin.refreshAdmin()
    if adminGui == nil or not adminGui.Enabled then
        return
    end
    clear(adminList)
    order = 0
    local result = adminInvoke({ Command = "get" })
    if result.Result ~= "Success" or type(result.State) ~= "table" then
        label(adminList, result.Message or "not authorized.", Theme.Colors.Danger, 30)
        return
    end
    local state = result.State
    label(
        adminList,
        "🛡 Admin — tier: " .. tostring(state.Tier),
        Theme.Colors.Gold,
        26,
        Theme.FontDisplay
    )

    if selectedUser ~= nil then
        renderActions(state)
        return
    end

    label(adminList, "Players in server", Theme.Colors.Ink, 26, Theme.FontDisplay)
    for _, p in ipairs(state.Players) do
        local tag = p.Tier ~= nil and ("  [" .. p.Tier .. "]") or ""
        local mutedTag = p.Muted and "  🔇" or ""
        rowButton(
            adminList,
            p.Name .. tag .. mutedTag,
            Theme.Colors.Row or Theme.Colors.DarkPill,
            function()
                selectedUser = { UserId = p.UserId, Name = p.Name }
                Admin.refreshAdmin()
            end
        )
    end
    renderOps(state)
    renderLog(state)
end

-- ===========================================================================================
-- REPORT panel render (everyone)
-- ===========================================================================================
local function submitReport(reasonBox)
    local okCall, result = pcall(function()
        return remotes.ReportPlayer:InvokeServer({
            TargetUserId = selectedUser.UserId,
            Reason = reasonBox.Text,
        })
    end)
    if okCall and type(result) == "table" then
        Notifications.show(
            result.Result == "Success" and "success" or "error",
            result.Message or ""
        )
        if result.Result == "Success" then
            selectedUser = nil
            Admin.refreshReport()
        end
    else
        Notifications.show("error", "report failed")
    end
end

function Admin.refreshReport()
    if reportGui == nil or not reportGui.Enabled then
        return
    end
    clear(reportList)
    order = 0
    label(
        reportList,
        "Report a player to the game's admins. You can also use Roblox's own report via the ≡ menu → Report.",
        Theme.Colors.InkSoft,
        50
    )

    if selectedUser ~= nil then
        label(
            reportList,
            "Reporting: " .. selectedUser.Name,
            Theme.Colors.Gold,
            24,
            Theme.FontDisplay
        )
        local reasonBox = inputBox(reportList, "what happened? (required)")
        rowButton(reportList, "🚩 Submit Report", Theme.Colors.Danger, function()
            submitReport(reasonBox)
        end)
        rowButton(reportList, "← Back", Theme.Colors.DarkPill, function()
            selectedUser = nil
            Admin.refreshReport()
        end)
        return
    end

    label(reportList, "Pick a player", Theme.Colors.Ink, 26, Theme.FontDisplay)
    local localPlayer = Players.LocalPlayer
    local any = false
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= localPlayer then
            any = true
            local safeName = other:GetAttribute("SafeName") or other.DisplayName
            rowButton(
                reportList,
                "🚩  " .. safeName,
                Theme.Colors.Row or Theme.Colors.DarkPill,
                function()
                    selectedUser = { UserId = other.UserId, Name = safeName }
                    Admin.refreshReport()
                end
            )
        end
    end
    if not any then
        label(reportList, "No other players in this server right now.", Theme.Colors.InkSoft, 34)
    end
end

-- ===========================================================================================
-- mount / toggles
-- ===========================================================================================
local function buildConfirmModal(parent)
    local modal = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(360, 180),
        BackgroundColor3 = Theme.Colors.Background,
        Visible = false,
        ZIndex = 20,
        Parent = parent,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(12) })
    Builder.create("TextLabel", {
        Name = "Msg",
        Size = UDim2.new(1, 0, 0, 100),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = "",
        TextColor3 = Theme.Colors.Ink,
        TextSize = 16,
        TextWrapped = true,
        ZIndex = 21,
        Parent = modal,
    })
    local yes = Builder.glossButton({
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromOffset(160, 40),
        color = Theme.Colors.Danger,
        Text = "Confirm",
        maxText = 18,
        Parent = modal,
    }, nil)
    yes.Name = "Yes"
    yes.ZIndex = 21
    local no = Builder.glossButton({
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromScale(1, 1),
        Size = UDim2.fromOffset(160, 40),
        color = Theme.Colors.DarkPill,
        Text = "Cancel",
        maxText = 18,
        Parent = modal,
    }, function()
        modal.Visible = false
    end)
    no.ZIndex = 21
    return modal
end

function Admin.mount(context)
    player = context.player
    remotes = context.remotes

    reportGui = Builder.screenGui("Report", player:WaitForChild("PlayerGui"), false)
    reportList = Builder.panel(reportGui, "Report", function()
        reportGui.Enabled = false
    end)

    adminGui = Builder.screenGui("Admin", player:WaitForChild("PlayerGui"), false)
    adminList = Builder.panel(adminGui, "Admin", function()
        adminGui.Enabled = false
    end)
    confirmModal = buildConfirmModal(adminGui)
end

function Admin.toggleReport()
    if reportGui == nil then
        return
    end
    reportGui.Enabled = not reportGui.Enabled
    if reportGui.Enabled then
        selectedUser = nil
        Admin.refreshReport()
    end
end

function Admin.toggleAdmin()
    if adminGui == nil then
        return
    end
    adminGui.Enabled = not adminGui.Enabled
    if adminGui.Enabled then
        selectedUser = nil
        Admin.refreshAdmin()
    end
end

return Admin
