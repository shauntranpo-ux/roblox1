# LiveOps Plan

How to run the game after launch. Every lever here is a **config edit** — no new code needed.

## The weekly loop
1. **Add content** — edit `src/Shared/Catalog.lua`: add brainrots (new `Id`, `DisplayName`, `Rarity`, `Price`, `IncomePerSec`). Art auto-swaps when a model named `ModelName` appears in `ServerStorage/Assets`.
2. **Drop a code** — edit `src/Server/CodesConfig.lua`: add `{ Code, Reward, Active=true }`. Reward types: `Cash`, `Boost` (timed multiplier), `Brainrot`.
3. **Announce** — bump `GameInfo.Version` in `src/Shared/GameInfo.lua` and update `GameInfo.Changelog` with the new code → the "What's New" card re-shows to everyone.
4. **Balance** — tune numbers only, in their config (`Catalog`, `Config.Plots`, `StealConfig`, `Monetization.Income`). Nothing is hardcoded.
5. **Ship the clip + Discord post.**

## Reading the analytics (Creator Dashboard → Analytics)
The game logs (all via `AnalyticsService`, names in `src/Server/Analytics.lua`):
- **Onboarding funnel** (`spawn → saw_starter → first_purchase → hooked`): watch where new players DROP.
  - Big drop `spawn → first_purchase` → the first buy is too slow/unclear. Lower early prices in `Catalog` (Commons) or strengthen the tutorial.
- **Economy source/sink** (`Gameplay` income, `Shop` sinks, `IAP`, `TimedReward`): watch **inflation**.
  - Sources ≫ sinks for long → cash inflates, prices feel trivial → raise mid/late prices or add sinks. Sinks ≫ sources → progression stalls → lower prices or raise income.
- **Retention (D1/D7)** + custom events (`session_start`, `first_steal`, `first_robbed`, `tier_up`, `gamepass_purchased`, `code_redeemed`): correlate behaviors with retention.
  - Players who `first_steal` early usually retain better → make stealing more discoverable.
  - Low `code_redeemed` → codes aren't visible enough → push them harder in "What's New" + Discord.

> Analytics only reach the real dashboard on a **published** place; in Studio they're pcall-swallowed no-ops.

## What to ship in early updates
- **Weeks 1–2:** stability + a code each week; small brainrot additions; fix funnel drop-offs.
- **Weeks 3–6:** more roster depth (higher tiers), tune the rebirth/prestige curve, seasonal-flavored codes.
- **Ongoing:** the next milestones (Trading is built; future: mutations, events, seasons) become the big "tentpole" updates — each with its own code + clip.

## Guardrails
- Never ship an update without a **new code** (it's the retention trigger).
- Keep the **SIM flag** off on live (it's auto-gated to Studio).
- Watch the leaderboard `Top Cash` for impossible values → would signal an exploit (cash is clamped + server-only, but watch anyway).
