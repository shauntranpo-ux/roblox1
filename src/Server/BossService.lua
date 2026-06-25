-- BossService (M11.3-combat): WORLD-BOSS CO-OP FIGHTS. The server periodically spawns ONE giant Titan
-- with an HP bar; the whole server is alerted and FIGHTS it down together -- each validated attack
-- deals damage = that player's SERVER-COMPUTED equipped-team power (the M11.1 loadout x factors x
-- combat perks). When HP hits zero, EVERY qualifying player gets their OWN freshly-FACTORY-MINTED
-- contribution-weighted reward (contribution = damage dealt). Co-op is EPHEMERAL -- the "party" is
-- whoever showed up, and it dissolves on kill. (Base-raid combat is a separate future phase -- NOT here;
-- this touches NOTHING in StealService / ownership transfer.)
--
-- ============================  SELF-AUDIT (boss path)  =======================================
-- (a) SERVER-AUTHORITATIVE + KILL RESOLVES ONCE: BossState (HP, contribution, timer) lives only in
--     server memory. HP drops ONLY from server-side PromptTriggered attacks, each re-validated
--     (proximity + rate cap) with damage computed server-side from the attacker's REAL equipped team
--     (CombatPower) -- the client never sends power/HP/damage/contribution. The kill is guarded by
--     boss.Resolved (set synchronously before any yield, like the steal INITIATE guard), so two
--     concurrent killing blows resolve the kill EXACTLY once.
-- (b) REWARDS ARE DUPE-SAFE: each qualifying player's reward is created fresh via BrainrotFactory
--     (a NEW unique Id) and/or cash via the guarded accessor -- NOTHING is transferred or split, so no
--     race can duplicate or lose anything. Distribution iterates the frozen contribution map ONCE;
--     each player appears once. No-free-pad -> safe cash fallback (always delivered, never lost/duped).
-- (c) NO SPOOF / NO LEECH: contribution comes only from validated holds (server proximity check +
--     per-player rate-limit); a client can't inject a number. A player below ParticipationThreshold
--     (AFK / standing near without holding) banks too little and gets NOTHING.
-- (d) INFEASIBLE FOR A WEAK SOLO, BEATABLE AS A GROUP OR STRONG TEAM: boss HP vs per-attack team-power
--     damage + AttackInterval is tuned so a base-tap-only player can't kill it before Timeout; more
--     players / higher team power = faster (emergent, no special-casing). All numbers in Boss/CombatConfig.
-- (e) FORWARD-COMPAT: spawns on a placeholder map at a default position (biomes later); combat perks
--     boost damage via CombatPower under caps; M11.2 boss XP via AwardAllXP.
-- (f) Touches NO other system's dupe-proofing -- it only reads CombatPower + mints via the factory.
--     StealService / ownership transfer are UNTOUCHED (base-raid combat is a separate Phase 2).
-- ===========================================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Shared.BossConfig)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local ProfileManager = require(script.Parent.ProfileManager)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local BrainrotService = require(script.Parent.BrainrotService)
local PlotService = require(script.Parent.PlotService)
local PlayerStats = require(script.Parent.PlayerStats)
local Leaderstats = require(script.Parent.Leaderstats)
local CombatPower = require(script.Parent.CombatPower) -- M11.3-combat: server-authoritative team power
local EvolutionService = require(script.Parent.EvolutionService)
local ExclusivesService = require(script.Parent.ExclusivesService)
local Analytics = require(script.Parent.Analytics)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)

local BossService = {}

-- Single authoritative boss (MaxConcurrent default 1). nil = none active.
local activeBoss = nil
local spawnAccum = 0
local hudAccum = 0

