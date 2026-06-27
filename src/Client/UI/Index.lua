-- Index: the collection book, styled to the reference (glossy pink header, a LEFT RAIL of filter
-- pills, a GRID of cards shown DISCOVERED or LOCKED, and a BOTTOM progress bar + "collect X for +Y").
-- Pure UI: renders from the server state (Discovered set, discovered Mutations, Claimed sets, Score)
-- and only sends a milestone Id to claim. The Index SYSTEM/logic is untouched.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local IndexConfig = require(Shared:WaitForChild("IndexConfig"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))
local SetsConfig = require(Shared:WaitForChild("SetsConfig"))

local Index = {}

local player = nil
local remotes = nil
local gui = nil
local grid = nil -- the card grid ScrollingFrame
local bottomBar = nil -- the progress/claim strip
local railButtons = {} -- [filterKey] = pill button
local filter = "All"
local lastState = nil

-- Client mirror of the server completion sets (premium excluded from free completion).
local rarityIds = {}
local allFreeIds = {}
for _, item in ipairs(Catalog.Items) do
    -- M11.4: seasonal exclusives appear in the grid (FOMO) but are NOT required for completion.
    local countable = (IndexConfig.IncludePremiumInCompletion or item.Premium ~= true)
        and item.ExclusiveSeason == nil
    if countable then
        rarityIds[item.Rarity] = rarityIds[item.Rarity] or {}
        table.insert(rarityIds[item.Rarity], item.Id)
        table.insert(allFreeIds, item.Id)
    end
end

-- Rail filters: All + each rarity (data-backed) + Mutations (the variant strip).
local FILTERS =
    { "All", "Sets", "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Mutations" }

local function countDiscovered(discovered)
    local n = 0
    for _ in pairs(discovered) do
        n += 1
    end
    return n
end

local function rewardText(reward)
    if reward.Type == "Multiplier" then
        return string.format("+%d%% cash", math.floor(reward.Bonus * 100 + 0.5))
    elseif reward.Type == "Cash" then
        return "$" .. Format.full(reward.Amount)
    elseif reward.Type == "Luck" then
        return string.format("x%.2g luck", reward.Mult)
    elseif reward.Type == "Brainrot" then
        return "a brainrot"
    end
    return "a reward"
end

-- ===========================================================================================
-- A single grid card (discovered or locked).
-- ===========================================================================================
local function gridCard(order, opts)
    local card = Builder.create("Frame", {
        Size = UDim2.fromOffset(104, 128),
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.padding(6) })
    Builder.rarityCard(card, opts.discovered and opts.color or Theme.Colors.Disabled)

    local portrait = Builder.create("ImageLabel", {
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.new(1, 0, 0, 70),
        BackgroundColor3 = opts.discovered and opts.color or Theme.Colors.Disabled,
        BackgroundTransparency = opts.discovered and 0 or 0.35,
        BorderSizePixel = 0,
        Image = (opts.iconId ~= nil and opts.iconId ~= 0) and ("rbxassetid://" .. tostring(
            opts.iconId
        )) or "",
        ScaleType = Enum.ScaleType.Fit,
        Parent = card,
    }, {
        Builder.corner(UDim.new(0, 10)),
        Builder.create("UIStroke", {
            Color = Theme.Colors.Outline,
            Thickness = 2,
            Transparency = 0.35,
        }),
    })
    if not opts.discovered then
        local lock = Builder.create("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Font = Theme.FontDisplay,
            Text = "?",
            TextColor3 = Theme.Colors.SubText,
            TextScaled = true,
            Parent = portrait,
        }, { Builder.padding(16) })
        Builder.styleText(lock, { ink = true })
    end

    local nameLabel = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(0, 74),
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        Text = opts.discovered and opts.title or "???",
        TextColor3 = opts.discovered and Theme.Colors.Ink or Theme.Colors.InkSoft,
        TextSize = 15,
        TextScaled = false,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = card,
    })
    Builder.styleText(nameLabel, { ink = true, keepColor = true })

    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(0, 100),
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = opts.sublabel or "",
        TextColor3 = opts.color,
        TextSize = 13,
        Parent = card,
    })

    card.Parent = grid
end

