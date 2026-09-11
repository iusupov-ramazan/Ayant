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
# Build (scheme SAN). CI uses iPhone 15; any installed simulator works.
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
- **Firestore rules ownership model:** `venues`/`deals` carry `ownerID`; `hosts/{uid}` doc id is the owner uid and hosts cannot self-set `verified`; `reviews` are writable by author / venue-owner (host reply) / admin. `analytics/{venueID}` writes are intentionally still open to any signed-in user (client telemetry increments — flagged with a TODO to move into a Cloud Function).
- **Push frequency caps** (`functions/src/index.ts`): production defaults are 1/day, 3/week, overridable for local testing via `PUSH_DAILY_CAP` / `PUSH_WEEKLY_CAP` env vars.
- **Functions are TypeScript.** Edit `functions/src/index.ts` (+ `types.ts`), never the compiled `functions/lib/*.js` (regenerated by `npm run build`). `package.json` `main` = `lib/index.js`. Deploy triggers the build via the predeploy hook, but run `npm run build` yourself to catch type errors first.
- **Secrets** (`serviceAccountKey.json`, `.env` files, `functions/certs/*.pem`, `google-services.json`) are gitignored and present only on local disk; only client-side Firebase config plists are (correctly) committed.

## Loyalty & bonus systems (TWO wallets — don't conflate them)

There are **two independent wallets**, plus the older stamp card. Full design + rationale: **`docs/design/san-points-system.md`**. When you touch any of this, mirror it on iOS + Android + the admin panel + `functions/src/index.ts` — the Firestore field names below are a hard contract across all four.

1. **Баллы САН — per-venue points (the real loyalty product).** Business-funded, earned by scanning at *that* venue, spent on *that* venue's rewards. **Cannot be earned by games.**
   - **Config on the venue doc** (self-serve in `docs/admin/index.html` «Бонусы САН»; parsed into `Venue`): `pointsEnabled`, `pointsMode` (`"flat"|"bands"|"cashback"`), `pointsFlat`, `pointsBands[]` (`{maxAmount,points}`), `cashbackPercent` (≤20), `pointsRewards[]` (`{id,type("item"|"money"),title,cost,ratio,active}`), `pointsExpiryMonths` (6), `redeemMode` (`"staffScan"|"customerInitiated"`), `earnCooldownMinutes` (60; `0` = no cooldown).
   - **Ledger**: `venuePoints/{userID}_{venueID}` (`balance,lifetimeEarned,lifetimeRedeemed,lastEarnAt,lastActivityAt`) + `ledger` subcollection. Rules: read-own, `write:if false` (Functions only).
   - **Earn**: customer shows QR `AYANT-PTS:<userID>` → `scanCoupon` Branch C (host enters bill amount for `cashback` / picks band for `bands`; `flat` needs nothing). 60-min earn cooldown.
   - **Redeem**: `AYANT-RDM:<userID>:<rewardId>[:points]` (staff scans) or in-app for `customerInitiated` → `redeemVenuePoints`.
   - **Files**: iOS `SAN/Bonus/VenuePointsViews.swift` (screens) + `AyantFeatures/Sources/AyantFeatures/PointsStore.swift` (state); Android `ui/vm/VenuePointsViewModel.kt` + `ui/bonus/VenuePointsScreens.kt`. Config rides in `HostVenueDTO`/`HostModels.kt`. Since 2026-09-11 the **iOS host app edits it too** (Лояльность tab → `HostIntent.savePointsConfig` → `HostForms.applyPoints`, which clamps to the server guardrails); `HostVenueDTO.firestoreData` writes the points fields with `merge: true`, and the admin panel edits the same fields — last write wins. Android still treats them as read-only (drift).

2. **Global wallet (`BonusEngine` / `BonusViewModel`).** Platform-wide, deliberately earns **near-zero** (`rewardPerGoal=1`, gameplay cap `3`/day) so it can't be farmed into money loss; spent on the global coupon `catalog` + gifting. Snake is the only mini-game (Tetris removed). Referral/welcome (+100) credit this wallet; `recordReferral` writes referral tracking to Firestore regardless.

3. **Loyalty stamp card (older).** `AYANT-CARD:<userID>:<venueID>` → `scanCoupon` Branch A → +1 stamp in `loyaltyCards/{userID}_{venueID}`. Has its own anti-multi-scan cooldown: **`DEFAULT_STAMP_COOLDOWN_MIN=15`** (separate from the 60-min points cooldown; both keyed on `lastStampAt`/`lastEarnAt`).

**Cooldown constants** live in `functions/src/index.ts`: `DEFAULT_STAMP_COOLDOWN_MIN=15`, `DEFAULT_EARN_COOLDOWN_MIN=60`, `DEFAULT_EXPIRY_MONTHS=6`, `MAX_CASHBACK_PERCENT=20`, `MAX_POINTS_PER_EARN=10000`.

**Points math is mirrored on the clients and pinned by one shared fixture.** The server is authoritative, but both clients need the same arithmetic to preview a scan ("you'll get 100 points", "you're 20 short") — so `AyantDomain/Sources/AyantDomain/PointsMath.swift` and `android/.../data/PointsMath.kt` reimplement award / cooldown / redeem, and `specs/fixtures/points-fixtures.json` is executed by **all three**:

