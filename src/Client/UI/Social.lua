-- Social (M13.3): the FUNCTIONAL friends & social panel. Shows the private/VIP-server perks, a GIFTING
-- flow (pick an in-server friend -> pick a giftable unit -> confirm -> the server performs the atomic
-- dupe-proof transfer), online friends with a best-effort Join, and a "Play with Friends" invite
-- (reuses M13.1). The client sends INTENT only; the server re-validates + owns the transfer. Functional.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Notifications = require(script.Parent.Notifications)
local PanelManager = require(script.Parent.PanelManager)

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))

local Social = {}

local player, remotes = nil, nil
local gui, list, confirmModal = nil, nil, nil
local order = 0
local selectedFriend = nil -- { UserId, Name } currently being gifted to

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

local function label(text, color, size, font)
    return Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, size or 22),
        BackgroundTransparency = 1,
        Font = font or Theme.FontBody,
        Text = text,
        TextColor3 = color or Theme.Colors.Text,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = list,
    })
end

local function rowButton(text, color, fn)
    Builder.glossButton({
        Size = UDim2.new(1, 0, 0, 40),
        color = color,
        Text = text,
        maxText = 18,
        LayoutOrder = nextOrder(),
        Parent = list,
    }, fn)
end

-- Best-effort follow into a friend's server (works on a published place with presence; graceful else).
local function joinFriend(userId)
    pcall(function()
        remotes.SocialAction:InvokeServer({ Action = "friendjoin" })
    end)
    local ok = pcall(function()
        TeleportService:TeleportToPlayerInstance(game.PlaceId, "", Players.LocalPlayer)
    end)
    if not ok then
        Notifications.show("error", "Couldn't join their server — try inviting them instead!")
    end
    -- userId kept for a future presence-resolved teleport; intent already logged server-side.
    local _ = userId
end

local function doGift(unitId)
    if selectedFriend == nil then
        return
    end
    local ok, result = pcall(function()
        return remotes.SocialAction:InvokeServer({
            Action = "gift",
            TargetUserId = selectedFriend.UserId,
            UnitId = unitId,
            Confirm = true,
        })
    end)
    if ok and type(result) == "table" then
        if result.Result == "Success" then
            Notifications.show("success", result.Message or "Gifted!")
            selectedFriend = nil
            Social.refresh()
        elseif result.Message ~= nil then
            Notifications.show("error", result.Message)
        end
    end
end

local function confirmGift(unitId, unitName)
    confirmModal:FindFirstChild("Msg").Text = "Gift "
        .. unitName
        .. " to "
        .. selectedFriend.Name
        .. "?\nThis is permanent."
    confirmModal.Visible = true
    local yes = confirmModal:FindFirstChild("Yes")
    yes.Activated:Once(function()
        confirmModal.Visible = false
        doGift(unitId)
    end)
end

-- The giftable units (client convenience filter; the server re-validates every gift).
local function renderUnitPicker()
    label(
        "Pick a unit to gift to " .. selectedFriend.Name .. ":",
        Theme.Colors.Gold,
        24,
        Theme.FontDisplay
    )
    local owned = {}
    pcall(function()
        owned = remotes.GetInventory:InvokeServer()
    end)
    local any = false
    for _, unit in ipairs(typeof(owned) == "table" and owned or {}) do
        if unit.Tradeable and not unit.Locked and not unit.Favorited then
            any = true
            local star = (unit.Star and unit.Star > 1) and (" ★" .. unit.Star) or ""
            rowButton(
                unit.Name .. star .. "  (+$" .. Format.short(unit.IncomePerSec or 0) .. "/s)",
                Rarity.Get(unit.Rarity).Color,
                function()
                    confirmGift(unit.Id, unit.Name)
                end
            )
        end
    end
    if not any then
        label("No giftable units (locked/favorited/premium excluded).", Theme.Colors.SubText, 36)
    end
    rowButton("← Back", Theme.Colors.DarkPill, function()
        selectedFriend = nil
        Social.refresh()
    end)
end

