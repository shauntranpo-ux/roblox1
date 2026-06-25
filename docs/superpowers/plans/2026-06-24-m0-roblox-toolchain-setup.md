# M0 Roblox Toolchain Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the M0 toolchain skeleton — add StyLua/Selene to Rokit, finalize all Rojo service mappings, scaffold missing src/ folders, create wally.toml, write Bootstrap.server.lua, verify everything builds clean, and commit.

**Architecture:** Server-authoritative Luau game synced via Rojo (local filesystem → Roblox Studio DataModel). Rokit pins all tool versions. Wally manages packages (none yet). StyLua + Selene enforce code style and correctness from day one. No gameplay code this milestone.

**Tech Stack:** Luau, Rojo 7.4.4, Wally 0.3.2, Rokit, StyLua, Selene, git/GitHub

---

## Current State (as of plan creation)

Already done:
- `rokit.toml` — rojo 7.4.4 + wally 0.3.2 pinned
- `default.project.json` — Server, Shared, Client mapped; StarterGui/ServerStorage are bare (no path)
- `.gitignore` — partial; missing DevPackages/, ServerPackages/, *.rbxm, *.rbxmx, sourcemap.json
- `src/Server/init.server.lua` — placeholder hello-print; will be replaced
- `src/Shared/.gitkeep`, `src/Client/.gitkeep` — exist

Still needed:
- stylua, selene added to `rokit.toml`
- `.gitignore` gaps filled
- `default.project.json` — StarterGui/$path, ServerStorage/Assets, ReplicatedStorage/Packages
- `wally.toml` — project metadata, no deps
- `stylua.toml`, `selene.toml` — linter/formatter configs
- `src/StarterGui/.gitkeep`, `src/ServerStorage/.gitkeep` — missing folders
- `src/Server/Bootstrap.server.lua` — the real M0 sync-test script
- `README.md`

---

## File Map

| Action  | Path                                   | Purpose                                        |
|---------|----------------------------------------|------------------------------------------------|
| Modify  | `rokit.toml`                           | Add stylua + selene pins                       |
| Modify  | `.gitignore`                           | Add DevPackages/, ServerPackages/, *.rbxm, *.rbxmx, sourcemap.json |
| Modify  | `default.project.json`                 | Add StarterGui/$path, ServerStorage/Assets, ReplicatedStorage/Packages |
| Create  | `wally.toml`                           | Wally project metadata, no deps yet            |
| Create  | `stylua.toml`                          | StyLua formatter config                        |
| Create  | `selene.toml`                          | Selene linter config for Roblox std            |
| Create  | `src/StarterGui/.gitkeep`              | Git-track the StarterGui src folder            |
| Create  | `src/ServerStorage/.gitkeep`           | Git-track the ServerStorage src folder         |
| Delete  | `src/Server/init.server.lua`           | Replaced by Bootstrap.server.lua               |
| Create  | `src/Server/Bootstrap.server.lua`      | M0 sync-test — only script this milestone      |
| Create  | `README.md`                            | Stack, folder map, exact commands              |

---

## Tasks

---

### Task 1: Add StyLua and Selene to Rokit

**Files:**
- Modify: `rokit.toml`

- [ ] **Step 1: Add tools via rokit add**

```powershell
rokit add JohnnyMorganz/StyLua
rokit add Kampfkarren/selene
```

Each command appends the latest stable version to `rokit.toml`. If either fails, check the exact repo slug at `aftman.rs` or the Rokit registry — casing matters.

- [ ] **Step 2: Verify rokit.toml has all four tools**

Open `rokit.toml` and confirm it has entries for rojo, wally, stylua, selene — all with pinned versions (format: `tool = "Author/Repo@X.Y.Z"`).

- [ ] **Step 3: Install all tools**

```powershell
rokit install
```

Expected: exits cleanly. If you see "tool not marked as trusted", run `rokit trust <Author/Repo>` for the new tools, then re-run `rokit install`.

- [ ] **Step 4: Smoke-test the new binaries**

```powershell
stylua --version
selene --version
```

Expected: version strings printed for both. Example: `stylua 0.20.0`, `selene 0.27.1`.

- [ ] **Step 5: Commit**

```powershell
git add rokit.toml
git commit -m "chore: pin stylua and selene in rokit.toml"
```

---

### Task 2: Update .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Replace .gitignore with complete content**

Overwrite the entire file with:

```gitignore
# Rojo build outputs
*.rbxl
*.rbxlx
*.rbxm
*.rbxmx
sourcemap.json

# Wally packages — all three realms
Packages/
DevPackages/
ServerPackages/

# Rokit toolchain binaries
.rokit/

# OS / editor junk
.DS_Store
Thumbs.db
.vscode/settings.json
```

`wally.toml` and `wally.lock` are intentionally NOT listed here — they must be tracked in git.

- [ ] **Step 2: Verify the right files are ignored**

```powershell
git status
```

Expected: only `.gitignore` shows as modified. `wally.toml` (once created in Task 5) should NOT appear as ignored.

- [ ] **Step 3: Commit**

