-- StealConfig: THE single place to retune the entire M4 steal economy. Every tunable
-- number for stealing, carrying, depositing, cooldowns, and the timer-based defense layer
-- lives here -- no service hardcodes any of them.
--
-- (Defense is intentionally simple + timer-based for v1: protection WINDOWS, not a
--  destructible-HP wall. A future option is per-plot HP "locks" you grind down -- NOT built
--  this milestone; left as a note only.)
--
-- M6 PACING INTENT (fun-but-fair; retune freely, all here):
--   * Robbing is EXCITING but commits you: a 3.5s hold (defenders get a reaction window), a carry
--     speed penalty + a 60s carry timeout (you must get home), and a 10s thief cooldown so there's
--     no instant chain-robbing.
--   * Being robbed is RECOVERABLE, not rage-quit: a long new-player grace, a 30s post-robbery
--     shield to regroup, and 10s per-unit immunity so the same unit can't be re-yoinked instantly.

local StealConfig = {}

-- ── Steal / carry timing ───────────────────────────────────────────────────────────────
StealConfig.HoldDuration = 3.5 -- s: ProximityPrompt hold time to grab a brainrot (defenders get a window)
StealConfig.PromptMaxDistance = 10 -- studs: how close a thief must be for the steal prompt to show
StealConfig.CarryTimeout = 60 -- s: auto-REVERT a steal not deposited in time (prevents stuck carries)
StealConfig.DepositRange = 14 -- studs: server-verified distance to the reserved pad that auto-deposits

-- ── Carry penalty (risk/reward) ────────────────────────────────────────────────────────
StealConfig.CarryWalkSpeedMult = 0.75 -- thief WalkSpeed multiplier while carrying (1 = no penalty). Restored on any exit.
StealConfig.CarryBob = true -- subtle vertical bob on the carried model (purely cosmetic)

-- ── Cooldowns / immunity ───────────────────────────────────────────────────────────────
StealConfig.StealCooldown = 10 -- s: minimum gap between a thief's successful steals (no instant chain-stealing)
StealConfig.PostStealImmunity = 10 -- s: a just-stolen unit can't be re-stolen for this long

-- ── M11.1 perk defense ───────────────────────────────────────────────────────────────────
StealConfig.StunDuration = 1.25 -- s: a thief stunned by a defender perk (Stampede/Kraken/Meltdown) is frozen this long

-- ── Defense: protection windows ────────────────────────────────────────────────────────
StealConfig.NewPlayerGrace = 120 -- s: protection granted when a player first spawns in this session
StealConfig.PostRobberyProtection = 30 -- s: protection granted to a victim right after they're successfully robbed

return StealConfig
