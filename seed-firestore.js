/**
 * Firestore Seed Script — SAN app
 *
 * Seeds all venues and deals from MockData.swift into Firebase Firestore.
 *
 * Setup:
 *   1. npm install firebase-admin
 *   2. Firebase Console → Project Settings → Service accounts → Generate new private key
 *      → save as serviceAccountKey.json next to this file
 *   3. node seed-firestore.js
 */

const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const serviceAccount = require("./serviceAccountKey.json");

initializeApp({ credential: cert(serviceAccount) });

const db = getFirestore();

// ─── Helpers ────────────────────────────────────────────────────────────────

function daysFromNow(n) {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return Timestamp.fromDate(d);
}

function hoursFromNow(n) {
  const d = new Date();
  d.setHours(d.getHours() + n);
  return Timestamp.fromDate(d);
}

// ─── Venues (10 заведений) ───────────────────────────────────────────────────

const venues = [
  {
    id: "navat",
    name: "Navat",
    category: "teahouse",
    district: "Центр",
    address: "пр. Чуй, 125",
    phone: "+996 312 909 000",
    emoji: "🫖",
    gradientFrom: "#E65C00",
    gradientTo: "#F9D423",
    active: true,
  },
  {
    id: "faiza",
    name: "Faiza",
    category: "cafe",
    district: "Восток-5",
    address: "ул. Медерова, 217",
    phone: "+996 555 919 555",
    emoji: "🥟",
    gradientFrom: "#11998E",
    gradientTo: "#38EF7D",
    active: true,
  },
  {
    id: "sierra",
    name: "Sierra Coffee",
    category: "coffee",
    district: "Центр",
    address: "ул. Манаса, 57",
    phone: "+996 312 311 000",
    emoji: "☕️",
    gradientFrom: "#5D4157",
    gradientTo: "#A8CABA",
    active: true,
  },
  {
    id: "bublik",
    name: "Bublik",
    category: "bakery",
    district: "Центр",
    address: "ул. Токтогула, 93",
    phone: "+996 700 905 905",
    emoji: "🥐",
    gradientFrom: "#F7971E",
    gradientTo: "#FFD200",
    active: true,
  },
  {
    id: "furusato",
    name: "Furusato",
    category: "restaurant",
    district: "Центр",
    address: "пр. Эркиндик, 35",
    phone: "+996 555 750 750",
    emoji: "🍣",
    gradientFrom: "#C31432",
    gradientTo: "#240B36",
    active: true,
  },
  {
    id: "chickenstar",
    name: "Chicken Star",
    category: "fastfood",
    district: "Центр",
    address: "пр. Эркиндик, 36",
    phone: "+996 708 700 007",
    emoji: "🍗",
    gradientFrom: "#F12711",
    gradientTo: "#F5AF19",
    active: true,
  },
  {
    id: "cyclone",
    name: "Cyclone",
    category: "restaurant",
    district: "Центр",
    address: "пр. Чуй, 136",
    phone: "+996 312 621 190",
    emoji: "🍝",
    gradientFrom: "#355C7D",
    gradientTo: "#C06C84",
    active: true,
  },
  {
    id: "adriano",
    name: "Adriano Coffee",
    category: "coffee",
    district: "Моссовет",
    address: "ул. Киевская, 77",
    phone: "+996 702 909 290",
    emoji: "🍵",
    gradientFrom: "#3E5151",
    gradientTo: "#DECBA4",
    active: true,
  },
  {
    id: "arzu",
    name: "Арзу",
    category: "cafe",
    district: "Юг-2",
    address: "ул. Горького, 1Б",
    phone: "+996 312 540 540",
    emoji: "🍲",
    gradientFrom: "#870000",
    gradientTo: "#190A05",
    active: true,
  },
  {
    id: "shaurma1",
    name: "Шаурма №1",
    category: "fastfood",
    district: "Аламедин-1",
    address: "ул. Лущихина, 10",
    phone: "+996 550 100 100",
    emoji: "🌯",
    gradientFrom: "#636FA4",
    gradientTo: "#E8CBC0",
    active: true,
  },
];

// ─── Deals (15 предложений) ──────────────────────────────────────────────────

