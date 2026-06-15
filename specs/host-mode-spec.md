# App Specification — Dual-Sided Platform (User + Host)
**Version:** 1.1 — Finalized
**Last updated:** 2026-06-14

---

## Overview

The app is a dual-sided local discovery platform for Central Asia. Users discover nearby venues and deals; businesses (hosts) manage their venue presence, post deals, and run promotions. Both sides live in the same app — no separate app or re-authentication required.

---

## Mode Switching

- Located in the **Profile tab** of the user-side app.
- Button: **"Switch to Host Mode"** / **"Switch to User Mode"**.
- If the user has no host account, tapping the button opens a simple host onboarding flow: business name, category, contact info.
- Once in host mode, the bottom tab bar is replaced by the host-specific navigation.
- One user account = one host profile. One host profile = one or more venues.

---

## User Mode

### Bottom Navigation

| Tab | Name |
|---|---|
| 1 | Home (Feed) |
| 2 | Search |
| 3 | Saved |
| 4 | Profile |

---

### Tab 1 — Home Feed

**Category selector (top row)**
- Horizontally scrollable row of circular icons — same visual pattern as Instagram/WhatsApp story circles.
- Each circle: category icon + label (Cafes, Restaurants, Barbershops, Gyms, Bakeries, …).
- "All" is selected by default. Selecting a category filters the feed.
- Active category gets a colored ring highlight.

**"Today's Special" banner**
- If any saved venue has posted a Today's Special, it appears as a horizontal scrollable strip just below categories — distinct from the main feed.
- Each card: venue photo, venue name, special text, "Open now" tag.
- Tapping opens the Venue Detail Page.

**Main feed (venue cards)**
- Vertical scrollable list.
- Each card: cover photo, venue name, category, star rating, distance, deal count badge, "Open now" / "Closed" status.
- Every 5th card slot is a **Sponsored** slot (labeled "Sponsored"). Initially renders as organic. Reserved in the API response shape from day one (`is_sponsored: false` until ad inventory is active).
- Tapping a card opens the Venue Detail Page.

**Feed Algorithm (v1 — organic)**

Ranked server-side per request, scoped to the user's selected city:

| Signal | Weight | Notes |
|---|---|---|
| Distance | High | Venues within 1 km ranked highest |
| Rating | Medium | `score × log(review_count)` — penalizes single-review venues |
| Deal recency | Medium | Deal added in last 48h = ranking boost |
| Today's Special | Medium | Venue with active special gets a boost in main feed too |
| Deal count | Low | More active deals = slightly higher rank |
| New venue bonus | Low | Venues created in last 14 days get a temporary boost for initial exposure |

---

### Tab 2 — Search

- Full-text search by venue name, category, or deal title.
- Filters: **Open now** | **Min rating** (★3+ / ★4+) | **Distance** (500m / 1km / 3km / 5km) | **Category**.
- Results use the same venue card format as the feed.
- Empty state: "No results — try a different category or expand your distance."

---

### Tab 3 — Saved

- **Saved Venues** — venues bookmarked via the Save button on any venue card or detail page.
- **Saved Deals** — individual deals saved from the venue detail page.
- Removing a saved item: swipe to delete or tap unsave.
- Notification trigger: when a host adds a new deal to a saved venue, the user receives an in-app + push notification.

---

### Tab 4 — Profile

- Avatar, display name.
- **My Reviews** — list of all reviews the user has written, with venue name, rating, and text. Tap to edit or delete.
- Settings: city selector, notification preferences, language (Russian / Uzbek / English).
- **"Switch to Host Mode"** button.
- Logout / Delete account.

---

### Venue Detail Page

Opened when a user taps any venue card or deal in the feed.

**Header**
- Venue cover photo + logo overlay.
- Venue name, category tag, aggregate star rating + review count.
- "Today's Special" badge if active.
- Action row: **Call** | **Directions** | **Save** | **Share**.
- "Verified" checkmark badge next to venue name if verified.
- "Saved by 214 people" social proof line.

**Info section**
- Address with **2GIS** and **Google Maps** deep-link buttons.
- Phone number (tap to call).
- Working hours — collapsible, shows "Open now" / "Closes at 22:00" / "Closed".
- **PDF Menu** button (if uploaded) — opens in-app PDF viewer.

**Deals grid**
- Instagram-style 3-column grid of all active deals.
- Tapping a deal opens a deal detail bottom sheet: full image, title, description, price/discount, validity period, **Save Deal** button.

**Photos gallery**
- Horizontal scrollable strip of photos — host-uploaded and user-uploaded (from reviews).
- Tap any photo to open full-screen viewer.

