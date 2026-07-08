# Ayant — Claude Design Prompt File

**How to use:** Copy everything below the divider line and paste into Claude, then add your request at the end — e.g. "Design the Home Feed screen" or "Design the Host Venue Form."

---

## CONTEXT BLOCK (paste this every time)

You are designing **Ayant** — a mobile app for iOS (iPhone). It is a local business discovery platform for Central Asia (Bishkek, Kyrgyzstan), similar to Yelp. The UI language is Russian.

The app has two sides:
- **User side** — people discover cafes, restaurants, deals, earn bonuses, collect loyalty stamps
- **Business (Host) side** — business owners manage their venue, post deals, view analytics, scan customer QR codes

Produce your designs as **self-contained HTML** that looks like an iPhone screen (390×844px, rounded corners, with a status bar). Use inline CSS only, no external dependencies. Make it pixel-precise and realistic — not a wireframe.

---

## BRAND & VISUAL STYLE

**App name:** Ayant (Аянт)

**Primary color:** `#FF4D29` (warm red-orange) — used for CTAs, active states, badges, icons
**Gradient:** `#FF4D29` → `#FFB300` — used for wallet card, loyalty pass, promo banners
**Dark background:** `#1C1C1E` — dark mode base
**Success/open:** `#34C759` (system green)
**Warning/paused:** `#FF9500` (system orange)
**Promo type:** `#AF52DE` (purple)
**Novelty type:** `#30B0C7` (teal)
**Announcement type:** `#007AFF` (blue)

**Font:** SF Pro (use system-ui or -apple-system in HTML)
**Border radius:** Cards = 16px, Buttons = 12px, Chips = 20px (pill), Bottom sheet = 24px top corners
**Shadows:** `0 2px 12px rgba(0,0,0,0.08)` for cards on light; `0 2px 12px rgba(0,0,0,0.3)` on dark
**Spacing unit:** 16px base padding, 12px between cards

**Design mood:** Clean, modern, warm. Think Yelp meets local Central Asian aesthetic. Friendly but premium.

**Default theme:** Light mode (white background `#F2F2F7`, card surface `#FFFFFF`)

---

## UI COMPONENTS (reuse across screens)

### Tab Bar (User side — 5 tabs)
Tabs: Главная (house icon) | Поиск (magnifier) | Сохранённое (heart) | Бонусы (gift) | Профиль (person)
Active tab: `#FF4D29` icon + label. Inactive: gray.

### Tab Bar (Host side — 5 tabs)
Tabs: Заведения (storefront) | Отзывы (star bubble) | Аналитика (bar chart) | Продвижение (megaphone) | Профиль (person)

### Venue Card
- Full-width, 16px horizontal padding, 16px corner radius, white bg, subtle shadow
- Top: cover image (full width, height ~180px) with gradient overlay at bottom
  - Overlay shows: venue name (white, bold 17px), category badge (pill, semi-transparent white)
- Bottom section (white, 12px padding):
  - Row 1: ⭐ rating (e.g. "4.7") + "(128 отзывов)" in gray + distance "· 0.8 км"
  - Row 2: district chip + open/closed status ("Открыто · до 22:00" in green OR "Закрыто" in gray)
  - Row 3: if today's special exists — orange pill "🔥 Сегодня: [special text]"
  - Heart icon (top-right of image, white with shadow, filled=saved)
  - Verified badge (✓ blue pill, top-left of image, if verified)

### Deal Card (grid cell, ~160px wide)
- Cover image (height ~100px) OR large emoji centered on gradient bg
- Deal type badge top-left (colored pill: Скидка/Акция/Новинка/Объявление)
- Title (2 lines, 13px bold)
- Price row: old price strikethrough + new price in `#FF4D29` OR discount % badge
- Urgency badge if ending soon: "Осталось Xч" in red

### Star Rating
5 stars, filled/empty, `#FF4D29` color for filled stars. Show numeric average next to stars.

### Category Chip
Pill shape, 8px padding, icon + label, gray bg light / slightly darker on press. Active = `#FF4D29` bg + white text.

### Status Badge
Pill, 6px padding horizontal: Активно=green, На паузе=orange, Черновик=blue, Завершено=gray, На модерации=orange

