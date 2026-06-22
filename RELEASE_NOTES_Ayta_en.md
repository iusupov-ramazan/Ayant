# Ayta — What's New in This Version

A local discovery platform for Central Asia (launching in Bishkek).
Two sides in one app: **user** and **business (host)**. Switching between them needs
no separate app and no re-login.

---

## Branding

- App renamed to **Ayta** (icon label, screen titles, auth screen, deal codes `AYTA-…`,
  share text "Found it on Ayta!", admin panel "Ayta Admin").

---

## User Side

### Onboarding (first launch)
- Step-by-step onboarding: **city** (Bishkek only for now), **location** permission
  ("while using"), and **notifications** permission. Without location the app still
  works — distances just aren't shown.

### Home — deals feed
- The feed now shows **deals**, not venues.
- Deal card: photo, venue (with verified check), discount, title, description, price,
  **Save** and **Share** (deep link) buttons.
- Top row of **category** circles (story-style) filters the feed.
- **"Today at saved venues"** strip — today's specials from saved venues.
- Every 5th slot is a **sponsored** placeholder ("Your ad could be here").
- Tapping a deal **pushes the detail screen** (slide-in with a back button), not a
  bottom sheet.
- City scope: feed and search are limited to the selected city; only **approved** and
  **non-paused** venues are shown.

### Search
- Full-text search by name, category, deal title, and district.
- Filters: **open now**, **minimum rating** (★3+/★4+), **distance**
  (500 m / 1 / 3 / 5 km), **category**.

### Saved
- Two tabs: **Venues** and **Deals**. Swipe to remove.

### Profile
- Avatar, name, city. **My reviews** (edit/delete). Settings: language (RU/UZ/EN),
  notifications, theme. **"Switch to host mode"** button. Sign out and delete account.

### Venue page
- Large **cover photo** (if any) + avatar logo; **no emoji** — when there's no photo it
  shows a clean background with an icon.
- Name + **verified check**, category, **aggregate rating + review count**, "Today"
  badge, "Saved by N people" line.
- Actions: **Call · Directions · Save · Share** (deep link).
- Address with **2GIS** and **Google Maps** buttons, phone, **per-weekday opening hours**
  (today highlighted), **price list / catalog (PDF)** in an in-app viewer, map pin.
- **Deals grid** (3 columns), **real photo gallery** (cover + item photos + review photos)
  with full-screen viewer and report.
- **Review objects** (food/services) with photos — tap to review that specific object.

### Reviews
- **Reviews always target a specific object** (a dish/service), not the venue as a whole.
- Stars, text, and **up to 3 real photos** (uploaded from the phone).
- 5★…1★ breakdown, owner replies ("Owner response"), 2-tap report.
- Reviews and replies are published to Firestore — visible to everyone, across devices.

### Other
- **Deep links**: `san://venue/<id>`, `san://deal/<id>`, plus Universal Links
  `https://<domain>/venue|deal/<id>`. Sharing sends a link; tapping a sponsored push
  opens the target venue.
- **Guest (anonymous sign-in)** is read-only: can't create venues, save, or review
  (prompts to sign in).
- **"Bonuses"** tab with a Snake game (active time → bonus points).

---

## Business (Host) Side

5 tabs: **My Venues · Promote · Analytics · Reviews · Profile**.

### Host onboarding
- Triggered by "Switch to host mode." Step 1 — business basics (name, category, phone,
  email). Step 2 — add the first venue now, or later.

### My Venues
- List of venues with **photo**, moderation status, and activity.
- Create/edit a venue:
  - Name, category, district, address, phone.
  - **Venue photo** (uploaded from the phone).
  - **Price list / catalog (PDF)** — upload a PDF of foods/services.
  - **Location on a map** (drop a pin) or manual coordinates.
  - **Per-weekday opening hours** (open/close time, day off; "apply Monday to all days").
  - **Review objects** (food/services) — name, type, **photo**.
  - **Today's special** (single line).
  - "Active / paused" toggle.
- **Deals**: grid with **Edit · Pause · Duplicate · Delete**, a **photo** per deal, and
  statuses (active/paused/expired/draft). Deal cells show the uploaded image.
- Host content is stored in Firestore (with `ownerID`) and appears in the user feed;
  a local cache is the offline fallback.

### Promote
- Campaigns across all venues. Two types:
  - **Boost a venue** (7/14/30 days, price shown upfront).
  - **Push notification** (headline ≤60, body ≤120) — a real send.

### Analytics
- Period 7/30/90 days. **Real data from Firestore**: profile views, deal taps, saves,
  phone clicks, map clicks — aggregated and per venue.

### Reviews
- Inbox of reviews across all venues, unread badge. Public owner reply.

### Host profile
- Business details, **request the "Verified" badge** (status), notifications, billing,
  "Switch to user mode."

---

## Moderation & Verification

- **A new venue is created as "pending"** and is hidden from users until approved. The
  host sees the status (pull to refresh).
- **Admin panel** (web, GitHub Pages): approve/reject venues, **verify venues/businesses**
  (badge), manage objects, photos, status.

---

## Backend & Infrastructure

- **Firestore** collections: `venues`, `deals`, `reviews`, `hosts`, `analytics`,
  `pushCampaigns`, `userTokens`, `pushLog`. Security rules published.
- **Cloud Function** `sendPushCampaign`: targeted push delivery by city tokens with a
  **frequency cap** — at most 1/day and 3/week per user.
- **Image storage — Cloudinary** (unsigned uploads from phone and admin; auto-compress
  `c_limit,w_1600,q_auto`). PDF catalogs go there too.
- **Admin panel** hosted on GitHub Pages (the `docs/` folder).
- Device FCM-token registration, push-tap handling (deep link), Universal Links
  (entitlement + AASA template).

---

## Technical Notes

- One account = one host profile = one or more venues.
- Opening hours stored per weekday (minutes from midnight), with a fallback to a single time.
- Images and PDFs are stored as URLs in Firestore; files live in Cloudinary.
- To deliver PDFs, enable in Cloudinary: **Settings → Security → Allow delivery of PDF and ZIP files**.