**Reviews section**
- Aggregate star rating with 5★–1★ breakdown bar chart.
- Paginated list of reviews: avatar, username, star rating, text, photos (if any), date.
- One review per user per venue — editable, not replaceable.
- **"Write a Review"** CTA — bottom sheet with star selector, text field, optional photo attach (max 3 photos). Open to all users, no visit or purchase required.
- Host reply shown inline under the review, labeled **"Owner response"**.
- **"Report review"** — 2-tap flow: tap report → select reason (Fake / Spam / Offensive) → submit. Routes to internal admin queue silently.

---

### In-App Notifications (User)

- "New deal at [Venue Name]" — triggered when a saved venue adds a deal.
- "[Venue Name] replied to your review."

---

## Host Mode

### Bottom Navigation

| Tab | Name |
|---|---|
| 1 | My Venues |
| 2 | Promote |
| 3 | Analytics |
| 4 | Reviews |
| 5 | Profile |

---

### Tab 1 — My Venues

The primary management hub. All venue and deal management lives here.

**Venue list view**
- List of all host-owned venues.
- Each card: cover photo, venue name, category, active deal count, status (active / paused), verified badge.
- FAB: **"+ Add Venue"**.

**Venue detail view** (tap a venue)
- Venue header with cover, name, status toggle (active / paused).
- **"Today's Special"** field — single text input (max 100 chars). Host sets or clears it here. Visible on the user-side feed and venue detail page. No expiry enforced by the app — host manages it manually.
- **Deals grid** — 3-column grid of all deals, same visual as user side.
  - Each deal card: thumbnail, title, status chip (active / paused / expired / draft).
  - Long-press or tap → options: **Edit | Pause/Resume | Duplicate | Delete**.
- FAB: **"+ Add Deal"**.
- **"Edit Venue Info"** button — opens venue edit form (same fields as creation).
- **"Promote this Venue"** button — shortcut into Tab 2 scoped to this venue.

**Add / Edit Deal form**
- Fields: title, description, price / discount text, images (up to 5), start date, end date (optional), status (active / draft).
- **Draft state**: save without publishing. Drafts are visible in the deals grid with a "Draft" chip.

**Venue creation form** (via FAB on venue list)
- Name, category, description, address (map picker with 2GIS/Google Maps), phone, working hours (per weekday), cover photo, logo, PDF menu upload (max 10 MB).
- After creation: prompted to add first deal or set Today's Special.

---

### Tab 2 — Promote

**Overview**
- List of all active and past campaigns across all venues.
- Each campaign card: type, venue, status, impressions, spend, end date.

**Campaign types**

*Boost a Venue*
- Pay to fill sponsored feed slots for a selected venue.
- Duration options: 7 / 14 / 30 days.
- Pricing shown upfront. Starts immediately after payment.

*Push Notification Ad*
- Send a sponsored push notification to users in a selected city and/or category.
- Compose: headline (max 60 chars), body (max 120 chars), target venue (deep-link destination).
- Audience: city | category | both.
- Schedule: send now or pick a date/time.
- **Frequency cap enforced server-side**: a single user receives at most 1 sponsored push per day and 3 per week. Hosts cannot override this.

**Per-venue shortcut**
- Tapping "Promote this Venue" from Tab 1 opens Tab 2 pre-filtered to that venue.

---

### Tab 3 — Analytics

**Overview dashboard**
- Period selector: 7d / 30d / 90d.
- Aggregate across all venues: total profile views, deal taps, saves, phone clicks, map clicks.

**Per-venue drill-down** (tap a venue)
- Profile views over time (line chart).
- Today's Special impressions (when set).
- Top 3 deals by taps and saves.
- Saves count over time.

**Per-deal stats** (tap a deal)
- Views, saves, tap-through rate.

**Ad performance**
- Per-campaign: impressions, taps, spend, cost-per-tap.

---

### Tab 4 — Reviews

- Aggregated inbox of all reviews across all venues.
- Default sort: unresponded first, then newest.
- Filter: by venue | by star rating | by status (responded / pending).
- Badge on tab icon = count of unresponded reviews.

**Review thread view** (tap a review)
- User's review: avatar, username, rating, text, photos, date.
- Reply field: host types a public response. Visible to all users on the venue page.
- Host can edit or delete their own response.

---

### Tab 5 — Profile

- Business display name, contact email, phone.
- **Request Verified Badge** — submits a verification request. Status shown (pending / verified / rejected).
- Notification preferences.
- Billing & payment methods for ad purchases.
- **"Switch to User Mode"** button.
- Logout.

---

### In-App Notifications (Host)

- "You have a new review on [Venue Name]." (with rating)
- "Your promotion campaign for [Venue Name] is now live."
- "Your boost for [Venue Name] ends in 24 hours."

---

## Data Model (High-level)

