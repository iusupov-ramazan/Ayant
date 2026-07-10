# Ayant — Android

Full Android mirror of the iOS **SAN / Ayant** app (Yelp-for-Central-Asia, Russian UI).
Built with **Kotlin + Jetpack Compose + Material 3** (Android HIG). Mirrors the iOS
`SAN/` sources in structure, features, and design tokens — both the **user side** and
the **host (business) side**.

## What's included

**User side**
- **Auth** — email sign-in/register, Google (stub), guest. Mirrors `AuthView`.
- **Onboarding** — 2 steps (location, notifications), Bishkek only. Mirrors `OnboardingView`.
- **Home feed** — category tiles, "today in favorites" strip, ranked deal cards. Mirrors `HomeFeedView`.
- **Search** — query + filters (open/deals/rating/distance/category), ranked venue list **and Google Maps view** with markers. Mirrors `SearchView`.
- **Venue detail** — header, actions, today special, loyalty banner, address/phone/hours, deals grid, photos, reviews + breakdown + write-review. Mirrors `VenueDetailView`.
- **Deal detail** — hero, badge, price, urgency, **get-coupon** (QR), venue link. Mirrors `DealDetailView`.
- **Saved** — venues + deals tabs.
- **Bonus** — wallet + activity-time economy, rewards catalog → coupons, **coupon wallet** (QR tickets), **loyalty cards** (per-venue QR + stamp grid), and **Snake + Tetris** mini-games (Compose Canvas) that award bonuses with daily caps. Mirrors `BonusHubView`/`BonusEngine`/`CouponStore`/`LoyaltyStore`/`Games`.
- **Profile** — profile card, my coupons, settings, host-mode entry, my reviews, referral share, help (About/FAQ/Support), account.

**Host side** (`ui/host/`, mirrors `SAN/Host/`)
- Onboarding → 5 tabs: **Заведения** (list + stats + CRUD), **Продвижение** (boost/push campaigns), **Аналитика** (period metrics), **Отзывы** (reply inbox), **Профиль** (business info, verification).
- Venue detail with today-special editor, review objects (items), deals grid with status menu, loyalty overview, coupon **scanner** (manual entry; camera scanner is the one remaining stub).
- Host content is written into the shared feed via `AppViewModel.setHostContent` (host edits override repo by id), exactly like iOS `HostStore.bind`.

**Deep links** — `ayant://venue/<id>`, `https://ayant.kg/deal/<id>` open the right screen (handled in `MainActivity`).

Data runs on the ported **MockData** by default; Firebase (same `san-25d32` backend) is
wired behind `AppConfig.useFirebase`. Saves, favorites, reviews, coupons, loyalty, host
data and session persist via `SharedPreferences`.

## Project structure

```
app/src/main/java/kg/ayant/app/
  AyantApp.kt, MainActivity.kt
  core/            AppConfig, Format, Icons, Actions (share/dial/maps/deeplinks)
  data/            model/Models.kt, MockData.kt, DataRepository.kt
  location/        LocationManager.kt (fused location + Haversine)
  ui/
    theme/         Color, Theme (AyantColors tokens + M3), Type, Modifiers, DesignWidgets
    components/    Basics, Cards, Widgets, QrCode
    vm/            AppViewModel (≈ AppStore), SessionViewModel (≈ SessionStore)
    navigation/    RootScaffold (bottom nav + NavHost)
    onboarding/ auth/ home/ search/ detail/ saved/ profile/ bonus/
    RootGate.kt    Auth → Onboarding → main app
```

Design tokens (`ui/theme/Color.kt`, `Theme.kt`) mirror **Ayant Refresh**: warm Canvas
background, Ink text, muted surfaces, bright orange accent (`#FF5A1F`) + gradient,
light/dark, 20dp cards with hairline borders.

## Building

The Gradle **wrapper binary** (`gradlew`, `gradle/wrapper/gradle-wrapper.jar`) is not
committed (binary files can't be written here). Generate it once, or just open the
`android/` folder in **Android Studio** (Ladybug+), which creates it automatically.

CLI alternative (needs a local Gradle ≥ 8.9):

```bash
cd android
gradle wrapper --gradle-version 8.9
./gradlew :app:assembleDebug
```

Requirements: Android Studio Ladybug+, JDK 17, Android SDK 34 (minSdk 26).

## Going live on Firebase (shared backend `san-25d32`)

The app runs on MockData by default. To share the iOS backend:

1. Firebase console → project `san-25d32` → add **Android app**, package `kg.ayant.app`.
2. Download `google-services.json` into `android/app/`. The Google Services plugin
   auto-applies when that file exists (see `app/build.gradle.kts`).
3. In `core/AppConfig.kt`, set `useFirebase = true`. `FirebaseDataRepository` already reads
   `venues`, `deals`, `reviews` into the same models (Firebase BOM + Auth + Firestore +
   coroutines-play-services deps are declared).
4. Confirm Firestore rules used by iOS (public read on venues/deals/reviews).

## Google Maps key

The search map needs a Maps SDK for Android key. Replace `YOUR_MAPS_API_KEY` in
`AndroidManifest.xml`. Until then the app builds and runs; only the map tiles are blank.

## Parity with iOS

Feature-complete against the iOS `SAN/` app. Also included now:
- **Theme switching** (system/light/dark) in Profile.
- **Camera QR scanner** (CameraX + ML Kit) for the host, with manual-code fallback.
- **Firebase Auth** behind `AppConfig` (email + anonymous guest; Mock default).
- **Analytics** service (Firestore `analytics/{venue}/days/{date}` increments; Mock default).
- **Venue detail** full parity: social links (WhatsApp/TG/IG), branches, PDF menu (WebView),
  tappable fullscreen photo viewer, item-specific review picker, verified-visit badges, guest prompts.
- **Gift coupons** from the rewards menu (share a gift link).

## Remaining deltas vs iOS

- **Google Sign-In**: email + guest are wired via Firebase; Google uses Credential Manager on
  Android (a later pass) — currently falls back to anonymous.
- **FCM push** + **Google Wallet** passes (iOS uses APNs + PassKit) — backend/plumbing pass.
- **Localization**: the app is Russian-first with inline strings (matching iOS's practical
  state; iOS ships a 374-key catalog still needing native ky/en review). Theme switching is
  fully wired; language selector shows Russian.
- Real image uploads in host forms (currently image URLs).

## Notes

- Package `kg.ayant.app` (iOS bundle is `kg.san.app`); register this Android package
  separately in Firebase.
- Apple Sign-In is iOS-only and intentionally omitted; Google + email + guest remain.
- No Android SDK was available when this was generated, so it's verified by static
  review, not a compiler run — build once in Android Studio and address any IDE hints.
```
