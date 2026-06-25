-- Fusion (M9.2): a FUNCTIONAL fuse interface. Groups the player's owned units by Type + Star, shows
-- each group that has enough copies to fuse (the same-species recipe), the odds, and the income the
-- star-up grants, and lets the player fuse. The client sends only the fodder Ids; the server rolls
-- + fuses. (Styling/juice is a later look-pass -- this just uses the existing shared components.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local FusionConfig = require(Shared:WaitForChild("FusionConfig"))

local Fusion = {}

local player = nil
local remotes = nil
local gui = nil
local list = nil
local order = 0
local lastMessage = nil
local lastKind = nil

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

local function label(text, color, size, parent)
    local l = Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, size or 22),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = text,
        TextColor3 = color or Theme.Colors.Text,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = parent or list,
    })
    return l
end

-- Sends the first N matching ids to the server (the server re-validates everything).
local function fuse(ids)
    local ok, result = pcall(function()
        return remotes.FuseRequest:InvokeServer({ FodderIds = ids })
    end)
    if ok and type(result) == "table" then
        lastMessage = result.Message or tostring(result.Result)
        lastKind = result.Result == "Success" and Theme.Colors.Positive
            or (result.Result == "Fail" and Color3.fromRGB(255, 170, 90))
            or Theme.Colors.Danger
    else
        lastMessage = "Fusion error."
        lastKind = Theme.Colors.Danger
    end
    Fusion.refresh()
end

-- One fusable group's card: name + current stars + count, the recipe + odds, the income preview,
-- and a Fuse button.
local function groupCard(sample, ids)
    local n = FusionConfig.SameSpeciesCount
    local star = sample.Star or 1
    local newStar = math.min(FusionConfig.MaxStar, star + 1)
    local rarity = Rarity.Get(sample.Rarity)

    local card = Builder.create("Frame", {
        Size = UDim2.new(1, 0, 0, 96),
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
    }, { Builder.padding(10) })
    Builder.rarityCard(card, rarity.Color)

    local title = Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -120, 0, 24),
        BackgroundTransparency = 1,
        Text = string.format("%s  %s  (x%d)", sample.Name, FusionConfig.Stars(star), #ids),
        TextColor3 = Theme.Colors.Text,
        TextSize = 18,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    Builder.applyChrome(title, { stroke = 2 })

    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 28),
        Size = UDim2.new(1, -120, 0, 18),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = string.format(
            "%d × %s  ->  %s   (crit %d%% · fail %d%%)",
            n,
            FusionConfig.Stars(star),
            FusionConfig.Stars(newStar),
            math.floor(FusionConfig.CritChance * 100 + 0.5),
            math.floor(FusionConfig.SoftFailChance * 100 + 0.5)
        ),
        TextColor3 = Theme.Colors.SubText,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    local curEach = sample.IncomePerSec or 0
    local nextEach = curEach
        * (FusionConfig.StarMultiplier(newStar) / FusionConfig.StarMultiplier(star))
    Builder.create("TextLabel", {
        Position = UDim2.fromOffset(2, 50),
        Size = UDim2.new(1, -120, 0, 18),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = string.format(
            "Each: +$%s/s  ->  +$%s/s",
            Format.full(curEach),
            Format.full(nextEach)
        ),
        TextColor3 = Theme.Colors.Positive,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    local fodder = { ids[1], ids[2], ids[3] }
    local button = Builder.glossButton({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(108, 64),
        color = Theme.accentColor("Fusion"),
        Text = "FUSE",
        maxText = 22,
        Parent = card,
    }, function()
        fuse(fodder)
    end)
    button.Name = "Fuse"

    card.Parent = list
end

function Fusion.refresh()
    if gui == nil then
        return
    end
    clearRows()
    order = 0

    -- Last fusion result (persisted across the refresh so the reveal stays visible).
    if lastMessage ~= nil then
        local l = label(lastMessage, lastKind, 28)
        l.Font = Theme.FontDisplay
        l.TextSize = 17
    end
    label(
        "Fuse 3 of the SAME unit at the SAME star into one higher-star version. Stars boost income.",
        Theme.Colors.SubText
    )

    local ok, owned = pcall(function()
        return remotes.GetInventory:InvokeServer()
    end)
    if not ok or typeof(owned) ~= "table" then
        label("Inventory unavailable.", Theme.Colors.Danger)
        return
    end

    -- Group by Type + Star; only non-premium units below max star can be fodder.
    local groups = {} -- [key] = { sample = entry, ids = {} }
    local sorder = {}
    for _, entry in ipairs(owned) do
        local star = entry.Star or 1
        if entry.Sellable ~= false and star < FusionConfig.MaxStar then
            local key = entry.Type .. "@" .. star
            local g = groups[key]
            if g == nil then
                g = { sample = entry, ids = {} }
                groups[key] = g
                table.insert(sorder, key)
            end
            table.insert(g.ids, entry.Id)
        end
    end

    local any = false
    for _, key in ipairs(sorder) do
        local g = groups[key]
        if #g.ids >= FusionConfig.SameSpeciesCount then
            any = true
            groupCard(g.sample, g.ids)
        end
    end
    if not any then
        label(
            "No fusable duplicates yet -- collect "
                .. FusionConfig.SameSpeciesCount
                .. " of the same unit at the same star.",
            Theme.Colors.SubText
        )
    end
end

function Fusion.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Fusion", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Fusion", function()
        gui.Enabled = false
    end)
end

function Fusion.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        lastMessage = nil -- clear the previous reveal when reopening
        Fusion.refresh()
    end
end

return Fusion
