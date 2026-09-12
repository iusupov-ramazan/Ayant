# App Store listing — Ayant 1.0

Copy for App Store Connect. Character limits are Apple's: name 30, subtitle 30,
promotional text 170, description 4000, keywords 100 (comma-separated, no spaces
needed), what's new 4000. Primary locale: Russian. English copy for the
secondary locale.

---

## Русский (основная локаль)

**Название (≤30):** Ayant

**Подзаголовок (≤30):** Скидки, акции и бонусы Бишкека

**Промо-текст (≤170):**
Акции заведений Бишкека в одной ленте. Показывайте QR при оплате — копите баллы и штампы, получайте награды и купоны. Первые заведения уже с нами.

**Описание (≤4000):**

Ayant — приложение о том, где в Бишкеке сегодня выгодно. Заведения публикуют скидки, акции и новинки, а вы получаете их одной лентой — без рекламных подборок и накруток.

ЛЕНТА ПРЕДЛОЖЕНИЙ
• Скидки, акции и новинки кафе, ресторанов, кофеен и фастфуда
• Фильтр по категориям и список всех заведений рядом
• Страница заведения: часы работы, адрес, маршрут в 2GIS или Google Maps, звонок в одно касание
• Сохраняйте любимые места и получайте push о новых предложениях именно там

КУПОНЫ
• Получите купон на акцию в приложении и покажите QR сотруднику перед оплатой
• Купон одноразовый и привязан к вашему аккаунту — сотрудник сканирует его, и предложение применяется

БАЛЛЫ САН
• Показывайте свой QR при оплате — заведение начисляет баллы за визит, по сумме чека или кэшбэком
• Баллы копятся у каждого заведения отдельно и тратятся на его награды: блюдо в подарок или скидка сомами
• История начислений и списаний, живой баланс, напоминание за неделю до сгорания

КАРТА ШТАМПОВ
• Штамп за каждый визит — сотрудник сканирует QR вашей карты
• Заполнили карту — награда сразу приходит купоном в «Мои купоны»

ОТЗЫВЫ
• Оценивайте заведения и отдельные блюда, добавляйте фото
• Владелец может ответить — вы получите уведомление

ДЛЯ БИЗНЕСА
Переключитесь в режим заведения прямо в приложении: добавьте заведение и акции, настройте баллы или карту штампов, сканируйте QR гостей и смотрите статистику — просмотры, звонки, маршруты, погашенные купоны, выданные награды.

Ayant работает в Бишкеке. Вход через Apple, Google или почту; можно смотреть ленту как гость.

**Ключевые слова (≤100):**
скидки,акции,бишкек,кафе,ресторан,купоны,бонусы,кэшбэк,лояльность,штампы,еда,доставка,кыргызстан

**Что нового (1.0):**
Первый выпуск: лента акций Бишкека, купоны, баллы САН и карта штампов, отзывы, режим заведения для бизнеса.

**URL поддержки:** https://ayant.kg/about
**URL маркетинга:** https://ayant.kg
**Политика конфиденциальности:** https://ayant.kg/privacy.html

---

## English (secondary locale)

**Name:** Ayant

**Subtitle (≤30):** Deals & rewards in Bishkek

**Promotional text (≤170):**
Every deal in Bishkek in one feed. Show your QR when you pay — earn points and stamps, get rewards and coupons. The first venues are already on board.

**Description:**

Ayant shows you where in Bishkek it pays to go today. Venues publish discounts, promotions and new items, and you get them in a single feed — no sponsored lists, no fake ratings.

THE FEED
• Discounts, promotions and novelties from cafés, restaurants, coffee shops and fast food
• Filter by category or browse every venue nearby
• Venue page with hours, address, directions in 2GIS or Google Maps, one-tap call
• Save your favourite places and get notified about new deals there

COUPONS
• Take a coupon for a deal and show the QR to staff before paying
• Coupons are single-use and tied to your account; staff scans it and the deal is applied

SAN POINTS
• Show your QR when you pay — the venue awards points per visit, by bill amount, or as cashback
• Points are earned and spent at that venue: a free item or a discount in som
• Full history, live balance, and a reminder a week before points expire

STAMP CARD
• One stamp per visit — staff scans your card's QR
• Fill the card and the reward arrives as a coupon in My Coupons

REVIEWS
• Rate venues and individual dishes, add photos
• Owners can reply, and you'll be notified

FOR BUSINESSES
Switch to venue mode inside the app: add your venue and deals, set up points or a stamp card, scan guests' QR codes and track views, calls, directions, redeemed coupons and issued rewards.

Ayant works in Bishkek. Sign in with Apple, Google or email, or browse the feed as a guest.

**Keywords (≤100):**
deals,discounts,bishkek,cafe,restaurant,coupons,rewards,cashback,loyalty,stamps,food,kyrgyzstan

**What's new (1.0):**
First release: Bishkek deals feed, coupons, SAN points and stamp cards, reviews, venue mode for businesses.

---

## App Review information

**Notes for the reviewer (English):**

Ayant is a deals and loyalty app for venues in Bishkek, Kyrgyzstan. The UI is in Russian; an English localization is included (Profile → Язык → English).

Two roles exist in one app:
1. Guest (default). Browse deals, take coupons, collect points and stamps.
2. Venue (host). Profile → «Режим заведения». Requires a business account. The scanner tab uses the camera to scan guests' QR codes; it only works for a venue owned by the signed-in business account.

Test accounts (fill in before submitting):
- Guest: <email> / <password>
- Venue owner: <email> / <password> — owns the venue «<name>» with points and a stamp card enabled.

To see the loyalty flow end to end with one device: sign in as the venue owner, open Сканер, and scan the guest QR shown at https://ayant.kg (or a second device signed in as the guest). Points and stamps are written by our Cloud Functions; balances update live.

Account deletion: Profile → «Удалить аккаунт». Sign in with Apple accounts revoke the Apple token before deletion.

Location is used only to show distances to venues. The camera is used only by the venue-mode scanner. No tracking; see the privacy manifest.

**Demo venue configuration checklist (do this in the admin panel before submitting):**
- at least 5 approved venues with photos and one active discount or promo deal each
- one venue with points enabled (flat mode, 50 points per visit, one item reward at 100 points)
- one venue with the stamp card enabled (goal 3)

---

## App Privacy answers (matches SAN/PrivacyInfo.xcprivacy)

Data collected, linked to the user, not used for tracking:
- Email address, Name, User ID — app functionality (account)
- Product interaction — analytics (venue statistics: views, taps, calls)

Data collected, not linked: Coarse location — app functionality (distances). Location is never stored.

No third-party advertising. No tracking; ATT prompt is not shown.

---

## Screenshots (6.9-inch, 1320×2868)

Order in App Store Connect, with the caption baked into each image:
1. Главная — «Все акции Бишкека в одной ленте»
2. Заведения — «Кафе, рестораны, кофейни рядом»
3. Страница заведения — «Часы, маршрут, звонок — в одно касание»
4. Акция и купон — «Купон в приложении, QR — сотруднику»
5. Мой QR — «Покажите QR — копите баллы»
6. Бонусы — «Баллы и штампы у каждого заведения»
7. Начислено — «Награда за каждый визит»

Frames 1–4 are produced by `docs/appstore/make_screenshots.py` from simulator captures in `docs/appstore/screenshots/raw/`. Frames 5–7 need a signed-in account with points: capture them on a device (Settings → screenshot on iPhone 17 Pro Max or any 6.9-inch iPhone), drop the PNGs into `raw/` as `05-qr.png`, `06-wallet.png`, `07-earned.png`, and rerun the script.
