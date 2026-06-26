-- Inventory (M12.3): a VIRTUALIZED inventory panel that stays smooth at hundreds+ of units. It pools a
-- small fixed set of row cells and recycles them across a scroll window (NEVER one frame per unit), with
-- client-side SORT / FILTER / SEARCH building a view over the server's replicated owned list. FAVORITE
-- + LOCK toggles and BULK actions (sell selected / by filter, mass-fuse, lock/favorite selected) all
-- send INTENT only -- the SERVER re-resolves + re-validates every action and excludes protected units.
-- A destructive bulk action shows a confirm dialog (server still re-validates). Styling is the look-pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Notifications = require(script.Parent.Notifications)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local FusionConfig = require(Shared:WaitForChild("FusionConfig"))

local Inventory = {}

local CELL_H = 60
local POOL = 16 -- recycled cells (covers the viewport + buffer; the key to scale)

local player, remotes = nil, nil
local gui, scroll, content, toolbar, statusLabel, confirmModal = nil, nil, nil, nil, nil, nil
local cells = {} -- pooled row cells { frame, name, info, income, favBtn, lockBtn, sellBtn, selDot, entry }
local owned = {} -- the server's owned list (last fetch)
local view = {} -- sorted/filtered/searched index into owned
local selected = {} -- [unitId] = true (multi-select)
local multiSelect = false
local sortMode, filterMode, search = "Rarity", "All", ""

local SORTS = { "Rarity", "Value", "Star", "Newest", "Favorited" }
local FILTERS =
    { "All", "Common", "Rare+", "Locked", "Favorited", "Duplicates", "Placed", "Unplaced" }

local function rarityOrder(entry)
    return Rarity.Get(entry.Rarity).Order
end

