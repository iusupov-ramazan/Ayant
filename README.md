# Ayant

**A local discovery & deals app for Central Asia — the "САН" feed of your city.**
Ayant is a dual-sided platform (users + businesses), Yelp/2GIS-inspired but built around what people open daily: **Скидки, Акции, Новинки** (Discounts, Promos, New items). Russian-language UI, launching in Bishkek.

iOS app (SwiftUI) · Firebase backend · Web admin panel · Telegram AI support bot.

---

## What it does

### For users
- **САН feed** — a single feed of discounts, promos, new items, and announcements from city venues.
- **Search** across venues, dishes/services, deals, and reviews; filters (open now, rating, distance, with-discount) and a map view.
- **Venue pages** — multiple branches, per-weekday hours, phone, WhatsApp/Instagram/Telegram, price-list PDF, publications.
- **Item-level reviews** — rate a specific dish/service, with photos; verified-visit badge after redeeming.
- **Coupons & bonuses** — earn bonuses from mini-games and referrals, exchange them for coupons (QR), gift a coupon to a friend.
- **Deep links & Universal Links** — share venues/deals/gifts; push-tap opens the target.

### For businesses (host mode)
- Create venues (with map picker, branches, photos, PDF, weekday hours) and deals (Скидка/Акция/Новинка/Объявление).
- Moderation & verification, analytics (views, taps, saves, calls, maps, redemptions).
- **Promotion** — push campaigns and in-feed boost (venue shown as a labeled ad), with admin approval.

---

## Tech stack

- **iOS** — SwiftUI (iOS 17+), no external UI deps. Repository pattern with Mock + Firebase implementations behind `AppConfig`.
- **Backend** — Firebase: Auth, Firestore, Cloud Messaging (push), Cloud Functions (v2, Node 20), Hosting (AASA for Universal Links).
- **Images/PDF** — Cloudinary (unsigned uploads).
- **Admin** — static web panel (`docs/`, GitHub Pages) for moderation, venues/deals, weekday hours, map marker, boost approval.
- **Support bot** — Node.js Telegram bot (grammY + Groq), FAQ + AI answers.

## Structure

```
SAN/                SwiftUI app (models, feed, search, venue/deal, reviews, bonus, host mode, Firebase layer)
functions/          Cloud Functions (push fan-out, redemption count, referral reward)
docs/ · admin/      Web admin panel (GitHub Pages serves docs/)
web/                Firebase Hosting (AASA, landing, privacy policy)
telegram-bot/       Telegram AI support bot
branding/           Logo (SVG)
*.js                Firestore seed / backup / restore scripts
```

## Setup

1. Open `SAN.xcodeproj` in Xcode 16+, set your Team, run on a device/simulator.
2. Firebase: add `GoogleService-Info.plist`; enable Auth, Firestore, Cloud Messaging; upload the APNs key. See `FIREBASE_SETUP.md`.
3. Deploy backend: `firebase deploy --only functions,firestore:rules,hosting` (requires the Blaze plan for Functions).
4. Seed data: `node reset-and-seed.js` (auto-backs-up first).
5. Support bot: see `telegram-bot/DEPLOY.md`.

## Status

MVP feature-complete; preparing a Bishkek pilot and TestFlight. Business overview and go-to-market in `AYANT_business_overview_ru.md`.

> Secrets (`serviceAccountKey.json`, `.env`, `*.p8`) are gitignored — never commit them.
