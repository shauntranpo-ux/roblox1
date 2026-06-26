-- KillFeed: the everyone-sees steal banner. Driven by the server's KillFeed remote
-- (FireAllClients), it stacks transient, auto-dismissing banners at the top-center of the
-- screen: "<Thief> stole [<Rarity> <Name>] from <Victim>", with the item rarity-colored.
-- All built in code, mobile-first. Reusable for later broadcast event types.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))

local KillFeed = {}

local container = nil
local showBanners = true -- M13.6: HUD pref (Settings.ShowKillFeed); applied live

-- Live-applied from the Settings panel. ShowKillFeed=false suppresses the steal banners (HUD pref).
function KillFeed.applySettings(s)
    if type(s) == "table" then
        showBanners = s.ShowKillFeed ~= false
    end
end

-- Color3 -> "#RRGGBB" for RichText spans.
local function toHex(color)
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

function KillFeed.mount(context)
    local gui = Builder.screenGui("KillFeed", context.player:WaitForChild("PlayerGui"), true)

    container = Builder.create("Frame", {
        Name = "Container",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.14),
        Size = UDim2.fromScale(0.9, 0.4),
        BackgroundTransparency = 1,
        Parent = gui,
    }, {
        Builder.create("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            VerticalAlignment = Enum.VerticalAlignment.Top,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }),
        Builder.create("UISizeConstraint", { MaxSize = Vector2.new(560, 9999) }),
    })
end

-- payload = { Thief, Victim, Name, Rarity }. Shows one banner; auto-dismisses after ~5s.
function KillFeed.show(payload)
    if container == nil or not showBanners or typeof(payload) ~= "table" then
        return
    end

    local rarity = Rarity.Get(payload.Rarity)
    local text = string.format(
        '<b>%s</b> stole <font color="%s"><b>[%s %s]</b></font> from <b>%s</b>',
        tostring(payload.Thief),
        toHex(rarity.Color),
        rarity.DisplayName,
        tostring(payload.Name),
        tostring(payload.Victim)
    )

    -- Soft DARK bubble (over the world -> white-fill text recipe + rarity glow rim). DarkPill, not the
    -- now-light Theme.Colors.Panel (which would make white text invisible).
    local feedLabel = Builder.create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Font = Theme.Font,
        RichText = true,
        Text = text,
        TextColor3 = Theme.Colors.Text,
        TextSize = 16,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    Builder.styleText(feedLabel, { keepColor = true })

    local banner = Builder.create("Frame", {
        BackgroundColor3 = Theme.Colors.DarkPill,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
    }, {
        Builder.corner(Theme.Radius.Card),
        Builder.padding(10),
        Builder.create("UIStroke", { Color = rarity.Color, Thickness = 2, Transparency = 0.2 }),
        feedLabel,
    })
    banner.Parent = container

    TweenService:Create(banner, TweenInfo.new(0.2), { BackgroundTransparency = 0.08 }):Play()

    task.delay(5, function()
        if banner.Parent == nil then
            return
        end
        local fade = TweenService:Create(banner, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
        fade:Play()
        fade.Completed:Wait()
        banner:Destroy()
    end)
end

return KillFeed