| Runner | Command |
|---|---|
| iOS | `swift test --package-path AyantDomain --filter PointsFixtureTests` |
| Android | `./gradlew :domain:test --tests "kg.ayant.app.domain.PointsFixtureTest"` |
| Functions | `cd functions && npm test` (drives the real `scanCoupon` / `redeemVenuePoints`) |

A new case goes **in the JSON**, never in one platform's test file — a case that runs once proves nothing about drift. The error strings in `expect.error` are the server's own `{"error": ...}` codes; `PointsError.code` returns them verbatim on both clients.

One server behavior is deliberately mirrored even though it looks like a bug — do not "fix" it on one side only: cashback rounds **half-up** (JS `Math.round`), which is why `PointsMath.kt` uses `floor(x + 0.5)` rather than `kotlin.math.round` (ties-to-even).

`earnCooldownMinutes: 0` means **no cooldown** (earn on every scan), as does any negative value; the 60-minute default applies only when the field is absent or non-numeric. This used to be the opposite — `parseInt(x) || 60` treated the falsy `0` as "not set", so 0 silently meant 60 and only a negative value disabled the cooldown — and both clients + the fixture mirrored that quirk on purpose. It is fixed everywhere now (`intOrDefault` in `functions/src/index.ts`, `PointsMath.effectiveCooldownMinutes` on both clients, the admin panel's save path). The sibling reads `venue.loyaltyGoal` and `venue.pointsExpiryMonths` still use `|| default` **on purpose**: `0` is not a meaningful value for either (their floors are 2 visits / 1 month), so zero is better read as "not configured" — see the comments at those two call sites.

**Live updates are snapshot listeners — do not reintroduce polling.** Stamps and points change server-side when a business scans a QR, and the customer client sees it immediately: `venuePoints` and `loyaltyCards` are read through `addSnapshotListener` / `callbackFlow`, and the listener is removed when its consumer is cancelled (`continuation.onTermination` on iOS, `awaitClose` on Android). The old `sleep(4s)` / `delay(4000)` loops are gone from both apps; if you find yourself adding one, add a listener instead. Note: a customer only reads `venuePoints`/`coupons` if the **Firestore rules are deployed** — a missing rule silently returns nothing (deploy `firestore:rules`, not just `functions`).

**Every money-path callable is idempotent.** Both `scanCoupon` (earn a stamp / earn points) and `redeemVenuePoints` (spend points) accept an `idempotencyKey` that the client generates **once per scanned QR / per redeem attempt** and reuses on retry. The outcome is stored in the same transaction — `scanKeys/{key}` under the card for scans, `redeemKeys/{key}` for redeems — and replayed instead of applying the mutation twice (response carries `replayed: true`). The key is checked **before** the cooldown: otherwise a retry inside the 15/60-minute window would get a `429` instead of the original result, which is exactly the case the key exists for. A different key inside the window still hits the cooldown, so accidental rescans are still blocked. Rules deny clients any access to `scanKeys`/`redeemKeys`.

**`citySlug` is a partition key, not decoration.** `Venue`, `Deal` and `Review` all carry it (Firestore field `city`), currently always `"bishkek"`. It exists so multi-city isn't a retrofit into a live catalog — **set it on any new model and any new write**, even though nothing reads it yet.

**Writing Cloud Function tests: the fake Firestore converts `Date` → Timestamp on write**, exactly like the real SDK (`test/helpers/fakeFirestore.js`, pinned by `test/fakeFirestore.test.js`). This matters because `toMillis()` in `index.ts` returns 0 for anything without a `toMillis` method — with a naive fake, *every* cooldown is silently disabled in tests and a "repeat is blocked" test passes while proving nothing. `harness.seed()` normalises the same way, so seeded documents read back like real ones.

**Nightly integrity checks (`reconcileVenuePoints`).** Following the project's "alerts instead of tests" trade-off, one scheduled pass over `venuePoints/{card}/ledger` covers three things a test can't: `balance == sum(ledger.points)` (a mismatch is money lost or double-issued), a heartbeat check that `expireVenuePoints` actually ran in the last 26 h, and per-venue issuance more than 3× its trailing 7-day mean (a "50% cashback" typo or staff abuse). Alerts go to `ops/alerts/items/{auto}` *and* to Cloud Logging with an `ALERT <kind>` prefix — configure the log-based alerting policy on that prefix. `ops/**` is admin-read, function-write-only.

**Key reuse is a collision, not a retry.** The same key sent for a *different* reward (or a different QR) → `409 key_reused`. Keep the key stable across retries of one attempt and fresh for a new one — `PointsStore`/`PointsViewModel` hold it until the attempt succeeds; the host scanners mint one per decoded QR.

## Release flags (iOS)

`SAN/ReleaseFlags.swift` holds the switches for surfaces that are built but hidden in the shipped app: `searchTab`, `globalBonusWallet`, `referrals`, `promote`, `appleWallet`. Each is a `static let` gating the UI entry points only — the stores, models and backend paths stay compiled and tested. Flip one on only when its prerequisite is real (Firestore-backed rewards for the wallet, payment for promote, a real pass type ID for Wallet, a tested map screen for search). Android has no equivalent yet; the Android app still shows all of these.

## Conventions

- Comments and doc-strings are frequently in **Russian** — match the surrounding language of the file.
- SharedPreferences/UserDefaults keys are load-bearing (existing installs depend on them) — don't rename them when refactoring persistence.
- Android persists host data via `kotlinx.serialization` to SharedPreferences; on-disk format differs from any older `org.json` layout, so decode failures degrade to empty rather than crash.