-- ── View building (client-side sort/filter/search over the server's list) ───────────────────
local function rebuildView()
    local dupeCount = {}
    for _, e in ipairs(owned) do
        dupeCount[e.Type] = (dupeCount[e.Type] or 0) + 1
    end
    view = {}
    local q = string.lower(search)
    for i, e in ipairs(owned) do
        local ok = true
        if filterMode == "Common" then
            ok = e.Rarity == "Common"
        elseif filterMode == "Rare+" then
            ok = rarityOrder(e) >= 2
        elseif filterMode == "Locked" then
            ok = e.Locked
        elseif filterMode == "Favorited" then
            ok = e.Favorited
        elseif filterMode == "Duplicates" then
            ok = (dupeCount[e.Type] or 0) > 1
        elseif filterMode == "Placed" then
            ok = e.PadIndex ~= nil
        elseif filterMode == "Unplaced" then
            ok = e.PadIndex == nil
        end
        if ok and q ~= "" then
            ok = string.find(string.lower(e.Name), q, 1, true) ~= nil
                or string.find(string.lower(e.Type), q, 1, true) ~= nil
        end
        if ok then
            table.insert(view, i)
        end
    end
    table.sort(view, function(a, b)
        local ea, eb = owned[a], owned[b]
        if sortMode == "Value" then
            return (ea.Value or 0) > (eb.Value or 0)
        elseif sortMode == "Star" then
            return (ea.Star or 1) > (eb.Star or 1)
        elseif sortMode == "Newest" then
            return a > b -- later in the owned list = more recently acquired
        elseif sortMode == "Favorited" then
            if ea.Favorited ~= eb.Favorited then
                return ea.Favorited
            end
            return rarityOrder(ea) > rarityOrder(eb)
        end
        if rarityOrder(ea) ~= rarityOrder(eb) then
            return rarityOrder(ea) > rarityOrder(eb)
        end
        return (ea.IncomePerSec or 0) > (eb.IncomePerSec or 0)
    end)
end

local function countSelected()
    local n = 0
    for _ in pairs(selected) do
        n += 1
    end
    return n
end

-- ── Virtualized render: position the pool over the visible window only ──────────────────────
local function paintCell(cell, entry)
    cell.entry = entry
    if entry == nil then
        cell.frame.Visible = false
        return
    end
    cell.frame.Visible = true
    Builder.rarityCard(cell.frame, Rarity.Get(entry.Rarity).Color)
    local star = (entry.Star and entry.Star > 1) and ("  " .. FusionConfig.Stars(entry.Star)) or ""
    local evo = (entry.EvolutionStage and entry.EvolutionStage > 1)
            and ("  E" .. entry.EvolutionStage)
        or ""
    cell.name.Text = entry.Name .. star .. evo
    cell.info.Text = Rarity.Get(entry.Rarity).DisplayName
        .. (entry.Mutation and ("  •  " .. tostring(entry.Mutation)) or "")
    cell.info.TextColor3 = Rarity.Get(entry.Rarity).Color
    cell.income.Text = "+$" .. Format.full(entry.IncomePerSec or 0) .. "/s"
    cell.favBtn.Text = entry.Favorited and "★" or "☆"
    cell.favBtn.TextColor3 = entry.Favorited and Theme.Colors.Gold or Theme.Colors.SubText
    cell.lockBtn.Text = entry.Locked and "🔒" or "🔓"
    cell.selDot.Visible = multiSelect
    local isSelected = selected[entry.Id] == true
    TweenService:Create(cell.frame, Theme.Tween.Squish, {
        BackgroundColor3 = isSelected and Theme.Colors.Accent or Theme.Colors.DarkPill,
    }):Play()
    cell.selDot.BackgroundColor3 = isSelected and Theme.Colors.Positive or Theme.Colors.DarkPill
    cell.sellBtn.Visible = not multiSelect
        and entry.Sellable
        and not entry.Locked
        and (entry.Value or 0) > 0
    cell.sellBtn.Text = "Sell $" .. Format.short(entry.Value or 0)
end

local function render()
    if scroll == nil then
        return
    end
    content.Size = UDim2.new(1, 0, 0, #view * CELL_H)
    local top = scroll.CanvasPosition.Y
    local first = math.max(0, math.floor(top / CELL_H) - 1)
    for k = 1, POOL do
        local cell = cells[k]
        local idx = first + k
        if idx <= #view then
            cell.frame.Position = UDim2.fromOffset(0, (idx - 1) * CELL_H)
            paintCell(cell, owned[view[idx]])
        else
            paintCell(cell, nil)
        end
    end
    statusLabel.Text = #view
        .. " / "
        .. #owned
        .. " units"
        .. (multiSelect and ("   •   " .. countSelected() .. " selected") or "")
end

-- ── Server fetch + actions ──────────────────────────────────────────────────────────────────
function Inventory.refresh()
    if gui == nil or not gui.Enabled then
        return
    end
    local result = remotes.GetInventory:InvokeServer()
    owned = typeof(result) == "table" and result or {}
    -- Drop selections for units no longer owned.
    local ownedIds = {}
    for _, e in ipairs(owned) do
        ownedIds[e.Id] = true
    end
    for id in pairs(selected) do
        if not ownedIds[id] then
            selected[id] = nil
        end
    end
    rebuildView()
    render()
end

local function toggleFlag(entry, flag)
    local action = flag == "Locked" and "lock" or "favorite"
    local cur = entry[flag] == true
    local ok, result = pcall(function()
        return remotes.InventoryAction:InvokeServer(action, entry.Id, not cur)
    end)
    if ok and type(result) == "table" and result.Result == "Success" then
        entry.Locked = result.Locked
        entry.Favorited = result.Favorited
        rebuildView()
        render()
    end
end

local function sellOne(entry)
    local ok, result = pcall(function()
        return remotes.SellRequest:InvokeServer({ Action = "one", Id = entry.Id, Confirm = true })
    end)
    if ok and type(result) == "table" then
        if result.Result == "Success" then
            Inventory.refresh()
        elseif result.Message ~= nil then
            Notifications.show("error", result.Message)
        end
    end
end

-- Runs a server action with the two-step Confirm dialog for destructive bulk ops.
local function runConfirmable(makePayload, invoke)
    local function attempt(confirm)
        local payload = makePayload()
        payload.Confirm = confirm
        local ok, result = pcall(function()
            return invoke(payload)
        end)
        if not ok or type(result) ~= "table" then
            return
        end
        if result.Result == "Confirm" then
            Inventory.showConfirm(result.Message or "Are you sure?", function()
                attempt(true)
            end)
        elseif result.Result == "Success" then
            if result.Message ~= nil then
                Notifications.show("success", result.Message)
            end
            Inventory.refresh()
        elseif result.Result == "Empty" then
            Notifications.show("error", result.Message or "Nothing matches.")
        elseif result.Message ~= nil then
            Notifications.show("error", result.Message)
        end
    end
    attempt(false)
end

local function sellSelected()
    local ids = {}
    for id in pairs(selected) do
        table.insert(ids, id)
    end
    if #ids == 0 then
        Notifications.show("error", "Select some units first.")
        return
    end
    runConfirmable(function()
        return { Action = "bulk", Mode = "Selection", Ids = ids }
    end, function(p)
        return remotes.SellRequest:InvokeServer(p)
    end)
end

local function sellFilter(mode, extra)
    runConfirmable(function()
        local p = { Action = "bulk", Mode = mode }
        if extra ~= nil then
            for k, v in pairs(extra) do
                p[k] = v
            end
        end
        return p
    end, function(p)
        return remotes.SellRequest:InvokeServer(p)
    end)
end

local function massFuse()
    runConfirmable(function()
        return { Mode = "MassFuse" }
    end, function(p)
        return remotes.FuseRequest:InvokeServer(p)
    end)
end

local function flagSelected(flag, value)
    local action = flag == "Locked" and "lock" or "favorite"
    for id in pairs(selected) do
        pcall(function()
            remotes.InventoryAction:InvokeServer(action, id, value)
        end)
    end
    Inventory.refresh()
end

-- ── Confirm modal ───────────────────────────────────────────────────────────────────────────
function Inventory.showConfirm(message, onConfirm)
    confirmModal.Visible = true
    confirmModal:FindFirstChild("Msg").Text = message
    local yes = confirmModal:FindFirstChild("Yes")
    yes.Activated:Once(function()
        confirmModal.Visible = false
        onConfirm()
    end)
end

-- ── Build ───────────────────────────────────────────────────────────────────────────────────
local function buildToolbar()
    toolbar = Builder.create("Frame", {
        Size = UDim2.new(1, -16, 0, 84),
        Position = UDim2.fromOffset(8, 44),
        BackgroundTransparency = 1,
        Parent = gui:FindFirstChild("Body"),
    }, {
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Wraps = true,
            Padding = UDim.new(0, 8),
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    local searchBox = Builder.create("TextBox", {
        Size = UDim2.fromOffset(200, 34),
        BackgroundColor3 = Theme.Colors.DarkPill,
        Font = Theme.FontBody,
        PlaceholderText = "Search…",
        Text = "",
        TextColor3 = Theme.Colors.White,
        TextSize = 15,
        ClearTextOnFocus = false,
        Parent = toolbar,
    }, { Builder.corner(UDim.new(0, 8)), Builder.padding(6) })
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        search = searchBox.Text
        rebuildView()
        render()
    end)

    Builder.dropdown(
        {
            Parent = toolbar,
            label = "Sort",
            color = Theme.Colors.Accent,
            Size = UDim2.fromOffset(160, 34),
        },
        SORTS,
        sortMode,
        function(v)
            sortMode = v
            rebuildView()
            render()
        end
    )

    Builder.dropdown(
        {
            Parent = toolbar,
            label = "Filter",
            color = Theme.Colors.Accent,
            Size = UDim2.fromOffset(160, 34),
        },
        FILTERS,
        filterMode,
        function(v)
            filterMode = v
            rebuildView()
            render()
        end
    )

    local selBtn = Builder.glossButton({
        Size = UDim2.fromOffset(120, 34),
        color = Theme.Colors.DarkPill,
        Text = "Select: Off",
        maxText = 15,
        Parent = toolbar,
    }, nil)
    selBtn.Activated:Connect(function()
        multiSelect = not multiSelect
        if not multiSelect then
            selected = {}
        end
        selBtn.Text = "Select: " .. (multiSelect and "On" or "Off")
        render()
    end)

    -- Bulk action buttons.
    local function bulkBtn(label, color, fn)
        local b = Builder.glossButton({
            Size = UDim2.fromOffset(150, 34),
            color = color,
            Text = label,
            maxText = 15,
            Parent = toolbar,
        }, nil)
        b.Activated:Connect(fn)
    end
    bulkBtn("Sell Selected", Theme.Colors.Danger, sellSelected)
    bulkBtn("Sell Commons", Theme.Colors.Danger, function()
        sellFilter("RarityAtMost", { Rarity = "Common" })
    end)
    bulkBtn("Sell Dupes", Theme.Colors.Danger, function()
        sellFilter("Duplicates", { Keep = 1 })
    end)
    bulkBtn("Fuse Eligible", Theme.Colors.Accent, massFuse)
    bulkBtn("Lock Sel", Theme.Colors.DarkPill, function()
        flagSelected("Locked", true)
    end)
    bulkBtn("Fav Sel", Theme.Colors.Gold, function()
        flagSelected("Favorited", true)
    end)
end

local function buildCell(index)
    local frame = Builder.create("Frame", {
        Size = UDim2.new(1, -8, 0, CELL_H - 4),
        BackgroundColor3 = Theme.Colors.DarkPill,
        BorderSizePixel = 0,
        Visible = false,
        Parent = content,
    }, { Builder.padding(6) })

    local selDot = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(22, 22),
        BackgroundColor3 = Theme.Colors.DarkPill,
        Text = "",
        Visible = false,
        Parent = frame,
    }, { Builder.corner(UDim.new(1, 0)) })

    local name = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(30, 2),
        Size = UDim2.new(1, -260, 0, 24),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = "",
        TextColor3 = Theme.Colors.White,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = frame,
    })
    local info = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(30, 28),
        Size = UDim2.new(1, -260, 0, 18),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = "",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })
    local income = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -150, 0, 4),
        Size = UDim2.fromOffset(120, 20),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = "",
        TextColor3 = Theme.Colors.Positive,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = frame,
    })
    local favBtn = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(34, 34),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = "☆",
        TextSize = 24,
        Parent = frame,
    })
    local lockBtn = Builder.create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -36, 0.5, 0),
        Size = UDim2.fromOffset(34, 34),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = "🔓",
        TextSize = 20,
        Parent = frame,
    })
    local sellBtn = Builder.glossButton({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -74, 0.5, 0),
        Size = UDim2.fromOffset(110, 30),
        color = Theme.Colors.Danger,
        Text = "Sell",
        maxText = 14,
        Parent = frame,
    }, nil)

    local cell = {
        frame = frame,
        name = name,
        info = info,
        income = income,
        favBtn = favBtn,
        lockBtn = lockBtn,
        sellBtn = sellBtn,
        selDot = selDot,
        entry = nil,
    }
    local function act(fn)
        return function()
            if cell.entry ~= nil then
                fn(cell.entry)
            end
        end
    end
    favBtn.Activated:Connect(act(function(e)
        toggleFlag(e, "Favorited")
    end))
    lockBtn.Activated:Connect(act(function(e)
        toggleFlag(e, "Locked")
    end))
    sellBtn.Activated:Connect(act(sellOne))
    selDot.Activated:Connect(act(function(e)
        selected[e.Id] = (not selected[e.Id]) or nil
        render()
    end))
    cells[index] = cell
