# brainrot-game

Multiplayer Roblox idle/theft game. Players collect meme creatures ("brainrot") that generate passive cash, unlock rarer ones, and steal each other's units.

Built in milestones. Current: **M6 — hardening, onboarding, juice, balance & performance**. A full adversarial security audit (every remote's trust boundary documented + enforced; ONE guarded cash accessor; steal + receipt paths re-proven dupe/double-grant-proof; rate limiting on every client remote), a wordless first-session tutorial, a lightweight pooled juice layer (particles / camera shake / sound + a settings panel), a fast-early balance pass, and a scale pass (cached income loop, distance-capped labels, janitor cleanup, `BindToClose` flush). No new systems — hardening + feel only. (M5: monetization + leaderboards. M4: dupe-proof steal mechanic + timer defense. M3: rarity roster + scaling economy. M2: mobile HUD + secure purchase. M1: income loop + ProfileStore. M0: toolchain.) Everything economic and every ownership change is server-authoritative — the client only requests intent; the server validates and mutates.

## Stack

| Tool   | Purpose                     |
|--------|-----------------------------|
| Luau   | Scripting language          |
| Rojo   | Filesystem → Studio sync    |
| Wally  | Package manager             |
| Rokit  | Toolchain version manager   |
| StyLua | Formatter                   |
| Selene | Linter                      |

## Folder Structure

```
src/
  Server/                    → ServerScriptService > Server
    Bootstrap.server.lua     wires services + owns join ordering
    ProfileManager.lua       ProfileStore wrapper (load/save, mock fallback, accessors)
    Remotes.lua              creates the ReplicatedStorage/Remotes folder (single source)
    PlotService.lua          builds bases + per-session plot assignment + free-pad lookup
    BrainrotService.lua      grants/restores/spawns brainrots (SpawnBrainrot reused by buys)
    IncomeService.lua        Heartbeat income loop + throttled display push
    Leaderstats.lua          leaderstats.Cash readout in the player list
    PlayerStats.lua          Cash + IncomePerSec player Attributes for the HUD
    PurchaseService.lua      validates client buy requests (server-authoritative) + debounce
    InventoryService.lua     GetInventory RemoteFunction (server-truth owned list)
    StealService.lua         steal state machine: INITIATE/DEPOSIT/REVERT + ownership invariant
    ProtectionService.lua    timer-based plot protection (grace/post-robbery) + dome + M5 hooks
    TransitRegistry.lua      runtime set of in-transit (carried) brainrot Ids (income skips them)
    DevConfig.lua            server-only SIM flag (Studio purchase testing; guarded off on live)
    Benefits.lua             per-player benefit state (income mult, VIP edge); read by Income/Steal
    MonetizationService.lua  gamepass ownership + benefit registry + the single ProcessReceipt
    LeaderboardService.lua   OrderedDataStore boards (throttled, fault-tolerant, mock fallback)
    LeaderboardBillboards.lua in-world ranked displays (procedural; Assets model forward-compat)
    RateLimiter.lua          per-player, per-action remote throttle (anti-spam, all remotes)
    SettingsService.lua      persists/serves client prefs (Music/SFX/Shake); validates the shape
    TutorialService.lua      one-time onboarding handshake + saved TutorialDone flag
    Lib/ProfileStore.luau    vendored third-party data lib (loleris)
  Client/                    → StarterPlayer > StarterPlayerScripts > Client
    Client.client.lua        builds UI on spawn, wires remotes, hides own steal prompts
    UI/Theme.lua             colors + fonts (single styling source)
    UI/Builder.lua           declarative instance/panel helpers
    UI/HUD.lua               top cash pill (count-up) + Shop/Inventory buttons
    UI/Shop.lua              tabbed: cash roster + gamepass + product sections (data-driven)
    UI/Inventory.lua         owned list, fetched via RemoteFunction
    UI/Notifications.lua     transient toast stack (victim "stole your X!" alerts)
    UI/KillFeed.lua          everyone-sees steal banner (server broadcast)
    UI/Effects.lua           juice toolbox: pooled particles, camera shake, flashes, sound
    UI/Settings.lua          tiny prefs panel (Music / SFX / Screen Shake)
    UI/Tutorial.lua          one-time onboarding arrow + coachmark (Janitor-cleaned)
  Shared/                    → ReplicatedStorage > Shared
    Config.lua               plot/world tuning (brainrot stats now live in Catalog)
    Rarity.lua               rarity ladder: tier names, colors, order (single source)
    Catalog.lua              full data-driven brainrot ROSTER + economy curve (+ premium flag)
    StealConfig.lua          ALL steal/carry/defense tunables (one retune surface)
    Monetization.lua         ALL gamepass/product IDs + benefits + leaderboard tuning (one file)
    Audio.lua                swappable music/SFX asset IDs (0 = silent; IP-safe, all in config)
    Janitor.lua              minimal connection/instance cleanup helper (no framework)
    Format.lua               compact number formatter (1.2K / 3.4M / 1B)
  StarterGui/                → StarterGui
  ServerStorage/             → ServerStorage > Assets  (plot/brainrot model templates later)

Packages/                    → ReplicatedStorage > Packages  (Wally, git-ignored)
```

### UI (all generated in code)

Every GUI instance is built programmatically from the client `UI/` modules — there are no
Studio-authored GUIs. The layout is mobile-first (UDim2 Scale, large tap targets,
`ScreenInsets = CoreUISafeInsets`). The HUD reads the server-set `Cash` / `IncomePerSec`
player Attributes and listens via `GetAttributeChangedSignal`; the M1 leaderstats IntValue is
kept for the player list.

### Secure purchase flow

The client Buy button sends only an item **id**. `PurchaseService` looks up the real
price/income from the server-side `Catalog`, checks affordability and a free pad, then (with no
yields between check and deduct, plus a per-player debounce) deducts cash, appends the brainrot,
reuses `BrainrotService.SpawnBrainrot`, refreshes attributes/leaderstats, and lets ProfileStore
save. Failures mutate nothing and send a toast back via the `Notify` remote.

### Rarity, roster & economy (M3)

Everything you'd retune lives in **two Shared data files** — no service or UI logic changes:

- **`src/Shared/Rarity.lua`** — the rarity ladder. Edit `Rarity.Tiers` to rename tiers, recolor
  them, change their order, or add a tier. The shop, the inventory, and the in-world unit
  tints all read their colors from here.
- **`src/Shared/Catalog.lua`** — the full brainrot roster. Edit `Catalog.Items` to add/remove
  brainrots or retune any `Price` / `IncomePerSec`. Each entry keys an `Id` (stable — saved in
  `OwnedBrainrots.Type`, never rename), `DisplayName`, `Rarity`, plus reserved `ModelName` /
  `IconId` / `SoundId` for later art. The **economy curve** (≈5× price per tier, income rising
  a touch faster so the income/price ratio improves with rarity) is documented at the top of the
  file. The free starter is *derived* (`Catalog.StarterId` = cheapest entry of the lowest tier),
  so retuning can't desync it.

Rarity-tinted placeholder units automatically swap to real art the moment a `Model` named after
an entry's `ModelName` is dropped into `ServerStorage/Assets` (same forward-compat pattern as
plots). Per-player **unlocked-pad count** is saved (`ProfileManager.SetUnlockedPads` is the hook
M5's pad gamepass will call) and a **Discovered** set records every roster Id ever owned — both
reconcile onto existing M1/M2 saves with no migration.

### Steal mechanic & defense (M4)

The core hook. A brainrot is always in one of two states, and **ownership only ever changes
in one guarded, atomic function** so it can never be duplicated or lost:

- **ON_PAD** → **IN_TRANSIT** (INITIATE): a server-side `ProximityPrompt` completion lifts the
  unit off the victim's pad and welds a carried model to the thief. The unit *stays in the
  victim's data* (flagged in-transit only via `TransitRegistry`, never saved) and earns for no
  one. All preconditions are re-checked on the server.
- **IN_TRANSIT** → **ON_PAD** (DEPOSIT): when a server-side distance check finds the thief near
  their own **reserved** pad, `transferOwnership` does `table.remove(victim)` +
  `table.insert(thief)` with no yields between — the only ownership change in the system.
- **IN_TRANSIT** → **ON_PAD** (REVERT): on thief death/disconnect/timeout or victim leave, the
  carry is torn down and the unit returns to the victim (a no-op on ownership).

Leaving players are fully resolved (`StealService.ResolvePlayer`) **before** their profile is
released/saved, so a save can never capture duped or half-moved state. The double-steal race is
closed by an `ActiveSteals[id]` guard set before any yield. The invariant audit lives at the top
of `StealService.lua`.

**Defense** is simple and timer-based (`ProtectionService`): a new-player grace window and a
post-robbery shield, shown as a translucent dome + countdown. While protected, steal prompts are
disabled and the server rejects steals. `ProtectionService.ExtendProtection(player, seconds)` is
the public hook M5's gamepass will call — no monetization is built this milestone.

**Retune everything in one file — `src/Shared/StealConfig.lua`:** `HoldDuration`,
`PromptMaxDistance`, `DepositRange`, `CarryTimeout`, `CarryWalkSpeedMult`, `CarryBob`,
`StealCooldown`, `PostStealImmunity`, `NewPlayerGrace`, `PostRobberyProtection`.

### Monetization & leaderboards (M5)

All Robux items are **ID-driven from one file — `src/Shared/Monetization.lua`** — so the code
works the moment you paste the numeric Ids you create on the Creator Dashboard, and skips any
row whose Id is still `0`.

- **Gamepasses** (permanent) use a **benefit-registry** pattern: each config row maps a gamepass
  to a `Benefit { Type, ... }`, and each `Type` has one server-side handler that hooks an existing
  system — `IncomeMultiplier` (consumed by `IncomeService`), `ExtraPads` (the M3 pad setter),
  `ReinforcedLock` (the M4 `ProtectionService` hook, auto-renewing), `VIP` (a nametag + reduced
  steal cooldown). Ownership is checked once per session (`UserOwnsGamePassAsync`, pcall + backoff,
  cached) and applied **idempotently** on join, on live purchase (`PromptGamePassPurchaseFinished`),
  and on rejoin — never double-stacked (income multipliers are keyed per source, pads are recomputed
  from sources). Adding a pass = a config row + (only if it's a new `Type`) one handler function.
- **Developer products** (consumable) flow through **exactly one** `MarketplaceService.ProcessReceipt`.
  It is **perfectly idempotent and crash-safe**: the grant and the `PurchaseId` record are written
  to the profile in the *same* mutation with no yields between, so a purchase grants **exactly once**
  even across retries and server restarts (dedupe persists in `PurchaseHistory`). An unloaded
  profile / unknown product / no-free-pad returns `NotProcessedYet` (safe retry); an already-seen
  `PurchaseId` returns `PurchaseGranted` without re-granting.
- **Premium/limited brainrots** are roster entries flagged `Premium = true` (`Buyable = false`):
  purchase-gated only, never cash, never random. They place, earn, are stealable, and count toward
  Discovered like any unit.
- **Leaderboards** (`LeaderboardService`): three global `OrderedDataStore` boards (Top Cash, Top
  Income/sec, Rarest Collection — a rarity-weighted integer over your Discovered set). Every value
  is floored + clamped to `[0, MaxValue]` (just under 2^53) before writing; every call is pcall'd
  with backoff; writes are throttled (~60s + on leave). In unpublished Studio it falls back to an
  in-memory board of the current players so the **in-world billboards** (procedural, in a central
  hub) still populate.

**DEV/TEST SIM mode** (`src/Server/DevConfig.lua`) mirrors the ProfileStore mock pattern: flip the
single `SIM_REQUESTED` line to `true` to simulate gamepass ownership + fire product grants through
the **real** receipt codepath in Studio, no Robux or publishing needed. It is **forced OFF on any
live server** (ANDed with `RunService:IsStudio()`), so it can never ship enabled. Each system prints
which mode it's in on startup.

**Retune in `src/Shared/Monetization.lua`:** the gamepass/product set + their Ids, income-multiplier
stacking cap (`Income.MaxMultiplier`), cash-pack amounts, pad amounts, leaderboard `RarityWeights`,
`RefreshInterval`, `TopN`, and the value clamp (`MaxValue`). New-player starting pads live in
`Config.Plots.DefaultUnlockedPads` (kept below `PadsPerPlot` so Extra Pads has headroom).

### Hardening, onboarding, juice & performance (M6)

**Security audit — every client-callable remote, its trust boundary, and the protections.** The
client may send **intent only**; the server reads values from its own roster/config and verifies
legality. Each handler carries this as a comment.

| Remote (type) | Client may send | Server verifies / does | Protections |
|---|---|---|---|
| `PurchaseRequest` (Event) | an item **id** (string) | resolves price/income from `Catalog`; loaded profile; free pad; affordability; spends + grants atomically | type check · 0.5s debounce · `TrySpend` (atomic, no-negative) |
| `GetInventory` (Function) | nothing | returns a fresh list from server profile + roster (display fields) | read-only · 0.25s rate limit |
| `PromptGamepass` / `PromptProduct` (Event) | a config **key** (string) | only opens a Marketplace prompt; never grants here | type check · 1s rate limit · unknown key dropped |
| `GetMonetization` (Function) | nothing | returns owned-map (from MarketplaceService/SIM) + SIM flag | read-only |
| `SaveSettings` (Event) | `{Music,SFX,Shake}` | stores **only** those three booleans (shape-sanitized) | type check · 0.3s rate limit · presentational only |
| `GetSettings` (Function) | nothing | returns the saved prefs | read-only |
| `Tutorial` (Event) | `"ready"`/`"done"`/`"skip"` | owns the `TutorialDone` flag; only ever sets it true | string check · 0.5s rate limit · idempotent |
| `Notify` / `KillFeed` / `MonetizationUpdate` (Event) | — | **server → client only** (outbound; clients can't meaningfully fire them) | n/a |

Developer-product receipts arrive via Roblox's `ProcessReceipt` (not a client remote) — still
exactly one handler, idempotent, atomic grant+record (see M5).

**Written self-audit:**
- **Cash integrity** — Cash is written in exactly TWO places, both in `ProfileManager`:
  `AddCash` (clamps to `[0, MAX_CASH]`, rejects NaN/inf) and `TrySpend` (atomic, never negative).
  Income, purchases, and product grants all route through them; **no scattered direct writes and
  no client path can set/add cash**. (`grep "Data.Cash"` → only these accessors + read-only
  display/board reads.)
- **Steal can't dupe/lose** — ownership still changes only in `transferOwnership`
  (`table.remove`+`table.insert`, no yields); deposit is a **server** distance check on the real
  character; the double-trigger race is closed by the `ActiveSteals` guard; death / disconnect /
  timeout / victim-leave all resolve **before** profile release (and on `BindToClose`); reserved
  pads are released on every failure path.
- **Money can't double-grant** — one `ProcessReceipt`; persisted `PurchaseHistory` dedupe; grant
  and record commit together; `NotProcessedYet` on unloaded profile. Gamepass benefits + the income
  multiplier are keyed/idempotent, so rejoin + live purchase can't double-stack.
- **No leaks** — per-player state (`rateCache`, rate-limit stamps, monetization session tables,
  benefit state) is cleared on leave; per-steal instances/welds are destroyed in `clearSteal`;
  the tutorial + effects track their connections/instances in a `Janitor` and release them on
  finish. Verified across repeated join/leave/steal/death cycles.
- **Debug locked** — the only debug affordances (`DevConfig.SimMode`, `TutorialService.ResetForTesting`)
  are server-only and gated to Studio SIM; there are no admin/test remotes exposed to clients.

**Onboarding** — brand-new players get a one-time, near-wordless flow (an arrow + coachmark toward
the Shop, then a celebration on the first buy), driven by a client→server **"ready" handshake** so
the start signal can't be missed. It's **skippable** and the saved `TutorialDone` flag means
returning players never see it. Re-test it in SIM via
`require(game.ServerScriptService.Server.TutorialService).ResetForTesting(game.Players.YOURNAME)`.

**Juice & settings** — `UI/Effects` adds pooled particle bursts, a cash-pill / rate-label pop, a
screen flash, and a subtle camera shake on buy / deposit / robbed / milestone, plus sound hooks.
Everything is **pooled + capped** (fixed 24-particle pool, one idle-safe render-step shake,
short-lived sounds) so it never blows up frame time at a full server. The **Settings** panel
(HUD ⚙) toggles Music / SFX / Screen Shake, persisted server-side. All audio IDs live in
`Shared/Audio` (0 = silent) — swap in your own/licensed assets; nothing copyrighted is hardcoded.

**Performance** — the income loop now reads a **cached per-player base rate** (recomputed only on
roster/multiplier change), so accrual is O(players)/frame, not O(brainrots); floating "+$/s"
labels use `MaxDistance` so far units stop drawing; replication stays on throttled attributes;
`BindToClose` flushes leaderboard writes + releases profiles on shutdown.

**Balance (retune in config):** early economy in `Shared/Catalog` (Commons tuned so the first ~3
buys land every ~20–25s — the loop hooks in the first minute; pacing documented at the top of the
file); starting pads in `Shared/Config` (`DefaultUnlockedPads`); steal feel in `Shared/StealConfig`
(hold, grace/post-robbery windows, cooldown, immunity, carry timeout/range/penalty — intent
documented inline). No balance number is hardcoded in logic.

### Data saving (ProfileStore)

`ProfileStore` is **vendored** as a single ModuleScript at `src/Server/Lib/ProfileStore.luau`
(downloaded from `MadStudioRoblox/ProfileStore`) rather than pulled via Wally — it lives under
ServerScriptService so it is server-only, tracked in git, and needs no install step after cloning.
`ProfileManager` auto-detects whether real DataStores are available and otherwise uses ProfileStore's
in-memory **mock** store, so the loop is testable in Studio immediately. The console prints which store
is active on startup.

## Setup (one-time after cloning)

```powershell
rokit install    # installs rojo, wally, stylua, selene
wally install    # creates Packages/ and installs any Wally packages
```

> Note: `wally install` must be run to create the `Packages/` directory locally.
> It is git-ignored but required for `rojo build` and `rojo serve` to work.

## Development

```powershell
rojo serve                 # start sync server (default port 34872)
rojo serve --port 5000     # use if default port is blocked
```

Then in Roblox Studio: open the Rojo plugin panel → Connect.

## Build (headless, no Studio)

```powershell
rojo build default.project.json --output game.rbxlx
```

## Format + Lint

```powershell
stylua src/          # format all Luau files in-place
stylua --check src/  # check only, no writes
selene src/          # lint all Luau files
```