const deals = [
  {
    id: "d1",
    venueID: "navat",
    type: "discount",
    title: "−30% на манты по будням",
    details: "С 11:00 до 15:00 на все виды мантов. Идеально на обед.",
    emoji: "🥟",
    oldPrice: 280,
    newPrice: 195,
    discountPercent: 30,
    validUntil: daysFromNow(12),
  },
  {
    id: "d2",
    venueID: "navat",
    type: "promo",
    title: "Чайник чая в подарок",
    details: "При заказе от 1500 сом — чайник ташкентского чая бесплатно.",
    emoji: "🫖",
    oldPrice: null,
    newPrice: null,
    discountPercent: null,
    validUntil: daysFromNow(6),
  },
  {
    id: "d3",
    venueID: "faiza",
    type: "discount",
    title: "−20% на лагман",
    details: "Фирменный лагман по будням после 16:00.",
    emoji: "🍜",
    oldPrice: 320,
    newPrice: 255,
    discountPercent: 20,
    validUntil: daysFromNow(9),
  },
  {
    id: "d4",
    venueID: "sierra",
    type: "promo",
    title: "1+1 на капучино",
    details: "Каждое утро до 10:00 — второй капучино бесплатно.",
    emoji: "☕️",
    oldPrice: null,
    newPrice: null,
    discountPercent: null,
    validUntil: daysFromNow(20),
  },
  {
    id: "d5",
    venueID: "sierra",
    type: "novelty",
    title: "Bumble с апельсином",
    details: "Новый летний кофе: эспрессо + свежевыжатый апельсин.",
    emoji: "🍊",
    oldPrice: null,
    newPrice: 290,
    discountPercent: null,
    validUntil: daysFromNow(25),
  },
  {
    id: "d6",
    venueID: "bublik",
    type: "discount",
    title: "−50% на выпечку вечером",
    details: "Ежедневно после 20:00 — вся витрина за полцены.",
    emoji: "🥐",
    oldPrice: null,
    newPrice: null,
    discountPercent: 50,
    validUntil: daysFromNow(30),
  },
  {
    id: "d7",
    venueID: "furusato",
    type: "novelty",
    title: "Сет «Бишкек» — 24 ролла",
    details: "Новый большой сет: филадельфия, калифорния, запечённые.",
    emoji: "🍣",
    oldPrice: null,
    newPrice: 1890,
    discountPercent: null,
    validUntil: daysFromNow(18),
  },
  {
    id: "d8",
    venueID: "furusato",
    type: "discount",
    title: "−15% на всё меню по вторникам",
    details: "Весь день, на зал и самовывоз.",
    emoji: "🍱",
    oldPrice: null,
    newPrice: null,
    discountPercent: 15,
    validUntil: daysFromNow(14),
  },
  {
    id: "d9",
    venueID: "chickenstar",
    type: "promo",
    title: "Комбо «Стар» за 390 сом",
    details: "Крылышки + картофель + напиток. Обычная цена 520 сом.",
    emoji: "🍗",
    oldPrice: 520,
    newPrice: 390,
    discountPercent: null,
    validUntil: daysFromNow(8),
  },
  {
    id: "d10",
    venueID: "cyclone",
    type: "discount",
    title: "−25% на пасту в обед",
    details: "Будни с 12:00 до 15:00, вся паста ручной работы.",
    emoji: "🍝",
    oldPrice: 480,
    newPrice: 360,
    discountPercent: 25,
    validUntil: daysFromNow(10),
  },
  {
    id: "d11",
    venueID: "adriano",
    type: "novelty",
    title: "Матча-латте",
    details: "Японская матча церемониального сорта, на любом молоке.",
    emoji: "🍵",
    oldPrice: null,
    newPrice: 270,
    discountPercent: null,
    validUntil: daysFromNow(22),
  },
  {
    id: "d12",
    venueID: "adriano",
    type: "promo",
    title: "Десерт в подарок к кофе",
    details: "С 14:00 до 16:00 — чизкейк или брауни к любому кофе.",
    emoji: "🍰",
    oldPrice: null,
    newPrice: null,
    discountPercent: null,
    validUntil: daysFromNow(5),
  },
  {
    id: "d13",
    venueID: "arzu",
    type: "discount",
    title: "−20% на бешбармак",
    details: "Для компаний от 4 человек, по предзаказу.",
    emoji: "🍲",
    oldPrice: null,
    newPrice: null,
    discountPercent: 20,
    validUntil: daysFromNow(11),
  },
  {
    id: "d14",
    venueID: "shaurma1",
    type: "promo",
    title: "Вторая шаурма −50%",
    details: "На классическую и сырную, ежедневно.",
    emoji: "🌯",
    oldPrice: null,
    newPrice: null,
    discountPercent: null,
    validUntil: daysFromNow(7),
  },
  {
    id: "d15",
    venueID: "shaurma1",
    type: "novelty",
    title: "Шаурма с сыром",
    details: "Двойной сыр, фирменный соус. Уже в меню.",
    emoji: "🧀",
    oldPrice: null,
    newPrice: 250,
    discountPercent: null,
    validUntil: daysFromNow(16),
  },
];

