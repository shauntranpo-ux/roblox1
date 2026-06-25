-- Slingshot (M-map): the FUNCTIONAL travel menu. Lists the biomes (+ unlock state from the server); tap
-- an unlocked one -> the server validates + returns the landing point -> we fling THIS character on a
-- ballistic arc to it (Roblox owns the local character, so the launch is applied client-side). Locked
-- biomes are shown but refused. Client sends INTENT only; the server owns the unlock authority.

local Workspace = game:GetService("Workspace")

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
        TextColor3 = color or Theme.Colors.Text,
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

-- Fling the local character to `target` (Vector3) so it ARRIVES there in `flightTime` seconds. Standard
-- projectile solve: v = horizontalGap/T for X/Z, and v_y = dy/T + 0.5*g*T (g = Workspace.Gravity).
local function fling(target, flightTime)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root == nil then
        return false
    end
    local g = Workspace.Gravity
    local t = math.clamp(flightTime or 1.7, 0.5, 4)
    local p0 = root.Position
    local vy = (target.Y - p0.Y) / t + 0.5 * g * t
    local v = Vector3.new((target.X - p0.X) / t, vy, (target.Z - p0.Z) / t)
    -- a tiny upward nudge so the launch clears the slingshot frame, then apply the arc velocity.
    root.CFrame = root.CFrame + Vector3.new(0, 3, 0)
    root.AssemblyLinearVelocity = v
    return true
end

local function doLaunch(biomeId)
    local ok, result = pcall(function()
        return remotes.SlingshotAction:InvokeServer({ Action = "launch", BiomeId = biomeId })
    end)
    if not ok or type(result) ~= "table" then
        Notifications.show("error", "Slingshot jammed -- try again.")
        return
    end
    if result.Result ~= "Success" then
        Notifications.show("info", result.Message or "Can't launch there.")
        return
    end
    gui.Enabled = false
    if fling(result.Target, result.FlightTime) then
        Notifications.show("success", "Launching!")
    else
        Notifications.show("error", "Couldn't launch (no character).")
    end
end

function Slingshot.refresh()
    if gui == nil or not gui.Enabled then
        return
    end
    clear()
    order = 0
    label("Pick where to launch:", Theme.Colors.Gold, 28)
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
            rowButton("🎯  " .. b.Name, Theme.Colors.Positive, function()
                doLaunch(b.BiomeId)
            end)
        else
            rowButton("🔒  " .. b.Name .. " (locked)", Theme.Colors.DarkPill, function()
                Notifications.show(
                    "info",
                    "Unlock " .. b.Name .. " by walking through its gate first."
                )
            end)
        end
    end
end

function Slingshot.mount(context)
    player = context.player
    remotes = context.remotes
    gui = Builder.screenGui("Slingshot", player:WaitForChild("PlayerGui"), false)
    list = Builder.panel(gui, "Slingshot", function()
        gui.Enabled = false
    end)
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
