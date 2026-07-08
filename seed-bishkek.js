/**
 * Seed — каталог заведений Бишкека (41) в Firestore по модели приложения Ayant.
 *
 * Запуск:  node seed-bishkek.js   (нужен serviceAccountKey.json рядом)
 *
 * Модель документа коллекции `venues` (как читает приложение):
 *   name, category (cafe|coffee|fastfood|restaurant|teahouse|bakery),
 *   district, address, phone, emoji, gradientFrom, gradientTo,
 *   city ("bishkek"), latitude, longitude,
 *   rating, reviewCount, savedByCount, isVerified, isPaused,
 *   status ("approved"|"pending"|"rejected"), ownerID,
 *   openHour, closeHour            // фолбэк-часы (приложение строит из них все дни)
 *   weekHours: []                  // часы по дням недели (пусто = брать openHour/closeHour)
 *   todaySpecial, pdfMenuURL, imageURL,
 *   photoEmojis: [...], items: []  // объекты для отзывов (хост добавит позже)
 */

const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const serviceAccount = require("./serviceAccountKey.json");

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

// Палитра градиентов по категории (используется как фон-фолбэк без фото).
const GRADIENT = {
  coffee:     ["#5D4157", "#A8CABA"],
  cafe:       ["#11998E", "#38EF7D"],
  fastfood:   ["#F12711", "#F5AF19"],
  restaurant: ["#355C7D", "#C06C84"],
  teahouse:   ["#E65C00", "#F9D423"],
  bakery:     ["#F7971E", "#FFD200"],
};

// helper: v(id, name, category, emoji, address, phone, lat, lng, rating, reviewCount, verified, open, close, extra)
const v = (id, name, category, emoji, address, phone, lat, lng, rating, reviewCount, verified, open, close, extra = {}) =>
  ({ id, name, category, emoji, address, phone, lat, lng, rating, reviewCount, verified, open, close, ...extra });

