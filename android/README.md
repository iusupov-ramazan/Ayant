# Ayant — Android

Android mirror of the iOS **SAN / Ayant** app (Yelp-for-Central-Asia, Russian UI).
Built with **Kotlin + Jetpack Compose + Material 3** (Android HIG). This first pass
covers the **user side, core discovery loop**; it mirrors the iOS `SAN/` sources 1:1
in structure and design tokens.

## What's included (this pass)

- **Auth** — email sign-in/register, Google (stub), guest. Mirrors `AuthView`.
- **Onboarding** — 2 steps (location, notifications), Bishkek only. Mirrors `OnboardingView`.
- **Home feed** — category tiles, "today in favorites" strip, ranked deal cards. Mirrors `HomeFeedView`.
- **Search** — query + filters (open now, with deals, rating, distance, category), ranked venue list. Mirrors `SearchView` (list mode).
- **Venue detail** — header, actions (call/route/save/share), today special, address/phone/hours, deals grid, photos, reviews + breakdown + write-review. Mirrors `VenueDetailView`.
- **Deal detail** — hero, badge, price, urgency, coupon QR, venue link. Mirrors `DealDetailView`.
- **Saved** — venues + deals tabs. Mirrors `SavedView`.
- **Profile** — profile card, settings, my reviews, referral share, account. Mirrors `ProfileView`.
- **Bonus** tab — placeholder (see roadmap).

Data runs on the ported **MockData** (same Bishkek venues/deals/reviews as iOS).
Saves, favorites, reviews and session persist via `SharedPreferences`.

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

The app currently runs on MockData. To share the iOS backend:

1. Firebase console → project `san-25d32` → add **Android app**, package `kg.ayant.app`.
2. Download `google-services.json` into `android/app/`. The Google Services plugin
   auto-applies when that file exists (see `app/build.gradle.kts`).
3. In `core/AppConfig.kt`, set `useFirebase = true` and implement `FirebaseDataRepository`
   (read `venues`, `deals`, `reviews` collections → the same models). The Firebase BOM +
   Auth + Firestore deps are already declared.
4. Publish/confirm Firestore rules already used by iOS (public read on venues/deals/reviews).

## Roadmap (next passes)

- **Bonus side**: bonus economy, games (Snake/Tetris), loyalty cards, coupons wallet + Wallet/Google Wallet.
- **Search map**: clustered Google Maps view (mirrors `VenuesMapView`) — currently list-only.
- **Firebase**: `FirebaseDataRepository`, Firebase Auth (email/Google), FCM push, analytics.
- **Host side**: full business mode (venues/deals management, reviews inbox, analytics, promote, scanner).
- **Localization**: RU/EN/KY string resources (iOS uses a 374-key catalog).
- Photo viewer, PDF menu, real image uploads, item-level reviews.

## Notes

- Package `kg.ayant.app` (iOS bundle is `kg.san.app`); register this Android package
  separately in Firebase.
- Apple Sign-In is iOS-only and intentionally omitted; Google + email + guest remain.
- No Android SDK was available when this was generated, so it's verified by static
  review, not a compiler run — build once in Android Studio and address any IDE hints.
```