-- ===========================================================================================
-- A single SET card (M9.4): progress N/M, the perk, and a CLAIM button when complete + unclaimed.
-- ===========================================================================================
local function setCard(order, set, state)
    local total = #set.Members
    local got = 0
    for _, id in ipairs(set.Members) do
        if state.Discovered[id] then
            got += 1
        end
    end
    local claimed = (state.SetsClaimed or {})[set.Key] == true
    local claimable = got >= total and not claimed
    local color = claimed and Theme.Colors.Positive
        or (claimable and Theme.Colors.Accent or Theme.Colors.Disabled)

    local card = Builder.create("Frame", {
        Size = UDim2.fromOffset(104, 128),
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, { Builder.padding(6) })
    Builder.rarityCard(card, color)

    local nameLabel = Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        Text = set.Name .. (set.Premium and "  [P]" or ""),
        TextColor3 = Theme.Colors.Ink,
        TextSize = 14,
        TextWrapped = true,
        Parent = card,
    })
    Builder.styleText(nameLabel, { ink = true, keepColor = true })

    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(0, 34),
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = string.format("%d / %d", got, total),
        TextColor3 = Theme.Colors.Ink,
        TextSize = 20,
        Parent = card,
    })

    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(0, 60),
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = rewardText(set.Reward),
        TextColor3 = Theme.Colors.Positive,
        TextSize = 12,
        TextWrapped = true,
        Parent = card,
    })

    if claimable then
        Builder.glossButton({
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromScale(0.5, 1),
            Size = UDim2.new(1, 0, 0, 30),
            color = Theme.Colors.Positive,
            Text = "CLAIM",
            maxText = 16,
            Parent = card,
        }, function()
            local ok, result = pcall(function()
                return remotes.ClaimSetPerk:InvokeServer(set.Key)
            end)
            if ok and type(result) == "table" and result.Result == "Success" then
                Index.refresh()
            end
        end)
    else
        local stateLabel = Builder.create("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromScale(0.5, 1),
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Font = Theme.FontDisplay,
            Text = claimed and "CLAIMED" or (set.Premium and "PREMIUM" or "LOCKED"),
            TextColor3 = claimed and Theme.Colors.Positive or Theme.Colors.InkSoft,
            TextSize = 14,
            Parent = card,
        })
        Builder.styleText(stateLabel, { ink = true, keepColor = true })
    end

    card.Parent = grid
end

-- ===========================================================================================
-- Render the grid for the current filter.
-- ===========================================================================================
local function renderGrid(state)
    for _, child in ipairs(grid:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    local order = 0
    if filter == "Mutations" then
        for _, mutation in ipairs(MutationConfig.Mutations) do
            if mutation.Key ~= "normal" then
                order += 1
                gridCard(order, {
                    discovered = (state.Mutations or {})[mutation.Key] == true,
                    title = mutation.DisplayName,
                    color = mutation.Color,
                    sublabel = "x" .. tostring(mutation.IncomeMultiplier),
                })
            end
        end
    elseif filter == "Sets" then
        for _, set in ipairs(SetsConfig.Sets) do
            order += 1
            setCard(order, set, state)
        end
    else
        for _, item in ipairs(Catalog.GetSorted()) do
            local include = IndexConfig.IncludePremiumInCompletion or item.Premium ~= true
            if include and (filter == "All" or item.Rarity == filter) then
                local rarity = Rarity.Get(item.Rarity)
                order += 1
                gridCard(order, {
                    discovered = state.Discovered[item.Id] == true,
                    title = item.DisplayName,
                    color = rarity.Color,
                    -- M11.4: an exclusive reads as a "Season N Exclusive" badge -- discovered = a flex,
                    -- locked = the FOMO "was available in Season N" (no exploitable info to obtain it).
                    sublabel = item.ExclusiveSeason ~= nil
                            and ("Season " .. item.ExclusiveSeason .. " Excl.")
                        or rarity.DisplayName,
                    iconId = item.IconId,
                })
            end
        end
    end
end

-- ===========================================================================================
-- Render the bottom bar: progress + the set perk, with a claim button when the set is complete.
-- ===========================================================================================
local function setMilestoneFor(rarityKey)
    for _, milestone in ipairs(IndexConfig.Milestones) do
        if milestone.Type == "Rarity" and milestone.Rarity == rarityKey then
            return milestone
        end
    end
    return nil
end

local function nextUnclaimed(state)
    for _, milestone in ipairs(IndexConfig.Milestones) do
        if not state.Claimed[milestone.Id] then
            return milestone
        end
    end
    return nil
end

local function renderBottom(state)
    for _, child in ipairs(bottomBar:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    -- Decide which milestone + progress this filter shows.
    local milestone, found, total
    if filter == "Mutations" then
        local got = 0
        for _, m in ipairs(MutationConfig.Mutations) do
            if m.Key ~= "normal" and (state.Mutations or {})[m.Key] then
                got += 1
            end
        end
        found, total = got, #MutationConfig.Mutations - 1
    elseif filter == "All" then
        milestone = nextUnclaimed(state)
        found, total = countDiscovered(state.Discovered), #allFreeIds
    elseif filter == "Sets" then
        -- Sets are claimed per-card above; the bar just shows how many sets are done.
        local got = 0
        for _, set in ipairs(SetsConfig.Sets) do
            if (state.SetsClaimed or {})[set.Key] then
                got += 1
            end
        end
        found, total = got, #SetsConfig.Sets
    else
        milestone = setMilestoneFor(filter)
        local ids = rarityIds[filter] or {}
        local got = 0
        for _, id in ipairs(ids) do
            if state.Discovered[id] then
                got += 1
            end
        end
        found, total = got, #ids
    end

    local line = milestone ~= nil
            and ("Collect " .. milestone.Name .. "  ->  " .. rewardText(milestone.Reward))
        or string.format("Collected %d / %d", found, total)
    local label = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -120, 0, 22),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = line,
        TextColor3 = Theme.Colors.Positive,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = bottomBar,
    })
    Builder.styleText(label, { ink = true, keepColor = true, font = Theme.FontBody })

    local barBg = Builder.create("Frame", {
        Position = UDim2.fromOffset(2, 30),
        Size = UDim2.new(1, -120, 0, 16),
        BackgroundColor3 = Theme.Colors.Background,
        BorderSizePixel = 0,
        Parent = bottomBar,
    }, { Builder.corner(UDim.new(1, 0)) })
    local pct = total > 0 and math.clamp(found / total, 0, 1) or 0
    Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = string.format("%d / %d", found, total),
        TextColor3 = Theme.Colors.Ink,
        TextSize = 13,
        ZIndex = 2,
        Parent = barBg,
    })
    Builder.create("Frame", {
        Size = UDim2.fromScale(pct, 1),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Parent = barBg,
    }, { Builder.corner(UDim.new(1, 0)) })

    -- Claim button (only when the set milestone is complete + unclaimed).
    if milestone ~= nil and not state.Claimed[milestone.Id] and found >= total and total > 0 then
        Builder.glossButton({
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -2, 0.5, 0),
            Size = UDim2.fromOffset(108, 44),
            color = Theme.Colors.Positive,
            Text = "CLAIM",
            maxText = 20,
            Parent = bottomBar,
        }, function()
            local ok, result = pcall(function()
                return remotes.ClaimIndexReward:InvokeServer(milestone.Id)
            end)
            if ok and type(result) == "table" and result.Result == "Success" then
                Index.refresh()
            end
        end)
    end
