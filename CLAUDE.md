# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Ayant** (internal name "SAN") is a Yelp-style deals / loyalty / reviews app for Bishkek, Kyrgyzstan, with a **Russian-first UI**. It is a monorepo of five surfaces that all share one Firebase project (`san-25d32`):

| Surface | Path | Stack |
|---|---|---|
| iOS app | `SAN/` (UI + composition root), `AyantFeatures/` (stores), `AyantData/` (Firebase), `AyantDomain/` (pure core), tests in `SANTests/` + `AyantDomain/Tests/` | Swift + SwiftUI |
| Android app | `android/app/` (Compose UI + composition root), `android/feature/` (ViewModels), `android/data/` (Firebase), `android/domain/` (pure core) | Kotlin + Jetpack Compose + Material 3 |
| Cloud Functions | `functions/` (TypeScript: `src/*.ts` → compiled to `lib/`) | Node 20, TypeScript, Firebase Functions v2 |
| Web (marketing + admin panel) | `web/`, `docs/admin/` | Static HTML + Firebase Web SDK (no framework) |
| Support bot | `telegram-bot/` | Node, grammy + Groq LLM (standalone, no Firebase) |

The iOS app is the source of truth; **Android is a deliberate near 1:1 port**. File headers cross-reference their iOS counterpart ("Mirrors `AppStore.swift`"). When you change shared behavior (ranking, models, Firestore field names, features), change it on **both** platforms or the two clients drift — they read/write the same Firestore documents with identical field names.

## Big-picture architecture

Read these cross-cutting patterns before editing; they span many files and are mirrored on both platforms.

- **Mock ↔ Firebase switch via a factory.** Both apps run fully offline on bundled mock data and flip to the live backend through a single toggle:
  - iOS: `SAN/AppConfig.swift` (`useFirebase`) + `make*()` factories returning either a `Mock*` or `Firebase*` implementation.
  - Android: `core/AppConfig.kt` (auto-detects `google-services.json` at startup in `AyantApp.kt`) + `makeX()` factories.
  Keep this switch working. Every data dependency has a protocol/interface with a `Mock*` and `Firebase*` pair.

- **Every layer is a separate build target on both platforms — the boundary is a compile error, not a convention.** The two platforms now have the same four layers, and the arrows between them are Gradle dependencies / SwiftPM package dependencies:

  | Layer | iOS | Android | Holds | May depend on |
  |---|---|---|---|---|
  | Domain | package `AyantDomain/` | module `:domain` | models, pure math (`Ranking`, `PointsMath`, `FeedAssembly`, `ReviewStats`), contracts (`DataRepository`, `CouponService`, `PushService`, `AuthService`, `LocalPreferencesStore`, `DistanceSource`, …), `*State`/`*Intent` | Foundation only / plain Kotlin-JVM |
  | Data | package `AyantData/` | module `:data` | `Mock*`/`Firebase*` implementations, Firestore schema + mapping, backend URLs | domain + Firebase SDK |
  | Feature | package `AyantFeatures/` | module `:feature` | stores (`AppStore`, `FeedStore`, …) / all ViewModels (`ui/vm/`) | domain **only** |
  | App | target `SAN` | module `:app` | SwiftUI/Compose screens, navigation, `AppConfig`, composition root | all of the above |

  Firestore/Auth/Storage are declared **only** in the data layer, so calling Firestore from a screen or a store is a missing-module error, not a review comment. On Android `:feature` has no Compose dependency either — a `mutableStateOf` in a ViewModel does not compile, which is what keeps §4 (`StateFlow` only) true by construction. `:app` still declares `firebase-common` + `firebase-messaging` for the two framework entry points below; CI grep guards (`.github/workflows/checks.yml`, `ios.yml`) keep Firebase out of everything else.

  On iOS the compiler enforces the same shape, with one Swift-specific catch: **types crossing a package boundary must be `public`, including an explicit `public init`** — the synthesized memberwise/empty init is internal, so `MockDataRepository()` from the app fails to compile until the package spells the init out.

  Dependencies point inward: `app → domain`, never the reverse. Adding `import FirebaseFirestore` (or `android.content.Context`) to the domain fails the build. SwiftUI/UIKit are system frameworks the Swift compiler *would* accept, so that half of the rule is held by a grep guard in `.github/workflows/ios.yml` — keep it passing.

  Host models (`HostProfile`, `HostVenueDTO`, `HostDealDTO`, `AdCampaign`, `VerificationStatus`) live in the domain on **both** platforms now — on iOS they used to be declared inside `HostStore.swift`.

  Because the domain has no UI types, colors are stored as numbers (`Venue.gradient` is `[UInt32]` on iOS, `List<Long>` on Android) and mapped to real colors in the UI layer: `SAN/Theme/ModelColors.swift` / `ui/theme/ModelColors.kt`.

- **Firestore field names live in exactly one file per platform.** Every collection and field name is a named constant in `FS`:
  - iOS: `AyantData/Sources/AyantData/FirestoreSchema.swift` — mapping code in `FirestoreMapping.swift` alongside it.
  - Android: `data/firestore/FirestoreSchema.kt` — mapping in `data/firestore/FirestoreMapping.kt`.

  **Never write a raw Firestore field string anywhere else.** Read and write paths for the same document use the same constant, so they can't drift apart, and a typo is a compile error instead of a silently-defaulted `nil`. `FS` also covers the Cloud Function response bodies (`ScanResponse`, `RedeemResponse`) and the FCM push payload, for the same reason. Renaming a field means editing `FS` on both clients **plus** `functions/src/index.ts` and `docs/admin/index.html` — the compiler can't see those two.

- **Firebase SDK imports are confined to the data layer, with four deliberate exceptions.** Every Firebase call goes through a protocol/interface with a `Mock*`/`Firebase*` pair (`DataRepository`, `CouponService`, `PointsRepository`, `AnalyticsService`, `ProductAnalytics`, `PushService`, `FileUploadService`, `HostRepository`). The only files above the data layer that may import Firebase are **framework entry points**, where the SDK type *is* the integration surface:
  - `SAN/SANApp.swift` / `AyantApp.kt` — `FirebaseApp.configure()`, the composition root.
  - `SAN/Deeplink/Deeplink.swift` / `push/AyantMessagingService.kt` — the FCM delegate / `FirebaseMessagingService` subclass. They may hold the APNs/FCM token plumbing, but **not** talk to Firestore — token writes go through `PushService`.

  Anything else importing Firebase above `data/` is a bug. Watch for it in Compose components and stores especially.

- **Repository abstraction isolates Firestore.** Firestore *access* (queries, writes) lives in `AyantData/Sources/AyantData/FirebaseServices.swift` and `android/data/.../FirebaseDataRepository.kt` (+ sibling `*Service` files); those files call the mappers above and contain no field names. **Every** service contract — `DataRepository`, `CouponService`, `AnalyticsService`, `RankingEventService`, `HostRepository`, `PushService`, `ProductAnalytics`, `PointsRepository`, `LocalPreferencesStore`, `AuthService` — lives in the domain module, and only the `Mock*`/`Firebase*` pairs live in the data module. Push campaigns go through `PushService.queuePushCampaign` on both platforms; no ViewModel or store writes Firestore directly.

- **Dependency injection is constructor-based (no DI framework), and neither platform reaches back to `AppConfig` any more.** A default like `init(repository: DataRepository = AppConfig.makeDataRepository())` would be a feature→app back-edge, so stores/ViewModels take their deps as plain required params and a composition root supplies them:
  - iOS: `SAN/AyantStores.swift` — `AyantStores.app()`, `.session()`, `.coupons()`, … called from `SANApp.swift` (`@StateObject private var store = AyantStores.app()`) and from SwiftUI previews.
  - Android: `core/AyantViewModels.kt`, used as `viewModel(factory = ayantFactory())`. Adding a ViewModel means adding a branch there; the factory throws with a pointed message otherwise.

  This is the seam tests inject fakes through on both platforms. **Test doubles belong to the tests** (`SANTests/Fakes.swift`), not to the data layer: importing `AyantData` from the test target would drag Firestore + gRPC into it and fail to link.

