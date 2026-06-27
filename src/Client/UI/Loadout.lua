-- Loadout (M11.1): a FUNCTIONAL signature-perk loadout panel. Shows the N perk slots, the unit
-- equipped in each + its perk and current scaled magnitude, and lets the player equip / swap /
-- unequip owned units. The client sends INTENT ONLY (unit Id + slot, or a slot to unequip); the
-- server validates ownership/lock + applies the perk. (Styling/juice is a later look-pass.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))
local FusionConfig = require(Shared:WaitForChild("FusionConfig"))
local PerksConfig = require(Shared:WaitForChild("PerksConfig"))

local Loadout = {}

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
        TextColor3 = color or Theme.Colors.Ink,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = list,
    })
end

local function starSuffix(star)
    return (star and star > 1) and ("  " .. FusionConfig.Stars(star)) or ""
end

local function getLoadout()
    local ok, result = pcall(function()
        return remotes.LoadoutRequest:InvokeServer({ Action = "get" })
    end)
    if ok and type(result) == "table" and type(result.Loadout) == "table" then
        return result.Loadout
    end
    return { Slots = {}, SlotCount = 0 }
end

local function applyResult(result)
    if type(result) == "table" then
        lastMessage = result.Message
    end
    Loadout.refresh()
end

local function doEquip(slot, unitId)
    local ok, result = pcall(function()
        return remotes.LoadoutRequest:InvokeServer({
            Action = "equip",
            UnitId = unitId,
            Slot = slot,
        })
    end)
    applyResult(ok and result or nil)
end

local function doUnequip(slot)
    local ok, result = pcall(function()
        return remotes.LoadoutRequest:InvokeServer({ Action = "unequip", Slot = slot })
    end)
    applyResult(ok and result or nil)
end

-- The unit picker for a slot: every owned unit not already equipped, each tagged with its perk.
local function renderPicker(slot, equippedIds)
    clearRows()
    order = 0
    label("Pick a unit for slot " .. slot, Theme.Colors.Ink, 26, Theme.FontDisplay)
    Builder.glossButton({
        Size = UDim2.new(1, 0, 0, 40),
        color = Theme.Colors.Disabled,
        Text = "< Back",
        maxText = 18,
        Parent = list,
        LayoutOrder = nextOrder(),
    }, function()
        Loadout.refresh()
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
        if not equippedIds[unit.Id] then
            any = true
            local rarity = Rarity.Get(unit.Rarity)
            local perkKey = PerksConfig.PerkForType(unit.Type)
            local perk = PerksConfig.Get(perkKey)
            local locked = unit.Sellable == false -- in transit / trade / equipped -> server re-checks
            local perkName = perk ~= nil and perk.Name or perkKey
            local mag = PerksConfig.MagnitudeLabel(perkKey, unit)
            local text = unit.Name
                .. starSuffix(unit.Star)
                .. "  ["
                .. perkName
                .. ": "
                .. mag
                .. "]"
                .. (locked and "  (busy)" or "")
            Builder.glossButton({
                Size = UDim2.new(1, 0, 0, 46),
                color = locked and Theme.Colors.Disabled or rarity.Color,
                Text = text,
                maxText = 16,
                Parent = list,
                LayoutOrder = nextOrder(),
            }, function()
                doEquip(slot, unit.Id)
            end)
        end
    end
    if not any then
        label("No free units to equip.", Theme.Colors.InkSoft)
    end
end

-- One perk slot card: perk name + scaled magnitude (if filled) + equip/unequip.
local function slotCard(entry, equippedIds)
    local filled = entry.UnitId ~= nil
    local rarity = filled and Rarity.Get(entry.Rarity) or nil
    local card = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 96),
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
    }, { Builder.padding(10) })
    Builder.rarityCard(card, filled and rarity.Color or Theme.Colors.Disabled)

    local titleText = "Slot " .. entry.Slot
    if filled then
        titleText = "Slot " .. entry.Slot .. ":  " .. entry.UnitName .. starSuffix(entry.Star)
    end
    local title = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -116, 0, 24),
        BackgroundTransparency = 1,
        Text = titleText,
        TextColor3 = Theme.Colors.Ink,
        TextSize = 17,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    Builder.styleText(title, { ink = true, keepColor = true })

    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 28),
        Size = UDim2.new(1, -116, 0, 18),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = filled and (entry.PerkName .. "  (" .. (entry.Category or "") .. ")")
            or "(empty slot)",
        TextColor3 = filled and Theme.Colors.Accent or Theme.Colors.InkSoft,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 60),
        Size = UDim2.new(1, -116, 0, 20),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = filled and (entry.Magnitude .. "  -  " .. (entry.PerkDesc or ""))
            or "Tap Equip to assign a unit.",
        TextColor3 = filled and Theme.Colors.Positive or Theme.Colors.InkSoft,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    Builder.glossButton({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(104, 64),
        color = filled and Theme.Colors.Danger or Theme.accentColor("Loadout"),
        Text = filled and "Unequip" or "Equip",
        maxText = 18,
        Parent = card,
    }, function()
        if filled then
            doUnequip(entry.Slot)
        else
            renderPicker(entry.Slot, equippedIds)
        end
    end)

    card.Parent = list
end

function Loadout.refresh()
    if gui == nil then
        return
    end
    clearRows()
    order = 0

    if lastMessage ~= nil then
        label(lastMessage, Theme.Colors.Accent, 26, Theme.FontDisplay)
    end
    label(
        "Equip a unit's SIGNATURE PERK into a slot. It KEEPS earning on its pad while equipped.",
        Theme.Colors.InkSoft
    )

    local loadout = getLoadout()
    local equippedIds = {}
    for _, entry in ipairs(loadout.Slots) do
        if entry.UnitId ~= nil then
            equippedIds[entry.UnitId] = true
        end
    end
    for _, entry in ipairs(loadout.Slots) do
        slotCard(entry, equippedIds)
    end
end

function Loadout.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Loadout", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Loadout", function()
        gui.Enabled = false
    end)
end

function Loadout.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        lastMessage = nil
        Loadout.refresh()
    end
end

return Loadout