// ─── Venue extra fields (рейтинг, координаты, спец, часы) ────────────────────
// Город — Бишкек для всех. Координаты — реальные районы Бишкека.

const venueExtras = {
  navat:       { rating: 4.6, reviewCount: 213, isVerified: true,  savedByCount: 214, latitude: 42.8760, longitude: 74.6010, openHour: 10, closeHour: 23, todaySpecial: "Плов по-фергански весь день — 290 сом", photoEmojis: ["🫖","🍚","🥗","🍢"] },
  faiza:       { rating: 4.4, reviewCount: 168, isVerified: true,  savedByCount: 156, latitude: 42.8825, longitude: 74.6300, openHour: 9,  closeHour: 22, photoEmojis: ["🥟","🍜","🥗"] },
  sierra:      { rating: 4.7, reviewCount: 402, isVerified: true,  savedByCount: 389, latitude: 42.8745, longitude: 74.5890, openHour: 8,  closeHour: 23, todaySpecial: "Раф на кокосовом −20% до 12:00", photoEmojis: ["☕️","🍰","🥐","🧋"] },
  bublik:      { rating: 4.3, reviewCount: 97,  isVerified: false, savedByCount: 88,  latitude: 42.8710, longitude: 74.6020, openHour: 8,  closeHour: 21, photoEmojis: ["🥐","🍞","🥨"] },
  furusato:    { rating: 4.5, reviewCount: 254, isVerified: true,  savedByCount: 271, latitude: 42.8690, longitude: 74.6105, openHour: 11, closeHour: 23, pdfMenuURL: "https://example.com/furusato-menu.pdf", photoEmojis: ["🍣","🍱","🍤","🥢"] },
  chickenstar: { rating: 4.2, reviewCount: 143, isVerified: false, savedByCount: 120, latitude: 42.8688, longitude: 74.6110, openHour: 10, closeHour: 24, todaySpecial: "Комбо «Стар» сегодня 350 сом", photoEmojis: ["🍗","🍟","🥤"] },
  cyclone:     { rating: 4.1, reviewCount: 76,  isVerified: false, savedByCount: 64,  latitude: 42.8762, longitude: 74.5990, openHour: 12, closeHour: 23, photoEmojis: ["🍝","🍷","🥩"] },
  adriano:     { rating: 4.8, reviewCount: 311, isVerified: true,  savedByCount: 342, latitude: 42.8770, longitude: 74.5805, openHour: 8,  closeHour: 22, photoEmojis: ["🍵","☕️","🍰"] },
  arzu:        { rating: 4.0, reviewCount: 52,  isVerified: false, savedByCount: 41,  latitude: 42.8530, longitude: 74.6000, openHour: 9,  closeHour: 22, photoEmojis: ["🍲","🥘"] },
  shaurma1:    { rating: 4.5, reviewCount: 188, isVerified: false, savedByCount: 173, latitude: 42.8900, longitude: 74.6200, openHour: 10, closeHour: 24, todaySpecial: "Вторая шаурма −50% после 18:00", photoEmojis: ["🌯","🧀","🥙"] },
};

// ─── Deal extra fields (статус, дата старта, картинки) ───────────────────────
const dealExtras = {
  d1:  { startDate: hoursFromNow(-20) }, d2: { startDate: daysFromNow(-5) },
  d3:  { startDate: daysFromNow(-3) },   d4: { startDate: hoursFromNow(-30) },
  d5:  { startDate: daysFromNow(-8) },   d6: { startDate: daysFromNow(-12) },
  d7:  { startDate: hoursFromNow(-10) }, d8: { startDate: daysFromNow(-6) },
  d9:  { startDate: daysFromNow(-2) },   d10:{ startDate: daysFromNow(-4) },
  d11: { startDate: daysFromNow(-9) },   d12:{ startDate: daysFromNow(-1) },
  d13: { startDate: daysFromNow(-7) },   d14:{ startDate: hoursFromNow(-40) },
  d15: { startDate: daysFromNow(-5) },
};

