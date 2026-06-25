# VM0 — STABILIZE: Triage Report

**Pass type:** debugging / hardening only (no features, no redesign, no UI styling).
**Verification:** `rojo build` ✅ · StyLua ✅ · Selene `0 errors / 0 warnings / 0 parse errors` ✅ · `wally install` ✅
**Scope of changes:** 7 files touched (5 surgical, 2 new), all additive/defensive. No gameplay, economy, schema-shape, or UI-design changes.

---

## TL;DR

I read the **entire** codebase (every server service, every config, every client UI module, the
remotes surface, the data template, the bootstrap, and the vendored ProfileStore boundary) and ran
the static toolchain. **The code is in unusually good shape:** I found **no duplication bug, no
cash bug, no idempotency gap, no require cycle, and no lint/build error.** All ten sacred invariants
hold in code.

Because the genuine risk that remains is **runtime** behavior I cannot observe without Studio, the
core of this pass is (a) one real robustness fix — **the boot can no longer be silently halted by a
single failing service** — and (b) a **diagnostic + invariant-validator harness** so that the
instant you press Play, the Output tells you exactly what is healthy and screams the moment any
sacred invariant breaks.

I deliberately did **not** invent bugs to "fix." Surgical only.

---

## Changes made (every one, with why)

| # | File | Change | Why |
|---|------|--------|-----|
| 1 | `src/Server/Bootstrap.server.lua` | Each service now starts through a `start(name, fn)` wrapper that `pcall`s it, records the result, and logs failures; then calls `Diagnostics.bootReport` + `InvariantValidator.Init`. | **Real robustness gap:** previously, if any one service's `Init`/`Start` threw, the script errored and **every later service never started** — remotes left unbound, and the `PlayerAdded` connection at the very bottom never connected, so **no player could ever load**. Now one bad service is isolated and named loudly; the rest of the boot proceeds. Happy-path behavior is byte-for-byte identical. |
| 2 | `src/Server/Bootstrap.server.lua` | `Diagnostics.playerReport(player, profile)` called right after the profile loads on join. | Surfaces profile-load + template-reconciliation health per join. |
| 3 | `src/Server/Diagnostics.lua` **(new)** | Boot health report + per-join health line. | Section 3 of the brief: make runtime health visible the instant you Play. |
| 4 | `src/Server/InvariantValidator.lua` **(new)** | Dev-only, read-only scanner of the sacred invariants; on-demand `Run()` + a SIM-gated 30s cadence. | Section 4 of the brief: make dupes / negative cash / cap breaks / dangling locks scream at runtime. |
| 5 | `src/Server/ProfileManager.lua` | Added `GetAllProfiles()` (read-only shallow copy) + `GetTemplateFieldNames()`. | Minimal read-only accessors the validator + diagnostic need. No change to existing behavior. |
| 6 | `src/Server/Remotes.lua` | Added static `Remotes.ExpectedNames` (the 24 remote names). | Single source the boot diagnostic verifies the network surface against; catches any future server↔client remote-name drift. |
| 7 | `src/Server/TransitRegistry.lua`, `src/Server/TradeLockRegistry.lua` | Added `All()` (read-only shallow copy). | So the validator can cross-check in-transit / trade-locked ids against live ownership without reaching into service internals. |

**Schema changes:** none. No field added/removed/renamed in `PROFILE_TEMPLATE`. Reconciliation is
untouched (and is now *verified at runtime* by the join diagnostic).

---

## High-risk classes — findings (audited the whole codebase for each)