end

-- ===========================================================================================
-- Refresh + shell
-- ===========================================================================================
local function setFilter(key, state)
    filter = key
    for filterKey, button in pairs(railButtons) do
        Builder.setPillSelected(button, "Index", filterKey == key)
    end
    renderGrid(state)
    renderBottom(state)
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
    state.Mutations = state.Mutations or {}
    state.SetsClaimed = state.SetsClaimed or {}
    lastState = state
    setFilter(filter, state)
end

local function buildShell()
    local panel = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.84, 0.7),
        BackgroundColor3 = Theme.Colors.Background,
        BackgroundTransparency = Theme.BodyTransparency,
        BorderSizePixel = 0,
    }, {
        Builder.corner(Theme.Radius.Panel),
        Builder.create(
            "UIStroke",
            { -- standard thick bright panel border (matches every other panel)
                Color = Theme.Border.Color,
                Thickness = Theme.Border.Width,
                Transparency = Theme.Border.Transparency,
            }
        ),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(560, 680) }),
        Builder.create("UIGradient", { -- bright gloss top -> soft cloud body
            Rotation = 90,
            Color = ColorSequence.new(Theme.Colors.CloudTop, Theme.Colors.Cloud),
        }),
    })
    panel:SetAttribute("Glassed", true)

    Builder.glossHeader(panel, "Index", "Index", function()
        gui.Enabled = false
    end)

    local top = Theme.HeaderHeight + 14
    local bottomH = 64

    -- Left rail of filter pills (vertical scroll).
    local rail = Builder.create("ScrollingFrame", {
        Position = UDim2.fromOffset(8, top),
        Size = UDim2.new(0, 104, 1, -(top + bottomH + 8)),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = panel,
    }, {
        Builder.create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        }),
        Builder.padding(4),
    })
    Builder.styleScroll(rail)
    for i, key in ipairs(FILTERS) do
        local button = Builder.glossButton({
            LayoutOrder = i,
            Size = UDim2.new(1, -4, 0, 38),
            color = Theme.Colors.Row,
            Text = key,
            maxText = 16,
            Parent = rail,
        }, function()
            if lastState ~= nil then
                setFilter(key, lastState)
            end
        end)
        railButtons[key] = button
    end

    -- The card grid.
    grid = Builder.create("ScrollingFrame", {
        Position = UDim2.fromOffset(118, top),
        Size = UDim2.new(1, -126, 1, -(top + bottomH + 8)),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = panel,
    }, {
        Builder.create("UIGridLayout", {
            CellSize = UDim2.fromOffset(104, 128),
            CellPadding = UDim2.fromOffset(14, 14),
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        }),
        Builder.padding(8),
    })
    Builder.styleScroll(grid)

    -- Bottom progress/claim strip.
    bottomBar = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -8),
        Size = UDim2.new(1, -16, 0, bottomH - 4),
        BorderSizePixel = 0,
        Parent = panel,
    }, { Builder.padding(8) })
    Builder.rarityCard(bottomBar, Theme.Colors.Accent)

    panel.Parent = gui
end

function Index.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Index", player:WaitForChild("PlayerGui"), false)
    buildShell()
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
