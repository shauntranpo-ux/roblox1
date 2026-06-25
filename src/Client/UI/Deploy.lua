-- Deploy (M9.3): a FUNCTIONAL loadout interface. Shows the role slots, the unit assigned to each +
-- its server-computed buff, and lets the player assign / swap / unassign owned units. The client
-- sends INTENT ONLY (a unit Id + slot, or a slot to unassign); the server validates + applies the
-- buff. (Styling/juice is a later look-pass -- this uses the existing shared components only.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))
local FusionConfig = require(Shared:WaitForChild("FusionConfig"))

local Deploy = {}

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

local function getLoadout()
    local ok, result = pcall(function()
        return remotes.DeployRequest:InvokeServer({ Action = "get" })
    end)
    if ok and type(result) == "table" and type(result.Loadout) == "table" then
        return result.Loadout
    end
    return {}
end

local function applyResult(result)
    if type(result) == "table" then
        lastMessage = result.Message
    end
    Deploy.refresh()
end

local function doAssign(slot, unitId)
    local ok, result = pcall(function()
        return remotes.DeployRequest:InvokeServer({
            Action = "assign",
            UnitId = unitId,
            Slot = slot,
        })
    end)
    applyResult(ok and result or nil)
end

local function doUnassign(slot)
    local ok, result = pcall(function()
        return remotes.DeployRequest:InvokeServer({ Action = "unassign", Slot = slot })
    end)
    applyResult(ok and result or nil)
end

-- The unit picker for a slot: list owned units not already deployed; tap to assign.
local function renderPicker(slot, deployedIds)
    clearRows()
    order = 0
    label("Pick a unit for " .. slot, Theme.Colors.Text, 26, Theme.FontDisplay)
    Builder.glossButton({
        Size = UDim2.new(1, 0, 0, 40),
        color = Theme.Colors.Disabled,
        Text = "< Back",
        maxText = 18,
        Parent = list,
        LayoutOrder = nextOrder(),
    }, function()
        Deploy.refresh()
    end)

    local ok, owned = pcall(function()
        return remotes.GetInventory:InvokeServer()
    end)
    if not ok or typeof(owned) ~= "table" then
        label("Inventory unavailable.", Theme.Colors.Danger)
        return
    end
    local any = false
    for _, unit in ipairs(owned) do
        if not deployedIds[unit.Id] then
            any = true
            local rarity = Rarity.Get(unit.Rarity)
            local stars = (unit.Star and unit.Star > 1) and ("  " .. FusionConfig.Stars(unit.Star))
                or ""
            Builder.glossButton({
                Size = UDim2.new(1, 0, 0, 44),
                color = rarity.Color,
                Text = unit.Name .. stars,
                maxText = 18,
                Parent = list,
                LayoutOrder = nextOrder(),
            }, function()
                doAssign(slot, unit.Id)
            end)
        end
    end
    if not any then
        label("No free units to assign.", Theme.Colors.SubText)
    end
end

-- One role slot card: name + buff (if filled) + assign/unassign.
local function slotCard(entry, deployedIds)
    local filled = entry.UnitId ~= nil
    local rarity = filled and Rarity.Get(entry.Rarity) or nil
    local card = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 96),
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
    }, { Builder.padding(10) })
    Builder.rarityCard(card, filled and rarity.Color or Theme.Colors.Disabled)

    local titleText = entry.Name
    if filled then
        local stars = (entry.Star and entry.Star > 1) and ("  " .. FusionConfig.Stars(entry.Star))
            or ""
        titleText = entry.Name .. ":  " .. entry.UnitName .. stars
    end
    local title = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -116, 0, 24),
        BackgroundTransparency = 1,
        Text = titleText,
        TextColor3 = Theme.Colors.Text,
        TextSize = 17,
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
        Text = entry.Desc,
        TextColor3 = Theme.Colors.SubText,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 60),
        Size = UDim2.new(1, -116, 0, 20),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = filled and ("Buff: " .. (entry.Effect or "")) or "(empty)",
        TextColor3 = filled and Theme.Colors.Positive or Theme.Colors.SubText,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    Builder.glossButton({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(104, 64),
        color = filled and Theme.Colors.Danger or Theme.accentColor("Deploy"),
        Text = filled and "Unassign" or "Assign",
        maxText = 18,
        Parent = card,
    }, function()
        if filled then
            doUnassign(entry.Slot)
        else
            renderPicker(entry.Slot, deployedIds)
        end
    end)

    card.Parent = list
end

function Deploy.refresh()
    if gui == nil then
        return
    end
    clearRows()
    order = 0

    if lastMessage ~= nil then
        label(lastMessage, Theme.Colors.Accent, 26, Theme.FontDisplay)
    end
    label(
        "Deploy units into role slots for buffs. They KEEP earning on their pads.",
        Theme.Colors.SubText
    )

    local loadout = getLoadout()
    local deployedIds = {}
    for _, entry in ipairs(loadout) do
        if entry.UnitId ~= nil then
            deployedIds[entry.UnitId] = true
        end
    end
    for _, entry in ipairs(loadout) do
        slotCard(entry, deployedIds)
    end
end

function Deploy.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Deploy", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Deploy", function()
        gui.Enabled = false
    end)
end

function Deploy.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        lastMessage = nil
        Deploy.refresh()
    end
end

return Deploy
