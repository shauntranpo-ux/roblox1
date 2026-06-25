-- Referral (M13.1): the FUNCTIONAL invite panel. Shows your qualified-friend count, the current capped
-- income BOOST, the tier-reward ladder (claimed / reached / locked), the qualifying milestone, and an
-- Invite button that fires SocialService:PromptGameInvite with the inviter's userId in launchData. The
-- client sends INTENT only (the actual attribution + rewards are server-authoritative). Degrades
-- gracefully if invites aren't available. Styling is the look-pass.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Notifications = require(script.Parent.Notifications)

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local Referral = {}

local player, remotes = nil, nil
local gui, list = nil, nil
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

-- Fire the platform invite prompt with the referral launchData. Guarded -> degrades cleanly.
local function doInvite()
    local ok, canSend = pcall(function()
        return SocialService:CanSendGameInviteAsync(player)
    end)
    if not ok or not canSend then
        Notifications.show("error", "Invites aren't available right now.")
        return
    end
    local options
    pcall(function()
        options = Instance.new("ExperienceInviteOptions")
        options.PromptMessage = "Join me -- we both get rewards!"
        options.LaunchData = "ref:" .. player.UserId -- the server reads this on the invitee's join
    end)
    local promptOk = pcall(function()
        SocialService:PromptGameInvite(player, options)
    end)
    if not promptOk then
        -- Fallback to the no-options form (still opens the prompt; attribution just won't attach).
        promptOk = pcall(function()
            SocialService:PromptGameInvite(player)
        end)
    end
    if promptOk then
        pcall(function()
            remotes.ReferralAction:InvokeServer("invitelog")
        end)
    else
        Notifications.show("error", "Couldn't open the invite prompt.")
    end
end

function Referral.refresh()
    if gui == nil or not gui.Enabled then
        return
    end
    local ok, result = pcall(function()
        return remotes.ReferralAction:InvokeServer("get")
    end)
    local state = (ok and type(result) == "table") and result.State or nil
    clearRows()
    order = 0
    if state == nil then
        label("Unavailable.", Theme.Colors.Danger)
        return
    end

    label("Invite Friends", Theme.Colors.Gold, 30, Theme.FontDisplay)
    label(
        "+" .. tostring(state.BoostPct) .. "% income  (max +" .. tostring(state.CapPct) .. "%)",
        Theme.Colors.Positive,
        30,
        Theme.FontDisplay
    )
    label(
        tostring(state.Count)
            .. " qualified friend(s)  —  +"
            .. tostring(state.PerPct)
            .. "% each",
        Theme.Colors.Text
    )
    label(
        "A friend QUALIFIES when they "
            .. tostring(state.Milestone)
            .. ". They also get a $"
            .. Format.short(state.Welcome)
            .. " welcome bonus.",
        Theme.Colors.SubText,
        40
    )

    -- Tier ladder.
    label("Reward Tiers", Theme.Colors.Text, 26, Theme.FontDisplay)
    for _, tier in ipairs(state.Tiers) do
        local statusColor = tier.Claimed and Theme.Colors.Positive
            or (tier.Reached and Theme.Colors.Gold or Theme.Colors.SubText)
        local status = tier.Claimed and "✓ claimed" or (tier.Reached and "reached" or "locked")
        label(
            tier.Count
                .. " friends — "
                .. tier.Title
                .. ":  $"
                .. Format.short(tier.Cash)
                .. "   ("
                .. status
                .. ")",
            statusColor,
            24
        )
    end

    -- Invite button.
    Builder.glossButton({
        Size = UDim2.new(1, 0, 0, 52),
        color = Theme.Colors.Gold,
        Text = "📨  Invite a Friend",
        maxText = 22,
        LayoutOrder = nextOrder(),
        Parent = list,
    }, doInvite)

    if state.WasReferred then
        label("You joined via an invite — thanks!", Theme.Colors.SubText, 22)
    end
end

function Referral.mount(context)
    player = context.player or Players.LocalPlayer
    remotes = context.remotes
    gui = Builder.screenGui("Referral", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Referral", function()
        gui.Enabled = false
    end)
    remotes.ReferralUpdate.OnClientEvent:Connect(function()
        Referral.refresh()
    end)
end

function Referral.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        Referral.refresh()
    end
end

return Referral
