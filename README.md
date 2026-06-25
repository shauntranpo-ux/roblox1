# brainrot-game

Multiplayer Roblox idle/theft game. Players collect meme creatures ("brainrot") that generate passive cash, unlock rarer ones, and steal each other's units.

Built in milestones. Current: **M1 — bare playable economy loop** (server-authoritative). A player spawns at a base, owns one placeholder brainrot that earns cash every second, sees their cash in the player list, and the data saves via ProfileStore.

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
    PlotService.lua          builds bases + per-session plot assignment
    BrainrotService.lua      grants/restores/spawns brainrots on pads
    IncomeService.lua        Heartbeat server-authoritative income loop
    Leaderstats.lua          leaderstats.Cash readout in the player list
    Lib/ProfileStore.luau    vendored third-party data lib (loleris)
  Client/                    → StarterPlayer > StarterPlayerScripts > Client
  Shared/                    → ReplicatedStorage > Shared
    Config.lua               data-driven brainrot roster + plot tuning
  StarterGui/                → StarterGui
  ServerStorage/             → ServerStorage > Assets  (plot/brainrot model templates later)

Packages/                    → ReplicatedStorage > Packages  (Wally, git-ignored)
```

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