// ─── Reviews (10 отзывов от пользователей) ───────────────────────────────────
const reviews = [
  { id: "r1", venueID: "navat", authorID: "u_aida", authorName: "Айда", rating: 5,
    text: "Лучшая чайхана в центре. Манты огонь, чай наливают бесконечно.",
    photoEmojis: ["🥟","🫖"], createdAt: daysFromNow(-3),
    hostReply: { text: "Спасибо, Айда! Ждём снова 🫖", createdAt: daysFromNow(-2) } },
  { id: "r2", venueID: "navat", authorID: "u_marat", authorName: "Марат", rating: 4,
    text: "Вкусно, но в обед бывает шумно. Сервис быстрый.", photoEmojis: [], createdAt: daysFromNow(-10) },
  { id: "r3", venueID: "sierra", authorID: "u_lena", authorName: "Лена", rating: 5,
    text: "Мой любимый кофе в городе. Раф на кокосовом — топ.", photoEmojis: ["☕️"], createdAt: daysFromNow(-1) },
  { id: "r4", venueID: "sierra", authorID: "u_ts", authorName: "Тимур", rating: 4,
    text: "Отличное место для работы с ноутом, розеток хватает.", photoEmojis: [], createdAt: daysFromNow(-14) },
  { id: "r5", venueID: "furusato", authorID: "u_dasha", authorName: "Даша", rating: 5,
    text: "Свежие роллы, большие порции. Сет «Бишкек» берём компанией.",
    photoEmojis: ["🍣","🍱"], createdAt: daysFromNow(-5),
    hostReply: { text: "Рады, что понравилось! 🍣", createdAt: daysFromNow(-4) } },
  { id: "r6", venueID: "adriano", authorID: "u_nur", authorName: "Нуржан", rating: 5,
    text: "Матча просто космос. Десерты тоже на уровне.", photoEmojis: ["🍵"], createdAt: daysFromNow(-2) },
  { id: "r7", venueID: "shaurma1", authorID: "u_beka", authorName: "Бека", rating: 4,
    text: "Сытно и недорого. Вторая по акции — приятно.", photoEmojis: [], createdAt: daysFromNow(-6) },
  { id: "r8", venueID: "faiza", authorID: "u_gulnara", authorName: "Гульнара", rating: 4,
    text: "Лагман как у бабушки. Уютно и по-домашнему.", photoEmojis: ["🍜"], createdAt: daysFromNow(-8) },
  { id: "r9", venueID: "chickenstar", authorID: "u_sam", authorName: "Сам", rating: 3,
    text: "Курица вкусная, но ждали комбо долго.", photoEmojis: [], createdAt: daysFromNow(-11) },
  { id: "r10", venueID: "bublik", authorID: "u_olya", authorName: "Оля", rating: 5,
    text: "Круассаны утром свежайшие. Вечерняя скидка — бонус.", photoEmojis: ["🥐"], createdAt: daysFromNow(-4) },
];

// ─── Seed ────────────────────────────────────────────────────────────────────

async function seed() {
  console.log("🔥 Seeding Firestore...\n");

  // Venues (+ enriched fields)
  const venuesBatch = db.batch();
  for (const { id, ...data } of venues) {
    const merged = { ...data, city: "bishkek", ...(venueExtras[id] ?? {}) };
    const clean = Object.fromEntries(
      Object.entries(merged).filter(([, v]) => v !== null && v !== undefined)
    );
    venuesBatch.set(db.collection("venues").doc(id), clean);
  }
  await venuesBatch.commit();
  console.log(`✅ venues:  ${venues.length} documents written`);

  // Deals (+ status / startDate / imageEmojis)
  const dealsBatch = db.batch();
  for (const { id, ...data } of deals) {
    const merged = {
      ...data,
      status: "active",
      imageEmojis: data.emoji ? [data.emoji] : [],
      ...(dealExtras[id] ?? {}),
    };
    const clean = Object.fromEntries(
      Object.entries(merged).filter(([, v]) => v !== null && v !== undefined)
    );
    dealsBatch.set(db.collection("deals").doc(id), clean);
  }
  await dealsBatch.commit();
  console.log(`✅ deals:   ${deals.length} documents written`);

  // Reviews
  const reviewsBatch = db.batch();
  for (const { id, ...data } of reviews) {
    const clean = Object.fromEntries(
      Object.entries(data).filter(([, v]) => v !== null && v !== undefined)
    );
    reviewsBatch.set(db.collection("reviews").doc(id), clean);
  }
  await reviewsBatch.commit();
  console.log(`✅ reviews: ${reviews.length} documents written`);

  console.log("\n🎉 Done! Open Firebase Console to verify.");
  process.exit(0);
}

seed().catch((err) => {
  console.error("❌ Seed failed:", err);
  process.exit(1);
});
