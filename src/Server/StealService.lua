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
--
-- ── M11.1 SIGNATURE PERKS (difficulty/params/visuals ONLY) ──────────────────────────────
-- RAID/DEF/MOVE perks read from the decoupled PerkEffects aggregate and adjust ONLY: the thief's
-- steal cooldown, deposit reach, how many units they may carry at once, carry walkspeed, raid
-- stealth (whether the victim is alerted), and the DEFENDER's pre-transfer block (stun/interrupt).
-- They NEVER touch transferOwnership -- multi-carry is just N independent single-unit steals by one
-- thief, each atomic + dupe-proof, and a thief's loss reverts ALL of them dupe-safely.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StealConfig = require(ReplicatedStorage.Shared.StealConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local MutationConfig = require(ReplicatedStorage.Shared.MutationConfig)
local PerksConfig = require(ReplicatedStorage.Shared.PerksConfig)
local EvolutionConfig = require(ReplicatedStorage.Shared.EvolutionConfig)

local ProfileManager = require(script.Parent.ProfileManager)
local PlotService = require(script.Parent.PlotService)
local BrainrotService = require(script.Parent.BrainrotService)
local ProtectionService = require(script.Parent.ProtectionService)
local PlayerStats = require(script.Parent.PlayerStats)
local Remotes = require(script.Parent.Remotes)
local TransitRegistry = require(script.Parent.TransitRegistry)
local Benefits = require(script.Parent.Benefits)
local Analytics = require(script.Parent.Analytics)
local GameSignals = require(script.Parent.GameSignals) -- M12.1 quest observation bus
local TradeLockRegistry = require(script.Parent.TradeLockRegistry)
local DeployLockRegistry = require(script.Parent.DeployLockRegistry)
local PerkEffects = require(script.Parent.PerkEffects)
local EventService = require(script.Parent.EventService)
local SeasonService = require(script.Parent.SeasonService)

local StealService = {}

-- Authoritative in-memory registries.
local ActiveSteals = {} -- [brainrotId] = steal record (its presence == IN_TRANSIT)
local carriedByThief = {} -- [Player] = { [brainrotId] = true } (a thief may carry up to a perk-set max)
local lastStealTime = {} -- [Player] = clock of last SUCCESSFUL steal (cooldown)
local immunityUntil = {} -- [brainrotId] = clock until which it can't be re-stolen
local moveMultByThief = {} -- [Player] = walkspeed multiplier from MOVE perks (default 1)

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

-- How many units a thief is currently carrying.
local function carryCount(player)
    local set = carriedByThief[player]
    if set == nil then
        return 0
    end
    local n = 0
    for _ in pairs(set) do
        n += 1
    end
    return n
end

