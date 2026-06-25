-- Seasons: the competitive-season panel. Renders ONLY the server-replicated season state
-- (GetSeasons) -- season id, a server-derived countdown, the top-N board, the player's own
-- score + rank, and the track/ranked reward tiers. The client never decides the season or rank.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local Seasons = {}

local player = nil
local remotes = nil
local gui = nil
local list = nil
local order = 0

local function nextOrder()
    order += 1
    return order
end

local function fmtTime(s)
    s = math.max(0, math.floor(s))
    local d = math.floor(s / 86400)
    local h = math.floor((s % 86400) / 3600)
    local m = math.floor((s % 3600) / 60)
    if d > 0 then
        return d .. "d " .. h .. "h"
    elseif h > 0 then
        return h .. "h " .. m .. "m"
    end
    return m .. "m"
end

local function clear()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end
end

local function label(text, color, size, bold)
    Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, size or 24),
        BackgroundTransparency = 1,
        Font = bold and Theme.FontBold or Theme.Font,
        Text = text,
        TextColor3 = color or Theme.Colors.Text,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = list,
    })
end

function Seasons.refresh()
    if gui == nil then
        return
    end
    local ok, state = pcall(function()
        return remotes.GetSeasons:InvokeServer()
    end)
    clear()
    order = 0
    if not ok or type(state) ~= "table" then
        label("Seasons unavailable right now.", Theme.Colors.SubText)
        return
    end

    local countdown = state.EndsAt == 0 and "ACTIVE"
        or ("ends in " .. fmtTime(state.EndsAt - state.Now))
    label("Season #" .. state.SeasonId .. "  —  " .. countdown, Theme.Colors.Accent, 28, true)
    label(
        string.format(
            "Your score: %s   (%s)",
            Format.short(state.MyScore),
            state.MyRank ~= nil and ("rank " .. state.MyRank) or "unranked"
        ),
        Theme.Colors.Positive,
        24,
        true
    )

    label("Leaderboard", Theme.Colors.Text, 22, true)
    if #state.Top == 0 then
        label("(no entries yet -- earn season points!)", Theme.Colors.SubText)
    end
    for _, row in ipairs(state.Top) do
        label(
            string.format("%d.  %s  —  %s pts", row.Rank, row.Name, Format.short(row.Value)),
            Theme.Colors.Text
        )
    end

    label("Track rewards (your score)", Theme.Colors.Text, 22, true)
    for _, tier in ipairs(state.Track) do
        local met = state.MyScore >= tier.Score
        label(
            string.format(
                "%s pts  ->  $%s  %s",
                Format.short(tier.Score),
                Format.short(tier.Reward.Amount),
                met and "✓" or ""
            ),
            met and Theme.Colors.Positive or Theme.Colors.SubText
        )
    end

    label("Ranked rewards (final rank)", Theme.Colors.Text, 22, true)
    for _, tier in ipairs(state.Ranked) do
        local range = tier.Min == tier.Max and ("Rank " .. tier.Min)
            or ("Rank " .. tier.Min .. "-" .. tier.Max)
        label(
            string.format("%s  ->  $%s", range, Format.short(tier.Reward.Amount)),
            Theme.Colors.SubText
        )
    end

    label(
        "Rewards are paid automatically on your next login after the season ends.",
        Theme.Colors.SubText
    )
end

function Seasons.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Seasons", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Seasons", function()
        gui.Enabled = false
    end)

    remotes.SeasonsUpdate.OnClientEvent:Connect(function()
        if gui.Enabled then
            Seasons.refresh()
        end
    end)
end

function Seasons.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        Seasons.refresh()
    end
end

return Seasons
