-- Index: the collection book. Shows every roster entry grouped by rarity as DISCOVERED (name +
-- rarity colour + income) or LOCKED (a greyed "???" silhouette revealing only the rarity slot),
-- per-rarity + overall progress, the rarity-weighted collection score, and the completion
-- milestones with claimed/claimable/locked states + a claim button. The client only sends a
-- milestone Id to claim; the server re-validates completion + dedupes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local IndexConfig = require(Shared:WaitForChild("IndexConfig"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))

local Index = {}

local player = nil
local remotes = nil
local gui = nil
local list = nil

-- Client mirror of the server completion sets (premium excluded from free completion).
local rarityIds = {}
local allFreeIds = {}
for _, item in ipairs(Catalog.Items) do
    if IndexConfig.IncludePremiumInCompletion or item.Premium ~= true then
        rarityIds[item.Rarity] = rarityIds[item.Rarity] or {}
        table.insert(rarityIds[item.Rarity], item.Id)
        table.insert(allFreeIds, item.Id)
    end
end

local function toHex(color)
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function countDiscovered(discovered)
    local n = 0
    for _ in pairs(discovered) do
        n += 1
    end
    return n
end

local function allIn(discovered, ids)
    for _, id in ipairs(ids) do
        if not discovered[id] then
            return false
        end
    end
    return true
end

-- Mirrors IndexService.isMet for display only; the claim is server-validated regardless.
local function isMet(discovered, milestone)
    if milestone.Type == "Rarity" then
        return allIn(discovered, rarityIds[milestone.Rarity] or {})
    elseif milestone.Type == "Total" then
        return countDiscovered(discovered) >= milestone.Count
    elseif milestone.Type == "FullRoster" then
        return allIn(discovered, allFreeIds)
    end
    return false
end

local function clearRows()
    -- Destroy ALL content (frames, labels, buttons); UIListLayout/UIPadding are UIComponents, not
    -- GuiObjects, so they survive. (Previously only Frames were cleared, so headers accumulated.)
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

local function header(text, order)
    local label = Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Theme.Colors.Text,
        TextSize = 19,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = order,
        Parent = list,
    })
    Builder.applyChrome(label, { stroke = 2 })
end

-- Compact reward text for the "collect X for +Y" callout.
local function rewardText(reward)
    if reward.Type == "Multiplier" then
        return string.format("+%d%% cash", math.floor(reward.Bonus * 100 + 0.5))
    elseif reward.Type == "Cash" then
        return "$" .. Format.full(reward.Amount)
    elseif reward.Type == "Brainrot" then
        return "a brainrot"
    end
    return "a reward"
end

-- The headline progress card: overall completion bar + the next unclaimed set's perk.
local function progressCard(state, order)
    local found = countDiscovered(state.Discovered)
    local total = #allFreeIds
    local pct = total > 0 and math.clamp(found / total, 0, 1) or 0

    local card = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 88),
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.padding(10) })
    Builder.rarityCard(card, Theme.Colors.Accent)

    local title = Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        Text = string.format("Collection   %d / %d", found, total),
        TextColor3 = Theme.Colors.Text,
        TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    Builder.applyChrome(title, { stroke = 2 })

    local barBg = Builder.create("Frame", {
        Position = UDim2.fromOffset(0, 30),
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundColor3 = Theme.Colors.Background,
        BorderSizePixel = 0,
        Parent = card,
    }, { Builder.corner(UDim.new(1, 0)) })
    Builder.create("Frame", {
        Size = UDim2.fromScale(pct, 1),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Parent = barBg,
    }, { Builder.corner(UDim.new(1, 0)) })

    local nextPerk = nil
    for _, milestone in ipairs(IndexConfig.Milestones) do
        if not state.Claimed[milestone.Id] then
            nextPerk = milestone
            break
        end
    end
    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(0, 52),
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = nextPerk ~= nil and ("Collect " .. nextPerk.Name .. "  ->  " .. rewardText(
            nextPerk.Reward
        )) or "All sets complete!",
        TextColor3 = Theme.Colors.Positive,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    card.Parent = list
end

