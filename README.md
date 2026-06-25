# brainrot-game

Multiplayer Roblox idle/theft game. Players collect meme creatures ("brainrot") that generate passive cash, unlock rarer ones, and steal each other's units.

Built in milestones. Current: **M4 — steal mechanic + timer-based defense**. Players hold a "Hold to steal" prompt on another base's brainrot, carry it home, and deposit it on a free pad to take ownership — all server-authoritative, dupe-proof, and loss-proof (one guarded atomic transfer; every brainrot is owned by exactly one player at all times). A simple timer-based defense layer (new-player grace + post-robbery shield, with an M5-ready `ExtendProtection` hook) protects bases, plus cooldowns, per-unit immunity, a carry timeout, a kill-feed banner, and victim toasts. (M3: rarity roster + scaling economy. M2: mobile HUD + secure purchase. M1: income loop + ProfileStore. M0: toolchain.) Everything economic and every ownership change is server-authoritative — the client only requests; the server validates and mutates.

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
    ProtectionService.lua    timer-based plot protection (grace/post-robbery) + dome + M5 hook
    TransitRegistry.lua      runtime set of in-transit (carried) brainrot Ids (income skips them)
    Lib/ProfileStore.luau    vendored third-party data lib (loleris)
  Client/                    → StarterPlayer > StarterPlayerScripts > Client
    Client.client.lua        builds UI on spawn, wires remotes, hides own steal prompts
    UI/Theme.lua             colors + fonts (single styling source)
    UI/Builder.lua           declarative instance/panel helpers
    UI/HUD.lua               top cash pill (count-up) + Shop/Inventory buttons
    UI/Shop.lua              data-driven catalog rows + reactive Buy buttons
    UI/Inventory.lua         owned list, fetched via RemoteFunction
    UI/Notifications.lua     transient toast stack (victim "stole your X!" alerts)
    UI/KillFeed.lua          everyone-sees steal banner (server broadcast)
  Shared/                    → ReplicatedStorage > Shared
    Config.lua               plot/world tuning (brainrot stats now live in Catalog)
    Rarity.lua               rarity ladder: tier names, colors, order (single source)
    Catalog.lua              full data-driven brainrot ROSTER + economy curve
    StealConfig.lua          ALL steal/carry/defense tunables (one retune surface)
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
