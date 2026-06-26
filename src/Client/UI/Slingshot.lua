-- Slingshot (M-map): the FUNCTIONAL travel menu. Lists the biomes (+ unlock state from the server); tap
-- an unlocked one -> the server validates + returns the landing point -> we fling THIS character on a
-- ballistic arc to it (Roblox owns the local character, so the launch is applied client-side). Locked
-- biomes are shown but refused. Client sends INTENT only; the server owns the unlock authority.

local TweenService = game:GetService("TweenService")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)
local Notifications = require(script.Parent.Notifications)

local Slingshot = {}

local player, remotes = nil, nil
local gui, list = nil, nil
local order = 0

local function nextOrder()
    order += 1
    return order
end

local function clear()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

local function label(text, color, size)
    return Builder.create("TextLabel", {
        Size = UDim2.new(1, 0, 0, size or 24),
        BackgroundTransparency = 1,
        Font = Theme.FontBody,
        Text = text,
        TextColor3 = color or Theme.Colors.Ink,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        Parent = list,
    })
end

local function rowButton(text, color, fn)
    Builder.glossButton({
        Size = UDim2.new(1, 0, 0, 44),
        color = color,
        Text = text,
        maxText = 18,
        LayoutOrder = nextOrder(),
        Parent = list,
    }, fn)
end

-- Ride the local character to `target` (Vector3) over `flightTime`s as an ANCHORED kinematic glide. Anchored
-- = no collision, so it passes the solid platforms in the way with NO head-bonk, then releases on the landing.
local function fling(target, flightTime)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if root == nil then
        return false
    end
    local t = math.clamp(flightTime or 1.6, 0.6, 4)
    if humanoid then
        humanoid.PlatformStand = true -- stop walk/fall fighting the ride
    end
    root.Anchored = true
    local rotation = root.CFrame - root.CFrame.Position -- keep current facing
    local goal = CFrame.new(target) * rotation
    local tween = TweenService:Create(
        root,
        TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
        { CFrame = goal }
    )
    tween:Play()
    tween.Completed:Connect(function()
        root.Anchored = false
        if humanoid then
            humanoid.PlatformStand = false
        end
    end)
    return true
end

local function doLaunch(biomeId)
    local ok, result = pcall(function()
        return remotes.SlingshotAction:InvokeServer({ Action = "launch", BiomeId = biomeId })
    end)
    if not ok or type(result) ~= "table" then
        Notifications.show("error", "Elevator stuck -- try again.")
        return
    end
    if result.Result ~= "Success" then
        Notifications.show("info", result.Message or "Can't ride there.")
        return
    end
    gui.Enabled = false
    if fling(result.Target, result.FlightTime) then
        Notifications.show("success", "Going up!")
    else
        Notifications.show("error", "Couldn't ride (no character).")
    end
end

function Slingshot.refresh()
    if gui == nil or not gui.Enabled then
        return
    end
    clear()
    order = 0
    label("Pick a level to ride the elevator to:", Theme.Colors.Gold, 28)
    local ok, result = pcall(function()
        return remotes.SlingshotAction:InvokeServer({ Action = "get" })
    end)
    local biomes = (ok and type(result) == "table") and result.Biomes or nil
    if biomes == nil then
        label("Couldn't load destinations.", Theme.Colors.Danger, 30)
        return
    end
    for _, b in ipairs(biomes) do
        if b.Unlocked then
            rowButton("🛗  " .. b.Name, Theme.Colors.Positive, function()
                doLaunch(b.BiomeId)
            end)
        else
            rowButton("🔒  " .. b.Name .. " (locked)", Theme.Colors.DarkPill, function()
                Notifications.show("info", "Unlock " .. b.Name .. " first to ride up there.")
            end)
        end
    end
end

function Slingshot.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Slingshot", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Elevator", function()
        gui.Enabled = false
    end, "Slingshot")
end

function Slingshot.toggle()
    if gui == nil then
        return
    end
    gui.Enabled = not gui.Enabled
    if gui.Enabled then
        Slingshot.refresh()
    end
end

return Slingshot
