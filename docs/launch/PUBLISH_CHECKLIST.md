# Publish Checklist

Ordered steps to take the game live. **You** do these (dashboard/Studio); the code is ready.

## 1. Publish the place
1. Open the place in Studio → **File → Publish to Roblox** (first time: create a new experience).
2. Note the **Universe/Experience** — everything below is on its page at create.roblox.com.

## 2. Enable persistence (REQUIRED — or saves/leaderboards/codes don't work)
- Creator Dashboard → your experience → **Settings → Security → enable "Studio Access to API Services"**.
- This is what makes ProfileStore (real saves), OrderedDataStore (leaderboards), global code limits, and `ProcessReceipt` work. Until then the game runs on the in-memory MOCK store (resets on stop).

## 3. Turn OFF dev/test SIM
- Open `src/Server/DevConfig.lua`. Confirm `ALLOW_SIM_IN_STUDIO` is the only sim switch and that `SimMode` is gated on `RunService:IsStudio()` — **it is already force-off on any live server**. Nothing to toggle, but verify the file is unchanged.

## 4. Paste your monetization IDs
Create the gamepasses + dev products on the dashboard, then paste each numeric Id into **`src/Shared/Monetization.lua`**:
- Gamepasses → `Monetization.Gamepasses.<Key>.Id` (DoubleCash, ExtraPads, ReinforcedLock, VIP).
- Dev products → `Monetization.Products.<Key>.Id` (CashSmall, CashLarge, PadUnlock, optional PremiumUnit).
- Any Id left `0` is safely hidden/skipped. **Re-publish** after pasting.

## 5. Configure the experience page
- **Genre/Tags**, **age guidelines** (complete the questionnaire), **device support** (Phone + Tablet + Computer; the UI is mobile-first), **Discord/social links**, **Servers**: keep default fill or set a sensible max.
- **Icon + 3 thumbnails**: create from `THUMBNAIL_ICON_BRIEF.md` and upload.
- Set the experience **Public** when ready.

## 6. Set up your first codes
- Edit **`src/Server/CodesConfig.lua`** (server-only — codes are never shipped to clients). The defaults (`LAUNCH`, `BOOST2X`, `FREEROT`) are live; the `GameInfo.Changelog` already advertises them.
- Bump `GameInfo.Version` in `src/Shared/GameInfo.lua` each update so the "What's New" card re-shows with the new code.

## 7. Final pre-launch smoke test (in Studio, then on the published place)
- [ ] Join → starter brainrot spawns, cash climbs, tutorial shows for a fresh player.
- [ ] Buy a brainrot (cash) → income rises.
- [ ] Open **Codes (🎁)** → redeem `LAUNCH` (Success), redeem again (AlreadyRedeemed), redeem `OLDCODE` (Inactive), redeem garbage (Invalid).
- [ ] Redeem `BOOST2X` → income/sec visibly doubles, then returns to normal after 10 min.
- [ ] Shop → Passes/Products show (SIM in Studio); on the published place buy a real product → it grants once.
- [ ] Leaderboard billboards populate; steal works with 2 players.
- [ ] (Published) Confirm cash/units **persist** across rejoin.

## 8. After launch
- Watch analytics (see `LIVEOPS.md`). Ship updates on a cadence, each with a new code (see `MARKETING_PLAYBOOK.md`).