-- THE single authority over a thief's WalkSpeed. Computes it from scratch every time -- base
-- walkspeed x MOVE-perk multiplier, then (while carrying) x the carry penalty eased by carry-speed
-- perks. No store/restore (which can't compose with multi-carry); always a fresh, correct value.
local function applyThiefWalkSpeed(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid == nil then
        return
    end
    local speed = PerksConfig.BaseWalkSpeed * (moveMultByThief[player] or 1)
    if carryCount(player) > 0 then
        local ease = PerkEffects.CarryEase(player)
        local penalty = StealConfig.CarryWalkSpeedMult
        penalty = penalty + (1 - penalty) * ease
        speed = speed * penalty
    end
    humanoid.WalkSpeed = speed
end

-- LoadoutService pushes the player's MOVE-perk multiplier here on every loadout change; we re-apply
-- the authoritative walkspeed immediately (covers equip/unequip/swap of a movement perk).
function StealService.SetMoveMult(player, mult)
    moveMultByThief[player] = mult
    applyThiefWalkSpeed(player)
end

-- Tears down all IN_TRANSIT runtime state for ONE steal (NOT ownership data). Always called by
-- both DEPOSIT and REVERT so every exit path kills the carried model, clears the registries,
-- recomputes the thief's walkspeed, and (optionally) releases the reserved pad.
local function clearSteal(steal, releaseReservation)
    TransitRegistry.Set(steal.BrainrotId, false)
    ActiveSteals[steal.BrainrotId] = nil
    local set = carriedByThief[steal.Thief]
    if set ~= nil then
        set[steal.BrainrotId] = nil
    end
    if steal.CarriedModel ~= nil then
        steal.CarriedModel:Destroy()
        steal.CarriedModel = nil
    end
    if releaseReservation then
        PlotService.ReleasePad(steal.Thief, steal.ReservedPadIndex)
    end
    applyThiefWalkSpeed(steal.Thief) -- carry count dropped -> recompute (may remove the penalty)
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
    -- TRANSFER SAFETY (M9.2 + M11.2): `entry` is the WHOLE per-unit record, so its intrinsic Mutation,
    -- Star, EvolutionStage AND XP all move with it UNCHANGED -- never re-rolled, stripped, reset, or
    -- duplicated (the steal only moves the ONE table reference between inventories). An evolved unit
    -- keeps its exact stage + XP for the thief (which makes evolved units premium steal targets). The
    -- thief now owns it -> discover the mutation.
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
    EventService.Signal(steal.Thief, "STEAL_BRAINROTS", 1)
    SeasonService.Signal(steal.Thief, "STEAL", 1)
    GameSignals.fire(steal.Thief, "steals_succeeded", 1) -- M12.1 quests; pure emit, no behavior change
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

-- DEFENDER perk punish: knock the thief back from the victim's base + freeze them briefly. This is
-- a PRE-TRANSFER physical effect on the thief's character only -- no steal state exists (we return
-- before COMMIT), so nothing can be duped or stranded.
local function applyStun(thief, victim, victimPlot)
    local character = thief.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if hrp == nil or humanoid == nil then
        return
    end
    local knock = PerkEffects.DefenderKnockback(victim)
    if knock > 0 and victimPlot ~= nil then
        local away = (hrp.Position - victimPlot.Origin.Position)
        local dir = away.Magnitude > 0.1 and away.Unit or hrp.CFrame.LookVector * -1
        hrp.AssemblyLinearVelocity = dir * knock + Vector3.new(0, knock * 0.4, 0)
    end
    humanoid.WalkSpeed = 0
    task.delay(StealConfig.StunDuration, function()
        if thief.Parent == Players then
            applyThiefWalkSpeed(thief) -- restore (respects current carry/move perks)
        end
    end)
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
    -- M11.1 EQUIP: an equipped (perk-holder) unit is locked and can't be stolen.
    if DeployLockRegistry.Has(brainrotId) then
        Remotes.NotifyPlayer(thief, "error", "That brainrot is equipped and can't be stolen.")
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

    -- CARRY CAPACITY: a thief may carry up to a perk-set max at once (default 1; Carpet Bomb 2, etc.).
    local maxCarry = PerkEffects.CarryCount(thief)
    if carryCount(thief) >= maxCarry then
        Remotes.NotifyPlayer(thief, "error", "Your hands are full.")
        return
    end

    local now = os.clock()
    local last = lastStealTime[thief]
    -- VIP edge + RAID perks: a per-thief cooldown multiplier (<1 shortens). Both combine here.
    local cooldown = StealConfig.StealCooldown
        * Benefits.GetStealCooldownMult(thief)
        * PerkEffects.AttackerCooldownMult(thief)
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

    -- M11.1 DEFENDER perks (defense): Stun (block + knockback) and/or Interrupt (block) form a
    -- PRE-TRANSFER gate ONLY -- on a block NOTHING is moved and NO steal state is created, so the
    -- dupe-proof ON_PAD -> IN_TRANSIT machine below is completely untouched.
    local victimStun = PerkEffects.DefenderStun(victim)
    local interruptChance = PerkEffects.DefenderInterrupt(victim)
    local blocked = victimStun or (interruptChance > 0 and math.random() < interruptChance)
    if blocked then
        if victimStun then
            applyStun(thief, victim, victimPlot)
        end
        -- M11.2 XP: the targeted unit SURVIVED a steal attempt -> it banks XP toward evolving (capped
        -- gracefully at max stage). This is intrinsic to the unit record; nothing else changes.
        EvolutionConfig.AddXP(entry, EvolutionConfig.SurviveStealXP)
        Remotes.NotifyPlayer(
            thief,
            "error",
            "Blocked! " .. victim.Name .. "'s defense stopped you."
        )
        Remotes.NotifyPlayer(victim, "info", "You blocked " .. thief.Name .. "'s steal!")
        return
    end

    -- ===== COMMIT: flip ON_PAD -> IN_TRANSIT. No yields through the registry writes. =====
    PlotService.ReservePad(thief, reservedIndex)
    local stackIndex = carryCount(thief) -- 0-based: stack additional carried models above the first
    local steal = {
        Thief = thief,
        Victim = victim,
        BrainrotId = brainrotId,
        Type = entry.Type,
        OriginalPadIndex = entry.PadIndex,
        ReservedPadIndex = reservedIndex,
        StartTime = now,
        CarryHeight = 3 + stackIndex * 3.2, -- weld height for this carry (stacks multi-carry models)
    }
    ActiveSteals[brainrotId] = steal
    carriedByThief[thief] = carriedByThief[thief] or {}
    carriedByThief[thief][brainrotId] = true
    TransitRegistry.Set(brainrotId, true)

    -- Visuals: lift it off the victim's pad, weld a carried model to the thief, recompute carry speed.
    BrainrotService.RemoveModel(victim, brainrotId)
    steal.CarriedModel = BrainrotService.MakeCarriedModel(character, entry, stackIndex)
    applyThiefWalkSpeed(thief)

    -- Victim stops earning this unit immediately.
    PlayerStats.UpdateIncome(victim, victimProfile)

    -- Feedback. M11.1 stealth: an Invisible raider does NOT alert the victim and is NOT broadcast to
    -- the kill-feed -- UNLESS the victim has the Alert defender perk (they always see raids).
    local thiefInvisible = PerkEffects.IsInvisible(thief)
    local victimAlerted = PerkEffects.DefenderAlert(victim) or not thiefInvisible

    local def = defFor(entry.Type)
    local rarity = Rarity.Get(def.Rarity)
    local mutDef = entry.Mutation ~= nil and MutationConfig.Get(entry.Mutation) or nil
    local displayName = (
        (mutDef ~= nil and mutDef.DisplayName ~= "") and (mutDef.DisplayName .. " ") or ""
    ) .. def.DisplayName
    if victimAlerted then
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
    end
    if not thiefInvisible then
        -- M13.4: broadcast the FILTERED SafeName (never a raw user-authored name) + the userIds, so the
        -- client can flag "you" by id instead of a brittle name-equality check.
        Remotes.BroadcastKillFeed({
            Thief = thief:GetAttribute("SafeName") or thief.Name,
            ThiefUserId = thief.UserId,
            Victim = victim:GetAttribute("SafeName") or victim.Name,
            VictimUserId = victim.UserId,
            Name = displayName,
            Rarity = def.Rarity,
            Mutation = entry.Mutation,
        })
    end
    Analytics.customOnce(victim, Analytics.Events.FirstRobbed)
end

-- Reverts ALL of a thief's carries if their character dies or is removed (covers death mid-carry
-- and a character removed without Died firing). Each unit returns to its victim, dupe-safely.
local function onThiefLost(player)
    local set = carriedByThief[player]
    if set == nil then
        return
    end
    local ids = {}
    for id in pairs(set) do
        table.insert(ids, id)
    end
    for _, id in ipairs(ids) do
        local steal = ActiveSteals[id]
        if steal ~= nil then
            revert(steal, true)
        end
    end