- **Android: obtain shared ViewModels at the Activity, never inside `composable {}`.** Inside a `NavHost` destination `LocalViewModelStoreOwner` is the `NavBackStackEntry`, so `viewModel()` there returns a **per-route instance**. That is how the feed once ended up rendering "no venues in this city" (the catalog was published into `RootScaffold`'s `FeedViewModel` while `HomeScreen` held its own), and how points earned in Snake missed the bonus screen. Every shared ViewModel is created once in `RootScaffold` and **passed down as a parameter** — `HomeScreen(app, location, feed, …)`, `MyCouponsScreen(coupons, …)`, `SnakeGame(bonus, …)`; only `VenueDetailViewModel` is deliberately per-route. For the same reason the factory is passed explicitly (`viewModel(factory = ayantFactory())`) rather than installed as `defaultViewModelProviderFactory`: inside a destination the default factory is the `NavBackStackEntry`'s, which knows nothing about dependencies.

- **State: two patterns exist right now — use the newer one for new work.**
  - **Legacy (wallets, session, theme).** iOS `ObservableObject` + `@Published` stores injected as `@environmentObject` from `SANApp.swift` (`SessionStore`, `CouponStore`, `LoyaltyStore`, `BonusEngine`, `ThemeStore`, `LocationManager`); Android mirrors each with an `AndroidViewModel`, created in `ui/navigation/RootScaffold.kt` and **passed down as parameters**. These expose plain published properties and methods rather than one state value — no Compose state remains in any Android ViewModel.
  - **Current (points, feed, venue, profile).** `AyantFeatures/Sources/AyantFeatures/PointsStore.swift` + `ui/vm/PointsViewModel.kt`; `AyantFeatures/Sources/AyantFeatures/FeedStore.swift` + `ui/vm/FeedViewModel.kt`; `AyantFeatures/Sources/AyantFeatures/VenueDetailStore.swift` + `ui/vm/VenueDetailViewModel.kt`; `AyantFeatures/Sources/AyantFeatures/ProfileStore.swift` + `ui/vm/ProfileViewModel.kt`. One immutable state value and one entry point: `state` + `send(_ intent:)`. Android uses `StateFlow`, not `mutableStateOf`. `PointsState`/`FeedState`/`*Intent`/`LoadState`/`AppError` live in the domain module with **identical field names on both platforms**. Views are pure functions of the state — no `isLoading`/`error`/`done` flags scattered in the view, because `LoadState`, `RedeemPhase` etc. make the impossible combinations unrepresentable.

  Points was rebuilt first (it is where the money bugs are), then feed, venue, profile and host. **All five features are on this shape.** `AppStore`/`AppViewModel` owns neither the catalog nor the personal library any more (see ownership below) — it keeps the session plus actions and exposes thin read adapters.

- **Host form rules are pure and shared.** Building a venue/deal DTO from the editor form lives in `HostForms` (`AyantDomain/Sources/AyantDomain/HostForms.swift`, `android/domain/.../HostForms.kt`) — not in the store and not in the Compose form. Three rules there are easy to break and hard to notice: editing a venue **keeps `id`, `status` and `todaySpecial`** (otherwise an approved venue silently returns to moderation), editing a deal **keeps `startDate`** (otherwise it looks fresh again and jumps up the feed), and text fields are trimmed with hours clamped to 0…24. All pinned by tests on both platforms.

  **Ownership after the migration.** `FeedStore`/`FeedViewModel` owns the **catalog** — venues, deals, reviews, ranking weights, the host overlay and the network load. `ProfileStore`/`ProfileViewModel` owns the **personal library** — saved venues, favourite deals, redeemed coupons, and its persistence. `AppStore`/`AppViewModel` owns neither any more: it holds the session (current user, city) plus actions (redeem, gifts, referrals, review CRUD) and exposes **thin read adapters** (`venues`, `deals`, `reviews`, `isLoading`) that delegate to the owners, so the ~100 existing call sites still compile. It creates both owners in its initialiser, which keeps it self-contained in tests.

  **Two gotchas whenever you move ownership like this.**

  (1) On iOS the moved sets stopped being `@Published` on `AppStore`, so it forwards `ProfileStore.objectWillChange` — without that, saving a venue silently stops re-rendering screens that observe only `AppStore`. (2) Build the default `ProfileStore` from the **injected** `LocalPreferencesStore`, not `UserDefaults` directly, or tests that inject `InMemoryPreferences` will read real device state and fail non-deterministically.

- **Android ViewModels expose `StateFlow`, never Compose state.** No `mutableStateOf`/`mutableIntStateOf` remains in `ui/vm/` — state survives process death properly and reads in tests without Compose. (`mutableStateListOf` is still used for a few list-shaped caches; convert on touch.) On iOS the equivalent is `@Published`, which is idiomatic and stays.

- **`Clock` is threaded all the way down.** Six stores/ViewModels take a `Clock` (`AppStore`, `FeedStore`, `PointsStore`, `BonusEngine`, `CouponStore`, `HostStore` and their Android twins), and the feature layer contains **zero** raw `Date()` / `.now` / `System.currentTimeMillis()` calls on either platform — `SystemClock` in the domain is the only place the real clock is read. Anything below the UI that needs "now" takes it as a parameter or from the injected clock; a `static`/companion helper that can't see the clock takes `now` as an argument instead (see `BonusEngine.dayKey(_:)`).

- **Feed ranking is pure and time-injected.** `FeedBuilder` (`AyantDomain/Sources/AyantDomain/Feed.swift`, `android/domain/.../Feed.kt`) takes a `FeedCatalog` snapshot plus an explicit `now`/`nowMs` and returns the ranked feed — no store, no system clock. **Do not add `Date()` / `System.currentTimeMillis()` inside ranking.** The time-dependent model properties come in pairs: `isActive(at:)`/`isActive`, `isBoosted(at:)`/`isBoosted`, `isFresh(at:)`/`isFresh`, `isOpen(at:)`/`isOpenNow` (Kotlin: `isActiveAt(nowMs)` …). The parameterised form is for anything below the UI; the zero-arg one is a convenience for views only.

  `AppStore`/`AppViewModel` still own catalog loading (search, favourites and venue detail read it too) and publish a snapshot into the feed store via `bind(feed:)`/`bindFeed(...)` — so Firestore is not read twice. Catalog ownership moves into the feed store when `venue` and `profile` are converted.

- **Ranking is pure and testable.** Venue/deal/feed scoring (rating + reviews + verified + saves, deal freshness, haversine distance weighting, and ad-venue interleaving in the feed) lives in `Ranking` in the domain module on both platforms (`AyantDomain/Sources/AyantDomain/Ranking.swift`, `android/domain/.../Ranking.kt`); `AppStore`/`AppViewModel` only call it. This is what the unit tests cover.

- **Host content overlays the user feed.** The host (business) side edits venues/deals that are merged over the repo feed by id: iOS `HostStore.bind(AppStore)` → `AppStore.setHostContent`; Android `HostViewModel` → `AppViewModel.setHostContent`.

- **Money / anti-cheat paths are server-authoritative.** Clients never write sensitive counters directly. They create request documents or call HTTPS callables; Cloud Functions (`functions/src/index.ts`, admin SDK, bypasses rules) do the privileged writes: `scanCoupon` (verifies host ID token + venue ownership; branches on QR prefix — `AYANT-CARD:` → loyalty stamp, `AYANT-PTS:` → САН points, else deal-coupon redeem), `redeemVenuePoints` (spend points on a reward), `expireVenuePoints` (scheduled), `countRedemption`, `rewardReferral`, `sendPushCampaign` (frequency-capped FCM), plus Apple Wallet `.pkpass` generation. Firestore rules force `coupons`/`redemptions`/`bonusGrants`/`loyaltyCards`/`venuePoints` mutations through these functions. See the **Loyalty & bonus systems** section below.

## Commands

### iOS (`SAN/`)
```bash
# Build (scheme SAN). Needs Xcode 16+ (project format 77). CI (macos-15) picks the newest stable Xcode and any available iPhone simulator; locally any installed simulator works.
xcodebuild build -project SAN.xcodeproj -scheme SAN \
  -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO

# Run all tests
xcodebuild test -project SAN.xcodeproj -scheme SAN \
  -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO

# Run a single test class / method
xcodebuild test -project SAN.xcodeproj -scheme SAN \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:SANTests/RankingTests
```
```bash
# Домен отдельно — на macOS, без симулятора (секунды, а не минуты).
swift test --package-path AyantDomain
swift test --package-path AyantDomain --filter PointsFixtureTests   # один класс
```
New Swift files are auto-included via Xcode 16 synchronized folder groups — no `.pbxproj` edit needed. **Files added under `AyantDomain/Sources/`, `AyantData/Sources/` or `AyantFeatures/Sources/` are picked up by SwiftPM automatically too, but a new type is invisible to the app until it is `public` — and so is its `init`.** Only `AyantDomain` builds standalone (`swift build/test --package-path AyantDomain`); the other two are iOS-only (Firebase, UIKit), so check them with the app build above. The `SAN` scheme is shared (`SAN.xcodeproj/xcshareddata/xcschemes/SAN.xcscheme`) and lists `SANTests` in its test action — CI depends on that file, don't delete it.

### Android (`android/`)
```bash
cd android
./gradlew :app:compileDebugKotlin        # fast compile check
./gradlew :app:assembleDebug             # build APK
./gradlew :domain:test                   # domain unit tests (pure JVM, no Android — seconds)
./gradlew :domain:test --tests "kg.ayant.app.domain.RankingTest"   # single test
./gradlew :app:testDebugUnitTest         # app-layer tests (currently none — all tests are in :domain)
```
Requires JDK 17 and Android SDK 34 (minSdk 26). If no system Java, Android Studio's bundled JBR works. The search map needs a Maps SDK key (`YOUR_MAPS_API_KEY` in `AndroidManifest.xml`); the app still builds/runs without it (blank tiles).

### Backend (Firebase)
```bash
# Cloud Functions are TypeScript now: source in functions/src/*.ts → compiled to functions/lib/.
cd functions && npm run build                   # tsc -p tsconfig.json (REQUIRED before deploying functions)
firebase deploy --only firestore:rules          # deploy firestore.rules (compiles server-side)
firebase deploy --only functions                # deploy functions/ (predeploy hook also runs the build)
firebase deploy --only hosting                  # deploy web/ marketing site
# Full backend push (rules + functions + admin/marketing site):
firebase deploy --only firestore:rules,functions,hosting

# Firestore seed / maintenance (root; all need serviceAccountKey.json, use admin SDK → bypass rules)
node seed-bishkek.js         # seed 41 Bishkek venues
node reset-and-seed.js       # DESTRUCTIVE: wipes venues/deals/reviews/hosts, auto-backs-up first
node backup-firestore.js     # dump to backup-<timestamp>.json
node restore-firestore.js backup-<file>.json
node scripts/set-admin-claim.js <email> [--revoke]   # grant/revoke admin custom claim (see below)
```

### Telegram bot (`telegram-bot/`)
```bash
cd telegram-bot && npm install && npm start   # long-polling; needs .env (TELEGRAM_BOT_TOKEN, optional GROQ_API_KEY)
```

## Backend gotchas

- **Admin access requires a custom claim.** `firestore.rules` restricts catalog writes (`venues`/`deals`/`categories`/`hosts`) to the document owner (`ownerID == uid`) or an admin, and `docs/admin/index.html` only admits users whose token has `admin: true`. **Before using the admin panel or writing catalog docs as a human, run `node scripts/set-admin-claim.js <email>`** or you will lock yourself out. Seed scripts use the admin SDK and are unaffected.
- **Firestore rules ownership model:** `venues`/`deals` carry `ownerID`; `hosts/{uid}` doc id is the owner uid and hosts cannot self-set `verified`; `reviews` are writable by author / venue-owner (host reply) / admin. `analytics/{venueID}/**` is `write: if false` — counters are written only by Cloud Functions (`countAnalyticsEvent`, `bumpAnalytics`).
- **Push frequency caps** (`functions/src/index.ts`): production defaults are 1/day, 3/week, overridable for local testing via `PUSH_DAILY_CAP` / `PUSH_WEEKLY_CAP` env vars.
- **Functions are TypeScript.** Edit `functions/src/index.ts` (+ `types.ts`), never the compiled `functions/lib/*.js` (regenerated by `npm run build`). `package.json` `main` = `lib/index.js`. Deploy triggers the build via the predeploy hook, but run `npm run build` yourself to catch type errors first.
- **Secrets** (`serviceAccountKey.json`, `.env` files, `functions/certs/*.pem`, `google-services.json`) are gitignored and present only on local disk; only client-side Firebase config plists are (correctly) committed.

## Loyalty & bonus systems (TWO wallets — don't conflate them)

There are **two independent wallets**, plus the older stamp card. Full design + rationale: **`docs/design/san-points-system.md`**. When you touch any of this, mirror it on iOS + Android + the admin panel + `functions/src/index.ts` — the Firestore field names below are a hard contract across all four.

1. **Баллы САН — per-venue points (the real loyalty product).** Business-funded, earned by scanning at *that* venue, spent on *that* venue's rewards. **Cannot be earned by games.**
   - **Config on the venue doc** (self-serve in `docs/admin/index.html` «Баллы САН — программа заведения»; parsed into `Venue`): `pointsEnabled`, `pointsMode` (`"flat"|"bands"|"cashback"`), `pointsFlat`, `pointsBands[]` (`{maxAmount,points}`), `cashbackPercent` (≤20), `pointsRewards[]` (`{id,type("item"|"money"),title,cost,ratio,active}`), `pointsExpiryMonths` (6), `redeemMode` (`"staffScan"|"customerInitiated"`), `earnCooldownMinutes` (60; `0` = no cooldown).
   - **Ledger**: `venuePoints/{userID}_{venueID}` (`balance,lifetimeEarned,lifetimeRedeemed,lastEarnAt,lastActivityAt`) + `ledger` subcollection. Rules: read-own, `write:if false` (Functions only).
   - **Earn**: customer shows QR `AYANT-PTS:<userID>` → `scanCoupon` Branch C (host enters bill amount for `cashback` / picks band for `bands`; `flat` needs nothing). 60-min earn cooldown.
   - **Redeem**: `AYANT-RDM:<userID>:<rewardId>:<points>:<nonce>` (staff scans; `points` = 0 for item rewards) or in-app for `customerInitiated` → `redeemVenuePoints`. Build/parse only through **`RedeemQR`** (domain, `RedeemQRTests`); old 3/4-part codes still parse. The nonce is one per guest attempt (new QR each time the reward screen opens): when the **owner** sends `nonce`, the server uses `rdm_<nonce>` as the idempotency key, so a second scan of the same QR (another cashier, a screenshot) replays instead of charging twice. `CouponService.redeemVenuePoints(..., nonce:)` — the extension without `nonce` passes `nil`.
   - **Files**: iOS `SAN/Bonus/VenuePointsViews.swift` (screens) + `AyantFeatures/Sources/AyantFeatures/PointsStore.swift` (state); Android `ui/vm/VenuePointsViewModel.kt` + `ui/bonus/VenuePointsScreens.kt`. Config rides in `HostVenueDTO`/`HostModels.kt`. Since 2026-09-11 the **iOS host app edits it too** (Лояльность tab → `HostIntent.savePointsConfig` → `HostForms.applyPoints`, which clamps to the server guardrails); `HostVenueDTO.firestoreData` writes the points fields with `merge: true`, and the admin panel edits the same fields — last write wins. Android mirrors this since 2026-09-18: `HostIntent.SavePointsConfig` → `HostForms.applyPoints` (same clamps, pinned by the same six tests in `HostFormsTest`) → `HostViewModel.savePointsConfig` → `HostRepository.saveVenue` (`FirebaseHostRepository`, `HostVenueDTO.toFirestoreMap(ownerID)` with `SetOptions.merge()`), edited from `HostLoyaltyScreen`. That write is the **only** server sync the Android host cabinet has — owned venues/deals/profile are still local-only on Android.

2. **Global wallet (`BonusEngine` / `BonusViewModel`).** Platform-wide; spent on the global coupon `catalog` + gifting. Time-in-app still earns near-zero (`rewardPerGoal=1`, at most `dailyGoalCap`=4 cycles a day), but **mini-games have no daily ceiling any more** — the `3`/day cap was removed on the owner's call on 2026-09-22, and `awardGameplay` now grants whatever was earned (pinned by `BonusEngineTests`). Four mini-games feed it: Snake (`+1`/apple), Tetris (`+1`/line — not 5: one line would otherwise take the whole daily cap; engine in `Tetris.swift`/`Tetris.kt`, tested on both platforms), «Три в ряд» (`+1` per `Match3.matchesPerBonus` = 12 matches; rules in `AyantDomain/.../Match3.swift`, pinned by `Match3Tests`) and «2048» (`+1` per new best tile from `Game2048.bonusFromValue` = 128 — so 128, 256, 512 fill the day; rules in `AyantDomain/.../Game2048.swift`, pinned by `Game2048Tests`). All four award through `BonusEngine.awardGameplay`, which caps nothing any more, so **each game's own rate is now the entire economy**. Those rates used to be four unrelated constants — fine under a 3/day ceiling that everyone reached anyway, ruinous without one: Snake paid a bonus per apple and «Три в ряд» one per twelve matches, so the same coupon cost 1.5 hours in one game and 5 in another, and players would simply farm the cheapest. **The price now comes from one anchor: `GameEconomy.minutesPerBonus`** (`AyantDomain/.../GameEconomy.swift`). Everything else there is a *measurement* of how fast a game is played, not a knob — change those when the game changes (drop speed, board size, cascade length), and change the anchor when a bonus should be worth more or less. At `minutesPerBonus = 1` a 300-bonus coupon is about five hours of play; that, not «apples» and «lines», is the number to discuss with venues. `GameEconomyTests` fails if any game drifts more than 25% off the anchor, or if two games differ by more than 1.5×. «2048» stays out of the linear calculation on purpose: its price is a ladder (each tile costs twice the last), which is its own anti-farm. **«Три в ряд» (shown to users as «Diamond» since 2026-09-30) is the one exception to «no ceiling»** (2026-09-29): the game became endless (no move limit, owner's call), and an endless game has no natural stop, so it pays through `BonusEngine.awardGameplay` with a per-game daily cap — default `GameEconomy.endlessDailyBonusCap = 30`, overridable by Remote Config `ios_bonus_diamond_daily_cap` (see «Remote kill switches» below; counter `san.bonus.earnedTodayByGame`, reset with the day and on `resetForNewUser`). The HUD shows what is left today; play continues after the cap, it just stops paying. The other games' `awardGameplay` is still uncapped — pinned by `BonusEngineTests`. Remember what a bonus buys now that coupons are venue goods — a real item handed over at a counter, paid for with currency a player minted by playing.

**Android is deliberately behind on all of this** (2026-09-22, owner's call): `BonusViewModel` still has `dailyGameplayCap = 3`, `Tetris.kt` still pays `BONUS_PER_LINE` per line, and `SnakeGame.kt` still awards a bonus per apple. So the same account earns differently on the two platforms — this is the one money rule that is currently NOT mirrored, and porting it means `GameEconomy.kt`, `BonusViewModel`, `Tetris.kt`, both game screens and `BonusScreen`. **«2048»'s doubling ladder is NOT what stops farming** (corrected 2026-10-01): tiles spawn mostly as 2s, so 128 takes ~58 moves and 512 ~233 — three restarts «до 128» are *faster* than one game to 512, and restarting after 128–256 is the optimal play. That is fine because the first bonus already costs about a minute (on the anchor); what protects the game is the **threshold itself** (start at 64 and a bonus costs seconds), now remote-configurable as `ios_bonus_2048_first_tile`. If restart-farming ever matters, cap the game with `ios_bonus_2048_daily_cap`. «Три в ряд» and «2048» are **iOS-only for now** — a deliberate lag like the Instagram import, not a forgotten mirror; the rules already sit in the domain, so each Kotlin port is mechanical (`Match3.kt` / `Game2048.kt` + the same tests, plus a Compose screen mirroring `SAN/Games/Match3Game.swift` / `SAN/Games/Game2048View.swift`).

«2048» has the same `Tile.id` rule as «Три в ряд», and one of its own. **A move is two frames, not one** (`Game2048.move` returns both): on the first every tile has arrived at its destination and a merging pair stands in the SAME cell with its old values; on the second the absorbed tile disappears and the survivor doubles. Collapse that into one frame and the merge reads as «a tile vanished where it stood and its neighbour changed number by itself». That is also why the board is a flat `[Tile]` with coordinates rather than `[[Tile?]]` — a grid cannot hold the two tiles that briefly share a cell. The survivor is always the tile nearer the wall, so the other one visibly slides into it.

Two things about «Три в ряд» break quietly if you touch them. **`Tile.id` is what makes stones fall.** The board is one view per stone keyed by that id, so SwiftUI moves a stone to its new cell and drops refilled ones in from above; render the board row by row instead and the animation silently degrades to an instant grid swap — the game still works, it just stops looking like one. The domain keeps ids unique forever (`State.nextID`) for the same reason: a reused id teleports a new stone into a dead one's place. **Stones are images, one per kind** — `gem_ruby` / `gem_amethyst` / `gem_rose` / `gem_gold` / `gem_emerald` / `gem_sapphire` in `Assets.xcassets`, cut from the artwork the owner supplied. Each kind has its own **shape** as well as its own colour (square, star, hexagon, circle, oval, pentagon): that is what keeps the board readable for someone who can't tell magenta from violet, so swap a stone's art only for art of a different shape. `GemView` falls back to drawing the stone in code (`FacetedGem`, one `Canvas` per stone) when the catalog has no image for a kind — a safety net for a dropped asset, not a staging area. The catalog is probed once per kind, not per frame: forty-nine stones redraw on every animation frame, which is also why the fallback is a `Canvas` and not the twenty `Shape`s it started as. `GemPalette` still matters even with images — the flash and the sparks take their colour from it, so it tracks the art. Referral/welcome (+100) credit this wallet; `recordReferral` writes referral tracking to Firestore regardless.

3. **Loyalty stamp card (older).** `AYANT-CARD:<userID>:<venueID>` → `scanCoupon` Branch A → +1 stamp in `loyaltyCards/{userID}_{venueID}`. Has its own anti-multi-scan cooldown: **`DEFAULT_STAMP_COOLDOWN_MIN=15`** (separate from the 60-min points cooldown; both keyed on `lastStampAt`/`lastEarnAt`).

   **A venue can have several stamp cards (2026-09-29, «Пармезан»: coffee and pizza).** Backward compatible by construction: the **first card is the old scalar fields** (`loyaltyGoal`/`loyaltyReward`, plus optional `loyaltyTitle`; id `default`) and keeps its ledger `loyaltyCards/{userID}_{venueID}`; **extra cards** live in `venues.stampCards[]` (`{id,title,goal,reward,active}`) and their ledgers in a **separate collection `extraLoyaltyCards/{userID}_{venueID}_{cardID}`** — separate on purpose: Android and already-shipped iOS builds read `loyaltyCards where userID == uid` and merge by venue, so a second card's doc there would overwrite their first card. `loyaltyEnabled` switches the whole programme. The guest QR is unchanged; after the scan the **staff pick the card** (`HostScannerView.cardPicker`) and the scan carries `cardID` — no `cardID` means the first card, which is what Android and old iOS send. Cooldown is per card. **Scan keys of all of a guest's cards at a venue live in one place** (`loyaltyCards/{userID}_{venueID}/scanKeys`, even if that doc doesn't exist) and record their `cardID`: the same key with another card is `409 key_reused`, and a retry replays from the key record *before* the card is looked up, so it still gets its original answer after the card was disabled. The iOS scanner mints the key per (QR, card) pair — coffee *and* pizza in one visit are two legitimate scans. Unknown/inactive card → `409 card_not_found`. The first card's goal keeps its legacy rule (0/garbage → 6, min 2, **no upper cap** — Android writes free numbers); extra cards are 2…12, ≤5 cards in total. Rules: `StampCards` (domain) ↔ `activeStampCards`/`stampCardDocID`/`stampCardCollection` (functions), both driven by **`specs/fixtures/stamp-cards-fixtures.json`** (`StampCardsFixtureTests` / `stampCardsFixture.test.js`) — new cases go in the JSON. **Two ways cards get wiped, both closed — keep them closed:** `HostForms.VenueFields.loyaltyTitle`/`extraStampCards` are optional (`nil` = keep), so the general venue form can't drop them; and `HostVenueDTO.stampCardsLoaded` is `false` for a cache from a build without cards, and `firestoreData` omits the card fields until a sync or the card editor sets it — otherwise the first pause-toggle after updating would write `stampCards: []`. `LoyaltyCard.id` is `venueID` for the first card and `venueID#cardID` for others (the store and wallet deck key by it). Editors: `StampCardsEditor` (iOS host — venue sheet and the Лояльность tab) and the admin panel's venue form (last write wins between them, like every venue field). **Android is not mirrored**: it edits and stamps only the first card and never sees the extra ledgers.

## Купоны: акция рекламирует, купон продаётся

**Акция больше не выдаёт купон.** Раньше гость открывал акцию, получал QR, сотрудник сканировал — заведение обязано было держать сканер ради обычной скидки, а купон не стоил ничего и выдавался всем. Теперь роли разведены:

- **`Deal` — объявление.** Приложение показывает («−20% на завтраки»), заведение применяет скидку у кассы само. У акции нет купона, нет QR, нет погашения. Флаг называется `isInformational` (бывший `isRedeemable` — старое имя обещало погашение, и под него путь отрастал обратно).
- **`CouponOffer` — товар.** Заведение выпускает купон, назначает **цену в бонусах**, остаток и срок; гость покупает за бонусы, накопленные в приложении. Коллекция `couponOffers`, форма — `HostForms.couponOffer`, экран — «Купоны за бонусы» в карточке заведения у хоста, модерация — страница «Купоны» в админ-панели.

**Уже выданные купоны акций (`kind: "deal"`) остаются рабочими** и гасятся через `scanCoupon` как раньше. Отнимать у людей выданное нельзя — путь создания убран, путь погашения оставлен.

**Срок и лимит купона (2026-10-01).** `couponOffers.expiresAt` — срок купона целиком: после него нельзя ни купить, ни погасить (`buyCoupon` копирует дату в `coupons.expiresAt`, `scanCoupon` ветка B отвечает `409 coupon_expired`). Раньше дата закрывала только продажу, а экраны подписывали её «Действует до». `couponOffers.perGuestLimit` (0/нет поля = без лимита; новый купон в iOS-форме — 1) — сервер считает покупки гостя в `bonusWallets/{uid}/offerBuys/{offerID}` в той же транзакции, сверх лимита — `409 limit_reached`.

**Один QR гостя.** Гость показывает только `AYANT-PTS:<uid>` («Мой QR» и экран карты штампов). `scanCoupon` сам направляет код туда, где у заведения лояльность: `AYANT-PTS` у заведения со штампами (без баллов) → штамп, `AYANT-CARD` своего заведения у заведения с баллами → баллы. Сканер хоста делает то же заранее (`GuestQR.route` в домене), чтобы показать ввод суммы или выбор карты. Сервер нужно задеплоить ДО релиза приложения: старый сервер на «Мой QR» у заведения со штампами отвечает `points_off`.

**Погашение баллов:** ретрай с тем же ключом отвечает сохранённым результатом ДО поиска награды (снятая/переоценённая награда больше не ломает повтор). Ответ несёт `receiptCode` (4 цифры, он же в `ledger`) и `redeemedAt` — экран «погашено» показывает их с живыми часами (`LiveRedeemStamp`), чтобы старый скриншот отличался от свежего. Курс денежной награды в режиме cashback не выше `20 / процент` (`effectiveMoneyRatio` ↔ `PointsMath.effectiveRatio`, `HostForms.applyPoints`): иначе «20% баллами + 1 балл = 5 сом» = 100% скидки. Android этого не знает и в превью покажет большую скидку, чем даст сервер.

**Уборка старых купонов** (`CouponStore.purgeLegacyOnce` v2, `scripts/purge-legacy-coupons.js`) удаляет только ПОГАШЕННЫЕ купоны до отсечки; действующий купон заведения не удаляется никогда. «Использовать купон» (купон без заведения) хранится локально в `san.coupons.usedLocally` — сервер о нём не знает, и снапшот иначе возвращал бы купон в активные.

**Три поля `couponOffers` заведению не принадлежат**, и это закреплено в `firestore.rules`: `soldCount` считает сервер при покупке (клиентская запись затёрла бы чужие покупки), `status` ставит модерация (иначе заведение одобряет себя само, как было бы с `venues`) — владелец может только вернуть купон в `pending`, а правка `cost`/`title`/`details`/`emoji`/`imageURL` у **одобренного** купона обязана это сделать (иначе правила отклоняют запись; с 2026-10-01), `ownerID` неизменен (смена = передача купона чужому аккаунту). `HostForms.couponOffer` держит ту же линию на клиенте: сохраняет `status`/`soldCount` при правке и не даёт опустить остаток ниже проданного.

**Баланс бонусов живёт НА СЕРВЕРЕ** (с 2026-09-30): `bonusWallets/{uid}` (`balance`, `lifetimeEarned/Spent`, `earnDay/earnedToday`) + `ledger`, `earnKeys`, `buyKeys`; правила — только чтение владельцем. Три функции (`functions/src/index.ts`, секция 9), все идемпотентны по ключу клиента:
- **`bonusWalletSync`** — заводит кошелёк, ОДИН раз перенося баланс устройства с потолком `BONUS_MIGRATION_CAP` (1000), и зачисляет незабранные `bonusGrants` (рефералка; `rewardReferral` пишет и грант `welcome_{invitee}` приглашённому — клиент с кошельком больше не начисляет его сам).
- **`earnBonus`** — игры и время. Проверить игру сервер не может, поэтому потолки: `BONUS_EARN_MAX_PER_CALL` (100) и `BONUS_DAILY_EARN_CAP` (**200** в сутки по Бишкеку ≈ 3 ч игры при `minutesPerBonus = 1`; было 1000 — по аудиту 2026-10-01 это три купона в день с каждого аккаунта-фермы). Это НЕ дневной лимит игр из «Loyalty & bonus systems» — тот убран намеренно. Ответ несёт `capReason` (`"daily"` — общий потолок, сегодня не платит ничто; `"source"` — потолок этой игры/времени; `"per_call"` — не потолок дня; `null` — не урезано), `dailyLeft` и `sourceLeft` (`null` — у источника нет потолка); клиент **не угадывает** чей потолок по имени источника (угадывание осталось только как запасной путь для сервера без `capReason`). На iOS общий потолок и потолки источников персистентны **раздельно** (`san.bonus.serverGlobalCapDay` / `san.bonus.serverCappedSources[Day]`): раньше один ключ на всё превращал потолок Diamond после перезапуска в запрет для всех игр. Источники — **закрытый список** `BONUS_EARN_SOURCES` (`time`, `game`, `game:snake|tetris|2048|diamond`; иное → `400 bad_source`): раньше потолок Diamond обходился подписью `game:x`. **Новая игра = новая строка в этом списке**, иначе её начисления отклоняются. Свои потолки в сутки: `time` 4, `game:diamond` 30 (`BONUS_SOURCE_DAILY_CAPS`). Все env-потолки прижаты сверху (`clampedCapFromEnv`): `BONUS_DAILY_EARN_CAP` ≤ 2000, `BONUS_TIME_DAILY_CAP` ≤ 100, `BONUS_DIAMOND_DAILY_CAP` (новый, по умолчанию 30) ≤ 500, `REFERRAL_REWARD`/`REFERRAL_WELCOME` (по умолчанию 100) ≤ 1000 — лишний ноль в `functions/.env` не снимает потолок.
- **`buyCoupon`** — купон заведения (`couponOffers`) или награда каталога (в т.ч. подарком → `giftCoupons`). Одна транзакция: доступность (как `CouponOffer.isAvailable`) → баланс → списание → `soldCount` → купон в `coupons`. Цена — только из серверных данных.

Клиент: `BonusWalletService` (домен) ↔ `FirebaseBonusWalletService`; в мок-режиме `nil`, и `BonusEngine`/`CouponStore` считают локально, как раньше (на этом стоят `BonusEngineTests`). С кошельком `BonusEngine.balance` — только отражение: подтверждённое сервером + очередь неотправленных начислений (`san.bonus.pendingEarns`, ключ на начисление); `spend` и `addFromGame` ничего не делают. `CouponStore.buy/redeem/gift` держат ключ покупки до окончательного ответа. Очередь начислений — **по пользователю** (`san.bonus.pendingEarns.<uid>`; ключ без uid забирает первый подключённый): выход без сети не стирает «+N», оно дойдёт при следующем входе того же человека; дневные счётчики тоже снимаются под uid при выходе. Ничего из очереди не выбрасывается молча: `app_check_failed` / `anonymous_not_allowed` держат её и выставляют `BonusEngine.syncProblem` (экран просит обновиться / войти), сбои — повтор с паузой 2…300 с (до 6 раз сами), застрявшее начисление уходит в конец очереди. Итог захода в игру в хабе — `BonusEngine.sessionEarned` (по ответам сервера), а не разница счётчиков. Тесты: `functions/test/bonusWallet.test.js`, `SANTests/BonusWalletTests.swift`. **Правило `coupons`**: клиент создаёт только непривязанные купоны (`venueID == ''`) — привязанный к заведению купон создаёт лишь сервер (раньше любой клиент мог записать купон с чужим `venueID`). **Android не портирован**: он всё ещё считает бонусы на устройстве и не видит серверный кошелёк.

**Клиент кошелька (аудит 2026-10-01):** `BonusEngine` держит **поколение кошелька** (`walletGeneration`) и сверяет его после каждого `await` в `flush`/`syncWallet` — выход посреди запроса больше не роняет приложение (`removeFirst` на пустой очереди) и не переносит баланс/гранты A в кошелёк B; очередь чистится по ключу. Сервер зачислил меньше запрошенного → `earnNotice` (`EarnNotice{requested,granted,source}`, снимает `clearEarnNotice()`), общий потолок → `serverDailyCapReached` (до смены суток по Бишкеку / `resetForNewUser`), и тогда `awardGameplay` возвращает 0 и ничего не ставит в очередь; урезанный `time`/`game:diamond` считается потолком источника и другие игры не останавливает. Отказ навсегда пересчитывает баланс. Подряд идущие **неотправленные** начисления одного источника сливаются (≤ 100) — отправленное не сливается никогда, его ключ мог сработать. `bonusWalletSync` — один раз за сессию в `attach`; `retryPending` (выход на передний план) досылает только очередь. Любой 5xx (`buy_failed`, `earn_failed`, `redeem_failed`, без тела) — как обрыв сети: ключ сохраняется. Ключи покупок (`san.coupons.purchaseKeys.<uid>`) и списаний баллов (`san.points.redeemKeys.<uid>`) лежат в UserDefaults и переживают убийство приложения; повтор `buyCoupon` (`replayed`) не применяет устаревший баланс. `CouponStore`/`PointsStore`/`LoyaltyStore` отбрасывают ответы, пришедшие после смены uid; `PointsStore .stop` стирает состояние. Первое начисление в новом заведении / первый штамп на новой карте тоже поднимают экран «Начислено» (раньше карту без прошлого снимка пропускали). `CouponStore.shopLoadFailed` — витрина не загрузилась (экран «нет связи», а не «пусто»). Тесты: `SANTests/BonusEngineSafetyTests.swift`.

**Защита кошелька от фарма (аудит 2026-09-30) — не ослаблять:** анонимные токены функции кошелька отклоняют (`403 anonymous_not_allowed`: анонимный вход доступен любому скрипту); перенос баланса устройства — только аккаунтам, созданным до `BONUS_MIGRATION_CUTOFF` (2026-10-01, Бишкек), иначе каждая регистрация = 1000 бонусов; у источника «game:diamond» серверный потолок 30/сутки (`BONUS_SOURCE_DAILY_CAPS`), игры шлют свой `source` (`game:snake|tetris|2048|diamond`). Подарки: создаёт `buyCoupon`, забирает `claimGift` (сервер создаёт купон с заведением); правила `giftCoupons` — только `get` по коду, `list`/запись закрыты. `couponOffers`: заведение купона должно принадлежать владельцу (правила на create + проверка в `buyCoupon`), `venueID` при правке не меняется. Ночной `reconcileBonusWallets` сверяет `balance == Σ ledger.amount` и шлёт `ALERT wallet_mismatch` / `wallet_cap_hit`. **App Check:** iOS шлёт `X-Firebase-AppCheck` во все вызовы функций с 2026-10-01 (`AyantData/.../AppCheckSupport.swift`: DeviceCheck в релизе, debug-провайдер в отладке; `AyantAppCheck.install()` — до `FirebaseApp.configure()`). Раскатка: зарегистрировать DeviceCheck-ключ в Firebase Console → `APPCHECK_MODE=monitor` → смотреть логи `app-check missing/invalid` → `enforce`. **Android заголовок не шлёт** — `enforce` отрежет Android-хостам `scanCoupon`/`redeemVenuePoints`; и не включайте enforcement Firestore в консоли, пока не портирован Android. Без App Check потолки `earnBonus` остаются единственной защитой от скрипта с настоящим (не анонимным) аккаунтом.

**Рефералы (аудит 2026-10-01):** `rewardReferral` платит только если приглашённый и пригласивший — настоящие (не анонимные) аккаунты, приглашённому не больше 30 дней (`REFERRAL_MAX_INVITEE_AGE_MS`), а потолок 20 держит счётчик `referralCounts/{referrerID}` в транзакции (раньше — запрос без транзакции, пачка рефералов разом его проходила). Отказ пишется в `referrals/{id}.rejected`. Правило `referrals` тоже отсекает анонимов.

**Заведения — модерацию себе не ставят:** правила `venues` пускают создание только со `status: "pending"` и без `isVerified`/`boostedUntil`/счётчиков; при правке владелец может вернуть на модерацию и снять `isVerified`, но не одобрить, не верифицировать, не продвинуть себя и не тронуть `rating`/`reviewCount`/`ratingHistogram`/`savedByCount`. Нет поля `status` = «одобрено» (старые записи сида), поэтому сохранение их со `"approved"` не повышение.

**Cooldown constants** live in `functions/src/index.ts`: `DEFAULT_STAMP_COOLDOWN_MIN=15`, `DEFAULT_EARN_COOLDOWN_MIN=60`, `DEFAULT_EXPIRY_MONTHS=6`, `MAX_CASHBACK_PERCENT=20`, `MAX_POINTS_PER_EARN=10000`.

**Global app settings live in one Firestore document, `config/appSettings`, edited on the admin panel's «Настройки» page.** Fields: `stampCooldownMinutes` (stamp cooldown, `0` = no cooldown, clamped 0…1440, absent → 15) and `adPlaceholderText` (the «Здесь может быть ваша реклама» watermark on the Snake board; empty → the localized default). `scanCoupon` reads the cooldown through `loadAppSettings()` with a 60-second per-instance cache and `intOrDefault` (explicit zero preserved); both clients load the document into `AppStore.settings` / `AppViewModel.settings` (domain model `AppSettings`, field constants in `FS.AppSettingsDoc`, `DataRepository.fetchAppSettings()`). The old `STAMP_COOLDOWN_MIN` env override is gone on purpose — a forgotten `=0` in `functions/.env` was how a test setting leaked toward production; change the value in the panel instead, and never leave `0` there outside a test session. The watermark text is fitted to the board on both platforms (word-wrap, then shrink), so any length is safe.

**Points math is mirrored on the clients and pinned by one shared fixture.** The server is authoritative, but both clients need the same arithmetic to preview a scan ("you'll get 100 points", "you're 20 short") — so `AyantDomain/Sources/AyantDomain/PointsMath.swift` and `android/.../data/PointsMath.kt` reimplement award / cooldown / redeem, and `specs/fixtures/points-fixtures.json` is executed by **all three**:

| Runner | Command |
|---|---|
| iOS | `swift test --package-path AyantDomain --filter PointsFixtureTests` |
| Android | `./gradlew :domain:test --tests "kg.ayant.app.domain.PointsFixtureTest"` |
| Functions | `cd functions && npm test` (drives the real `scanCoupon` / `redeemVenuePoints`) |

A new case goes **in the JSON**, never in one platform's test file — a case that runs once proves nothing about drift. One deliberate exception: `redeemRatio` (the cashback ratio cap, `effectiveMoneyRatio` ↔ `PointsMath.effectiveRatio`) is a separate top-level key run by iOS + Functions only, because Android's `PointsMath.kt` has no `effectiveRatio` yet; port it, then wire `redeemRatio` into `PointsFixtureTest.kt`. The error strings in `expect.error` are the server's own `{"error": ...}` codes; `PointsError.code` returns them verbatim on both clients.

One server behavior is deliberately mirrored even though it looks like a bug — do not "fix" it on one side only: cashback rounds **half-up** (JS `Math.round`), which is why `PointsMath.kt` uses `floor(x + 0.5)` rather than `kotlin.math.round` (ties-to-even).

`earnCooldownMinutes: 0` means **no cooldown** (earn on every scan), as does any negative value; the 60-minute default applies only when the field is absent or non-numeric. This used to be the opposite — `parseInt(x) || 60` treated the falsy `0` as "not set", so 0 silently meant 60 and only a negative value disabled the cooldown — and both clients + the fixture mirrored that quirk on purpose. It is fixed everywhere now (`intOrDefault` in `functions/src/index.ts`, `PointsMath.effectiveCooldownMinutes` on both clients, the admin panel's save path). The sibling reads `venue.loyaltyGoal` and `venue.pointsExpiryMonths` still use `|| default` **on purpose**: `0` is not a meaningful value for either (their floors are 2 visits / 1 month), so zero is better read as "not configured" — see the comments at those two call sites.

**Auditing the money paths.** `.claude/agents/bonus-audit.md` defines a read-only `bonus-audit` subagent that runs the three fixture runners plus the functions tests and cross-checks constants, `FS` field names, rules, idempotency ordering and the coupon lifecycle across all four surfaces. Run it (Agent tool, `subagent_type: bonus-audit`) after touching anything in this section and before `firebase deploy`.

**Live updates are snapshot listeners — do not reintroduce polling.** Stamps and points change server-side when a business scans a QR, and the customer client sees it immediately: `venuePoints` and `loyaltyCards` are read through `addSnapshotListener` / `callbackFlow`, and the listener is removed when its consumer is cancelled (`continuation.onTermination` on iOS, `awaitClose` on Android). The old `sleep(4s)` / `delay(4000)` loops are gone from both apps; if you find yourself adding one, add a listener instead. Note: a customer only reads `venuePoints`/`coupons` if the **Firestore rules are deployed** — a missing rule silently returns nothing (deploy `firestore:rules`, not just `functions`).

**Every money-path callable is idempotent.** Both `scanCoupon` (earn a stamp / earn points) and `redeemVenuePoints` (spend points) accept an `idempotencyKey` that the client generates **once per scanned QR / per redeem attempt** and reuses on retry. The outcome is stored in the same transaction — `scanKeys/{key}` under the card for scans, `redeemKeys/{key}` for redeems — and replayed instead of applying the mutation twice (response carries `replayed: true`). The key is checked **before** the cooldown: otherwise a retry inside the 15/60-minute window would get a `429` instead of the original result, which is exactly the case the key exists for. In `scanCoupon` it is checked even **before the QR rewrite and every config check** (`earlyScanReplay`: looks under both the stamp card and the points card of that guest at that venue), so a retry after the venue switched mechanics, disabled loyalty/points, changed mode (`missing_amount`) or disabled a card still gets its original answer (`functions/test/moneyPathRetries.test.js`). A different key inside the window still hits the cooldown, so accidental rescans are still blocked. Rules deny clients any access to `scanKeys`/`redeemKeys`.

**`citySlug` is a partition key, not decoration.** `Venue`, `Deal` and `Review` all carry it (Firestore field `city`), currently always `"bishkek"`. It exists so multi-city isn't a retrofit into a live catalog — **set it on any new model and any new write**, even though nothing reads it yet.

**Writing Cloud Function tests: the fake Firestore converts `Date` → Timestamp on write**, exactly like the real SDK (`test/helpers/fakeFirestore.js`, pinned by `test/fakeFirestore.test.js`). This matters because `toMillis()` in `index.ts` returns 0 for anything without a `toMillis` method — with a naive fake, *every* cooldown is silently disabled in tests and a "repeat is blocked" test passes while proving nothing. `harness.seed()` normalises the same way, so seeded documents read back like real ones.

**Nightly integrity checks (`reconcileVenuePoints`).** Following the project's "alerts instead of tests" trade-off, one scheduled pass over `venuePoints/{card}/ledger` covers three things a test can't: `balance == sum(ledger.points)` (a mismatch is money lost or double-issued), a heartbeat check that `expireVenuePoints` actually ran in the last 26 h, and per-venue issuance more than 3× its trailing 7-day mean (a "50% cashback" typo or staff abuse). Alerts go to `ops/alerts/items/{auto}` *and* to Cloud Logging with an `ALERT <kind>` prefix — configure the log-based alerting policy on that prefix. `ops/**` is admin-read, function-write-only.

**Nightly jobs, hardened 2026-10-01.** All nightly passes run with `NIGHTLY_JOB` (540 s timeout — the 60 s default would make them die silently as data grows). `reconcileVenuePoints` and `reconcileBonusWallets` each write a heartbeat and check the other's (plus `expireVenuePoints`) → `job_stale`. A venue with no 7-day history issuing more than `NEW_VENUE_DAILY_ISSUANCE_ALERT` (5000) points in a day raises `issuance_new_venue` (the ×3 spike rule can't see new venues). `wallet_cap_hit` looks at today AND yesterday (Bishkek), since the wallet keeps only the last earn day's counter. `expireVenuePoints` re-checks `lastActivityAt` inside the transaction, so points earned between the query and the write aren't zeroed.

**Rules hardening, 2026-10-01:** a venue owner may change only `hostReply` on a review (not rating/text/author), an author can't move a review to another venue or change `authorID`; `userTokens` can be written only with your own `uid` (or none) and deleted only if yours; `redemptions` are accepted only for a real deal of that venue (`countRedemption` re-checks). `scanCoupon` branch B looks the coupon up by `code` **and** `venueID` first, so a client-planted unbound coupon with someone's code can't shadow the real one. Since 2026-10-01 the author also can't write `hostReply` or `verifiedVisit: true` on create, nor change either on update (`Review.firestoreData` no longer sends them — the verified-visit badge needs a server-side setter now); the iOS host app's venue update (`FirebaseHostRepository.saveVenue`: `updateData`, falling back to a create on `notFound`) no longer sends `status`/`isVerified`/`boostedUntil` — only a create does (`pending`/`false`) — and `saveProfile` sends `verification` only on create or as a `pending` request when the server has `none`/`rejected`, so a stale cabinet copy can't undo moderation, verification or a paid boost. All checked against the emulator (no committed rules test suite yet).

**Key reuse is a collision, not a retry.** The same key sent for a *different* reward (or a different QR) → `409 key_reused`. Keep the key stable across retries of one attempt and fresh for a new one — `PointsStore`/`PointsViewModel` hold it until the attempt succeeds; the host scanners mint one per decoded QR.

## Instagram → акции (импорт постов)

Заведение подключает свой инстаграм в кабинете, жмёт «Синхронизировать», выбирает пост — и попадает в обычную форму акции с заполненными заголовком, описанием и фото. Отдельного типа контента нет: импорт создаёт **черновик `Deal`** обычным путём (`HostRepository.saveDeal`), то есть не проходит мимо правил владения.

**Четыре вещи, которые ломаются молча — прочитайте до правок:**

1. **Личные аккаунты не подключаются в принципе.** Basic Display API закрыт Meta 4 декабря 2024-го; работает только *Instagram API with Instagram Login* и только для профессиональных аккаунтов (Business/Creator). Экран предупреждает об этом до кнопки входа.
2. **`media_url` с CDN инстаграма протухает за часы.** Поэтому `instagramImportMedia` перезаливает фото на Cloudinary (тот же аккаунт, что у iOS и админ-панели) и отдаёт клиенту постоянные ссылки. Положить ссылку Meta прямо в акцию — получить каталог с битыми фото назавтра. Это закреплено тестом (`functions/test/instagram.test.js`) и в `HostStoreTests`.
3. **Токен не покидает сервер.** `igAccounts/{ownerID}_{venueID}` закрыта правилами целиком (`read, write: if false`); клиент читает только `igConnections/{...}` — имя аккаунта, дату, `needsReauth`, `lastSyncAt` — снапшот-листенером (`FirebaseInstagramService.connection`), без опроса. `igAuthStates/{nonce}` — одноразовый `state` OAuth, тоже закрыт.
4. **Длинный токен живёт 60 дней.** `refreshInstagramTokens` (раз в сутки) продлевает всё, чему осталось меньше 10 дней; провал ставит `needsReauth`, и кабинет показывает «войдите заново» вместо пустого списка.

**Функции** (`functions/src/index.ts`, секция INSTAGRAM): `instagramAuthStart` → `instagramAuthCallback` (публичная, редиректит в приложение по `san://ig/connected`) → `instagramMedia` (кнопка «Синхронизировать») → `instagramImportMedia` → `instagramDisconnect`, плюс `refreshInstagramTokens` и обязательные для App Review `instagramDeauthorize` / `instagramDataDeletion` (проверяют `signed_request` HMAC-подписью).

**Конфигурация:** `INSTAGRAM_APP_ID`, `INSTAGRAM_REDIRECT_URI`, `INSTAGRAM_RETURN_URL` в `functions/.env`; `INSTAGRAM_APP_SECRET` — в Secret Manager (`firebase functions:secrets:set INSTAGRAM_APP_SECRET`). Redirect URI в приложении Meta должен совпадать с URL `instagramAuthCallback`.

**Дедупликация:** `HostDealDTO.sourcePostID` (поле Firestore `igPostId`) — по нему кабинет помечает пост «Добавлено». `HostForms.deal` сохраняет связь при правке, как и `startDate`; потеря связи означает предложение импортировать тот же пост второй раз.

**Разбор подписи** — чистый `InstagramCaption.parse` в домене: первая строка → заголовок, остальное → описание, хвост из хэштегов отрезается. Правило, закреплённое тестами: **описание ничего не теряет** — обрезается только заголовок-витрина.

**Состояние фичи:** бэкенд готов и покрыт тестами; iOS-экран (`SAN/Host/HostInstagramView.swift`) виден во всех сборках — флага у него больше нет. **Пока приложение Meta не переведено в Live, подключиться могут только аккаунты из ролей приложения** (`ayant_kg`): у любого другого заведения вход закончится ошибкой «Insufficient Developer Role». Это осознанный компромисс ради TestFlight, а не недосмотр — если релиз в App Store случится раньше одобрения, экран стоит снова спрятать. **Android пока не портирован** — осознанное отставание, а не забытое зеркало.

## Host cabinet (iOS, 2026-09-29) — not mirrored on Android yet

Owner's call: this round is iOS-only. Tabs are Заведения · Лояльность · Сканер · Аналитика · Профиль — «Отзывы» is a row inside «Профиль» (with the unanswered badge, also on the tab), so the sixth tab no longer falls under «Ещё». «Объекты для отзывов» is now «Меню»; the «Сканировать купоны гостей» button is gone (the scanner is its own tab). Android still has the Отзывы tab, the old section layout and the scan button.

**Tab 1 is split into work vs settings (2026-09-30).** The venue page (`HostVenueDetailView`) holds only daily work: card → «Данные заведения», «Предложение дня», and three pinned sections Акции · Меню · Купоны, each with the same «primary + second way» buttons (Новая акция / Из Instagram, Блюдо / Из файла, Новый купон). Loyalty is **not** on this page any more — it lives only in the Лояльность tab (`HostStampCardFormView` was removed). Everything about the venue itself is on `HostVenueSettingsView` (`SAN/Host/HostVenueSettingsView.swift`): «Показывать гостям», Название и фото / Адреса / Часы / Телефон и соцсети / Прайс-лист, promotion, delete. Each row opens `HostVenueFormView(existing:part:)` showing only that part; hidden parts stay in the form state and are saved as they were, so editing hours never wipes addresses — keep `fields` built from **all** state. `part: nil` is the full form (venue creation). «Принимать купоны» was dropped from the form (deals no longer issue coupons); the value is preserved. Venue switching: with 2+ venues a labelled strip «Ваши заведения · N» (chips + «Все» sheet + «Добавить»); with one venue no switcher — the second venue is added from «Профиль → Заведения». The title is no longer a dropdown.

**Menu categories by hand.** `HostIntent.addItem(venueID:item:)` takes a whole `VenueItem` (section, price, description, photo), like `updateItem`; both go through one cleaner in `HostStore` that snaps the section to an existing spelling via `MenuImport.canonicalSection` (pinned by `MenuImportTests`) — the menu groups by exact string, so «супы» would otherwise become a second «Супы». The category is **chosen**, not typed: `MenuSectionPicker` (chips: «Без раздела», existing sections from `MenuImport.sections`, «+ Новый раздел»). Categories live only in `VenueItem.section`; there is no separate list, so a category with no dishes disappears. Each section header in «Меню» has «+ Добавить», which pre-fills that category.

## Меню из файла: PDF, Excel, CSV (iOS, 2026-09-29) — на устройстве, бесплатно

Хозяин выбирает файл меню → **`OnDeviceMenuParsingService`** (данные) разбирает его на телефоне → хозяин **проверяет и правит** черновик (`HostMenuImportView`, `MenuImportStore`) → `HostIntent.importMenu` сливает отмеченные блюда в `venues.items` через **`MenuImport.merge`**. Ни сети, ни ключей, ни Cloud Function: раньше PDF читала языковая модель (`parseMenuPdf`), её убрали по решению владельца ради нулевой стоимости — не возвращайте без его решения.

- **PDF**: `MenuPDFTextExtractor` — текстовый слой PDFKit, а если его нет или он битый — распознавание Vision (ru+en). **Распознавание идёт в два прохода** (3200 px и 2400 px с полями 6 %), берётся проход с бо́льшим числом букв: Vision на отдельных масштабах теряет первые буквы строк («hopped beef» вместо «Chopped beef») с уверенностью ≈ 1, и по confidence такой проход не отличить. Не «оптимизируйте» до одного прохода без проверки на реальных сканах.
- Разбор текста — **`MenuTextParser`** (домен, чистый): колонки по вертикальным коридорам (столбцы цен/граммовок приклеиваются к колонке слева) → строки → две вёрстки: «таблица» (`Название … 330 г 450`, перенос названия, состав ниже) и «карточки» (НАЗВАНИЕ / описание / `35 cm 820 som`). Цена — **`MenuPrice`**: «350 г», «0,5 л», «Service 15%», «24/7», «2024» — не цены; «1 200», «720/1220», «90/180KGS» — цены. Варианты «with chives» под «CHEBUREKS» становятся «Chebureks with chives». Повторы 3+ раз (пометки, колонтитулы), телефоны, бейджи — шум.
- **Excel/CSV**: `MenuXLSXReader` (данные; свой мини-ZIP + Compression + XMLParser, скрытые листы пропускаются, .xls не поддерживается) и `MenuTable` (домен): столбцы по заголовку RU/EN/KY или по содержимому, строки-разделы, CSV с угадыванием `,`/`;`/таб и cp1251.
- Правила закреплены `MenuTextParserTests`/`MenuTableTests` на вёрстке реальных меню (ZERNO, NAVAT, FRUNZE). **Новая вёрстка, которую парсер читает неверно, — новый тест там**, а не правка наугад: у каждого правила есть меню, которое оно чинит, и меню, которое оно может сломать. Проверочный стенд на Mac собирается из исходников домена + `MenuPDFTextExtractor.swift` + `MenuXLSXReader.swift` (оба без Firebase намеренно).
- `merge` не удаляет и не переименовывает: совпавшее по названию блюдо сохраняет id (к нему привязаны отзывы), фото и эмодзи. Цена — целые сомы, `nil` = «не указана».
- Поля `VenueItem` `price`, `details` (Firestore `description`), `section` — в `FS.ItemField`. **Android пишет `items` только своими пятью полями**: сохранение заведения из Android-кабинета сотрёт цены/описания/разделы.

## Адреса заведения и акции «только по адресу» (iOS, 2026-09-30) — Android не портирован

У заведения больше нет «главного адреса» и «филиалов» — только **список адресов** (`VenueLocations`, домен). Схема Firestore прежняя: первый адрес — поля `address`/`latitude`/`longitude` заведения (id всегда `VenueLocations.firstID = "main"`), остальные — `branches`. Экраны читают только `Venue.locations` / `HostVenueDTO.locations`. Кабинет правит все адреса одним списком «Адреса» (первый не удаляется).

Акция может действовать не во всех адресах: `deals.locationIDs` (`FS.DealDoc.locationIDs`, массив id адресов; нет/пусто — везде). Читать только через `Venue.locations(for:)` — он прощает удалённые адреса (акция, чей адрес удалили, становится «везде», а не пропадает). Гость видит «Действует только по адресу …» на странице акции и чип в ленте. Правила закреплены `DomainVenueLocationsTests`. **Android `locationIDs` не читает** — там такая акция выглядит действующей везде.

## Release flags (iOS)

`SAN/ReleaseFlags.swift` holds the switches for surfaces that are built but hidden in the shipped app: `searchTab`, `globalBonusWallet`, `referrals`, `promote`, `appleWallet`, `couponShopPurchase` (the «Купоны за бонусы» shop on the guest venue page is always shown; this flag enables only the «Обменять» button — on since 2026-09-30, backed by the server wallet `buyCoupon` — requires deployed functions + rules). Each is a `static let` gating the UI entry points only — the stores, models and backend paths stay compiled and tested. Flip one on only when its prerequisite is real (payment for promote, a real pass type ID for Wallet, a tested map screen for search). Android has no equivalent yet; the Android app still shows all of these.

**Remote kill switches + forced update (2026-10-01).** Every flag above is now «on in the build **AND** not switched off in Firebase Remote Config» — key `ios_<flag>_enabled` (Boolean, default true), plus `ios_instagramImport_enabled` / `ios_menuImport_enabled` for the two host imports. Remote can only switch **off**: a feature hidden in the build (`promote`, `appleWallet`) cannot be opened from the console. Flags are **live**: `ReleaseFlags` reads an `@Observable` `RemoteFlagsStorage`, so any screen that read a flag in its `body` re-renders when the value changes — no call-site changes needed, but read flags in `body`, not cached in `@State`/`init`. Values come from the cache at launch, then from `refresh()` (launch + foreground, release fetch interval 1 h) and from the **real-time listener** (`addOnConfigUpdateListener` → `RemoteSettingsStore.listen()`), so a publish reaches an open app within seconds. (Until 2026-10-01 flags were read once per launch and took effect only on the next cold start — that looked like «the switch doesn't work».) Per-game earning switches `ios_bonus_<snake|tetris|diamond|2048>_enabled` (`BonusGame`) are checked inside `BonusEngine.awardGameplay` and apply **immediately** after a fetch (the game stays, it just stops paying and shows a notice; a paused Diamond does not consume its daily cap — pinned by `BonusEngineTests`). `BonusGame.source` is the same string the server caps by (`BONUS_SOURCE_DAILY_CAPS`) — don't rename. Per-game daily limits `ios_bonus_<game>_daily_cap` (Number) go through the same choke point: positive = limit, 0/negative/absent = no limit, **except Diamond** (endless) where those fall back to `GameEconomy.endlessDailyBonusCap` = 30 (`BonusCaps.effective`, pinned by `RemoteConfigTests`). Counters are per game in `san.bonus.earnedTodayByGame` (Diamond's old `san.bonus.endlessEarnedToday` is read once as today's carry-over); `awardEndlessGameplay`/`remainingEndlessToday` are gone — use `awardGameplay(source:)` + `remainingToday(_:)`. A client limit above the server's (`BONUS_SOURCE_DAILY_CAPS`, `BONUS_DAILY_EARN_CAP`) changes nothing. The full console template is `remoteconfig.template.json` — **documentation only, deliberately NOT wired in `firebase.json`** (since 2026-10-01): deploying a template replaces the whole Remote Config, including a switch flipped in the console during an incident, and a bare `firebase deploy` used to do exactly that. Edit values in the console; if you really need to push the template, add the `remoteconfig` target temporarily and copy console changes into it first. `ios_bonus_time_enabled` (Boolean, default true) is the kill switch for time-in-app earning (`RemoteSettings.timeEarningPaused` → `BonusEngine.setTimeEarningPaused`: the timer stops, no `time` earns, games unaffected, reminder cancelled). `ios_globalBonusWallet_enabled = false` now also **stops the engine** (`SANApp.startBonusIfAllowed` doesn't attach/start; `RemoteSettingsEffects` pauses it and refreshes the reminder on change). The reminder is cancelled for guests, on sign-out and when the wallet is off; `NotificationManager.refresh` takes `now` from the caller (`bonus.now`), and `reachedGoalToday` uses the injected clock and the Bishkek day. `ios_min_version` (String) is different: `RemoteSettingsStore` re-checks it after every fetch and shows the blocking `AppUpdateRequiredView` immediately; `ios_update_url` is the button target (empty → App Store search — put the real `apps.apple.com/app/id…` link there). An empty or malformed minimum never blocks anyone (`AppVersion`, pinned by `RemoteConfigTests`). Layers: contract + rules in `AyantDomain/.../RemoteConfig.swift`, `FirebaseRemoteConfigService`/`MockRemoteConfigService` in `AyantData`, store in `AyantFeatures` (`RemoteSettingsStoreTests`). Key names are a contract with the console — don't rename `RemoteFeature` cases.

**Crashlytics.** Release builds upload dSYMs in the «Upload dSYMs to Crashlytics» build phase (skipped for Debug, so CI and simulator builds don't wait on it); Debug builds don't send crash reports at all (`setCrashlyticsCollectionEnabled(false)` in `SANApp.init`), so the crash-free rate reflects real users only.

`globalBonusWallet` is **on** (games, «БОНУСЫ» capsule, rewards catalog, gifting). The old `wrong_venue` gap is closed: catalog rewards without a partner venue are dropped by the client and refused by `buyCoupon`, and gifts are created server-side with a venue (`claimGift`).

**Game economy is remote-configurable (iOS, 2026-10-01).** Every rate games and in-app time pay comes from `GameRates` (domain, `GameEconomy.swift`), filled from Remote Config keys `GameRates.Key` (`ios_bonus_minutes_per_bonus` anchor, `ios_bonus_snake_apples_per_bonus`, `ios_bonus_tetris_lines_per_bonus`, `ios_bonus_diamond_matches_per_bonus`, `ios_bonus_2048_first_tile`, `ios_bonus_time_goal_minutes|reward|goals_per_day`; documented in `remoteconfig.template.json`). 0/garbage/absent = built-in value, out-of-range values are clamped (`GameRates.resolve`, pinned by `GameRatesTests`): the anchor to 0.25…60 minutes, the «2048» first tile to powers of two 64…2048 (lower turns restarts into a farm). `BonusEngine.gameRates` is applied the moment Remote Config loads; each game snapshots it at the start of a round. The server still caps independently: `BONUS_DAILY_EARN_CAP` (200), `BONUS_TIME_DAILY_CAP` env (4) for `time` — raise it together with the time keys. The bonus reminder push is once a day at 18:00, and its text is built from the live rates (it used to promise «+50» every 4 hours). `BonusEngine` day counters follow Bishkek time, like the server. With the server wallet, `BonusEngine.syncingAmount` is earned-but-unconfirmed (offline queue) and `spendableBalance` excludes it — the shop decides «can buy» from `spendableBalance`. Snake pays per full batch of apples during the round, not only at game over.

**Words: «бонусы» = only the global wallet, «баллы» = only per-venue points** (UI, FAQ, admin panel, feed chip «+5% баллами»). Keep them apart in new copy.

## Conventions

- Comments and doc-strings are frequently in **Russian** — match the surrounding language of the file.
- SharedPreferences/UserDefaults keys are load-bearing (existing installs depend on them) — don't rename them when refactoring persistence.
- Android persists host data via `kotlinx.serialization` to SharedPreferences; on-disk format differs from any older `org.json` layout, so decode failures degrade to empty rather than crash.

## Archive (iOS)

`ENABLE_USER_SCRIPT_SANDBOXING = NO` on the **SAN target** (Debug + Release): the «Upload dSYMs to Crashlytics» run-script phase calls the Firebase SDK's `Crashlytics/run` from `SourcePackages`, which the user-script sandbox blocks, failing the archive. The project-level setting stays `YES`.

## Launch hardening (2026-10-01) — security, crashes, App Store, data

Result of the pre-ads launch audit. Server parts are deployed; iOS parts ship with the next build. **Android is not mirrored for any of this** (review ids, redeem token, userLibraries, content filter, push consent…).


### Redeem token (replaces uid-in-QR) — Баллы САН
- The staff-scan redeem QR is now `AYANT-RDT:<token>` (`RedeemQR.tokenCode/parseToken/scan`). The token comes from the new HTTPS function `issueRedeemToken` (body `{venueID, rewardId, pointsToSpend}`; non-anonymous, App Check; checks reward + balance as a preview). It is stored in `redeemTokens/{token}` `{uid, venueID, rewardId, points, cost, used, createdAt, expiresAt}`, lives **3 minutes** (`REDEEM_TOKEN_TTL_MS` / `RedeemQR.tokenTTL`) and is closed to clients by the rules.
- `redeemVenuePoints` with `token` (owner path only): the card's uid, the reward and the points are taken **from the token, never from the request**. The idempotency key is `rdm_<token>`, and replay is checked **before** expiry and used, so a retry after expiry still gets the original answer with `replayed: true`. In the transaction: `token_used` / `token_expired`, then the token is marked used. Other errors: token for another venue → `409 wrong_venue`; unknown token → `404 token_not_found`; non-owner → `403 not_owner`.
- The legacy uid QR (`AYANT-RDM:`) still works while env **`REDEEM_REQUIRE_TOKEN`** is not `"true"` (default `"false"`, so old guest builds keep working). **Flip it to `"true"` in `functions/.env` once the token build is the minimum supported version.** After that, the old path returns `400 token_required`. `customerInitiated` (guest redeems themselves) is not affected.
- iOS guest (`RedeemSheet`): `RedeemTokenStore` (in `PointsStore.swift`) requests a token when the QR is shown and again when the amount changes. It refreshes the token `RedeemQR.refreshLead` (20 s) before expiry and stops on close or once staff redemption is detected. The countdown reads «Код обновится через N с». Offline shows `failed(.network)` with a message and a Retry button. A 404 with no error body (function not deployed yet) maps to `not_deployed` and shows the legacy QR instead.
- `CouponService.issueRedeemToken` / `redeemVenuePoints(venueID:token:idToken:)` have protocol-extension defaults: mock mode gets a local token, and redeeming by token returns `not_supported`. Only `FirebaseCouponService` implements them for real.
- **Android is not ported**: it still shows the uid QR and its scanner doesn't know `AYANT-RDT:`. Port it before flipping `REDEEM_REQUIRE_TOKEN`.
- Set a Firestore TTL policy on `redeemTokens.expiresAt`, e.g. `gcloud firestore fields ttls update expiresAt --collection-group=redeemTokens --enable-ttl`.

### Firestore rules (launch audit 2026-10-01)
- `deals`: create requires `isVenueOwner(venueID)` (plus `ownerID == uid`). Update pins both `venueID` and `ownerID`.
- `hosts/{uid}`: readable only by the owner or an admin. No guest code reads other hosts' profiles; guests see verification as `venues.isVerified`.
- `reviews` create:
  - non-anonymous only (`isRealUser()`);
  - doc id must be `{uid}_{venueID}_{itemID}`, or `{uid}_{venueID}_venue` when `itemID` is missing or empty;
  - `rating` int 1…5, `text` ≤ 2000, `authorName` ≤ 60, `photos` ≤ 6, `photoEmojis` ≤ 6;
  - the venue must exist.
  
  Author updates go through the same field validation.
- `rankingEvents`: `userID == uid()`, `items` ≤ 30.
- `analyticsEvents`: `venueID` is a 1…128-char string, `metric` must be in the allow-list, and only the keys `venueID`, `metric`, `createdAt` are allowed.
- `reviewReports`: `reviewID` must match `^[A-Za-z0-9_-]{1,120}$`.
- `pushCampaigns`:
  - create: venue owner only, with status `pending`, `delivered` false, headline ≤ 120, body ≤ 400;
  - read: the owner or an admin.
  
  **Android hosts without a Firestore-synced venue can no longer queue campaigns.**
- `userTokens`: create and update both require `uid == caller`; uid-less docs are gone. **Clients should pass the Firebase auth uid (including anonymous) to `registerToken`.** Today iOS passes `session.user?.id`, so guests without a session no longer get a token doc. Those devices are still reachable through the `all_users` topic fallback.
- URL fields — `venues.imageURL`, `venues.pdfMenuURL`, `deals.imageURL`, `couponOffers.imageURL` — must be empty, null or `https://…` (no spaces, ≤ 2048). On update only a changed field is checked, so legacy `http://` data doesn't block other edits. Not covered: `deals.imageURLs[]` and `venues.items[].imageURL`, because rules can't loop.
- `redeemTokens/*` and `pushThrottle/*` are server-only.
- `analytics/{venueID}/**` is already `write: if false`; counters are function-written only.

### Functions changes
- `notifyOnNewDeal` pushes only when all of these hold:
  - `deal.ownerID == venue.ownerID`;
  - the venue is approved (no status = approved) and not paused;
  - the deal is active.
  
  At most one push per venue per 24 h, tracked in `pushThrottle/deal_{venueID}`. Title is capped at 60 characters, body at 140.
- `notifyHostOnReview`: at most `REVIEW_PUSH_DAILY_CAP` = 10 pushes per venue per day (`pushThrottle/review_{venueID}`).
- `recomputeVenueRating`: five `count()` aggregates (one per star) instead of reading up to 3000 reviews. No 3000-review cap any more.
- `deleteAccount`: venue owners no longer get a 409. Their venues get `status: "pending", isPaused: true, ownerDeleted: true, ownerDeletedAt`, and the venue data is kept. Their deals and couponOffers are deleted, matched by `ownerID` and by the venues' `venueID`. Also deleted:
  - `reviewReports` (reporterID), `pushCampaigns` (ownerID), `igAccounts`/`igConnections` (ownerID), `redeemTokens` (uid), `referralCounts/{uid}`;
  - unclaimed `giftCoupons` bought by the user (fromUserID).
  
  `rankingEvents.userID` is not indexed (fieldOverrides), so that query fails: it is now skipped with an `ALERT delete_account_ranking_events_skipped` log line instead of failing the whole deletion. **Follow-up:** index `userID` or pseudonymize ranking events.
- `sendPushCampaign`:
  - runs with 540 s and 512 MiB;
  - atomically moves the campaign `approved → sending` before sending, so a redelivered event or a retry can't double-send (a stuck `sending` is visible in the admin panel);
  - reads `pushLog` in `getAll` batches of up to 500;
  - waits for stale-token deletes.
- Email verification for money: `walletUser` covers `bonusWalletSync`, `earnBonus`, `buyCoupon` and `claimGift`. It returns `403 email_not_verified` for an email/password account with an unverified email created on or after env **`BONUS_VERIFY_CUTOFF`** (default `2026-10-02T00:00:00+06:00`). A stale `email_verified` in the ID token is re-checked against the Auth record. Apple and Google accounts count as verified.

  **Referral:** when the invitee is unverified, the referral is not rejected. It is marked `pendingVerification: true`, and `bonusWalletSync` completes it once the invitee is verified (`processReferral`).
- `signCloudinaryUpload`:
  - non-anonymous only, with App Check;
  - folders are an allow-list: `ayant/images`, `ayant/documents`;
  - `resourceType` is `image` or `auto`;
  - signs `folder` + `timestamp`, the client uploads to `/v1_1/<cloud>/<resourceType>/upload`;
  - returns `{cloudName, apiKey, timestamp, signature, folder, resourceType}`, or `503 not_configured` when unconfigured.
  
  The secret is in Secret Manager as **`CLOUDINARY_API_SECRET`**; **`CLOUDINARY_API_KEY`** (and optionally `CLOUDINARY_CLOUD_NAME`, default `dsb14gwxw`) go in `functions/.env`. `instagramImportMedia` re-uploads with a signed upload when configured and falls back to the unsigned preset otherwise.
- `countAnalyticsEvent`: up to 4 attempts with exponential backoff (`withRetry`); the trigger doc is deleted in `finally`. **Follow-up:** shard `analytics/{venue}/days/{day}`. The readers are iOS `FirebaseAnalyticsService.fetchStats/fetchDailyStats`, Android `AnalyticsService.kt` and the admin panel.
- `buyCoupon`: the catalog (`config/globalRewards`) and the offer's venue owner are read outside the transaction. The offer's `venueID` is re-checked inside it.
- `reconcileVenuePoints` / `reconcileBonusWallets`:
  - page through `orderBy(documentId)`, 300 per page;
  - ledger sums come from `AggregateField.sum` (plus `count()`);
  - issuance only reads a card's `ledger where at >= now-8d`, and only when `lastEarnAt` is recent.
- Every HTTPS function has `maxInstances` set: 20, or 10 for the Instagram functions. Money-path concurrency stays at 80.

### Tests
- `functions/test/launchA.test.js` (32 tests).
- The fake Firestore (`test/helpers/fakeFirestore.js`) now supports `count()`, `aggregate({sum,count,average})`, `orderBy(FieldPath.documentId())`, `startAfter`, `getAll`, `recursiveDelete` and Timestamp-aware range filters.
- The harness supports `unverifiedUsers`, `providers`, `staleTokens` and `deletedUsers`.
- iOS: `RedeemQRTests` (token format), `SANTests/RedeemTokenStoreTests.swift`.
- Rules: `scratchpad/rules-check-launchA.cjs`. The older harnesses were updated for the intentional changes: deterministic review ids, and uid-less `userTokens` now denied.

### Admin panel security (proposed CLAUDE.md addition, launch-fix B, 2026-10-01)

**The admin panel renders host- and user-written data in an admin session — treat it as hostile.** Venue/deal/coupon/points-reward fields come from hosts; `reviewReports.reviewID` comes from any signed-in user. Rules in `docs/admin/`:

- **Logic lives in `docs/admin/admin.js`** (ES module, Firebase SDK from gstatic). `index.html` has no inline `<script>` and no `on*=` attributes, and the page CSP (`<meta http-equiv>` + the same header in `firebase.json` for `/admin{,/**}`) has no `'unsafe-inline'` for scripts — an inline handler would simply not run.
- **Buttons carry `data-click|data-input|data-change="<action>"` + `data-id/-index/-field/-status/-type`**; three delegated listeners dispatch to the `ACTIONS` allow-list at the bottom of `admin.js`. A new button = a new `ACTIONS` entry. Functions are module-scoped (not on `window`).
- **Every `${}` in an HTML template goes through `escapeHtml()` (text + attribute safe) or `num()`**; URLs from data through `safeUrl()` (https only); doc ids from data through `isDocId()` (single path segment). `deleteReportedReview` reads `reviewID` from the loaded report, never from the DOM.
- Leaflet CSS/JS are pinned with SRI (cdnjs sha512). Bumping the Leaflet version means new `integrity` values.
- A new external host (CDN, API) must be added to the CSP in **both** places (meta + `firebase.json`), or it is blocked.
- Static check: `node <scratch>/check-admin-xss.mjs docs/admin` (no deps) — reports inline handlers, unescaped `${}` in HTML templates and unknown actions; must print 0 problems. (Consider moving it to `scripts/` + CI.)
- Hosting note: `firebase.json` hosting serves `web/`, not `docs/`; the admin headers there apply only if the panel is deployed under `/admin` on Firebase Hosting. On GitHub Pages only the meta CSP applies (no `frame-ancestors`/`X-Frame-Options` via meta) — `admin.js` refuses to run inside a frame as the fallback.

### Launch fixes C (iOS crashes / memory / performance) — notes for CLAUDE.md

- **Photos from Cloudinary are requested at display size.** `CloudinaryURL.sized(_:points:)` (`SAN/Services/CloudinaryImage.swift`) inserts `f_auto,q_auto,w_<px>,c_limit` after `/upload/` for `res.cloudinary.com` URLs (other hosts untouched, existing transforms not doubled). Width = points × 3, capped at 2000 px. `VenuePhoto`/`CoverImage`/`VenueAvatar`/`ItemThumb`/`GalleryImage` take a `points:` hint; a new raw `AsyncImage` on a Cloudinary URL should go through the helper too.
- **Uploads are downscaled with ImageIO off the main thread** (`ImageDownsampler.jpegOffMain`, 1200 px, scale 1). Don't go back to `UIImage(data:)` + `UIGraphicsImageRenderer` with the default format — its scale is the screen's, so "1200" became 3600 px.
- **Cloudinary uploads are signed first.** `ImageUploader.upload` asks `signCloudinaryUpload` (Bearer ID token + App Check; body `{folder, resourceType}`; folders `ayant/images`, `ayant/documents`) and posts `api_key/timestamp/signature/folder`. Any signer failure (503 `not_configured`, guest without token, no network) falls back to the unsigned preset `Ayta_ios` — disable the preset in Cloudinary only after the secret is configured.
- **FeedStore never publishes an empty catalog before the first successful load** (`hasLoadedCatalog`), a failed load stays `.failed` (no `recombine` after it), and `FeedStore.isLoading` counts `.idle` as loading. `AppStore.isLoading` still reads `catalog.isLoading` directly (idle = false) — use `feedStore.isLoading` in views.
- **Review cache:** `upsertUserReview`/`removeReview` edit `baseReviews` too (base wins in `ReviewStats.merge`), and a complete fetch (< page size) drops cached reviews of that scope the server no longer returns. Pinned by `LaunchStabilityTests`.
- **Feed ranking computes each score once per build** (`FeedBuilder.ScoreContext`: venues by id, active-deal counts, one Calendar per city) and sorts by cached score with index tie-break. Order is pinned against the old naive implementation by `FeedPerformanceTests`. Boost rotation uses `StableHash.orderKey("id|window")` — `hashValue` is salted per launch and `hash &+ rotation` never changed the order. **Android `Feed.kt` still uses `hashCode() + rotation`** (same no-rotation bug) — port when touching it.
- **Stamp rows:** never `ForEach(0..<goal)` — the first card's goal has no upper cap. Use `StampRows`/`StampLayout` (`SAN/Components.swift`): ≤ 30 dots, wrapped 12 per row; negative goal → none.
- **Snake:** `SnakeScene.frameDelta` clamps a frame to 0.25 s and `startGame` resets `lastUpdate` (otherwise restart/background = instant death). Empty `adPlaceholderText` → no watermark (the old «Здесь может быть ваша реклама» default read as a placeholder, App Store 2.1).
- **Menu PDF OCR:** pages are processed in an `autoreleasepool`, cancellation is checked between pages (`OnDeviceMenuParsingService` now uses `async let`, so `MenuImportStore` cancel reaches it), at most `maxRecognizedPages = 30` scanned pages are OCR'd, and the second Vision pass runs only when the first is empty or has a line starting with a lowercase letter (the "hopped beef" symptom). This narrows the earlier "always two passes" rule — re-check on real scans if recognition quality drops.
- **XLSX reader caps:** per-entry uncompressed size ≤ 50 MB, ZIP64 markers rejected, empty deflate payloads refused, column refs capped at XFD.
- **Info.plist** has `NSPhotoLibraryAddUsageDescription` — the gift share sheet's «Save Image» killed the app without it.
- **Crashlytics** collection is set to `true` explicitly in release (a Debug build on the same device persists `false`).

- Onboarding: notification step = single «Продолжить» → always requestAuthorization (5.1.1(iv)); no skip on any permission step.
- Marketing push consent (4.5.4): `MarketingPush` (SAN/Deeplink/Deeplink.swift). Topics all_users/city_* subscribed only if notifications authorized AND `san.push.marketing` (default true; Profile toggle «Новости и акции заведений»). Synced on launch, .active, sign-in, toggle. Badge cleared on .active. registerPushToken on uid change / guest upgrade.
- Account deletion order: server delete FIRST, then Apple revoke (best-effort), then signOut. FirebaseAuthService.deleteAccount no longer signs out on 200 (SessionStore does, after revoke).
- Email verification: AuthService.needsEmailVerification/sendEmailVerification/reloadEmailVerification (defaults in protocol extension); EmailVerificationPolicy.requiredSince = 2026-10-02 00:00 Bishkek — mirror of server cutoff. Banner `EmailVerificationBanner` (Profile; add to BonusHubView).
- RankingEvent: `distanceKm` removed from items (location linked to uid). ml/ tolerates absence (W_DISTANCE gets no signal). Android RankingEvent.kt still sends it.
- Analytics: new events sign_up/login (method), onboarding_complete, first_points_earned, first_stamp, game_played, bonus_earned. No uid/referrer ids in params.
- «Тетрис» shown to users as «Блоки» (trademark). Code identifiers unchanged.
- Terms: web/terms.html (AyantLinks.terms); linked on AuthView and Help/About/Support.
- SAN/InfoPlist.xcstrings: ru/en/ky permission strings.

### Отзывы: модерация UGC (iOS, 2026-10-01) — Android не портирован

- **Фильтр перед публикацией** — чистый `ContentFilter` (домен): мат RU/KY/EN (корни + целые слова + латинские двойники «xуй/cyka» + «х.у.й»), ссылки, телефоны (≥ 9 цифр). `AppStore.saveReview` возвращает `ContentFilter.Violation?` — экран показывает «Отзыв содержит недопустимые слова» / «Ссылки и номера телефонов…». Список намеренно скромный; у каждого корня есть обычные слова, которые он мог бы задеть («колебаться», «хлеб», «застрахуйте») — они в `innocentStems` и закреплены `ContentFilterTests`. Новое слово — сначала тест на ложное срабатывание.
- **Скрыть отзывы автора** (Guidelines 1.2, блокировка): «…» и контекстное меню у чужого отзыва → `AppStore.blockAuthor(of:)` → `ProfileStore.blockedAuthorIDs`. Фильтр стоит в адаптере `AppStore.reviews`, поэтому автор пропадает везде (карточка, фото в галерее, инбокс). Список с «Показывать» — `BlockedAuthorsView` (SAN/Reviews/ReviewViews.swift), ссылка на него — в профиле.
- **Жалоба на фото** уходит в `reviewReports` с `reason: "photo"`, `photoReason`, `photoURL` (`PhotoReport`, id `photo_<fnv(url)>_<uid>`); фото самого заведения — `reviewID: "venuePhoto"`. Реализация — протокол `PhotoReporting` на `FirebaseDataRepository`.
- **Id нового отзыва** — `ReviewIdentity.documentID` = `{uid}_{venueID}_{itemID|venue}` (то же требует `reviewIDMatches` в правилах); правка сохраняет старый id (`ur_…`). Отзыв о заведении в целом — `itemID` nil/пусто, сравнивать через `ReviewIdentity.normalizedItemID`, не `== nil`. Отзыв можно оставить и у заведения без меню.
- **`verifiedVisit` клиент не ставит и не показывает**: правила разрешают его только серверу, а сервер его пока не выставляет. Вернуть бейдж — только вместе с серверной отметкой (например, в `scanCoupon`/`countRedemption`).
- **Заголовок рейтинга карточки** — серверные `venue.rating`/`reviewCount`; живой расчёт только когда загружен весь набор (< 50) и он не меньше серверного счётчика (`VenueDetailState.aggregate`). Разбивка по звёздам — по загруженной странице, подпись «По последним N отзывам» (`ratingBreakdownIsPartial`).
- Публикация отзыва больше не `try?`: провал откатывает локальную копию и показывает тост. Выход/удаление аккаунта стирают `san.userReviews`/`san.hostReplies` (`FeedStore.clearLocalUserCaches`).

### Личная библиотека в аккаунте — `userLibraries/{uid}` (iOS, 2026-10-01) — Android не портирован

Сохранённые места, избранные акции, лайки и скрытые авторы синхронизируются: `ProfileStore(storage:library:)`, `library` = `repository as? UserLibrarySyncing` (только `FirebaseDataRepository`; мок — без синхронизации). Поля — `FS.UserLibraryDoc`; правила — только владелец, только эти пять полей, каждый список ≤ 500 (`UserLibrary.maxItems`). Слияние при входе: чужой uid в `san.library.owner` → локальное стирается; есть неотправленные правки (`san.library.dirty`) или библиотека с версии до синхронизации (без владельца) → объединение; иначе сервер — источник правды (удалённое на другом устройстве не воскресает). Правки до сведения с сервером не пишутся (частичная копия затёрла бы аккаунт), после — одной записью через 0,8 с. `resetForNewUser` (выход) обнуляет `state.userID` — иначе отложенное сведение скачало бы библиотеку вышедшего обратно. Тесты: `ProfileLibrarySyncTests`, эмулятор — `rules-check-launchE.cjs`. `deleteAccount` удаляет и `userLibraries/{uid}`.

### Кабинет: запись заведения — по очереди (iOS)

`HostStore.remoteSaveVenue` больше не запускает по `Task` на правку: на заведение одна запись в полёте, правки за это время схлопываются в последнюю (`pendingVenueWrites`), порядок записей = порядок правок. Раньше `getDocument`+`updateData` двух быстрых правок могли прийти в обратном порядке. Тест — `HostVenueWriteQueueTests`. Акции (`remoteSaveDeal`) пока без очереди (`setData merge`).

### Акции: дата окончания и пауза (домен, обе платформы должны совпасть)

`HostForms.deal` закрывает дату окончания концом выбранного дня 23:59:59 в поясе города (`endOfDay(_:pickedIn:citySlug:)`; день — из календаря телефона, нетронутая при правке дата не пересчитывается), а статус считает `HostForms.dealStatus`: черновик → `draft`, правка акции на паузе остаётся `paused`, остальное → `active`. Тесты — `DomainHostFormsDealTests`. **Android `HostForms.kt` не обновлён.**

### Часы работы: ночная смена

`Venue.openShiftClose(at:)` / `isOpen(at:)`: смена через полночь принадлежит дню начала — пятничная 18:00–02:00 открыта в субботу в 01:00 (даже если суббота выходной), а субботняя ночная не открывает субботнее утро. Тесты — `VenueOpeningHoursTests`. **Android не обновлён.**

### Контакты и аналитика

- Ссылки WhatsApp/Telegram/Instagram — `ContactLinks` (домен): «0555…» → `wa.me/996555…`, «instagram.com/x», «t.me/x», «@x» без удвоения хоста. `Venue.whatsappURL`/`instagramURL`/`telegramURL` — старые, карточка их больше не использует.
- «Аналитика» хоста: ключ дня — UTC, как `dayKey()` в функциях (`HostAnalyticsSeries`); пустые дни — нули в графике; один запрос на заведение (суммы из ряда); ошибка — плашка с «Повторить», а не «Данных пока нет».
