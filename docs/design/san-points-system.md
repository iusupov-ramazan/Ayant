# САН Points — per-venue loyalty ledger (System 1)

Status: **Design locked, pre-implementation** · Owner: product · Last updated: 2026-07-30

This is the first of the loyalty/bonus systems. It replaces the retired app-usage
`BonusEngine`. Scope here is **per-venue points only** — cross-venue growth mechanics
(referral, welcome, gifts) are a separate system, see "Knock-on: growth payouts" below.

---

## 1. The model in one sentence

Every venue runs its own points ledger. Points are earned by scanning at the counter,
are worth **1 point = 1 som** of redemption value, are spent on a business-defined
catalog of item rewards and/or money-off, and expire after inactivity.

## 2. Locked decisions

| Area | Decision |
|---|---|
| Earning | Business picks one mode: **flat per visit**, **amount bands**, or **% cashback** |
| Redemption | Business-defined catalog, mixes **item rewards** and **money-off** |
| Config | **Full self-serve** in host panel, with hard guardrails |
| Expiry | Whole balance expires after **N months of inactivity** (default 6), warning push before |
| Redeem trigger | Per-venue: **staff-scans-to-redeem** OR **customer-initiated** |
| Point value | **1 point = 1 som** (universal) |
| Earn cooldown | Default **60 min** per user/venue, configurable |
| Old BonusEngine | **Retired** (see §9) |

## 3. Data model (Firestore)

### Venue config (extends `venues/{id}`)
```
pointsEnabled: bool                 // master switch
pointsMode: "flat" | "bands" | "cashback"
pointsFlat: int                     // mode=flat: points per visit
pointsBands: [{ maxAmount: int, points: int }]   // mode=bands, ascending; last = catch-all
cashbackPercent: number             // mode=cashback, 0 < x <= 20 (guardrail)
pointsRewards: [Reward]             // redemption catalog (below)
pointsExpiryMonths: int             // default 6
redeemMode: "staffScan" | "customerInitiated"
earnCooldownMinutes: int            // default 60
```

### Reward (element of `pointsRewards`)
```
id: string
type: "item" | "money"
title: string                       // "Бесплатный кофе" / "Скидка баллами"
cost: int                           // type=item: fixed points; type=money: minRedeem
ratio: number                       // type=money only: som off per point (default 1)
active: bool
```

### Ledger head — `venuePoints/{userID}_{venueID}` (Functions write only)
```
userID, venueID, venueName
balance: int
lifetimeEarned: int
lifetimeRedeemed: int
lastActivityAt: timestamp           // drives expiry
updatedAt: timestamp
```

### Ledger rows — `venuePoints/{userID}_{venueID}/ledger/{txnID}` (audit trail)
```
type: "earn" | "redeem" | "expire"
points: int                         // signed: +earn, -redeem, -expire
billAmount: int?                    // earn via cashback/bands
rewardId: string?                   // redeem
byVenue: bool                       // true = staff-triggered, false = customer-initiated
at: timestamp
```

The ledger subcollection is the dispute/audit record — never mutate a row, only append.

## 4. Firestore rules

```
match /venuePoints/{cardId} {
  allow read: if isSignedIn() && resource.data.userID == request.auth.uid;
  allow write: if false;            // Cloud Functions (admin SDK) only
  match /ledger/{txnId} {
    allow read: if isSignedIn()
                && get(/databases/$(db)/documents/venuePoints/$(cardId)).data.userID == request.auth.uid;
    allow write: if false;
  }
}
```
Venue config fields are writable by the venue owner/admin under the existing
`venues/{id}` ownership rule, BUT the guardrails (cashback ≤ 20, etc.) must be
enforced in a rule condition or a config-validation Function, not trusted from the client.

## 5. Cloud Functions

### 5a. Earn — extend `scanCoupon` with **Branch C**
Customer's earn QR: `AYANT-PTS:<userID>`. Staff scans it in `HostScannerView`; for
`bands`/`cashback` modes the host app first collects the amount/band, then calls
`scanCoupon` with `{ code, billAmount? , bandIndex? }`.

Server (transaction):
1. Verify host ID token, load `venue`, assert `venue.ownerID == uid` and `pointsEnabled`.
2. Read `venuePoints/{userID}_{venueID}`. If `lastActivityAt` earn within `earnCooldownMinutes` → reject `cooldown`.
3. Compute points by mode:
   - flat → `pointsFlat`
   - bands → `pointsBands[bandIndex].points`
   - cashback → `round(billAmount * cashbackPercent / 100)`
4. `balance += pts`, `lifetimeEarned += pts`, `lastActivityAt = now`; append `earn` ledger row.
5. Return `{ balance, awarded }`.

### 5b. Redeem — new callable `redeemVenuePoints`
Inputs: `{ venueID, userID, rewardId, pointsToSpend? }`.
- **staffScan mode**: authed as host; assert `venue.ownerID == uid`. Customer shows redeem
  QR `AYANT-RDM:<userID>:<rewardId>:<nonce>` which staff scans.
- **customerInitiated mode**: authed as the customer; assert `request.auth.uid == userID`.
- Load reward; compute cost (item → `cost`; money → `pointsToSpend`, must be ≥ `cost`/minRedeem
  and ≤ balance). Transactionally `balance -= cost`, `lifetimeRedeemed += cost`,
  `lastActivityAt = now`; append `redeem` row. Reject if `balance < cost`.

