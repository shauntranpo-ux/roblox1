-- StealService: the heart of M4. Implements the steal STATE MACHINE
-- (ON_PAD -> IN_TRANSIT -> ON_PAD) with the OWNERSHIP INVARIANT as the top priority.
--
-- ── OWNERSHIP INVARIANT (audited) ───────────────────────────────────────────────────────
-- Every brainrot is owned by EXACTLY ONE player at all times. While carried it stays in the
-- VICTIM's OwnedBrainrots (flagged in-transit only via the runtime TransitRegistry, never in
-- saved data) and is excluded from income. Ownership changes in EXACTLY ONE place --
-- transferOwnership() -- which does table.remove(victim) + table.insert(thief) with NO yields
-- between them, so there is never a moment the unit is in both sets or in neither:
--   * INITIATE: data untouched (still the victim's); only visuals + the in-transit flag move.
--   * DEPOSIT : the ONLY ownership change; atomic remove+insert; if it can't complete it
--               REVERTS instead, leaving the unit with the victim.
--   * REVERT  : data untouched (still the victim's); only visuals + flag are torn down.
-- A leaving player is fully resolved (ResolvePlayer) BEFORE their profile is released/saved,
-- so a save can never capture a duped or half-moved unit. The double-steal race is closed by
-- the ActiveSteals[id] guard set before any yield. Net: no path duplicates or loses a unit.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StealConfig = require(ReplicatedStorage.Shared.StealConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local MutationConfig = require(ReplicatedStorage.Shared.MutationConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local ProtectionService = require(script.Parent.ProtectionService)
local PlayerStats = require(script.Parent.PlayerStats)
local Remotes = require(script.Parent.Remotes)
local TransitRegistry = require(script.Parent.TransitRegistry)
local Benefits = require(script.Parent.Benefits)
local Analytics = require(script.Parent.Analytics)
local TradeLockRegistry = require(script.Parent.TradeLockRegistry)

local StealService = {}

-- Authoritative in-memory registries.
local ActiveSteals = {} -- [brainrotId] = steal record (its presence == IN_TRANSIT)
local carryingByThief = {} -- [Player] = brainrotId (a player carries AT MOST one)
local lastStealTime = {} -- [Player] = clock of last SUCCESSFUL steal (cooldown)
local immunityUntil = {} -- [brainrotId] = clock until which it can't be re-stolen

local LOOP_INTERVAL = 0.1 -- s: deposit-distance + timeout poll rate (~10 Hz)
local loopAccum = 0

-- Forward declarations (mutually referencing transitions).
local deposit, revert

-- Color3 -> "#RRGGBB" for the rarity-colored victim toast.
local function toHex(color)
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function findEntry(profile, brainrotId)
    for index, brainrot in ipairs(profile.Data.OwnedBrainrots) do
        if brainrot.Id == brainrotId then
            return brainrot, index
        end
    end
    return nil
end

local function defFor(brainrotType)
    return Catalog.Get(brainrotType) or Catalog.GetStarter()
end

-- Applies the optional carry WalkSpeed penalty, remembering the thief's real speed to restore.
local function applyCarryPenalty(thief, steal)
    if StealConfig.CarryWalkSpeedMult == 1 then
        return
    end
    local character = thief.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid ~= nil then
        steal.OriginalWalkSpeed = humanoid.WalkSpeed
        humanoid.WalkSpeed = humanoid.WalkSpeed * StealConfig.CarryWalkSpeedMult
    end
end

local function restoreWalkSpeed(steal)
    if steal.OriginalWalkSpeed == nil then
        return
    end
    local character = steal.Thief.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid ~= nil then
        humanoid.WalkSpeed = steal.OriginalWalkSpeed
    end
    steal.OriginalWalkSpeed = nil
end

-- Tears down all IN_TRANSIT runtime state for a steal (NOT ownership data). Always called by
-- both DEPOSIT and REVERT so every exit path restores speed, kills the carried model, clears
-- the registries, and (optionally) releases the reserved pad.
local function clearSteal(steal, releaseReservation)
    TransitRegistry.Set(steal.BrainrotId, false)
    ActiveSteals[steal.BrainrotId] = nil
    if carryingByThief[steal.Thief] == steal.BrainrotId then
        carryingByThief[steal.Thief] = nil
    end
    restoreWalkSpeed(steal)
    if steal.CarriedModel ~= nil then
        steal.CarriedModel:Destroy()
        steal.CarriedModel = nil
    end
    if releaseReservation then
        PlotService.ReleasePad(steal.Thief, steal.ReservedPadIndex)
    end
end

-- THE single guarded ownership mutation. Removes the unit from the victim and inserts it into
-- the thief at the reserved pad, synchronously with NO yields. Returns the moved entry, or
-- nil (leaving ownership with the victim) if a profile/entry is missing.
local function transferOwnership(steal)
    local victimProfile = ProfileManager.GetProfile(steal.Victim)
    local thiefProfile = ProfileManager.GetProfile(steal.Thief)
    if victimProfile == nil or thiefProfile == nil then
        return nil
    end
    local entry, index = findEntry(victimProfile, steal.BrainrotId)
    if entry == nil then
        return nil
    end
    table.remove(victimProfile.Data.OwnedBrainrots, index)
    entry.PadIndex = steal.ReservedPadIndex
    table.insert(thiefProfile.Data.OwnedBrainrots, entry)
    thiefProfile.Data.Discovered[entry.Type] = true
    -- The unit's intrinsic Mutation field moves WITH the whole record (never re-rolled); the thief
    -- now owns it, so they discover that mutation.
    if entry.Mutation ~= nil then
        thiefProfile.Data.MutationsDiscovered[entry.Mutation] = true
    end
    return entry
end

-- DEPOSIT (IN_TRANSIT -> ON_PAD, ownership transfers). Triggered by the server-side distance
-- check in the loop. Verified entirely on the server -- no client claim involved.
function deposit(steal)
    if ActiveSteals[steal.BrainrotId] ~= steal then
        return -- already resolved
    end

    local thiefPlot = PlotService.GetPlot(steal.Thief)
    local moved = thiefPlot ~= nil and transferOwnership(steal) or nil
    if moved == nil then
        -- Couldn't transfer (e.g. thief plot/profile gone) -> dupe-safe REVERT to victim.
        revert(steal, true)
        return
    end

    clearSteal(steal, true) -- pad is now owned, not reserved
    BrainrotService.SpawnBrainrot(steal.Thief, thiefPlot, moved)

    -- Recompute BOTH players' income; refresh thief prompts (thief may be protected).
    local victimProfile = ProfileManager.GetProfile(steal.Victim)
    if victimProfile ~= nil then
        PlayerStats.UpdateIncome(steal.Victim, victimProfile)
    end
    local thiefProfile = ProfileManager.GetProfile(steal.Thief)
    if thiefProfile ~= nil then
        PlayerStats.UpdateIncome(steal.Thief, thiefProfile)
    end
    ProtectionService.RefreshPrompts(steal.Thief)

    -- Post-steal: thief cooldown, per-unit immunity, victim post-robbery protection.
    local now = os.clock()
    lastStealTime[steal.Thief] = now
    immunityUntil[steal.BrainrotId] = now + StealConfig.PostStealImmunity
    ProtectionService.GrantPostRobbery(steal.Victim)

    Remotes.NotifyPlayer(steal.Thief, "success", "Deposited your steal!", "deposit")
    Analytics.customOnce(steal.Thief, Analytics.Events.FirstSteal)
end

-- REVERT (IN_TRANSIT -> ON_PAD on the victim's ORIGINAL pad). A no-op on ownership: the unit
-- was the victim's the whole time. respawnOnVictim = false only when the victim is LEAVING
-- (the unit stays in their saving data; the thief just loses the steal).
function revert(steal, respawnOnVictim)
    if ActiveSteals[steal.BrainrotId] ~= steal then
        return -- already resolved
    end

    clearSteal(steal, true)

    if respawnOnVictim then
        local victimPlot = PlotService.GetPlot(steal.Victim)
        local victimProfile = ProfileManager.GetProfile(steal.Victim)
        if victimPlot ~= nil and victimProfile ~= nil then
            local entry = findEntry(victimProfile, steal.BrainrotId)
            if entry ~= nil then
                entry.PadIndex = steal.OriginalPadIndex
                BrainrotService.SpawnBrainrot(steal.Victim, victimPlot, entry)
                PlayerStats.UpdateIncome(steal.Victim, victimProfile)
                ProtectionService.RefreshPrompts(steal.Victim)
            end
        end
    end
end

-- INITIATE (ON_PAD -> IN_TRANSIT). Fires on the SERVER when a "Hold to steal" prompt
-- completes, so completion is inherently server-authoritative. ALL preconditions are
-- re-checked here; if any fails, nothing changes and the thief gets a clear toast.
local function onPromptTriggered(prompt, thief)
    if prompt.Name ~= "StealPrompt" then
        return
    end
    local brainrotId = prompt:GetAttribute("BrainrotId")
    local ownerUserId = prompt:GetAttribute("OwnerUserId")
    if brainrotId == nil or ownerUserId == nil then
        return
    end

    -- DOUBLE-STEAL RACE: if already in transit, the second trigger loses. Checked before any
    -- yield, and nothing below yields before we write ActiveSteals -> race-proof.
    if ActiveSteals[brainrotId] ~= nil then
        return
    end
    -- TRADE COORDINATION: a unit locked in a trade offer can't be stolen (can't become IN_TRANSIT).
    if TradeLockRegistry.Has(brainrotId) then
        Remotes.NotifyPlayer(thief, "error", "That brainrot is locked in a trade.")
        return
    end
    -- CARRY-WHILE-CARRYING: never hold two.
    if carryingByThief[thief] ~= nil then
        Remotes.NotifyPlayer(thief, "error", "You're already carrying something.")
        return
    end

    local victim = Players:GetPlayerByUserId(ownerUserId)
    if victim == nil then
        return
    end
    if victim == thief then
        Remotes.NotifyPlayer(thief, "error", "You can't steal your own brainrot.")
        return
    end

    local now = os.clock()
    local last = lastStealTime[thief]
    -- VIP edge: Benefits returns a cooldown multiplier (<1 shortens) for this thief; 1 otherwise.
    local cooldown = StealConfig.StealCooldown * Benefits.GetStealCooldownMult(thief)
    if last ~= nil and now - last < cooldown then
        Remotes.NotifyPlayer(thief, "error", "Steal is on cooldown.")
        return
    end
    local imm = immunityUntil[brainrotId]
    if imm ~= nil and now < imm then
        Remotes.NotifyPlayer(thief, "error", "That one was just stolen -- wait a moment.")
        return
    end
    if ProtectionService.IsProtected(victim) then
        Remotes.NotifyPlayer(thief, "error", "That base is protected.")
        return
    end

    local victimProfile = ProfileManager.GetProfile(victim)
    local thiefProfile = ProfileManager.GetProfile(thief)
    if victimProfile == nil or thiefProfile == nil then
        return
    end
    -- Target must exist and be ON_PAD (present in victim data; not in transit -- checked).
    local entry = findEntry(victimProfile, brainrotId)
    if entry == nil then
        return
    end

    local thiefPlot = PlotService.GetPlot(thief)
    local victimPlot = PlotService.GetPlot(victim)
    if thiefPlot == nil or victimPlot == nil then
        return
    end
    -- Require + RESERVE a free pad up front so DEPOSIT always has a home (FULL THIEF PADS).
    local reservedIndex = PlotService.FindFreePad(thief, thiefProfile)
    if reservedIndex == nil then
        Remotes.NotifyPlayer(thief, "error", "You have no free pad to steal to.")
        return
    end
    local character = thief.Character
    if character == nil or character:FindFirstChild("HumanoidRootPart") == nil then
        Remotes.NotifyPlayer(thief, "error", "Can't carry right now.")
        return
    end

    -- ===== COMMIT: flip ON_PAD -> IN_TRANSIT. No yields through the registry writes. =====
    PlotService.ReservePad(thief, reservedIndex)
    local steal = {
        Thief = thief,
        Victim = victim,
        BrainrotId = brainrotId,
        Type = entry.Type,
        OriginalPadIndex = entry.PadIndex,
        ReservedPadIndex = reservedIndex,
        StartTime = now,
    }
    ActiveSteals[brainrotId] = steal
    carryingByThief[thief] = brainrotId
    TransitRegistry.Set(brainrotId, true)

    -- Visuals: lift it off the victim's pad, weld a carried model to the thief, slow the thief.
    BrainrotService.RemoveModel(victim, brainrotId)
    steal.CarriedModel = BrainrotService.MakeCarriedModel(character, entry)
    applyCarryPenalty(thief, steal)

    -- Victim stops earning this unit immediately.
    PlayerStats.UpdateIncome(victim, victimProfile)

    -- Feedback: rarity-colored victim toast + everyone-sees kill-feed banner. The mutation name is
    -- prefixed (e.g. "RAINBOW Tralalero") to amplify the drama -- the mutation travels with the unit.
    local def = defFor(entry.Type)
    local rarity = Rarity.Get(def.Rarity)
    local mutDef = entry.Mutation ~= nil and MutationConfig.Get(entry.Mutation) or nil
    local displayName = (
        (mutDef ~= nil and mutDef.DisplayName ~= "") and (mutDef.DisplayName .. " ") or ""
    ) .. def.DisplayName
    Remotes.NotifyPlayer(
        victim,
        "error",
        thief.Name
            .. ' stole your <font color="'
            .. toHex(rarity.Color)
            .. '"><b>'
            .. displayName
            .. "</b></font>!",
        "robbed"
    )
    Remotes.BroadcastKillFeed({
        Thief = thief.Name,
        Victim = victim.Name,
        Name = displayName,
        Rarity = def.Rarity,
        Mutation = entry.Mutation,
    })
    Analytics.customOnce(victim, Analytics.Events.FirstRobbed)
end

-- Reverts a carry if the thief's character dies or is removed (covers death mid-carry and a
-- character removed without Died firing). The unit returns to the victim.
local function onThiefLost(player)
    local id = carryingByThief[player]
    if id == nil then
        return
    end
    local steal = ActiveSteals[id]
    if steal ~= nil then
        revert(steal, true)
    end
end

local function onCharacter(player, character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid == nil then
        humanoid = character:WaitForChild("Humanoid", 5)
    end
    if humanoid ~= nil then
        humanoid.Died:Connect(function()
            onThiefLost(player)
        end)
    end
end

local function hookPlayer(player)
    player.CharacterAdded:Connect(function(character)
        onCharacter(player, character)
    end)
    if player.Character ~= nil then
        onCharacter(player, player.Character)
    end
    -- CharacterRemoving fires before the character is destroyed (death-respawn, fall, etc.).
    player.CharacterRemoving:Connect(function()
        onThiefLost(player)
    end)
end

-- Called by Bootstrap on PlayerRemoving, BEFORE ProfileManager releases/saves the profile, so
-- every steal the player is involved in is settled against correct, un-duped data first.
function StealService.ResolvePlayer(player)
    -- As THIEF: return the carried unit to its victim.
    onThiefLost(player)
    -- As VICTIM: cancel each steal of their units (dupe-safe -- unit stays in their data and
    -- saves with them; thief loses it). Do NOT respawn on the leaving victim's pad.
    for _, steal in pairs(ActiveSteals) do
        if steal.Victim == player then
            revert(steal, false)
        end
    end
    lastStealTime[player] = nil
    carryingByThief[player] = nil
end

-- Read by IncomeService/PlayerStats indirectly via TransitRegistry; exposed for completeness.
function StealService.IsInTransit(brainrotId)
    return ActiveSteals[brainrotId] ~= nil
end

-- True if the player is involved in any in-flight steal (as thief carrying, or as a victim whose
-- unit is mid-carry). Used by RebirthService/TradeService to refuse a destructive op mid-steal so
-- nothing can be duped or stranded.
function StealService.IsBusy(player)
    if carryingByThief[player] ~= nil then
        return true
    end
    for _, steal in pairs(ActiveSteals) do
        if steal.Victim == player or steal.Thief == player then
            return true
        end
    end
    return false
end

function StealService.Init()
    -- Server-authoritative completion: the prompt fires here, never asserted by the client.
    ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

    for _, player in ipairs(Players:GetPlayers()) do
        hookPlayer(player)
    end
    Players.PlayerAdded:Connect(hookPlayer)

    -- DEPOSIT detection (server-side distance) + carry TIMEOUT + carried-model bob.
    RunService.Heartbeat:Connect(function(deltaTime)
        loopAccum += deltaTime
        if loopAccum < LOOP_INTERVAL then
            return
        end
        loopAccum = 0

        local now = os.clock()
        -- Safe to remove the current key during pairs(); deposit/revert only remove their own.
        for _, steal in pairs(ActiveSteals) do
            if now - steal.StartTime > StealConfig.CarryTimeout then
                revert(steal, true) -- STALE/STUCK CARRY: force-revert
            else
                local character = steal.Thief.Character
                local hrp = character and character:FindFirstChild("HumanoidRootPart")
                local pad = PlotService.GetPad(steal.Thief, steal.ReservedPadIndex)
                if hrp ~= nil and pad ~= nil then
                    if (hrp.Position - pad.Position).Magnitude <= StealConfig.DepositRange then
                        deposit(steal)
                    elseif StealConfig.CarryBob and steal.CarriedModel ~= nil then
                        local weld = steal.CarriedModel:FindFirstChild("CarryWeld")
                        if weld ~= nil then
                            weld.C0 = CFrame.new(0, 3 + math.sin(now * 4) * 0.25, 0)
                        end
                    end
                elseif character == nil then
                    revert(steal, true) -- character gone without Died/CharacterRemoving
                end
            end
        end
    end)
end

return StealService