-- ===========================================================================================
-- Spawn / model
-- ===========================================================================================
local function makeBossModel(def)
    local part = Instance.new("Part")
    part.Name = "WorldBoss_" .. def.Key
    part.Anchored = true
    part.CanCollide = false -- players approach + hold the prompt; never trap them
    part.Size = def.ModelSize or Vector3.new(18, 26, 18)
    part.Color = def.Color or Color3.fromRGB(180, 60, 220)
    part.Material = Enum.Material.Neon
    part.Position = BossConfig.DefaultSpawnPosition

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BossUI"
    billboard.Size = UDim2.fromScale(12, 3)
    billboard.StudsOffsetWorldSpace =
        Vector3.new(0, (def.ModelSize and def.ModelSize.Y or 26) / 2 + 5, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.Parent = part

    local name = Instance.new("TextLabel")
    name.Size = UDim2.fromScale(1, 0.5)
    name.BackgroundTransparency = 1
    name.Font = Enum.Font.FredokaOne -- VM-THEME world label font
    name.Text = "TITAN " .. def.DisplayName
    name.TextColor3 = Color3.fromRGB(255, 230, 120)
    name.TextStrokeTransparency = 0.3
    name.TextScaled = true
    name.Parent = billboard

    local barBg = Instance.new("Frame")
    barBg.Position = UDim2.fromScale(0.05, 0.55)
    barBg.Size = UDim2.fromScale(0.9, 0.35)
    barBg.BackgroundColor3 = Color3.fromRGB(30, 20, 40)
    barBg.BorderSizePixel = 0
    barBg.Parent = billboard

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(1, 1)
    fill.BackgroundColor3 = Color3.fromRGB(230, 70, 90)
    fill.BorderSizePixel = 0
    fill.Parent = barBg

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "BossPrompt"
    prompt.ActionText = "Attack"
    prompt.ObjectText = def.DisplayName
    prompt.HoldDuration = def.AttackHold -- a quick TAP per attack (damage = the attacker's team power)
    prompt.MaxActivationDistance = def.PromptRange
    prompt.RequiresLineOfSight = false
    prompt.Parent = part

    part.Parent = Workspace
    return part, prompt, fill
end

local function spawnBoss(def)
    if activeBoss ~= nil then
        return
    end
    local model, prompt, fill = makeBossModel(def)
    activeBoss = {
        Def = def,
        Model = model,
        Prompt = prompt,
        Fill = fill,
        HP = def.HP,
        MaxHP = def.HP,
        StartTime = os.clock(),
        Contribution = {}, -- [Player] = total DAMAGE dealt (server-only; = the M11.3 contribution)
        LastHit = {}, -- [Player] = clock of last validated attack (rate-limit)
        Resolved = false,
    }
    Remotes.BroadcastBoss({
        Kind = "spawn",
        Name = def.DisplayName,
        Biome = def.Biome,
        HP = def.HP,
        Max = def.HP,
        Pos = model.Position,
        TimeLeft = def.Timeout,
    })
    -- LogCustomEvent needs a player; the spawn is server-wide, so attribute it to each present player.
    for _, p in ipairs(Players:GetPlayers()) do
        Analytics.custom(p, Analytics.Events.BossSpawn, 1)
    end
end

local function despawn(boss)
    if boss.Model ~= nil then
        boss.Model:Destroy()
        boss.Model = nil
    end
    if activeBoss == boss then
        activeBoss = nil
    end
    Remotes.BroadcastBoss({ Kind = "gone" })
end

-- ===========================================================================================
-- Rewards (dupe-safe: factory-minted per player; nothing split/transferred)
-- ===========================================================================================
local function rollReward(def)
    local table_ = def.Reward.Table
    local total = 0
    for _, entry in ipairs(table_) do
        total += (entry.Weight or 0)
    end
    if total <= 0 then
        return table_[1]
    end
    local pick = math.random() * total
    local acc = 0
    for _, entry in ipairs(table_) do
        acc += (entry.Weight or 0)
        if pick <= acc then
            return entry
        end
    end
    return table_[#table_]
end

-- Grants ONE qualifying player their OWN reward. Cash scales with contribution share (higher
-- contribution pays more); the unit roll is fair + freshly minted via the factory.
local function grantReward(player, boss, dmg, total)
    local profile = ProfileManager.GetProfile(player)
    if profile == nil then
        return -- player left / not ready -> skip safely (can't place a unit for an absent player)
    end
    local rewardDef = boss.Def.Reward
    local share = total > 0 and (dmg / total) or 0
    local cash = math.floor(rewardDef.Cash.Min + (rewardDef.Cash.Max - rewardDef.Cash.Min) * share)

    local entry = rollReward(boss.Def)
    local revealName = nil
    if entry.Type == "Cash" then
        cash += entry.Amount or 0
        revealName = "bonus cash"
    elseif entry.Type == "Brainrot" then
        local def = Catalog.Get(entry.Species)
        if def ~= nil then
            local plot = PlotService.GetPlot(player)
            local pad = plot ~= nil and PlotService.FindFreePad(player, profile) or nil
            if pad ~= nil then
                -- DUPE-SAFE: a brand-new unit minted for THIS player (never shared/transferred).
                -- M11.4: if the reward species is a SEASONAL EXCLUSIVE, only mint it while its window is
                -- OPEN now (an authorized in-window drop); otherwise the factory refuses -> cash fallback.
                local allowExcl = def.ExclusiveSeason ~= nil
                    and ExclusivesService.IsObtainable({
                        Source = "boss",
                        SeasonId = def.ExclusiveSeason,
                    })
                local unit = BrainrotFactory.create(player, def, pad, false, allowExcl)
                if unit ~= nil then
                    if entry.Mutation ~= nil then
                        unit.Mutation = entry.Mutation -- boss-only mutation granted directly
                        profile.Data.MutationsDiscovered[entry.Mutation] = true
                    end
                    table.insert(profile.Data.OwnedBrainrots, unit)
                    profile.Data.Discovered[def.Id] = true
                    BrainrotService.SpawnBrainrot(player, plot, unit)
                    revealName = (entry.Mutation ~= nil and (entry.Mutation .. " ") or "")
                        .. def.DisplayName
                else
                    cash += rewardDef.NoPadCash or 25000 -- exclusive window closed -> cash fallback
                    revealName = "cash (exclusive expired)"
                end
            else
                -- NO-FREE-PAD: deliver the safe cash fallback (never lost, never duped).
                cash += rewardDef.NoPadCash or 25000
                revealName = "cash (no free pad)"
            end
        end
    end

    if cash > 0 then
        ProfileManager.AddCash(player, cash)
    end
    -- M11.2: the player's units gain boss XP (forward-compat hook, now wired).
    EvolutionService.AwardAllXP(player, boss.Def.BossXP or 0)

    PlayerStats.PushCash(player, profile)
    PlayerStats.UpdateIncome(player, profile)
    Leaderstats.Update(player, profile)
    ProfileManager.ForceSave(player)

    Remotes.NotifyPlayer(
        player,
        "success",
        "TITAN reward: " .. (revealName or "loot") .. (cash > 0 and ("  +$" .. cash) or ""),
        "buy"
    )
    Analytics.custom(player, Analytics.Events.BossReward, 1)
end

-- ===========================================================================================
-- Kill resolution (guarded: resolves EXACTLY once)
-- ===========================================================================================
local function resolveKill(boss)
    if boss.Resolved then
        return
    end
    boss.Resolved = true -- GUARD: set before any yield so concurrent final hits resolve once
    if boss.Prompt ~= nil then
        boss.Prompt.Enabled = false -- no more contributions
    end

    -- Freeze the contribution map + pick qualifiers (present + met the threshold).
    local total = 0
    for _, banked in pairs(boss.Contribution) do
        total += banked
    end
    local winners = {}
    for player, banked in pairs(boss.Contribution) do
        if banked >= boss.Def.ParticipationThreshold and player.Parent == Players then
            table.insert(winners, { Player = player, Dmg = banked })
        end
    end

    Remotes.BroadcastBoss({
        Kind = "defeat",
        Name = boss.Def.DisplayName,
        Participants = #winners,
    })

    -- Mint each qualifier's OWN reward (exactly once per player) + log the kill + damage per participant.
    for _, win in ipairs(winners) do
        Analytics.custom(win.Player, Analytics.Events.BossKill, #winners)
        Analytics.custom(win.Player, Analytics.Events.BossDamage, math.floor(win.Dmg))
        grantReward(win.Player, boss, win.Dmg, total)
    end

    despawn(boss)
end

-- Timeout: the boss enrages + leaves with NO rewards; state cleared cleanly.
local function enrageDespawn(boss)
    if boss.Resolved then
        return
    end
    boss.Resolved = true
    if boss.Prompt ~= nil then
        boss.Prompt.Enabled = false
    end
    Remotes.BroadcastBoss({ Kind = "flee", Name = boss.Def.DisplayName })
    for _, p in ipairs(Players:GetPlayers()) do
        Analytics.custom(p, Analytics.Events.BossFlee, 1)
    end
    despawn(boss)
end

-- ===========================================================================================
-- The validated hit (server-authoritative; the ONLY way the meter drains)
-- ===========================================================================================
local function onBossPromptTriggered(prompt, player)
    if prompt.Name ~= "BossPrompt" then
        return
    end
    local boss = activeBoss
    if boss == nil or boss.Resolved or boss.Prompt ~= prompt then
        return
    end
    -- Server-enforced attack RATE CAP (per player) -- blunts spam + bounds a player's DPS.
    if not RateLimiter.check(player, "boss", boss.Def.AttackInterval) then
        return
    end
    -- Server-side proximity re-check on the REAL character: the client can't spoof being near the boss.
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if hrp == nil or boss.Model == nil then
        return
    end
    if (hrp.Position - boss.Model.Position).Magnitude > boss.Def.ValidateRange then
        return
    end

    -- DAMAGE = the attacker's SERVER-COMPUTED team power (their equipped loadout x factors x combat
    -- perks, capped) x attack scalar + base tap. The client NEVER sends power/damage/death. The damage
    -- is added to this player's contribution entry (M11.3 contribution = total DAMAGE dealt now).
    local dmg = CombatPower.AttackDamage(player)
    boss.HP = math.max(0, boss.HP - dmg)
    boss.Contribution[player] = (boss.Contribution[player] or 0) + dmg
    if boss.Fill ~= nil then
        boss.Fill.Size = UDim2.fromScale(math.clamp(boss.HP / boss.MaxHP, 0, 1), 1)
    end
    -- Targeted attack-juice cue: this attacker sees their OWN damage number pop at the boss (the
    -- big shared HP bar drains via the throttled broadcast below).
    Remotes.BossUpdate:FireClient(player, { Kind = "hit", Damage = dmg, Pos = boss.Model.Position })

    if boss.HP <= 0 then
        resolveKill(boss)
    end
end

-- ===========================================================================================
-- Lifecycle
-- ===========================================================================================

-- A leaving player is dropped from the live contribution map (so a stale ref isn't held, and they're
-- not granted a reward they can't receive). Called from Bootstrap before profile release.
function BossService.ClearPlayer(player)
    if activeBoss ~= nil then
        activeBoss.Contribution[player] = nil
        activeBoss.LastHit[player] = nil
    end
end

-- Dev/test helper: spawn a boss immediately if none is active (lower BossConfig timings to test fast).
function BossService.ForceSpawn()
    if activeBoss ~= nil then
        return false
    end
    local def = BossConfig.PickSpawn()
    if def == nil then
        return false
    end
    spawnBoss(def)
    return true
end

function BossService.Init()
    -- Server-authoritative completion: the prompt fires here, never asserted by the client.
    ProximityPromptService.PromptTriggered:Connect(onBossPromptTriggered)

    if not BossConfig.Enabled then
        return
    end
    -- First spawn after FirstSpawnDelay, then every SpawnInterval.
    spawnAccum = BossConfig.SpawnInterval - BossConfig.FirstSpawnDelay

    RunService.Heartbeat:Connect(function(deltaTime)
        local boss = activeBoss
        if boss ~= nil and not boss.Resolved then
            if os.clock() - boss.StartTime > boss.Def.Timeout then
                enrageDespawn(boss)
            else
                hudAccum += deltaTime
                if hudAccum >= 0.3 then -- throttled live meter/timer broadcast for the HUD (~3 Hz)
                    hudAccum = 0
                    Remotes.BroadcastBoss({
                        Kind = "update",
                        HP = boss.HP,
                        Max = boss.MaxHP,
                        Pos = boss.Model ~= nil and boss.Model.Position or nil,
                        TimeLeft = math.max(0, boss.Def.Timeout - (os.clock() - boss.StartTime)),
                    })
                end
            end
        end

        if activeBoss == nil then
            spawnAccum += deltaTime
            if spawnAccum >= BossConfig.SpawnInterval then
                spawnAccum = 0
                local def = BossConfig.PickSpawn()
                if def ~= nil then
                    spawnBoss(def)
                end
            end
        end
    end)
end

return BossService