```
User
  ├── SavedVenue[] → Venue references
  ├── SavedDeal[]  → Deal references
  └── Review[]

Host (linked to User)
  └── Venue (1 or more)
        ├── metadata: name, category, description, address, phone,
        │             working_hours, logo, cover, pdf_menu, is_verified,
        │             today_special: { text, updated_at } | null
        ├── Deal (0 or more)
        │     ├── title, description, price_text, images[]
        │     ├── status: active | paused | expired | draft
        │     └── validity: start_date, end_date | null
        └── Review (0 or more)
              ├── author: User reference
              ├── rating: 1–5
              ├── text, photos[]
              ├── created_at, updated_at
              └── HostReply (0 or 1)
                    ├── text
                    └── created_at, updated_at

AdCampaign
  ├── host: Host reference
  ├── venue: Venue reference
  ├── type: boost | push_notification
  ├── status: scheduled | active | completed | cancelled
  ├── targeting: { city, category | null }
  ├── schedule: { start_at, end_at }
  └── stats: { impressions, taps, spend }
```

---

## Onboarding Flows

### New User Onboarding (first launch)

A 3-step flow shown once, before the feed is displayed. Cannot be skipped — city selection is required for the feed to work.

**Step 1 — City selector**
- Full-screen with search field + list of supported cities.
- Subtext: "We'll show you venues and deals near you."
- Selection is saved to the user profile and used to scope all feed/search results.

**Step 2 — Location permission**
- System permission prompt for "while using" location access.
- Pre-prompt screen explains the value: "Allow location to see how far venues are from you."
- If denied: app works normally, but distances show as "—" instead of km. No forced re-prompt.

**Step 3 — Notification permission**
- System permission prompt for push notifications.
- Pre-prompt screen: "Get notified when your saved venues post new deals."
- If denied: app works normally. User can enable later from Profile → Settings.
- After this step: land on the home feed.

### New Host Onboarding

Triggered when a user taps "Switch to Host Mode" for the first time.

**Step 1 — Business basics**
- Fields: business display name, primary category (picker), contact phone, contact email.

**Step 2 — First venue**
- Option A: **"Add my venue now"** → opens the venue creation form.
- Option B: **"I'll do this later"** → lands on Tab 1 (My Venues) with an empty state prompt.

No payment or verification required to create a host account.

---

## Empty States

Empty states are critical at launch when venue density is low. Each screen needs a designed state, not a blank page.

### User side

| Screen | Empty state message | CTA |
|---|---|---|
| Home feed (no venues in city) | "No venues in [City] yet. Know a great spot?" | "Add a venue →" (links to host onboarding) |
| Home feed (category filtered, 0 results) | "No [Category] venues yet in [City]." | "Clear filter" |
| Search (0 results) | "Nothing found. Try a different name or expand your distance." | — |
| Saved Venues (nothing saved) | "Save venues you love — they'll appear here." | — |
| Saved Deals (nothing saved) | "Tap the bookmark on any deal to save it here." | — |

### Host side

| Screen | Empty state message | CTA |
|---|---|---|
| My Venues (no venues yet) | "You haven't added a venue yet." | "+ Add your first venue" |
| Venue deals grid (no deals) | "No deals yet. Add one to start attracting customers." | "+ Add Deal" |
| Analytics (no data yet) | "Data will appear after your venue gets its first views." | — |
| Reviews (no reviews yet) | "No reviews yet. Share your venue to get started." | — |
| Promote — active campaigns (none) | "No active campaigns. Boost your venue to reach more customers." | "Boost a Venue" |

---

## Admin Panel (Internal)

Minimal internal tool required before launch. Does not need to be a polished product — a web dashboard is sufficient.

### Capabilities

**Venues**
- List all venues with status, city, host contact, verified flag.
- Approve / reject verified badge requests.
- Manually pause or delete a venue (abuse cases).

**Reviews**
- Queue of reported reviews, sorted by report count.
- Actions per report: **Dismiss** (keep review) | **Remove review** | **Ban user**.
- View reporter, review text, report reason.

**Photos**
- Queue of reported user-uploaded photos.
- Actions: **Approve** (clear report) | **Remove photo**.

**Ad campaigns**
- List of all campaigns with status and spend.
- Ability to pause or cancel a campaign manually.

**Users**
- Search by email or phone.
- View account status, review count, report history.
- Ban / unban account.

