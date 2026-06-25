# brainrot-game

Multiplayer Roblox idle/theft game. Players collect meme creatures ("brainrot") that generate passive cash, unlock rarer ones, and steal each other's units.

Built in milestones. This is M0 — toolchain skeleton only.

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
  Server/        → ServerScriptService > Server
  Client/        → StarterPlayer > StarterPlayerScripts > Client
  Shared/        → ReplicatedStorage > Shared
  StarterGui/    → StarterGui
  ServerStorage/ → ServerStorage > Assets

Packages/        → ReplicatedStorage > Packages  (Wally, git-ignored)
```

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