const venues = [
  v("kulikov",       "Kulikov",        "coffee",     "🍰", "пр. Тоголок Молдо, 22",        "+996 556 58 38 58", 42.8744, 74.6020, 4.6, 210, true,  8, 22),
  v("capito",        "Capito",         "cafe",       "🍕", "ул. Турусбекова, 100",         "+996 990 61 10 00", 42.8720, 74.5950, 4.4, 160, false, 9, 23),
  v("booblik",       "Booblik",        "coffee",     "🥯", "ул. Тоголок Молдо, 5/1",       "+996 551 15 55 55", 42.8735, 74.6095, 4.3, 140, false, 8, 22),
  v("dodo-pizza",    "Dodo Pizza",     "fastfood",   "🍕", "ул. Шопокова, 101/1",          "+996 551 55 05 50", 42.8731, 74.5945, 4.5, 380, true,  0, 24),
  v("wok-lagman",    "Wok Lagman",     "fastfood",   "🍜", "ул. Киевская, 95",             "",                  42.8730, 74.5990, 4.2, 90,  false, 0, 24),
  v("plovster",      "Plovster",       "fastfood",   "🍚", "ул. Горького, 124",            "",                  42.8760, 74.5872, 4.3, 110, false, 10, 22),
  v("drippa",        "Drippa",         "coffee",     "☕️", "ул. Анарбека Бакаева, 130/2",  "+996 500 82 98 29", 42.8710, 74.6040, 4.7, 130, false, 8, 22),
  v("ants",          "Ant's",          "restaurant", "🍽", "б. Эркиндик, 35",              "+996 772 00 10 35", 42.8740, 74.5895, 4.6, 260, true,  10, 24),
  v("giraffe",       "Giraffe Coffee", "coffee",     "☕️", "б. Эркиндик, 23",              "+996 556 33 33 53", 42.8745, 74.5900, 4.4, 120, false, 8, 22),
  v("mubarak",       "Mubarak",        "teahouse",   "🫖", "ул. Горького, 148",            "",                  42.8762, 74.5870, 4.3, 150, false, 10, 23),
  v("navat",         "Navat",          "teahouse",   "🫖", "ул. Аалы Токомбаева, 32/4",    "",                  42.8615, 74.5820, 4.6, 420, true,  0, 24),
  v("vkus-vostoka",  "Vkus Vostoka",   "restaurant", "🍲", "Бишкек (уточнить на 2ГИС)",    "",                  42.8700, 74.5950, 4.1, 60,  false, 10, 23),
  v("wasabi-sushi",  "Wasabi Sushi",   "restaurant", "🍣", "ул. Токомбаева, 23/4",         "+996 505 410 707",  42.8700, 74.5950, 4.3, 180, false, 0, 24),
  v("cooksoo",       "Cooksoo",        "restaurant", "🍜", "Бишкек, центр",                "",                  42.8720, 74.5970, 4.5, 95,  false, 11, 22),
  v("buffet",        "Buffet",         "restaurant", "🍽", "Бишкек (уточнить на 2ГИС)",    "",                  42.8700, 74.5980, 4.0, 40,  false, 11, 23),
  v("besh-manty",    "Besh Manty",     "cafe",       "🥟", "Бишкек (уточнить на 2ГИС)",    "",                  42.8700, 74.6000, 4.2, 70,  false, 9, 22),
  v("kfc",           "KFC",            "fastfood",   "🍗", "ТРЦ Bishkek Park, ул. Киевская, 148", "",           42.8697, 74.6019, 4.2, 350, true,  10, 23),
  v("chikenoff",     "Chikenoff",      "fastfood",   "🍗", "Бишкек (уточнить на 2ГИС)",    "",                  42.8710, 74.5970, 4.1, 55,  false, 10, 23),
  v("my-burger",     "My Burger",      "fastfood",   "🍔", "Бишкек (уточнить на 2ГИС)",    "",                  42.8700, 74.5940, 4.2, 65,  false, 10, 23),
  v("muslim-sushi",  "Muslim Sushi",   "restaurant", "🍣", "Бишкек (уточнить на 2ГИС)",    "",                  42.8710, 74.5980, 4.3, 80,  false, 11, 23),
  v("asia-sushi",    "Asia Sushi",     "restaurant", "🍣", "ул. Ахунбаева, 90а",           "+996 550 664 405",  42.8593, 74.5936, 4.4, 240, true,  0, 24),
  v("hi-tea",        "Hi Tea",         "coffee",     "🧋", "Бишкек (уточнить на 2ГИС)",    "",                  42.8710, 74.5950, 4.4, 90,  false, 10, 22),
  v("teaday",        "Teaday",         "coffee",     "🧋", "Бишкек (уточнить на 2ГИС)",    "",                  42.8730, 74.5980, 4.3, 85,  false, 10, 22),
  v("makaronnaya",   "Makaronnaya",    "restaurant", "🍝", "Бишкек (уточнить на 2ГИС)",    "",                  42.8720, 74.5930, 4.2, 70,  false, 11, 23),
  v("sierra-coffee", "Sierra Coffee",  "coffee",     "☕️", "пр. Манаса, 57а",              "+996 770 969 690",  42.8710, 74.5980, 4.7, 402, true,  8, 23),
  v("zebra-coffee",  "Zebra Coffee",   "coffee",     "☕️", "Бишкек (уточнить на 2ГИС)",    "",                  42.8730, 74.6020, 4.3, 95,  false, 8, 22),
  v("social-coffee", "Social Coffee",  "coffee",     "☕️", "ул. Раззакова, 62",            "",                  42.8742, 74.6008, 4.5, 110, false, 8, 22),
  v("bellagio",      "Bellagio Coffee","coffee",     "☕️", "пр. Манаса, 49",               "+996 707 128 888",  42.8720, 74.5985, 4.4, 200, true,  8, 23),
  v("mantovarka",    "Mantovarka",     "cafe",       "🥟", "Бишкек (уточнить на 2ГИС)",    "",                  42.8710, 74.5970, 4.2, 75,  false, 9, 22),
  v("dan-dan",       "Dan-Dan",        "restaurant", "🍜", "Бишкек (уточнить на 2ГИС)",    "",                  42.8720, 74.5960, 4.3, 80,  false, 11, 23),
  v("ali-burger",    "Ali Burger",     "fastfood",   "🍔", "ул. Токтогула, 165",           "+996 505 24 72 47", 42.8737, 74.5988, 4.2, 160, false, 10, 23),
  v("oasis",         "Oasis",          "restaurant", "🍽", "Бишкек (уточнить на 2ГИС)",    "",                  42.8730, 74.5980, 4.1, 50,  false, 11, 23),
  v("eki-dos",       "Eki Dos",        "restaurant", "🍽", "Бишкек (уточнить на 2ГИС)",    "",                  42.8720, 74.5970, 4.1, 45,  false, 11, 23),
  v("pili-shvili",   "Pili Shvili",    "restaurant", "🥟", "Бишкек (уточнить на 2ГИС)",    "",                  42.8720, 74.6010, 4.5, 130, false, 11, 23),
  v("maarek",        "Maarek",         "restaurant", "🍽", "ул. Раззакова, 19",            "+996 502 00 22 22", 42.8740, 74.5950, 4.5, 140, false, 11, 23),
  v("papuri",        "Papuri",         "restaurant", "🥟", "Бишкек, центр (двор)",         "",                  42.8720, 74.5980, 4.8, 320, true,  11, 23),
  v("iwa",           "IWA Roof Bar",   "restaurant", "🍣", "ул. Киевская, 148б, 23 этаж (Sheraton)", "+996 999 535 353", 42.8700, 74.6017, 4.7, 280, true, 12, 24,
    { pdf: "https://iwa.kg/contact.html" }),
  v("etiler",        "Etiler Steakhouse","restaurant","🥩","ул. Шопокова, 91, 8 этаж (ЦУМ-2)", "+996 508 77 78 88", 42.8720, 74.5940, 4.6, 150, false, 12, 24),
  v("zaandukki",     "Zaandukki",      "cafe",       "🍷", "ул. Логвиненко, 1в",           "",                  42.8755, 74.6012, 4.4, 90,  false, 11, 23),
  v("zerno",         "Zerno",          "restaurant", "🌾", "ул. Турусбекова, 31",          "+996 773 53 33 33", 42.8715, 74.5970, 4.7, 260, true,  9, 23),
  v("embassy",       "Embassy",        "restaurant", "🍷", "пр. Айтматова, 299/4",         "",                  42.8650, 74.5780, 4.8, 300, true,  12, 24),
];

async function seed() {
  console.log(`🔥 Seeding ${venues.length} Bishkek venues...\n`);
  const batch = db.batch();
  for (const x of venues) {
    const [from, to] = GRADIENT[x.category] || GRADIENT.cafe;
    const doc = {
      name: x.name,
      category: x.category,
      district: "Центр",
      address: x.address,
      phone: x.phone || "",
      emoji: x.emoji,
      gradientFrom: from,
      gradientTo: to,
      city: "bishkek",
      latitude: x.lat,
      longitude: x.lng,
      rating: x.rating,
      reviewCount: x.reviewCount,
      savedByCount: Math.round(x.reviewCount * 0.7),
      isVerified: !!x.verified,
      isPaused: false,
      status: "approved",
      ownerID: "",
      openHour: x.open,
      closeHour: x.close,
      weekHours: [],
      todaySpecial: "",
      pdfMenuURL: x.pdf || "",
      imageURL: "",
      photoEmojis: [x.emoji],
      items: [],
    };
    batch.set(db.collection("venues").doc(x.id), doc, { merge: true });
  }
  await batch.commit();
  console.log(`✅ venues: ${venues.length} documents written`);
  process.exit(0);
}

seed().catch((e) => { console.error("❌", e); process.exit(1); });
