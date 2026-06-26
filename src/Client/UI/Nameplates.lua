-- Nameplates (VM-THEME): a dark rounded PILL BillboardGui above every OTHER character with the
-- player's name in white FredokaOne (+ black outline). Handles join / leave / respawn cleanly: the
-- BillboardGui is parented to the character's Head, so it's destroyed automatically on respawn + leave
-- (no GUI leak). The local player's own plate is skipped.

local Players = game:GetService("Players")

local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

local Nameplates = {}

local function attach(targetPlayer, character, localPlayer)
    local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 5)
    if head == nil then
        return
    end
    if head:FindFirstChild("Nameplate") ~= nil then
        return
    end
    -- M13.3 FRIEND INDICATOR: flag this character if they're the local player's Roblox friend.
    local isFriend = false
    if localPlayer ~= nil then
        pcall(function()
            isFriend = localPlayer:IsFriendsWith(targetPlayer.UserId)
        end)
    end

    local billboard = Builder.create("BillboardGui", {
        Name = "Nameplate",
        Size = UDim2.fromScale(4.2, 1.1),
        StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0),
        AlwaysOnTop = false,
        MaxDistance = 120,
        Adornee = head,
        Parent = head,
    })
    local pill = Builder.pill({
        Size = UDim2.fromScale(1, 1),
        radius = UDim.new(1, 0),
        transparency = 0.25,
        Parent = billboard,
    })
    -- M13.4: render the server-published, TextService-FILTERED SafeName (never a raw user-authored
    -- name). It may publish a beat after we attach, so refresh the label if/when it changes.
    local function safeName()
        return targetPlayer:GetAttribute("SafeName") or targetPlayer.DisplayName
    end
    local name = Builder.create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = isFriend and ("★ " .. safeName()) or safeName(),
        TextColor3 = isFriend and Theme.Colors.Gold or Theme.Colors.White,
        TextScaled = true,
        Parent = pill,
    }, { Builder.padding(4), Builder.create("UITextSizeConstraint", { MaxTextSize = 22 }) })
    Builder.styleText(name, { keepColor = true })
    targetPlayer:GetAttributeChangedSignal("SafeName"):Connect(function()
        name.Text = isFriend and ("★ " .. safeName()) or safeName()
    end)
end

function Nameplates.mount(context)
    local localPlayer = context.player

    local function hook(targetPlayer)
        if targetPlayer == localPlayer then
            return -- skip our own plate
        end
        targetPlayer.CharacterAdded:Connect(function(character)
            attach(targetPlayer, character, localPlayer)
        end)
        if targetPlayer.Character ~= nil then
            attach(targetPlayer, targetPlayer.Character, localPlayer)
        end
    end

    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        hook(targetPlayer)
    end
    Players.PlayerAdded:Connect(hook)
end

return Nameplates
