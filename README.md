# brainrot-game

Multiplayer Roblox idle/theft game. Players collect meme creatures ("brainrot") that generate passive cash, unlock rarer ones, and steal each other's units.

Built in milestones. Current: **M2 — HUD + secure purchase plumbing**. A code-generated, mobile-first HUD shows live Cash + Cash/sec; a data-driven Shop sells placeholder brainrots; buying fires a client→server request that the server validates (price, affordability, free pad) before deducting cash, spawning the unit, and saving. Everything economic is server-authoritative — the client only requests. (M1: passive income loop + ProfileStore saving. M0: toolchain.)

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
    Lib/ProfileStore.luau    vendored third-party data lib (loleris)
  Client/                    → StarterPlayer > StarterPlayerScripts > Client
    Client.client.lua        builds UI on spawn, wires remotes
    UI/Theme.lua             colors + fonts (single styling source)
    UI/Builder.lua           declarative instance/panel helpers
    UI/HUD.lua               top cash pill (count-up) + Shop/Inventory buttons
    UI/Shop.lua              data-driven catalog rows + reactive Buy buttons
    UI/Inventory.lua         owned list, fetched via RemoteFunction
    UI/Notifications.lua     transient toast stack
  Shared/                    → ReplicatedStorage > Shared
    Config.lua               starter brainrot stats + plot tuning
    Catalog.lua              data-driven shop catalog (M3 expands this only)
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
