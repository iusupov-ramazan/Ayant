# Adding Firebase to the Android app

The code is already wired for Firebase (Gradle plugin, BOM, Auth + Firestore deps,
and `FirebaseDataRepository`/`FirebaseAuthService`/`FirebaseAnalyticsService`). The app
**auto-switches** to the live backend as soon as `google-services.json` is present —
you don't flip any flag. Without the file it runs on MockData.

## 1. Register the Android app in the Firebase console

1. Open the Firebase console → your existing project **`san-25d32`** (same one iOS uses,
   so both platforms share data).
2. Click **Add app → Android**.
3. **Android package name:** `kg.ayant.app`  ← must match exactly.
4. App nickname: e.g. "Ayant Android" (optional).
5. (Skip the SHA-1 for now — it's only needed later for Google Sign-In.)
6. Click **Register app**.

## 2. Download and drop in `google-services.json`

1. Download the generated **`google-services.json`**.
2. Put it here:
   ```
   android/app/google-services.json
   ```
   (next to `build.gradle.kts`, not in the repo root).
3. That's it — the Google Services Gradle plugin auto-applies when the file exists,
   and `AyantApp` detects Firebase at startup and sets `AppConfig.useFirebase = true`.

## 3. Enable the Auth sign-in methods

Firebase console → **Build → Authentication → Sign-in method**, enable:
- **Email/Password**
- **Anonymous** (used for "Зайти как гость" and the Google fallback)

## 4. Firestore

Firebase console → **Build → Firestore Database**.
- The `venues`, `deals`, and `reviews` collections should already exist (iOS seeded them).
- Confirm the security **rules** allow public read on those collections (iOS already
  uses public read on venues/deals/reviews, authed write). Same rules work for Android.

## 5. Rebuild

```
./gradlew :app:assembleDebug
```
Sync Gradle in Android Studio first if it's open. On launch the app now reads live
data from `san-25d32`, and sign-in/register go through Firebase Auth.

## Notes / later

- **Google Sign-In** currently falls back to anonymous. To make the real Google button
  work you'll add the Credential Manager flow + register your app's **SHA-1**
  (`./gradlew signingReport`) in the Firebase console, and download an updated
  `google-services.json`.
- **FCM push** and **Google Wallet** passes are separate later passes.
- `google-services.json` contains project keys — add it to `.gitignore` if the repo is
  shared publicly (it's generally safe to commit for a private repo).
- To force MockData even with the file present, set `AppConfig.useFirebase = false`
  after the auto-detect line in `AyantApp.onCreate`.