### Review Row
- Avatar: circle with initial letter, gradient bg (#FF4D29→#FFB300)
- Author name (bold) + date (gray, right)
- Stars row
- Review text (up to 3 lines)
- Item tag if present: "📍 Отзыв об объекте: [item name]" in small gray pill
- Host reply box (if present): indented, gray bg, "Ответ заведения:" label in orange

### Action Button (primary)
Full-width or prominent, `#FF4D29` bg, white text, 12px radius, 50px height

### Section Header
Bold 20px title (left) + optional "Смотреть все" link (right, `#FF4D29`, 14px)

---

## SCREENS — USER SIDE

### U1. Home Feed (Главная)
Content (top to bottom, scrollable):
1. Top bar: "Бишкек ▾" city label left, notification bell right, search bar below (gray bg pill)
2. Category story row (horizontal scroll): round icons for Кафе / Кофейня / Фастфуд / Ресторан / Чайхана / Пекарня
3. Section "Сегодня особенное 🔥" — horizontal scroll of compact venue cards (120px wide) with today's special text
4. Section "Рядом с вами" — vertical list of VenueCards (show 3, then "Смотреть все")
5. Every 5th card: Ad placeholder card — gray dashed border, "📢 Здесь может быть ваша реклама" centered, "Узнать больше" link in `#FF4D29`

### U2. Search (Поиск)
1. Search bar (active, keyboard shown)
2. Segmented control: Список | Карта
3. Filter row (horizontal chips): Категория | По рейтингу | Открыто сейчас
4. List mode: VenueCards matching query
5. Map mode: Apple Maps style, colored pins, MapPreviewCard mini-sheet at bottom (88px fixed height, slides up on pin tap) showing: venue name, stars, distance, open status, "→" arrow to open full detail

### U3. Venue Detail
Sections (scrollable):
1. Hero image full-bleed (250px) with gradient overlay — name, category, verified badge, rating, share button
2. Action row (horizontal icons): 📞 Позвонить | 🗺 Маршрут | 💬 WhatsApp | 📸 Instagram | 📨 Telegram
3. Info card: address | hours today ("Открыто · до 22:00") | expandable week schedule
4. Today's Special highlight card (if set) — gradient bg `#FF4D29`→`#FFB300`, white text
5. Loyalty card banner (if venue has loyalty) — stamp icon, "Соберите N штампов → награда", orange
6. Deals grid section: 2-column grid of Deal Cards, "Смотреть все" if >6
7. Items strip (horizontal scroll): emoji + item name chips for reviewable items
8. Reviews section: rating breakdown bars + list of ReviewRows
9. "Написать отзыв" button

### U4. Deal Detail
1. Hero image carousel (or emoji on gradient, 240px)
2. Deal type badge + urgency badge
3. Title (24px bold) + details text
4. Price: old price strikethrough → new price (28px, `#FF4D29`) + "−X%" badge
5. "Действует до [date]" in gray
6. "Получить купон" primary button (full-width, `#FF4D29`)
7. Venue info row: emoji + name + "→" link

### U5. Saved (Сохранённое)
1. Segmented: Заведения | Акции
2. Grid/list of saved VenueCards or DealCards
3. Empty state: heart icon illustration + "Сохраняйте заведения и акции"

### U6. Bonus Hub (Бонусы)
1. Wallet card: gradient `#FF4D29`→`#FFB300`, white text, large balance "1 240 бонусов", "Твой баланс" label
2. Active Time card: circular progress ring (`#FF4D29`), "⚡ Осталось 18:30", "За 30 мин активности +20 бонусов", daily progress "3 из 4 циклов сегодня"
3. Games section: two cards side by side — 🐍 Змейка and 🟦 Тетрис, "Играй и зарабатывай бонусы"
4. Rewards section "Потрать бонусы": 4 reward tiles in 2-col grid — each shows emoji, title, cost pill

### U7. Loyalty Card Screen
1. Venue name + "Программа лояльности" header
2. Large stamp card visual: 3×2 (or N) grid of stamp cells — filled = `#FF4D29` circle with ✓, empty = gray dashed circle
3. Progress "4 / 6 штампов"
4. Reward label "Награда: [reward text]" in green pill
5. QR code (show as placeholder square) with "Показать кассиру для сканирования"
6. "Добавить в Apple Wallet" button (black, Apple Wallet style)

### U8. Coupon Detail
1. Large emoji + title (centered, 20px bold)
2. Venue name chip
3. Code in monospace, large — "AYANT-ABC123"
4. QR code placeholder
5. Status pill: "✓ Активен" (green) or "Использован" (gray)
6. If venue-bound: "Покажите купон сотруднику заведения" + "Добавить в Wallet"
7. If generic: "Отметить как использованный" button

### U9. Profile (Профиль)
1. Avatar circle (initial, gradient) + name + email
2. List sections:
   - "Мои отзывы" → count badge
   - "Настройки" (Тема / Язык / Уведомления)
   - "Переключиться в режим бизнеса" (orange accent, storefront icon)
   - "Помощь / FAQ"
   - "О приложении" (version + social links)
   - "Выйти" (red text)

### U10. Write Review Sheet (bottom sheet)
1. "Оставить отзыв" title + close button
2. Item picker: horizontal chips for each venue item (required selection)
3. Star selector: 5 large tappable stars
4. Text area: "Расскажите о вашем опыте…" placeholder
5. "Опубликовать" primary button (disabled until item + rating selected)

---

## SCREENS — BUSINESS (HOST) SIDE

### H1. Host Onboarding
1. "Режим бизнеса" large title + storefront illustration
2. Form fields: Название бизнеса / Категория (picker) / Телефон / Email
3. "Зарегистрировать бизнес" primary button
4. Note: "После регистрации ваше заведение пройдёт модерацию"

### H2. My Venues (Заведения tab)
1. "Мои заведения" title + scanner icon (top right) + "+" add button
2. List of venue rows: emoji circle + name + category + moderation badge + paused indicator
3. Each row: chevron right
4. Empty state: "Добавьте ваше первое заведение" with "+" CTA

### H3. Venue Form
Long scrollable form in sections:
1. **Основное:** Название / Категория / Эмодзи / Фото (URL field + 100px image preview) / PDF меню
2. **Контакты:** Телефон / WhatsApp / Instagram / Telegram
3. **Расположение:** Map preview (120px, non-interactive) + "Выбрать точку на карте" button / Район / Адрес / Филиалы
4. **Часы работы:** 7-day table (Пн–Вс), each row: day label + toggle "Выходной" + time range "09:00 – 22:00"
5. **Сегодня особенное:** Text field
6. **Программа лояльности:** Toggle + if on: stepper "N штампов" + "Текст награды" field
7. **Купоны:** Toggle "Принимать купоны"
8. **Блюда / Услуги:** List of items (emoji + name + kind) + "Добавить позицию" button
9. **Модерация:** Status badge (read-only) + "Запросить верификацию" button
10. "Сохранить" primary button (floating or at bottom)

### H4. Deal Form
Form:
1. Тип (segmented or picker): Скидка | Акция | Новинка | Объявление
2. Заголовок / Описание / Эмодзи
3. Цены: Старая цена / Новая цена / Скидка %
4. Даты: Начало — Конец (date pickers)
5. Статус: Активно / На паузе / Черновик
6. Фото: URL field + gallery URLs
7. "Сохранить" button

### H5. Reviews Inbox (Отзывы tab)
1. "Отзывы" title
2. Unseen badge count
3. List sorted (unanswered first):
   - Venue name chip (orange) above each review
   - ReviewRow (avatar, stars, text, date)
   - "Ответить" / "Изменить ответ" button (bordered, orange)
4. HostReplyView sheet: text editor + "Опубликовать ответ" button

### H6. Analytics (Аналитика tab)
1. Period picker: 7 дней | 30 дней | 90 дней
2. Venue selector (if multiple venues)
3. Metrics grid (2-col): each cell = icon + metric name + big number + trend arrow
   - 👁 Просмотры / ❤️ Сохранения / 📞 Звонки / 🗺 Маршруты / 🏷 Акции
4. Simple bar chart (daily breakdown for selected period)

### H7. Promote (Продвижение tab)
Two sections:
1. **Реклама:** Campaign list cards — title, audience, budget, status badge, "просмотры: X · тапы: Y" analytics row. "Создать кампанию" button.
2. **Push-рассылка:** Form — Заголовок / Текст / Аудитория (Бишкек / Все пользователи). "Запустить рассылку" button. Note about frequency cap.

### H8. QR Scanner (HostScannerView)
1. Full-screen camera viewfinder
2. Square scan frame with corner brackets (`#FF4D29`)
3. Venue selector row at top (dropdown)
4. Bottom sheet (slides up on scan):
   - ✅ / ❌ icon
   - Result text: "Купон принят — штамп добавлен!" or "Купон уже использован"
   - Customer name + deal/loyalty info
5. "Ввести код вручную" link at bottom

### H9. Host Profile tab
1. Business name + category + verification badge
2. Edit fields: phone / email
3. "Запросить верификацию" (if not verified)
4. "Переключиться в режим пользователя" button (secondary)

---

## HOW TO REQUEST A SPECIFIC SCREEN

After pasting this whole document, add one of:

- `"Design screen U1 — Home Feed"`
- `"Design screen U3 — Venue Detail, showing a coffee shop called 'Аромат' with a loyalty banner and 3 deals"`
- `"Design screen H6 — Analytics, showing 30-day data"`
- `"Design the empty state for U5 — Saved"`
- `"Design the MapPreviewCard mini-sheet from U2"`
- `"Design the Venue Card component in both saved and unsaved states"`
- `"Design screens U1 and H2 side by side for comparison"`

You can also specify: **light/dark mode**, **specific content to show**, or **a particular state** (empty, error, loading).