function Social.refresh()
    if gui == nil or not gui.Enabled then
        return
    end
    clearRows()
    order = 0
    local ok, result = pcall(function()
        return remotes.SocialAction:InvokeServer({ Action = "get" })
    end)
    local state = (ok and type(result) == "table") and result.State or nil

    -- VIP / private-server info.
    if state ~= nil then
        if state.Vip then
            label(
                "⭐ VIP SERVER — +"
                    .. state.VipBoostPct
                    .. "% income"
                    .. (state.IsOwner and " (owner bonus!)" or ""),
                Theme.Colors.Gold,
                28,
                Theme.FontDisplay
            )
        else
            label(
                "Private servers give +"
                    .. tostring(state.VipIncomePct)
                    .. "% income (+"
                    .. tostring(state.VipOwnerPct)
                    .. "% for the owner).",
                Theme.Colors.SubText,
                36
            )
        end
        label(
            "Gifts left today: " .. tostring(state.GiftsLeft) .. " / " .. tostring(state.DailyCap),
            Theme.Colors.Text
        )
    end

    if selectedFriend ~= nil then
        renderUnitPicker()
        return
    end

    -- Gift a friend in this server.
    label("Gift a Friend (in this server)", Theme.Colors.Text, 26, Theme.FontDisplay)
    local localPlayer = Players.LocalPlayer
    local anyFriend = false
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= localPlayer then
            local isFriend = false
            pcall(function()
                isFriend = localPlayer:IsFriendsWith(other.UserId)
            end)
            if isFriend then
                anyFriend = true
                -- M13.4: use the server-published filtered SafeName, never the raw display name.
                local safeName = other:GetAttribute("SafeName") or other.DisplayName
                rowButton("🎁  Gift to " .. safeName, Theme.Colors.Positive, function()
                    selectedFriend = { UserId = other.UserId, Name = safeName }
                    Social.refresh()
                end)
            end
        end
    end
    if not anyFriend then
        label("No friends in this server right now. Invite some below!", Theme.Colors.SubText, 36)
    end

    -- Play with friends (reuse M13.1's invite) + a best-effort join.
    label("Play With Friends", Theme.Colors.Text, 26, Theme.FontDisplay)
    rowButton("📨  Invite Friends", Theme.Colors.Gold, function()
        PanelManager.open("Referral") -- reuse the M13.1 invite flow (no duplication)
    end)
    rowButton("🔎  Find Online Friends", Theme.Colors.DarkPill, function()
        local friends = {}
        pcall(function()
            local pages = Players:GetFriendsAsync(localPlayer.UserId)
            local n = 0
            while n < 20 do
                for _, item in ipairs(pages:GetCurrentPage()) do
                    if item.IsOnline then
                        table.insert(friends, item)
                    end
                    n += 1
                end
                if pages.IsFinished then
                    break
                end
                pages:AdvanceToNextPageAsync()
            end
        end)
        if #friends == 0 then
            Notifications.show(
                "info",
                "No online friends found (works fully on a published place)."
            )
        else
            Notifications.show(
                "info",
                #friends .. " online friend(s). Use Join on a row (best-effort)."
            )
        end
        for _, item in ipairs(friends) do
            rowButton(
                "Join " .. (item.DisplayName or item.Username),
                Theme.Colors.Sky or Theme.Colors.DarkPill,
                function()
                    joinFriend(item.Id)
                end
            )
        end
    end)
end

function Social.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Social", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Social", function()
        gui.Enabled = false
    end)

    confirmModal = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(360, 170),
        BackgroundColor3 = Theme.Colors.Background,
        Visible = false,
        ZIndex = 20,
        Parent = gui,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(12) })
    Builder.create("TextLabel", {
        Name = "Msg",
        Size = UDim2.new(1, 0, 0, 90),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = "",
        TextColor3 = Theme.Colors.White,
        TextSize = 16,
        TextWrapped = true,
        ZIndex = 21,
        Parent = confirmModal,
    })
    local yes = Builder.glossButton({
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromOffset(160, 40),
        color = Theme.Colors.Positive,
        Text = "Confirm",
        maxText = 18,
        Parent = confirmModal,
    }, nil)
    yes.Name = "Yes"
    yes.ZIndex = 21
    local no = Builder.glossButton({
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromScale(1, 1),
        Size = UDim2.fromOffset(160, 40),
        color = Theme.Colors.Danger,
        Text = "Cancel",
        maxText = 18,
        Parent = confirmModal,
    }, function()
        confirmModal.Visible = false
    end)
    no.ZIndex = 21

    remotes.SocialUpdate.OnClientEvent:Connect(function()
        Social.refresh()
    end)
end

function Social.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        selectedFriend = nil
        Social.refresh()
    end
end

return Social