### 5c. Expiry — scheduled `expireVenuePoints` (daily)
- **Warn pass**: `lastActivityAt` between (expiry − 14d) and (expiry − 13d) and `balance > 0`
  → queue push "твои баллы в {venue} сгорят через 2 недели".
- **Expire pass**: `lastActivityAt < now − expiryMonths` and `balance > 0` → set `balance = 0`,
  append `expire` row.

## 6. iOS client changes
- **Add** `VenuePointsStore` (server-backed): `sync(userID:)` reads `venuePoints/*`, exposes
  per-venue balances + ledger. No local balance writes — backend is source of truth (mirror `LoyaltyStore`).
- **Customer**: points card UI per venue (balance, catalog, earn QR `AYANT-PTS:`, redeem QR/redeem button per `redeemMode`).
- **Host** (`HostScannerView`): after scanning `AYANT-PTS:`, branch on venue mode → amount/band
  sheet → call `scanCoupon`. Add redeem handling for `AYANT-RDM:`.
- **Retire** `BonusEngine`, `ActivityTracker`, mini-game earning, and the hardcoded
  `CouponStore.catalog` bonus-redeem path (see §9).

## 7. Android parity
Mirror as `VenuePointsViewModel` + `venuePoints` reads in `FirebaseDataRepository`/`CouponService`,
host scanner amount/band step, retire `BonusViewModel` earning. Keep constants identical to iOS.
Fix the pre-existing referral deep-link path mismatch while here (`/ref/` vs `/invite/`).

## 8. Host/admin config UI (self-serve)
In `docs/admin/` (and host app): a "Бонусы САН" section on the venue editor —
toggle `pointsEnabled`, pick mode, set rate(s), edit reward catalog rows, set expiry + redeem mode.
Client-side hints + server-side validation enforce guardrails.

## 9. Retiring the old BonusEngine
**Remove**: `SAN/Bonus/BonusEngine.swift`, `ActivityTracker`, 30-min active-time earning,
`dailyGameplayCap` mini-game earning, `CouponStore.catalog` (the −10%/coffee/dessert/VIP
hardcoded rewards bought with global points), and the "earn by using the app" UI in `BonusHubView`.
Android: same in `BonusViewModel`. Delete `san.bonus.balance` usage.

**Keep for now** (own systems, not part of System 1): stamp `LoyaltyCard`, deal coupons,
gift coupons, referral tracking.

### Knock-on: growth payouts ⚠️ NEEDS DECISION
Referral (+100), the invitee welcome bonus (+100), and gift-coupon purchases all currently
pay **into the global BonusEngine balance we are deleting**. They have nowhere to land once
it's gone. Per-venue points is NOT their home (they aren't tied to a venue). Options:

- **A (recommended):** Scope referral/welcome/gift into a later **System 2 (Growth)** with its
  own platform-funded promo wallet. For System 1 launch, temporarily disable those payouts
  (keep referral *tracking* so we don't lose data). Clean separation, no unfunded liability now.
- **B:** Keep a minimal global promo-credit wallet just for referral/welcome/gift, walled off
  from business points and redeemable only for platform-funded perks. More to keep alive.

## 10. Phased build
1. ✅ **Backend** (done): rules + `venuePoints` model + `scanCoupon` Branch C + `redeemVenuePoints` + `expireVenuePoints`.
2. ✅ **Host + config** (done): admin panel «Бонусы САН» self-serve UI (verified); iOS Venue/DTO config round-trip; iOS host scanner earn (flat/bands/cashback amount sheet) + staff-scan redeem. iOS build green.
   - Deferred: in-app **host venue-editor** points UI (config lives in the admin panel for now); host `firestoreData` intentionally does NOT write points fields so host saves can't clobber admin config.
3. ✅ **Customer** (done): `VenuePointsStore` + `fetchVenuePoints`; points card (balance, `AYANT-PTS:` earn QR); per-venue screen with reward catalog + redeem (staffScan → `AYANT-RDM:` QR, customerInitiated → direct call); surfaced in venue detail banner + Bonuses tab. iOS build green.
4. ✅ **Two-wallet model** (done, revised): instead of retiring the global wallet, the product keeps **two** wallets — per-venue САН points (business-funded, this doc) **and** one global wallet (`BonusEngine`) for platform-wide coupons. The global wallet now earns **near-zero** (`rewardPerGoal 20→1`, gameplay cap `30→3`) so it can't be farmed into money loss; **Snake kept, Tetris removed**. Referral/welcome still credit the global wallet; `recordReferral` tracking kept. Bonuses tab shows: global wallet + catalog + **Баллы САН** + Карты лояльности + Snake.
5. ✅ **Android parity** (done): model+config parsing, host scanner earn(amount/band)/redeem, `VenuePointsViewModel` + points card + venue-detail banner + Bonuses-tab link, and the same global-wallet slim-down (near-zero, Snake-only). iOS + Android both compile green.

## Two-wallet summary
- **Баллы САН** (per venue): business-funded, earned by scanning at that venue, spent on that venue's rewards. The real loyalty product. Cannot be earned by playing games.
- **Global wallet** (`BonusEngine`): platform-wide, earns near-zero (Snake + active-time + referral/welcome), spent on the global coupon catalog + gifting. Kept small on purpose — it's engagement, not a money sink. ⚠️ The catalog coupons (free coffee, etc.) are still a small platform-funded liability; near-zero earning is the mitigation. Tune/fund deliberately.

## 11. Open items
- Growth payouts decision (§9).
- Do venues run points **and** stamps simultaneously, or pick one? (deferred — stamp card is its own system.)
- Warning-push copy + timing final wording.