end

local function onCharacter(player, character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid == nil then
        humanoid = character:WaitForChild("Humanoid", 5)
    end
    if humanoid ~= nil then
        -- Re-assert the MOVE-perk walkspeed on (re)spawn so a movement perk persists across death.
        applyThiefWalkSpeed(player)
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
    -- As THIEF: return EVERY carried unit to its victim.
    onThiefLost(player)
    -- As VICTIM: cancel each steal of their units (dupe-safe -- unit stays in their data and
    -- saves with them; thief loses it). Do NOT respawn on the leaving victim's pad.
    for _, steal in pairs(ActiveSteals) do
        if steal.Victim == player then
            revert(steal, false)
        end
    end
    lastStealTime[player] = nil
    carriedByThief[player] = nil
    moveMultByThief[player] = nil
end

-- Read by IncomeService/PlayerStats indirectly via TransitRegistry; exposed for completeness.
function StealService.IsInTransit(brainrotId)
    return ActiveSteals[brainrotId] ~= nil
end

-- True if the player is involved in any in-flight steal (as thief carrying, or as a victim whose
-- unit is mid-carry). Used by RebirthService/TradeService to refuse a destructive op mid-steal so
-- nothing can be duped or stranded.
function StealService.IsBusy(player)
    if carryCount(player) > 0 then
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
                    -- M11.1 RAID: extend the deposit reach by the thief's perk reach bonus (studs).
                    local range = StealConfig.DepositRange + PerkEffects.AttackerReach(steal.Thief)
                    if (hrp.Position - pad.Position).Magnitude <= range then
                        deposit(steal)
                    elseif StealConfig.CarryBob and steal.CarriedModel ~= nil then
                        local weld = steal.CarriedModel:FindFirstChild("CarryWeld")
                        if weld ~= nil then
                            weld.C0 = CFrame.new(0, steal.CarryHeight or 3, 0)
                                * CFrame.new(0, math.sin(now * 4) * 0.25, 0)
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