end

function Inventory.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Inventory", player:WaitForChild("PlayerGui"), false)

    local body = Builder.create("Frame", {
        Name = "Body",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.82, 0.74),
        BackgroundColor3 = Theme.Colors.Background,
        Parent = gui,
    }, { Builder.corner(UDim.new(0, 14)) })

    Builder.create("TextLabel", {
        Size = UDim2.new(1, -100, 0, 40),
        Position = UDim2.fromOffset(12, 4),
        BackgroundTransparency = 1,
        Font = Theme.FontDisplay,
        Text = "INVENTORY",
        TextColor3 = Theme.Colors.Ink,
        TextSize = 24,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = body,
    })
    statusLabel = Builder.create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -56, 0, 12),
        Size = UDim2.fromOffset(220, 24),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = "",
        TextColor3 = Theme.Colors.InkSoft,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = body,
    })
    local close = Builder.glossButton({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 6),
        Size = UDim2.fromOffset(40, 34),
        color = Theme.Colors.Danger,
        Text = "✕",
        maxText = 20,
        Parent = body,
    }, function()
        gui.Enabled = false
    end)
    close.Parent = body

    buildToolbar()

    scroll = Builder.create("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 132),
        Size = UDim2.new(1, -16, 1, -140),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 6,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Parent = body,
    })
    content = Builder.create("Frame", {
        Size = UDim2.fromScale(1, 0),
        BackgroundTransparency = 1,
        Parent = scroll,
    })
    for i = 1, POOL do
        buildCell(i)
    end
    scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(render)

    -- Confirm modal (overlay).
    confirmModal = Builder.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(360, 160),
        BackgroundColor3 = Theme.Colors.Background,
        Visible = false,
        ZIndex = 10,
        Parent = body,
    }, { Builder.corner(UDim.new(0, 12)), Builder.padding(12) })
    Builder.create("TextLabel", {
        Name = "Msg",
        Size = UDim2.new(1, 0, 0, 80),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = "",
        TextColor3 = Theme.Colors.Ink,
        TextSize = 16,
        TextWrapped = true,
        ZIndex = 11,
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
    yes.ZIndex = 11
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
    no.ZIndex = 11
end

function Inventory.refreshIfOpen()
    if gui ~= nil and gui.Enabled then
        Inventory.refresh()
    end
end

function Inventory.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        Inventory.refresh()
    end
end

return Inventory
