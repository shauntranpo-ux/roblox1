-- Exclusives (M11.4): a FUNCTIONAL panel for SEASONAL EXCLUSIVES. Shows THIS season's exclusives
-- (what they are, how to obtain each, owned status), a season countdown (reused from GetSeasons), and
-- the full owned/missed list (FOMO). Shop exclusives can be bought here with earned cash. The client
-- sends INTENT ONLY ({ Action="buy", Key }); the server gates by server-time window + the claim set.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local Exclusives = {}

local player = nil
local remotes = nil
local gui = nil
local list = nil
local order = 0
local lastMessage = nil

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

local function getState()
    local ok, result = pcall(function()
        return remotes.ExclusiveAction:InvokeServer({ Action = "get" })
    end)
    if ok and type(result) == "table" and type(result.State) == "table" then
        return result.State
    end
    return { SeasonId = 0, Current = {}, All = {} }
end

local function countdownText()
    local ok, season = pcall(function()
        return remotes.GetSeasons:InvokeServer()
    end)
    if not ok or type(season) ~= "table" then
        return ""
    end
    if (season.EndsAt or 0) <= 0 then
        return "  (forced window)"
    end
    local secs = math.max(0, (season.EndsAt or 0) - (season.Now or 0))
    local d = math.floor(secs / 86400)
    local h = math.floor((secs % 86400) / 3600)
    return string.format("  ·  leaves in %dd %dh", d, h)
end

local function doBuy(key)
    local _, result = pcall(function()
        return remotes.ExclusiveAction:InvokeServer({ Action = "buy", Key = key })
    end)
    if type(result) == "table" then
        lastMessage = result.Message
    end
    Exclusives.refresh()
end

local function sourceText(ex)
    if ex.Source == "track" then
        return "Earn: reach " .. tostring(ex.TrackScore) .. " season pts"
    elseif ex.Source == "ranked" then
        return "Earn: finish Top " .. tostring(ex.RankMax)
    elseif ex.Source == "shop" then
        return "Shop: $" .. Format.full(ex.Price or 0)
    elseif ex.Source == "boss" then
        return "Drops from world bosses this season"
    elseif ex.Source == "catch" then
        return "Catch in the wild this season"
    end
    return ex.Source or ""
end

local function exclusiveCard(ex)
    local card = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 78),
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
    }, { Builder.padding(10) })
    Builder.rarityCard(card, ex.Owned and Theme.Colors.Positive or Theme.accentColor("Exclusives"))

    local title = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -116, 0, 22),
        BackgroundTransparency = 1,
        Text = ex.DisplayName .. "  [" .. ex.Kind .. "]",
        TextColor3 = Theme.Colors.Ink,
        TextSize = 16,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    Builder.applyChrome(title, { stroke = 2 })

    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 28),
        Size = UDim2.new(1, -116, 0, 18),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = sourceText(ex),
        TextColor3 = Theme.Colors.InkSoft,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    if ex.Owned then
        local owned = Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(104, 48),
            BackgroundTransparency = 1,
            Font = Theme.FontDisplay,
            Text = "OWNED",
            TextColor3 = Theme.Colors.Positive,
            TextSize = 16,
            Parent = card,
        })
        Builder.applyChrome(owned, { stroke = 2 })
    elseif ex.Source == "shop" and ex.Obtainable then
        Builder.glossButton({
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(104, 54),
            color = Theme.accentColor("Exclusives"),
            Text = "BUY",
            maxText = 18,
            Parent = card,
        }, function()
            doBuy(ex.Key)
        end)
    else
        local note = Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(104, 48),
            BackgroundTransparency = 1,
            Font = Theme.FontBody,
            Text = ex.Obtainable and "earn it!" or "window closed",
            TextColor3 = Theme.Colors.InkSoft,
            TextSize = 13,
            TextWrapped = true,
            Parent = card,
        })
        note.TextXAlignment = Enum.TextXAlignment.Center
    end

    card.Parent = list
end

function Exclusives.refresh()
    if gui == nil then
        return
    end
    clearRows()
    order = 0

    if lastMessage ~= nil then
        label(lastMessage, Theme.Colors.Accent, 26, Theme.FontDisplay)
    end

    local state = getState()
    label(
        "Season " .. tostring(state.SeasonId) .. " exclusives" .. countdownText(),
        Theme.Colors.Ink,
        26,
        Theme.FontDisplay
    )
    label(
        "Get these ONLY this season -- then they're gone forever. Owned copies stay yours + are tradeable.",
        Theme.Colors.InkSoft,
        32
    )

    if #state.Current == 0 then
        label("No exclusives are live this season. Check back next season!", Theme.Colors.InkSoft)
    else
        for _, ex in ipairs(state.Current) do
            exclusiveCard(ex)
        end
    end

    -- The full owned/missed roll (FOMO): every configured exclusive + whether you have it.
    label("All exclusives (owned / missed)", Theme.Colors.Ink, 28, Theme.FontDisplay)
    for _, ex in ipairs(state.All) do
        label(
            (ex.Owned and "  ✓ " or "  ✗ ")
                .. ex.DisplayName
                .. "  (Season "
                .. tostring(ex.SeasonId)
                .. ")",
            ex.Owned and Theme.Colors.Positive or Theme.Colors.InkSoft,
            20
        )
    end
end

function Exclusives.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Exclusives", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Exclusives", function()
        gui.Enabled = false
    end)
end

function Exclusives.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        lastMessage = nil
        Exclusives.refresh()
    end
end

return Exclusives