### What it does NOT need in v1
- Revenue dashboards (use payment gateway's own dashboard).
- Automated content moderation (async human review is fine at launch scale).
- Role-based access for multiple admins (single admin account is enough initially).

---

## Venue Location — Latitude & Longitude

### Why it matters

Every venue needs a precise coordinate pair (latitude, longitude) stored at creation time. This drives: distance calculation in the feed algorithm, map pin on the venue detail page, "Directions" deep-link to 2GIS/Google Maps, and future geo-search (e.g., venues within X km of GPS position).

### Data stored per venue

```
location: {
  latitude:       Float       // e.g. 41.299496
  longitude:      Float       // e.g. 69.240073
  address_text:   String      // human-readable, e.g. "Amir Temur ko'chasi 15, Toshkent"
  city:           String      // slug, e.g. "tashkent" — used for feed scoping
  district:       String?     // optional borough/district, e.g. "Yunusobod"
}
```

`latitude` and `longitude` are the source of truth for all distance math. `address_text` is display-only — shown to users and used as the deep-link label. Never derive coordinates from `address_text` at runtime (geocoding is slow and unreliable in Central Asia).

### How coordinates are set (host flow)

**During venue creation — Step: Address**

1. Host types an address into a search field.
2. Field queries the **2GIS Geocoding API** and shows an autocomplete dropdown of matching addresses (limited to the host's selected city).
3. Host selects a result → map view renders below the field with a draggable pin at the geocoded coordinate.
4. Host drags the pin to the exact entrance/storefront if the geocoded position is off.
5. Final `latitude` and `longitude` are taken from the pin position at save time — not from the geocoded result directly. This handles cases where 2GIS geocoding is imprecise for smaller streets.
6. `address_text` is pre-filled from the selected autocomplete result but editable by the host.

**Editing an existing venue**

Same flow. The existing pin is shown on the map at the stored coordinate. Host can move it or re-search.

**Fallback if 2GIS geocoding fails**

Host can skip the search and place the pin manually on the map (starts centered on the selected city). This guarantees a coordinate is always set, even for venues on unnamed lanes.

### Distance calculation (user side)

```
// Haversine formula — client-side
distance_km = haversine(user.lat, user.lng, venue.lat, venue.lng)
```

Computed on the client using the user's last known GPS position. Result shown on venue cards as "0.8 km" or "1.2 km". If location permission was denied, distance field is hidden (not shown as 0 or unknown).

Distance used in the feed ranking algorithm is computed server-side using the user's last reported position (updated on each app open). Server stores `user.last_lat`, `user.last_lng` — never a history, only the current position.

### Directions deep-link

```
// 2GIS (primary)
dgis://2gis.ru/routeSearch/to/{longitude},{latitude}/go

// Google Maps (fallback)
https://www.google.com/maps/dir/?api=1&destination={latitude},{longitude}
```

"Directions" button checks if the 2GIS app is installed. If yes: 2GIS deep-link. If no: Google Maps URL (opens in browser or Google Maps app).

### Map pin on venue detail page

- Embedded static map tile showing the venue pin (non-interactive).
- Tapping the map tile triggers the Directions deep-link flow above.
- Use **2GIS Static Maps API** for the tile. Fallback: Google Static Maps API.
- Do not embed a full interactive map widget in the venue detail page — it adds significant load time and the use case (navigate to the venue) is served by the deep-link.

### Database indexing

Store `latitude` and `longitude` as separate `FLOAT` / `DOUBLE PRECISION` columns (not a JSON blob) so a spatial index can be added later.

For v1: a regular index on `(city, latitude, longitude)` is sufficient — all queries are scoped to a city first, which reduces the dataset to a manageable size.

For future geo-search (e.g., "venues within 2 km of my GPS"): add a PostGIS `GEOGRAPHY` column or use a geospatial index (H3 hexagons or similar) at that point. Don't pre-build it — v1 city-scoped queries don't need it.

---

## Technical Notes

- **Auth**: single JWT with a `role` field (`user` | `host`). Mode switch changes tab bar and API scope — no re-login.
- **Feed**: ranked server-side. Response shape includes `is_sponsored: Boolean` on every card from day one. Sponsored slots are every 5th position.
- **Push notifications**: FCM. Host ad campaigns trigger server-side scheduled jobs. Frequency cap (1/day, 3/week per user) enforced at send time.
- **PDF menu**: S3-compatible object storage. Max 10 MB. In-app viewer only.
- **Maps**: 2GIS deep-link first (dominant in Central Asia); Google Maps fallback.
- **Share**: native share sheet with a universal deep link. Primary targets: Telegram, WhatsApp.
- **Ad payments**: Payme / Click (Uzbekistan); extend per market.
- **Location**: "while using" permission only. Distances computed client-side from last known position — no continuous tracking.
- **Photo moderation**: user-uploaded photos (via reviews) are stored but flagged for async moderation. A "report photo" option is available on full-screen photo view, same 2-tap flow as review reporting.
- **City scope**: all feed, search, and ad targeting is scoped to the user's selected city. City stored in user profile, changeable anytime.