local function rosterRow(item, discovered, order)
    local rarity = Rarity.Get(item.Rarity)
    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 46),
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.padding(8) })
    -- Discovered = rarity-bordered card; locked = muted/disabled border (reads as a silhouette slot).
    Builder.rarityCard(row, discovered and rarity.Color or Theme.Colors.Disabled)

    Builder.create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = discovered and rarity.Color or Theme.Colors.Disabled,
        BorderSizePixel = 0,
        Parent = row,
    }, {
        Builder.corner(UDim.new(0, 8)),
        Builder.create("UIStroke", {
            Color = Theme.Colors.Outline,
            Thickness = 2,
            Transparency = 0.3,
        }),
    })

    local label = Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(40, 0),
        Size = UDim2.new(1, -44, 1, 0),
        Font = Theme.FontBody,
        RichText = true,
        Text = discovered
                and string.format(
                    '%s  <font color="%s">%s</font>  +$%s/s',
                    item.DisplayName,
                    toHex(rarity.Color),
                    rarity.DisplayName,
                    Format.full(item.IncomePerSec)
                )
            or (
                '🔒 ??? <font color="'
                .. toHex(rarity.Color)
                .. '">'
                .. rarity.DisplayName
                .. "</font>"
            ),
        TextColor3 = discovered and Theme.Colors.Text or Theme.Colors.SubText,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    Builder.applyChrome(label, { font = Theme.FontBody, stroke = 2, softShadow = false })
    row.Parent = list
end

local function milestoneRow(milestone, state, order)
    local claimed = state.Claimed[milestone.Id] == true
    local met = isMet(state.Discovered, milestone)
    local row = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = Theme.Colors.Row,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.corner(UDim.new(0, 10)), Builder.padding(8) })
    Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(2, 0),
        Size = UDim2.new(1, -110, 1, 0),
        Font = Theme.FontBold,
        Text = milestone.Name,
        TextColor3 = Theme.Colors.Text,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    local button = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(100, 38),
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        TextSize = 15,
        Parent = row,
    }, { Builder.corner(UDim.new(0, 8)) })

    if claimed then
        button.Text = "Claimed"
        button.BackgroundColor3 = Theme.Colors.Disabled
        button.TextColor3 = Theme.Colors.SubText
        button.Active = false
        button.AutoButtonColor = false
    elseif met then
        button.Text = "CLAIM"
        button.BackgroundColor3 = Theme.Colors.Positive
        button.TextColor3 = Theme.Colors.Text
        button.Activated:Connect(function()
            local ok, result = pcall(function()
                return remotes.ClaimIndexReward:InvokeServer(milestone.Id)
            end)
            if ok and type(result) == "table" and result.Result == "Success" then
                Index.refresh()
            end
        end)
    else
        button.Text = "Locked"
        button.BackgroundColor3 = Theme.Colors.Disabled
        button.TextColor3 = Theme.Colors.SubText
        button.Active = false
        button.AutoButtonColor = false
    end
    row.Parent = list
end

function Index.refresh()
    if gui == nil then
        return
    end
    local ok, state = pcall(function()
        return remotes.GetIndex:InvokeServer()
    end)
    if not ok or type(state) ~= "table" then
        return
    end
    state.Discovered = state.Discovered or {}
    state.Claimed = state.Claimed or {}

    clearRows()
    local order = 0
    local function nextOrder()
        order += 1
        return order
    end

    progressCard(state, nextOrder())

    header("Milestones", nextOrder())
    for _, milestone in ipairs(IndexConfig.Milestones) do
        milestoneRow(milestone, state, nextOrder())
    end

    -- Mutations discovery strip (compact -- NOT a full species x mutation grid).
    local mutations = state.Mutations or {}
    header("Mutations", nextOrder())
    for _, m in ipairs(MutationConfig.Mutations) do
        if m.Key ~= "normal" then
            local has = mutations[m.Key] == true
            Builder.create("TextLabel", {
                Size = UDim2.new(1, 0, 0, 26),
                BackgroundTransparency = 1,
                Font = Theme.FontBold,
                Text = string.format(
                    "%s (x%d)  %s",
                    m.DisplayName,
                    m.IncomeMultiplier,
                    has and "owned" or "locked"
                ),
                TextColor3 = has and m.Color or Theme.Colors.Disabled,
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = nextOrder(),
                Parent = list,
            })
        end
    end

    -- Each rarity tier: a header with its found/total, then that tier's roster rows beneath it.
    for _, tier in ipairs(Rarity.Ordered) do
        local ids = rarityIds[tier.Key]
        if ids ~= nil then
            local found = 0
            for _, id in ipairs(ids) do
                if state.Discovered[id] then
                    found += 1
                end
            end
            header(string.format("%s  (%d/%d)", tier.DisplayName, found, #ids), nextOrder())
            for _, item in ipairs(Catalog.GetSorted()) do
                if
                    item.Rarity == tier.Key
                    and (IndexConfig.IncludePremiumInCompletion or item.Premium ~= true)
                then
                    rosterRow(item, state.Discovered[item.Id] == true, nextOrder())
                end
            end
        end
    end
end

function Index.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Index", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Index", function()
        gui.Enabled = false
    end)
end

function Index.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        Index.refresh()
    end
end

return Index
