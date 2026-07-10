# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Ayant** (internal name "SAN") is a Yelp-style deals / loyalty / reviews app for Bishkek, Kyrgyzstan, with a **Russian-first UI**. It is a monorepo of five surfaces that all share one Firebase project (`san-25d32`):

| Surface | Path | Stack |
|---|---|---|
| iOS app | `SAN/`, tests in `SANTests/` | Swift + SwiftUI |
| Android app | `android/` | Kotlin + Jetpack Compose + Material 3 |
| Cloud Functions | `functions/` | Node 20, JS, Firebase Functions v2 |
| Web (marketing + admin panel) | `web/`, `docs/admin/` | Static HTML + Firebase Web SDK (no framework) |
| Support bot | `telegram-bot/` | Node, grammy + Groq LLM (standalone, no Firebase) |

The iOS app is the source of truth; **Android is a deliberate near 1:1 port**. File headers cross-reference their iOS counterpart ("Mirrors `AppStore.swift`"). When you change shared behavior (ranking, models, Firestore field names, features), change it on **both** platforms or the two clients drift — they read/write the same Firestore documents with identical field names.

## Big-picture architecture

Read these cross-cutting patterns before editing; they span many files and are mirrored on both platforms.

- **Mock ↔ Firebase switch via a factory.** Both apps run fully offline on bundled mock data and flip to the live backend through a single toggle:
  - iOS: `SAN/AppConfig.swift` (`useFirebase`) + `make*()` factories returning either a `Mock*` or `Firebase*` implementation.
  - Android: `core/AppConfig.kt` (auto-detects `google-services.json` at startup in `AyantApp.kt`) + `makeX()` factories.
  Keep this switch working. Every data dependency has a protocol/interface with a `Mock*` and `Firebase*` pair.

- **Repository abstraction isolates Firestore.** Firestore access lives in exactly one file per client: `SAN/Firebase/FirebaseServices.swift` and `android/.../data/FirebaseDataRepository.kt` (+ sibling `*Service` files). Domain models (`Models.swift`, `data/model/Models.kt`) stay Firebase-free; do not import the Firebase SDK or UI types into the data/model layer.

- **Dependency injection is constructor-based with factory defaults** (no DI framework). Stores/ViewModels take their deps as init params defaulting to `AppConfig.make*()`, e.g. `init(repository: DataRepository = AppConfig.makeDataRepository())` (iOS) / `@JvmOverloads constructor(app, repo = AppConfig.makeDataRepository())` (Android). This is the seam tests inject fakes through.

- **State: iOS "Store" pattern → Android ViewModels.** iOS uses `ObservableObject` + `@Published` stores injected as `@environmentObject` from `SANApp.swift` (`AppStore`, `HostStore`, `SessionStore`, `CouponStore`, `LoyaltyStore`, `BonusEngine`, `ThemeStore`, `LocationManager`). Android mirrors each with an `AndroidViewModel` using Compose `mutableStateOf` (not `StateFlow`) obtained via `viewModel()` in `ui/navigation/RootScaffold.kt`. `AppStore`/`AppViewModel` is the largest — it owns the ranking algorithm, feed assembly, saves/favorites, and review CRUD.

- **Ranking is pure and testable.** Venue/deal/feed scoring (rating + reviews + verified + saves, deal freshness, haversine distance weighting, and ad-venue interleaving in the feed) lives in `AppStore` (iOS) and is extracted into `android/.../data/Ranking.kt` (pure Kotlin) on Android. This is what the unit tests cover.

- **Host content overlays the user feed.** The host (business) side edits venues/deals that are merged over the repo feed by id: iOS `HostStore.bind(AppStore)` → `AppStore.setHostContent`; Android `HostViewModel` → `AppViewModel.setHostContent`.

- **Money / anti-cheat paths are server-authoritative.** Clients never write sensitive counters directly. They create request documents or call HTTPS callables; Cloud Functions (`functions/index.js`, admin SDK, bypasses rules) do the privileged writes: `scanCoupon` (verifies host ID token + venue ownership, marks coupons used, awards loyalty stamps), `countRedemption`, `rewardReferral`, `sendPushCampaign` (frequency-capped FCM), plus Apple Wallet `.pkpass` generation. Firestore rules force `coupons`/`redemptions`/`bonusGrants`/`loyaltyCards` mutations through these functions.

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
New Swift files are auto-included via Xcode 16 synchronized folder groups — no `.pbxproj` edit needed. Note: `.github/workflows/ios.yml` still has the test step commented out (build-only CI).

### Android (`android/`)
```bash
cd android
./gradlew :app:compileDebugKotlin        # fast compile check
./gradlew :app:assembleDebug             # build APK
./gradlew :app:testDebugUnitTest         # all unit tests
./gradlew :app:testDebugUnitTest --tests "kg.ayant.app.data.RankingTest"   # single test
```
Requires JDK 17 and Android SDK 34 (minSdk 26). If no system Java, Android Studio's bundled JBR works. The search map needs a Maps SDK key (`YOUR_MAPS_API_KEY` in `AndroidManifest.xml`); the app still builds/runs without it (blank tiles).

### Backend (Firebase)
```bash
firebase deploy --only firestore:rules          # deploy firestore.rules (compiles server-side)
firebase deploy --only functions                # deploy functions/ (Node 20)
firebase deploy --only hosting                  # deploy web/ marketing site

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
- **Push frequency caps** (`functions/index.js`): production defaults are 1/day, 3/week, overridable for local testing via `PUSH_DAILY_CAP` / `PUSH_WEEKLY_CAP` env vars.
- **Secrets** (`serviceAccountKey.json`, `.env` files, `functions/certs/*.pem`, `google-services.json`) are gitignored and present only on local disk; only client-side Firebase config plists are (correctly) committed.

## Conventions

- Comments and doc-strings are frequently in **Russian** — match the surrounding language of the file.
- SharedPreferences/UserDefaults keys are load-bearing (existing installs depend on them) — don't rename them when refactoring persistence.
- Android persists host data via `kotlinx.serialization` to SharedPreferences; on-disk format differs from any older `org.json` layout, so decode failures degrade to empty rather than crash.