```powershell
git add .gitignore
git commit -m "chore: expand .gitignore for full Roblox/Wally project"
```

---

### Task 3: Update default.project.json

**Files:**
- Modify: `default.project.json`

- [ ] **Step 1: Rewrite with full service mapping**

Replace the entire file with:

```json
{
  "name": "brainrot-game",
  "tree": {
    "$className": "DataModel",
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "Server": { "$path": "src/Server" }
    },
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "Shared": { "$path": "src/Shared" },
      "Packages": { "$path": "Packages" }
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "StarterPlayerScripts": {
        "$className": "StarterPlayerScripts",
        "Client": { "$path": "src/Client" }
      }
    },
    "StarterGui": {
      "$path": "src/StarterGui"
    },
    "ServerStorage": {
      "$className": "ServerStorage",
      "Assets": { "$path": "src/ServerStorage" }
    }
  }
}
```

Notes:
- `StarterGui` uses `$path` only — Rojo knows it's a StarterGui service from the DataModel context; `$className` is redundant here.
- `ServerStorage/Assets` will be a Folder named "Assets" inside ServerStorage — this is where brainrot model templates go in later milestones.
- `ReplicatedStorage/Packages` maps the Wally `Packages/` directory so client scripts can require packages.

- [ ] **Step 2: Quick sanity check — rojo source-list**

```powershell
rojo sourcemap default.project.json
```

Expected: prints a JSON sourcemap with no errors. If `rojo sourcemap` is not available in your version, skip to Task 9 where we do a full build.

- [ ] **Step 3: Commit**

```powershell
git add default.project.json
git commit -m "feat: expand Rojo mappings — StarterGui, ServerStorage/Assets, ReplicatedStorage/Packages"
```

---

### Task 4: Scaffold missing src/ folders

**Files:**
- Create: `src/StarterGui/.gitkeep`
- Create: `src/ServerStorage/.gitkeep`

- [ ] **Step 1: Create both folders with .gitkeep**

```powershell
New-Item -ItemType File -Force "src\StarterGui\.gitkeep"
New-Item -ItemType File -Force "src\ServerStorage\.gitkeep"
```

- [ ] **Step 2: Verify full src/ tree**

```powershell
Get-ChildItem -Recurse src
```

Expected:
```
src/
  Client/.gitkeep
  Server/init.server.lua      ← will be replaced in Task 7
  Shared/.gitkeep
  StarterGui/.gitkeep
  ServerStorage/.gitkeep
```

- [ ] **Step 3: Commit**

```powershell
git add "src\StarterGui\.gitkeep" "src\ServerStorage\.gitkeep"
git commit -m "feat: add StarterGui and ServerStorage src folders"
```

---

### Task 5: Create wally.toml

**Files:**
- Create: `wally.toml`

- [ ] **Step 1: Write wally.toml**

Create the file with exactly this content:

```toml
[package]
name = "shaun/brainrot-game"
version = "0.1.0"
registry = "https://github.com/UpliftGames/wally-index"
realm = "shared"

[dependencies]
# No dependencies yet — ProfileStore and others added in later milestones
```

- [ ] **Step 2: Run wally install to confirm zero-dep install works**

```powershell
wally install
```

