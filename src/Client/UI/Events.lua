-- Events: the limited-time events panel. Renders ONLY the server-replicated active-event state
-- (GetEvents) -- it never decides whether an event is active. Quests show live progress + claim
-- buttons; the event shop spends event currency. The client sends intent (claim/buy) only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local Events = {}

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
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h > 0 then
        return h .. "h " .. m .. "m"
    elseif m > 0 then
        return m .. "m"
    end
    return s .. "s"
end

local function clear()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton") then
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

local function actionButton(text, onClick)
    local b = Builder.create("TextButton", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.Colors.Positive,
        BorderSizePixel = 0,
        Font = Theme.FontBold,
        Text = text,
        TextColor3 = Theme.Colors.Text,
        TextSize = 16,
        LayoutOrder = nextOrder(),
        Parent = list,
    }, { Builder.corner(UDim.new(0, 8)) })
    b.Activated:Connect(onClick)
end

function Events.refresh()
    if gui == nil then
        return
    end
    local ok, state = pcall(function()
        return remotes.GetEvents:InvokeServer()
    end)
    clear()
    order = 0
    if not ok or type(state) ~= "table" or #state.Active == 0 then
        label("No active events right now. Check back soon!", Theme.Colors.SubText)
        return
    end

    for _, event in ipairs(state.Active) do
        local countdown = event.IsActive
                and (event.EndsAt == 0 and "ACTIVE" or ("ends in " .. fmtTime(
                    event.EndsAt - state.Now
                )))
            or "ENDED (claim window)"
        label(event.Name .. "  —  " .. countdown, Theme.Colors.Accent, 28, true)
        label(event.Description, Theme.Colors.SubText)
        if event.CurrencyName ~= nil then
            label(
                event.CurrencyName .. ": " .. Format.short(event.Currency),
                Theme.Colors.Positive,
                22,
                true
            )
        end

        for _, quest in ipairs(event.Quests or {}) do
            local prog = math.min(quest.Target, (event.Progress[quest.Id] or 0))
            local done = prog >= quest.Target
            label(
                string.format(
                    "%s  (%s/%s)",
                    quest.Description,
                    Format.short(prog),
                    Format.short(quest.Target)
                ),
                done and Theme.Colors.Positive or Theme.Colors.Text
            )
            if event.Claimed[quest.Id] then
                label("  ✓ claimed", Theme.Colors.SubText)
            elseif done then
                local key, objId = event.Key, quest.Id
                actionButton("Claim reward", function()
                    pcall(function()
                        remotes.ClaimEventReward:InvokeServer(key, objId)
                    end)
                    Events.refresh()
                end)
            end
        end

        if event.IsActive and #(event.Shop or {}) > 0 then
            label("Event Shop", Theme.Colors.Accent, 22, true)
            for _, entry in ipairs(event.Shop) do
                local key, entryId = event.Key, entry.Id
                actionButton(
                    string.format(
                        "%s  —  %s %s",
                        entry.Name,
                        Format.short(entry.Price),
                        event.CurrencyName or ""
                    ),
                    function()
                        pcall(function()
                            remotes.EventShopBuy:InvokeServer(key, entryId)
                        end)
                        Events.refresh()
                    end
                )
            end
        end
    end
end

function Events.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Events", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Events", function()
        gui.Enabled = false
    end)

    -- Server pings when events change; re-pull if the panel is open.
    remotes.EventsUpdate.OnClientEvent:Connect(function()
        if gui.Enabled then
            Events.refresh()
        end
    end)
end

function Events.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        Events.refresh()
    end
end

return Events
