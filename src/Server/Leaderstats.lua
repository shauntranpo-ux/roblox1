-- Leaderstats: the only cash readout in M1. A "leaderstats" folder with an IntValue
-- named "Cash" shows up for free in the Roblox player list. We keep precise fractional
-- Cash in the profile and only floor it for display.

local Leaderstats = {}

local MAX_INT_VALUE = 2147483647 -- IntValue ceiling; clamp so long sessions never error.

local function flooredCash(profile)
    return math.clamp(math.floor(profile.Data.Cash), 0, MAX_INT_VALUE)
end

-- Creates the leaderstats folder + Cash value for a player.
function Leaderstats.Setup(player, profile)
    local folder = Instance.new("Folder")
    folder.Name = "leaderstats"

    local cash = Instance.new("IntValue")
    cash.Name = "Cash"
    cash.Value = flooredCash(profile)
    cash.Parent = folder

    folder.Parent = player
end

-- Pushes the player's current (floored) cash into the display.
function Leaderstats.Update(player, profile)
    local folder = player:FindFirstChild("leaderstats")
    if folder == nil then
        return
    end
    local cash = folder:FindFirstChild("Cash")
    if cash ~= nil then
        cash.Value = flooredCash(profile)
    end
end

return Leaderstats