Expected: exits cleanly with "No packages to install" or similar. No errors. A `Packages/` folder may or may not be created (either is fine — it's git-ignored).

- [ ] **Step 3: Commit**

```powershell
git add wally.toml
git commit -m "chore: add empty wally.toml (no deps yet)"
```

---

### Task 6: Create StyLua config

**Files:**
- Create: `stylua.toml`

- [ ] **Step 1: Write stylua.toml**

```toml
# Line length before StyLua tries to break expressions onto multiple lines
column_width = 100

# Unix line endings — consistent across Windows/Mac/Linux
line_endings = "Unix"

# 4-space indentation (Roblox community standard)
indent_type = "Spaces"
indent_width = 4

# Use double quotes; fall back to single if string contains a double-quote
quote_style = "AutoPreferDouble"

# Always write call parentheses: foo() not foo
call_parentheses = "Always"
```

- [ ] **Step 2: Verify StyLua accepts the config**

```powershell
stylua --check src/
```

Expected: either "1 file would be reformatted" or clean exit. The key signal is **no config-parse errors**. If you see `Error reading config file`, something is wrong with the toml syntax.

- [ ] **Step 3: Commit**

```powershell
git add stylua.toml
git commit -m "chore: add stylua.toml formatter config"
```

---

### Task 7: Create Selene config

**Files:**
- Create: `selene.toml`

- [ ] **Step 1: Write selene.toml**

```toml
# Use Roblox standard library definitions so Selene knows about
# game, workspace, Instance, print, task, etc. without false-positive warnings.
std = "roblox"
```

- [ ] **Step 2: Lint src/ to verify config is accepted**

```powershell
selene src/
```

Expected: zero errors (the only .lua file is a simple print, which is valid). If Selene says it can't find the "roblox" std, you may need to run `selene generate-roblox-std` first — but typically the roblox std is bundled with the Selene binary.

- [ ] **Step 3: Commit**

```powershell
git add selene.toml
git commit -m "chore: add selene.toml linter config (roblox std)"
```

---

### Task 8: Create Bootstrap.server.lua (replace init.server.lua)

**Files:**
- Delete: `src/Server/init.server.lua`
- Create: `src/Server/Bootstrap.server.lua`

- [ ] **Step 1: Remove the old placeholder**

```powershell
Remove-Item "src\Server\init.server.lua"
```

- [ ] **Step 2: Write Bootstrap.server.lua**

Create `src/Server/Bootstrap.server.lua` with exactly this content:

```lua
print("[BRAINROT] M0 sync OK -- server is running")
```

That is the entire file. Nothing else.

- [ ] **Step 3: Format with StyLua**

```powershell
stylua src/Server/Bootstrap.server.lua
```

Expected: file unchanged (single-line print needs no reformatting). No errors.

- [ ] **Step 4: Lint with Selene**

```powershell
selene src/Server/Bootstrap.server.lua
```

Expected: no warnings or errors.

- [ ] **Step 5: Commit**

```powershell
git rm "src\Server\init.server.lua"
git add "src\Server\Bootstrap.server.lua"
git commit -m "feat: add Bootstrap.server.lua M0 sync-test script"
```

---

### Task 9: Rojo build verification

Verifies `default.project.json` is valid without opening Studio.

- [ ] **Step 1: Build to a temp file**

```powershell
rojo build default.project.json --output _verify.rbxlx
```

Expected: exits with no errors. `_verify.rbxlx` appears in the project root.

- [ ] **Step 2: Remove the temp file**

```powershell
Remove-Item _verify.rbxlx
```

- [ ] **Step 3: Attempt rojo plugin install**

```powershell
rojo plugin install
```

If this succeeds: the Studio plugin is installed automatically — skip the manual Creator Store step in the GUI checklist below.

If this outputs an error like "plugin install not supported" or similar: **that is fine** — just note it and install the plugin manually from Studio's Creator Store (search "Rojo" by rojo-rbx). This is expected in headless environments.

---

### Task 10: Write README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md**

```markdown
# brainrot-game

Multiplayer Roblox idle/theft game. Players collect meme creatures ("brainrot") that generate passive cash, unlock rarer ones, and steal each other's units.

Built in milestones. This is M0 — toolchain skeleton only.

## Stack

| Tool     | Purpose                              |
|----------|--------------------------------------|
| Luau     | Scripting language                   |
| Rojo     | Filesystem → Studio sync             |
| Wally    | Package manager                      |
| Rokit    | Toolchain version manager            |
| StyLua   | Formatter                            |
| Selene   | Linter                               |

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

## Setup (one-time)

```powershell
rokit install    # installs rojo, wally, stylua, selene
wally install    # installs Wally packages (none in M0)
```

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
```

- [ ] **Step 2: Commit**

```powershell
git add README.md
git commit -m "docs: add README with stack, folder structure, and commands"
```

---

### Task 11: Full verification pass

- [ ] **Step 1: Format check**

```powershell
stylua --check src/
```

Expected: clean exit (no files need reformatting).

- [ ] **Step 2: Lint check**

```powershell
selene src/
```

Expected: zero errors or warnings.

- [ ] **Step 3: Final Rojo build**

```powershell
rojo build default.project.json --output _final.rbxlx
Remove-Item _final.rbxlx
```

Expected: no errors.

- [ ] **Step 4: Confirm clean git state**

```powershell
git status
git log --oneline
```

Expected: `nothing to commit, working tree clean`. Log shows one commit per task above.

---

## GUI Steps (cannot be done via terminal)

After all tasks above are complete, these steps require Roblox Studio:

1. **Install Roblox Studio** if not already — download from roblox.com
2. **Install the Rojo plugin in Studio:**
   - Studio → Plugins tab → Creator Store → search **Rojo** by **rojo-rbx** → Install
   - (Skip if `rojo plugin install` succeeded in Task 9)
3. **Start Rojo serve** in a terminal:
   ```powershell
   rojo serve
   # or if the default port is blocked:
   rojo serve --port 5000
   ```
4. **Connect in Studio:** open Rojo plugin panel → set port to 5000 if you used `--port 5000` → click **Connect**
5. **Press Play (F5)** → check the **Output** panel at the bottom for:
   ```
   [BRAINROT] M0 sync OK -- server is running
   ```

---

## GitHub Push Commands

```powershell
git remote -v   # check if origin is already set
```

If no remote set:
```powershell
git remote add origin https://github.com/shauntranpo-ux/roblox1.git
git branch -M main
git push -u origin main
```

If origin already points to the right repo, just:
```powershell
git push
```

---

## M0 Done When

- [ ] `rokit.toml` has rojo, wally, stylua, selene — all pinned
- [ ] `rojo build` exits clean
- [ ] `stylua --check src/` exits clean
- [ ] `selene src/` exits clean
- [ ] `git log` shows clean commit history with no untracked files
- [ ] Studio Play shows `[BRAINROT] M0 sync OK -- server is running` in Output