- **Service start order / bootstrap** — All 20 services are actually started, in dependency-safe
  order; no milestone service was left unstarted. **Fixed** the silent-halt risk (change #1). The
  boot report now prints `Services: N/N started` and names any failure.
- **Remote wiring** — All 24 remotes are created exactly once in `Remotes.Init`; the client waits
  for exactly those 24; names match on both sides. No double-creation. Added `ExpectedNames` + boot
  verification so a drift is caught immediately.
- **Nil indexing / lifecycle** — Existing-player backfill is present everywhere it matters
  (`Bootstrap` loops `Players:GetPlayers()`; `StealService`, `MonetizationService` re-hook on init).
  Legacy units with `Mutation = nil` are handled everywhere (`MutationConfig.MultiplierFor(nil) = 1`,
  `unit.Mutation ~= nil and …`). No nil-index path found.
- **Template reconciliation gaps** — Every field read in code exists in `PROFILE_TEMPLATE`. The join
  diagnostic now confirms each loaded profile has all template fields (flags any gap by name).
- **Cross-system integration drift** — The canonical `UnitIncome.effective()` is used in **every**
  income read: the income loop (`PlayerStats.computeBaseRate`), the world billboards
  (`BrainrotService`), inventory, trade snapshot (`TradeService.itemize`), and the income
  leaderboard. Mutation is applied **exactly once**; the global multiplier is capped consistently in
  `Benefits.recomputeIncome`; prestige is the separate multiplicative axis in the income loop,
  display refresh, and leaderboard alike. Steal + trade move the **whole** unit record including
  `Mutation`. The income loop excludes in-transit units. No drift.
- **Duplicate ProcessReceipt** — Exactly **one** `MarketplaceService.ProcessReceipt` in the whole
  codebase (`MonetizationService`), idempotent, atomic grant+record, `NotProcessedYet` on unloaded
  profile.
- **Player-removing ordering** — Steal resolution → trade resolution → leaderboard write → season
  write → analytics flush → state clears → `ProfileManager.ReleaseProfile` **last**. All resolution
  happens before release/save. One coordinating handler in `Bootstrap`; the only other
  `PlayerRemoving` (PurchaseService) just nils a local timestamp — no ordering risk.
- **Janitor / leak audit** — On-pad models, carried steal model, protection dome, VIP tag, tutorial
  connections (Janitor), benefit state, rate-limit stamps, cached rates — all torn down on the leave
  path. No orphan found.
- **DataStore / OrderedDataStore** — All calls `pcall`+backoff; values floored + clamped
  non-negative; MOCK auto-detected via a probe; per-season store name derives from an
  `os.time()`-based id (identical on every server); only the **current** season is ever written.
- **Rate-limit / validation** — Every client-callable remote validates argument types/shapes and is
  rate-limited or cooldown-gated (purchase, trade actions, codes, settings, tutorial, rebirth,
  index, event claim/shop, monetization prompts, inventory). Reads (`GetSeasons`, `GetMonetization`)
  are pure reads.
- **Time / scheduler** — Event + season active-state derive purely from `os.time()` + config;
  transitions diff the active set and fire once per boundary; modifiers are keyed sources that
  apply-once and remove cleanly (no residue).
- **Require cycles** — **None.** Verified by building the full server dependency graph. The
  decoupling registries (`TransitRegistry`, `TradeLockRegistry`) and the externally-set
  `SeasonService.RolloverCallback` break every potential cycle.
- **Client / UI errors** — Every UI mount is `pcall`-wrapped (`safeMount`); panels nil-guard their
  `gui`; no code-gen-before-exists or nil-handler path found.

---

## Could-not-fully-verify-without-runtime (flagged, not guessed)

- **`AnalyticsService` signatures** (`LogEconomyEvent`, `LogOnboardingFunnelStepEvent`,
  `LogCustomEvent`) — match the current Creator docs as far as I can confirm statically, and **every
  call is already `pcall`-wrapped**, so a future signature drift is swallowed and can never affect
  gameplay. If the AnalyticsService dashboard shows nothing after launch, that is where to look
  first — it will not crash anything.

## Known papercut (environmental, not a code bug)

- `Packages/` is git-ignored and there are no Wally dependencies yet, so a fresh clone has an empty
  `Packages/` dir. `rojo build` needs the dir to exist. If a build ever errors with *"Packages could
  not be turned into a Roblox Instance"*, recreate it: `New-Item -ItemType Directory Packages`.

---

## Production-safety re-verification

- **SIM flag** is `false` in production by construction: `DevConfig.SimMode = ALLOW_SIM_IN_STUDIO and
  RunService:IsStudio()`, so a published server **always** has it off. The boot report prints the
  state and **loud-warns** if SIM is ever true on a non-Studio server (impossible today; the assert
  guards against a future regression).
- **Force hooks** (`EventService.ForceEvent`, `SeasonService.ForceRollover`,
  `MonetizationService.SimGrantGamepass/SimFireProduct`, `TutorialService.ResetForTesting`) are
  server-module methods gated on `DevConfig.SimMode`; **none is exposed via a remote**, so no client
  can reach them.
- **No debug/admin remote** exists. The new diagnostic + validator are server-only modules; the
  validator only **reads** state and can never affect gameplay.
- **Monetization Ids** are all `0` (placeholder) → those rows are hidden on a live server and never
  granted; they light up only when real Ids are pasted in `Shared/Monetization`.

---

## What to watch in the Output when you Play

1. The **`[BRAINROT] BOOT HEALTH CHECK`** block: `Services: N/N started` (any `[X] … FAILED` line is
   the first thing to fix), `Remotes: folder OK, 24/24 present`, and `DataStores: … REAL/MOCK`.
2. The **per-join** line `[Diag] <you> JOIN ok: store=…, fields=33/33` — a `MISSING template fields`
   warning means a reconciliation gap.
3. **`[Invariants] OK`** every 30s in Studio — if it ever prints `VIOLATION(S)`, copy those `!!`
   lines; they pinpoint a dupe / negative cash / cap break / dangling lock with the exact ids.
4. Run a manual check any time from the command bar:
   `require(game.ServerScriptService.Server.InvariantValidator).Run()`
