import { initializeApp }           from 'https://www.gstatic.com/firebasejs/11.1.0/firebase-app.js';
import { getAuth, signInWithEmailAndPassword, signOut as fbSignOut, onAuthStateChanged }
  from 'https://www.gstatic.com/firebasejs/11.1.0/firebase-auth.js';
import { getFirestore, collection, getDocs, getDoc, doc, setDoc, updateDoc, addDoc, deleteDoc,
         deleteField, query, where, writeBatch, Timestamp, onSnapshot }
  from 'https://www.gstatic.com/firebasejs/11.1.0/firebase-firestore.js';

// ── БЕЗОПАСНОСТЬ РАЗМЕТКИ ─────────────────────────────────────────────────
// Почти всё, что панель рисует, написал не админ: названия, эмодзи, категории,
// награды, id документов задают заведения, а id отзыва в жалобе — любой
// вошедший пользователь. Поэтому три правила, без исключений:
//  1. Каждое значение в шаблонной строке для innerHTML — через escapeHtml(),
//     числа — через num()/Number().
//  2. Никаких inline-обработчиков (onclick="…${id}…"): кнопки несут
//     data-атрибуты, обработчики навешаны делегированием (см. «ДЕЙСТВИЯ» внизу).
//     CSP страницы и не пропустит inline-скрипт.
//  3. URL из данных — только через safeUrl() (https:, иначе пусто).
//
// Защита от кликджекинга, если хостинг не умеет заголовок frame-ancestors
// (GitHub Pages): в чужом фрейме панель не рисуется вовсе.
if (window.top !== window.self) {
  document.documentElement.textContent = '';
  throw new Error('Ayant admin: отказ работать во фрейме');
}

// Экранирование для текста И для значения атрибута в кавычках.
function escapeHtml(s) {
  if (s === null || s === undefined) return '';
  return String(s).replace(/[&<>"'`]/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;', '`': '&#96;' }[c]));
}
// Число для разметки: строка/мусор из документа → fallback, а не HTML.
function num(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}
// id документа из данных → одиночный сегмент пути Firestore, иначе false.
function isDocId(id) {
  return typeof id === 'string' && id.length > 0 && id.length <= 1500
    && !id.includes('/') && id !== '.' && id !== '..' && !/^__.*__$/.test(id);
}
// Ссылка из данных → только https: (javascript:, data:, http: — пусто).
function safeUrl(u) {
  if (typeof u !== 'string' || !u.trim()) return '';
  try {
    const url = new URL(u.trim());
    return url.protocol === 'https:' ? url.href : '';
  } catch { return ''; }
}

// ── PASTE YOUR FIREBASE CONFIG HERE ──────────────────────────────────────
const firebaseConfig = {
  apiKey:            "AIzaSyC3nHjZ-qZpvZ1iK846A4cYTqd5dKhtcbw",
  authDomain:        "san-25d32.firebaseapp.com",
  projectId:         "san-25d32",
  storageBucket:     "san-25d32.firebasestorage.app",
  messagingSenderId: "320025643761",
  appId:             "1:320025643761:ios:cf053e2b5347d14208f750",
};
// ─────────────────────────────────────────────────────────────────────────

const app  = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db   = getFirestore(app);

// ── STATE ─────────────────────────────────────────────────────────────────
let venues = [];
let deals  = [];
let categories = [];
let editingVenueId = null;
let editingDealId  = null;
let editingCategoryId = null;
let pendingDeleteFn = null;

// ── ЖИВЫЕ ПОДПИСКИ ────────────────────────────────────────────────────────
// Раньше каждая страница читала коллекцию один раз (getDocs), и купон,
// выпущенный заведением после открытия панели, не появлялся до перезагрузки.
// Теперь очереди модерации слушаются снапшотами. Реестр по ключу: повторный
// вызов не создаёт второй листенер (иначе при каждом переходе по вкладкам
// их копилось бы по одному), а выход из аккаунта снимает все.
//
// Два вида подписок:
//  • сессионные (venues, deals, hosts, couponOffers, pushCampaigns) — нужны
//    на нескольких страницах и для счётчиков «ждёт модерации» в меню;
//  • страничные (reviewReports) — снимаются при уходе со страницы.
const liveSubs = new Map();   // key → { unsub, ready: Promise }
const liveLoaded = new Set(); // ключи, по которым уже пришёл первый снапшот

function subscribe(key, ref, onData, onError) {
  const existing = liveSubs.get(key);
  if (existing) return existing.ready;
  let markReady;
  const ready = new Promise(r => { markReady = r; });
  const unsub = onSnapshot(ref,
    snap => {
      liveLoaded.add(key);
      try { onData(snap); }
      catch (e) { console.error(`[live:${key}] render failed`, e); }
      finally { markReady(); }
    },
    err => {
      // После ошибки SDK сам закрывает листенер — убираем из реестра, чтобы
      // следующий заход на страницу попробовал подписаться заново.
      console.error(`[live:${key}]`, err);
      liveSubs.delete(key);
      try { onError?.(err); } finally { markReady(); }
    });
  liveSubs.set(key, { unsub, ready });
  return ready;
}
function unsubscribe(key) {
  const s = liveSubs.get(key);
  if (s) { s.unsub(); liveSubs.delete(key); }
  liveLoaded.delete(key);
}
function unsubscribeAll() {
  for (const key of [...liveSubs.keys()]) unsubscribe(key);
}
// Страничные подписки: какая страница какие держит.
const PAGE_SUBS = { reports: ['reviewReports'] };

function setNavCount(id, n) {
  const el = document.getElementById(id);
  if (el) el.textContent = n > 0 ? String(n) : '';
}

// Firestore Timestamp | Date | число (мс) | строка → Date или null.
function toDate(v) {
  if (v === null || v === undefined || v === '') return null;
  if (typeof v.toDate === 'function') return v.toDate();
  if (typeof v.seconds === 'number') return new Date(v.seconds * 1000);
  const d = new Date(v);
  return isNaN(d.getTime()) ? null : d;
}

// Встроенные категории — используются для первичного заполнения (seed),
// если коллекция `categories` пуста.
const BUILTIN_CATEGORIES = [
  { slug:'cafe',       name:'Кафе',     icon:'fork.knife',                              emoji:'🍽', order:0 },
  { slug:'coffee',     name:'Кофейня',  icon:'cup.and.saucer.fill',                     emoji:'☕️', order:1 },
  { slug:'fastfood',   name:'Фастфуд',  icon:'takeoutbag.and.cup.and.straw.fill',       emoji:'🍔', order:2 },
  { slug:'restaurant', name:'Ресторан', icon:'wineglass.fill',                          emoji:'🍷', order:3 },
  { slug:'teahouse',   name:'Чайхана',  icon:'mug.fill',                                emoji:'🫖', order:4 },
  { slug:'bakery',     name:'Пекарня',  icon:'birthday.cake.fill',                      emoji:'🧁', order:5 },
];
let currentItems = [];   // объекты для отзывов в открытом модале заведения
let currentBranches = []; // доп. адреса (филиалы) в открытом модале заведения

function renderVenueItems() {
  const box = document.getElementById('vItemsList');
  if (!currentItems.length) {
    box.innerHTML = '<small style="color:var(--muted)">Объектов нет</small>';
    return;
  }
  const kindLabel = { food:'Блюдо', service:'Услуга', other:'Объект' };
  box.innerHTML = currentItems.map(it => {
    const img = safeUrl(it.imageURL);
    const thumb = img
      ? `<img src="${escapeHtml(img)}" alt="" referrerpolicy="no-referrer" style="width:20px;height:20px;object-fit:cover;border-radius:4px" />`
      : escapeHtml(it.emoji || '🍽');
    return `
    <span class="badge" style="background:#eef;color:#334;display:inline-flex;gap:6px;align-items:center">
      ${thumb} ${escapeHtml(it.name)} <small style="color:var(--muted)">${escapeHtml(kindLabel[it.kind] || '')}</small>
      <span style="cursor:pointer;color:var(--danger);font-weight:700" data-click="removeVenueItem" data-id="${escapeHtml(it.id)}">×</span>
    </span>`;
  }).join('');
}

const addVenueItem = () => {
  const name = document.getElementById('vItemName').value.trim();
  if (!name) return;
  const emoji = document.getElementById('vItemEmoji').value.trim() || '🍽';
  const kind = document.getElementById('vItemKind').value;
  const imageURL = document.getElementById('vItemImageURL').value.trim();
  if (imageURL && !safeUrl(imageURL)) { toast('Фото — только ссылка https://', 'error'); return; }
  currentItems.push({ id: 'it_' + Math.random().toString(36).slice(2, 10), name, emoji, kind, imageURL });
  document.getElementById('vItemName').value = '';
  document.getElementById('vItemEmoji').value = '';
  document.getElementById('vItemImageURL').value = '';
  renderVenueItems();
};

const removeVenueItem = (id) => {
  currentItems = currentItems.filter(it => it.id !== id);
  renderVenueItems();
};

// ── Доп. адреса (филиалы) ────────────────────────────────────────────────────
function renderVenueBranches() {
  const box = document.getElementById('vBranchesList');
  if (!currentBranches.length) {
    box.innerHTML = '<small style="color:var(--muted)">Филиалов нет</small>';
    return;
  }
  box.innerHTML = currentBranches.map(b => `
    <span class="badge" style="background:#eef;color:#334;display:inline-flex;gap:6px;align-items:center">
      📍 ${escapeHtml(b.address)} <small style="color:var(--muted)">${num(b.latitude).toFixed(4)}, ${num(b.longitude).toFixed(4)}</small>
      <span style="cursor:pointer;color:var(--danger);font-weight:700" data-click="removeVenueBranch" data-id="${escapeHtml(b.id)}">×</span>
    </span>`).join('');
}

const addVenueBranch = () => {
  const address = document.getElementById('vBranchAddress').value.trim();
  if (!address) { toast('Впиши адрес филиала', 'error'); return; }
  const num = (v, d) => { const n = Number(v); return v === '' || isNaN(n) ? d : n; };
  currentBranches.push({
    id: 'br_' + Math.random().toString(36).slice(2, 10),
    address,
    latitude:  num(document.getElementById('vBranchLat').value, 42.8746),
    longitude: num(document.getElementById('vBranchLng').value, 74.5698),
    phone: document.getElementById('vBranchPhone').value.trim(),
  });
  document.getElementById('vBranchAddress').value = '';
  document.getElementById('vBranchLat').value = '';
  document.getElementById('vBranchLng').value = '';
  document.getElementById('vBranchPhone').value = '';
  renderVenueBranches();
};

const removeVenueBranch = (id) => {
  currentBranches = currentBranches.filter(b => b.id !== id);
  renderVenueBranches();
};

// ── Дополнительные карты штампов (stampCards) ────────────────────────────────
// Зеркало StampCards.swift / activeStampCards в functions: id латиницей без
// «_» (он разделяет части id документа), цель 2–12, без награды — не карта.
let currentStampCards = [];   // [{ id, title, goal, reward, active }]
const STAMP_CARD_MAX_EXTRAS = 4;

function renderStampCards() {
  const box = document.getElementById('vStampCardsList');
  if (!currentStampCards.length) { box.innerHTML = '<small style="color:var(--muted)">Только первая карта</small>'; return; }
  box.innerHTML = currentStampCards.map((c, i) => `
    <div style="display:grid;grid-template-columns:1.2fr 70px 1.6fr auto auto;gap:6px;align-items:center">
      <input placeholder="Название" maxlength="30" value="${escapeHtml(c.title)}" data-input="editStampCard" data-index="${i}" data-field="title" />
      <input type="number" min="2" max="12" value="${num(c.goal, 6)}" data-input="editStampCard" data-index="${i}" data-field="goal" />
      <input placeholder="Награда" maxlength="60" value="${escapeHtml(c.reward)}" data-input="editStampCard" data-index="${i}" data-field="reward" />
      <label style="display:flex;gap:4px;align-items:center;font-size:12px"><input type="checkbox" ${c.active ? 'checked' : ''} data-change="editStampCard" data-index="${i}" data-field="active" />вкл</label>
      <span style="cursor:pointer;color:var(--danger);font-weight:700" title="Удалить" data-click="removeStampCard" data-index="${i}">×</span>
    </div>`).join('');
}
const addStampCard = () => {
  if (currentStampCards.length >= STAMP_CARD_MAX_EXTRAS) { toast('Не больше 5 карт у заведения', 'error'); return; }
  currentStampCards.push({ id: 'card-' + Math.random().toString(36).slice(2, 10), title: '', goal: 6, reward: '', active: true });
  renderStampCards();
};
const editStampCard = (i, key, value) => {
  const c = currentStampCards[i]; if (!c) return;
  c[key] = key === 'goal' ? (parseInt(value) || 6) : value;
};
const removeStampCard = (i) => {
  if (!confirm('Удалить карту? Гости перестанут видеть её и собранные на ней штампы.')) return;
  currentStampCards.splice(i, 1);
  renderStampCards();
};
function collectStampCards() {
  const seen = new Set(['default']);
  return currentStampCards
    // Обрезка по кодовым точкам — как на сервере: .slice режет эмодзи пополам.
    .map(c => ({ id: String(c.id || ''), title: Array.from(String(c.title || '').trim()).slice(0, 30).join(''),
                 goal: (parseInt(c.goal) > 0 ? Math.min(Math.max(parseInt(c.goal), 2), 12) : 6),
                 reward: Array.from(String(c.reward || '').trim()).slice(0, 60).join(''), active: c.active !== false }))
    .filter(c => /^[A-Za-z0-9-]{1,32}$/.test(c.id) && !seen.has(c.id) && c.reward && seen.add(c.id))
    .slice(0, STAMP_CARD_MAX_EXTRAS);
}

// ── Баллы САН: диапазоны начисления + каталог наград ────────────────────────
let currentPointsBands = [];    // [{ id, maxAmount, points }]
let currentPointsRewards = [];  // [{ id, type, title, cost, ratio, active }]

// Показ полей режима начисления (flat / bands / cashback).
const updatePointsUI = () => {
  const mode = document.getElementById('vPointsMode').value;
  document.getElementById('vPointsFlatRow').style.display = mode === 'flat' ? '' : 'none';
  document.getElementById('vCashbackRow').style.display   = mode === 'cashback' ? '' : 'none';
  document.getElementById('vBandsRow').style.display      = mode === 'bands' ? '' : 'none';

  // Механика лояльности ОДНА на заведение (домен: LoyaltyKind, сервер: scanCoupon
  // Branch A → 409 loyalty_is_points). Раньше обе галки жили независимо, и
  // заведение могло включить и штампы, и баллы: гость видел два виджета, а по
  // одному скану не понимал, что ему начислили. Приоритет у баллов — они
  // привязаны к деньгам. Здесь только подсказка; запрет — на сервере.
  const pointsOn  = document.getElementById('vPointsEnabled').value === 'true';
  const stampsOn  = document.getElementById('vLoyaltyEnabled').value === 'true';
  document.getElementById('vLoyaltyOffNote').style.display = (pointsOn && stampsOn) ? '' : 'none';
  for (const id of ['vLoyaltyGoal', 'vLoyaltyReward']) {
    const el = document.getElementById(id);
    el.disabled = pointsOn;
    el.style.opacity = pointsOn ? 0.5 : '';
  }
};

function renderPointsBands() {
  const box = document.getElementById('vBandsList');
  if (!currentPointsBands.length) { box.innerHTML = '<small style="color:var(--muted)">Диапазонов нет</small>'; return; }
  const sorted = currentPointsBands.slice().sort((a, b) => a.maxAmount - b.maxAmount);
  box.innerHTML = sorted.map((b, i) => {
    const label = i === sorted.length - 1 ? `${num(b.maxAmount)}+ сом` : `до ${num(b.maxAmount)} сом`;
    return `<span class="badge" style="background:#eef;color:#334;display:inline-flex;gap:6px;align-items:center">
      ${label} → ${num(b.points)} б.
      <span style="cursor:pointer;color:var(--danger);font-weight:700" data-click="removePointsBand" data-id="${escapeHtml(b.id)}">×</span></span>`;
  }).join('');
}
const addPointsBand = () => {
  const maxAmount = parseInt(document.getElementById('vBandMax').value);
  const points = parseInt(document.getElementById('vBandPoints').value);
  if (!(maxAmount > 0) || !(points >= 0)) { toast('Впиши сумму и баллы', 'error'); return; }
  currentPointsBands.push({ id: 'bd_' + Math.random().toString(36).slice(2, 10), maxAmount, points });
  document.getElementById('vBandMax').value = '';
  document.getElementById('vBandPoints').value = '';
  renderPointsBands();
};
const removePointsBand = (id) => {
  currentPointsBands = currentPointsBands.filter(b => b.id !== id);
  renderPointsBands();
};

function renderPointsRewards() {
  const box = document.getElementById('vRewardsList');
  if (!currentPointsRewards.length) { box.innerHTML = '<small style="color:var(--muted)">Наград нет</small>'; return; }
  box.innerHTML = currentPointsRewards.map(r => {
    const kind = r.type === 'money' ? `скидка · мин. ${num(r.cost)} б.` : `${num(r.cost)} б.`;
    return `<span class="badge" style="background:#efe;color:#243;display:inline-flex;gap:6px;align-items:center">
      ${r.type === 'money' ? '💸' : '🎁'} ${escapeHtml(r.title)} <small style="color:var(--muted)">${kind}</small>
      <span style="cursor:pointer;color:var(--danger);font-weight:700" data-click="removePointsReward" data-id="${escapeHtml(r.id)}">×</span></span>`;
  }).join('');
}
const addPointsReward = () => {
  const title = document.getElementById('vRewardTitle').value.trim();
  const cost = parseInt(document.getElementById('vRewardCost').value);
  const type = document.getElementById('vRewardType').value;
  if (!title || !(cost > 0)) { toast('Впиши название и стоимость в баллах', 'error'); return; }
  currentPointsRewards.push({ id: 'rw_' + Math.random().toString(36).slice(2, 10), type, title, cost, ratio: 1, active: true });
  document.getElementById('vRewardTitle').value = '';
  document.getElementById('vRewardCost').value = '';
  renderPointsRewards();
};
const removePointsReward = (id) => {
  currentPointsRewards = currentPointsRewards.filter(r => r.id !== id);
  renderPointsRewards();
};

// Геокодинг адреса филиала → заполняет поля широты/долготы.
const geocodeBranch = async () => {
  const addr = document.getElementById('vBranchAddress').value.trim();
  if (!addr) { toast('Сначала впиши адрес филиала', 'error'); return; }
  try {
    const q = encodeURIComponent(addr + ', Бишкек, Кыргызстан');
    const res = await fetch(`https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${q}`,
      { headers: { 'Accept-Language': 'ru' } });
    const data = await res.json();
    if (!data.length) { toast('Адрес не найден — впиши координаты вручную', 'error'); return; }
    document.getElementById('vBranchLat').value = parseFloat(data[0].lat).toFixed(6);
    document.getElementById('vBranchLng').value = parseFloat(data[0].lon).toFixed(6);
    toast('Координаты филиала найдены', 'success');
  } catch (e) {
    toast('Не удалось найти адрес', 'error');
  }
};

// ── Загрузка фото в Cloudinary (подписанная) ─────────────────────────────────
// Пресет `Ayant_ios` переведён в Signed: неподписанная загрузка с публичным
// именем пресета позволяла кому угодно лить файлы на наш счёт. Подпись выдаёт
// Cloud Function `signCloudinaryUpload` только вошедшему пользователю; секрет
// Cloudinary живёт на сервере (Secret Manager), в браузер не попадает.
const SIGN_UPLOAD_URL = 'https://us-central1-san-25d32.cloudfunctions.net/signCloudinaryUpload';
const uploadImage = async (input, targetId) => {
  const file = input.files && input.files[0];
  if (!file) return;
  if (!file.type.startsWith('image/')) { toast('Только изображения', 'error'); input.value=''; return; }
  if (file.size > 5 * 1024 * 1024) { toast('Файл больше 5 МБ — выберите меньше', 'error'); input.value=''; return; }
  toast('Загрузка фото…');
  try {
    const idToken = auth.currentUser ? await auth.currentUser.getIdToken() : '';
    if (!idToken) { toast('Войдите заново, чтобы загрузить фото', 'error'); input.value = ''; return; }
    const signRes = await fetch(SIGN_UPLOAD_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${idToken}` },
      body: JSON.stringify({ folder: 'ayant/images', resourceType: 'image' }),
    });
    const sign = await signRes.json().catch(() => ({}));
    if (!signRes.ok || !sign.signature) {
      toast('Ошибка подписи загрузки: ' + String(sign.error || signRes.status), 'error');   // toast — textContent
      input.value = '';
      return;
    }
    const form = new FormData();
    form.append('file', file);
    form.append('api_key', sign.apiKey);
    form.append('timestamp', String(sign.timestamp));
    form.append('signature', sign.signature);
    form.append('folder', sign.folder);
    const res = await fetch(`https://api.cloudinary.com/v1_1/${encodeURIComponent(sign.cloudName)}/image/upload`,
      { method: 'POST', body: form });
    const json = await res.json();
    if (json.secure_url) {
      document.getElementById(targetId).value = json.secure_url;
      toast('Фото загружено', 'success');
    } else {
      toast('Ошибка: ' + (json.error?.message || 'не удалось загрузить'), 'error');
    }
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
  input.value = '';
};

// ── DEMO SEED (через веб-SDK, под текущим логином — без service account) ──────
const daysAgoTS  = n => Timestamp.fromDate(new Date(Date.now() - n * 86400000));
const hoursAgoTS = n => Timestamp.fromDate(new Date(Date.now() - n * 3600000));

const SEED_VENUE_EXTRAS = {
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

const SEED_DEAL_START = {
  d1: hoursAgoTS(20), d2: daysAgoTS(5), d3: daysAgoTS(3), d4: hoursAgoTS(30),
  d5: daysAgoTS(8), d6: daysAgoTS(12), d7: hoursAgoTS(10), d8: daysAgoTS(6),
  d9: daysAgoTS(2), d10: daysAgoTS(4), d11: daysAgoTS(9), d12: daysAgoTS(1),
  d13: daysAgoTS(7), d14: hoursAgoTS(40), d15: daysAgoTS(5),
};

const SEED_REVIEWS = [
  { id: "r1", venueID: "navat", authorID: "u_aida", authorName: "Айда", rating: 5, text: "Лучшая чайхана в центре. Манты огонь, чай наливают бесконечно.", photoEmojis: ["🥟","🫖"], createdAt: daysAgoTS(3), updatedAt: daysAgoTS(3), hostReply: { text: "Спасибо, Айда! Ждём снова 🫖", createdAt: daysAgoTS(2) } },
  { id: "r2", venueID: "navat", authorID: "u_marat", authorName: "Марат", rating: 4, text: "Вкусно, но в обед бывает шумно. Сервис быстрый.", photoEmojis: [], createdAt: daysAgoTS(10), updatedAt: daysAgoTS(10) },
  { id: "r3", venueID: "sierra", authorID: "u_lena", authorName: "Лена", rating: 5, text: "Мой любимый кофе в городе. Раф на кокосовом — топ.", photoEmojis: ["☕️"], createdAt: daysAgoTS(1), updatedAt: daysAgoTS(1) },
  { id: "r4", venueID: "sierra", authorID: "u_ts", authorName: "Тимур", rating: 4, text: "Отличное место для работы с ноутом, розеток хватает.", photoEmojis: [], createdAt: daysAgoTS(14), updatedAt: daysAgoTS(14) },
  { id: "r5", venueID: "furusato", authorID: "u_dasha", authorName: "Даша", rating: 5, text: "Свежие роллы, большие порции. Сет «Бишкек» берём компанией.", photoEmojis: ["🍣","🍱"], createdAt: daysAgoTS(5), updatedAt: daysAgoTS(5), hostReply: { text: "Рады, что понравилось! 🍣", createdAt: daysAgoTS(4) } },
  { id: "r6", venueID: "adriano", authorID: "u_nur", authorName: "Нуржан", rating: 5, text: "Матча просто космос. Десерты тоже на уровне.", photoEmojis: ["🍵"], createdAt: daysAgoTS(2), updatedAt: daysAgoTS(2) },
  { id: "r7", venueID: "shaurma1", authorID: "u_beka", authorName: "Бека", rating: 4, text: "Сытно и недорого. Вторая по акции — приятно.", photoEmojis: [], createdAt: daysAgoTS(6), updatedAt: daysAgoTS(6) },
  { id: "r8", venueID: "faiza", authorID: "u_gulnara", authorName: "Гульнара", rating: 4, text: "Лагман как у бабушки. Уютно и по-домашнему.", photoEmojis: ["🍜"], createdAt: daysAgoTS(8), updatedAt: daysAgoTS(8) },
  { id: "r9", venueID: "chickenstar", authorID: "u_sam", authorName: "Сам", rating: 3, text: "Курица вкусная, но ждали комбо долго.", photoEmojis: [], createdAt: daysAgoTS(11), updatedAt: daysAgoTS(11) },
  { id: "r10", venueID: "bublik", authorID: "u_olya", authorName: "Оля", rating: 5, text: "Круассаны утром свежайшие. Вечерняя скидка — бонус.", photoEmojis: ["🥐"], createdAt: daysAgoTS(4), updatedAt: daysAgoTS(4) },
];

const seedDemo = async () => {
  if (!confirm('Дополнить заведения/предложения новыми полями и добавить демо-отзывы?')) return;
  try {
    for (const [id, ex] of Object.entries(SEED_VENUE_EXTRAS)) {
      await setDoc(doc(db, 'venues', id), { city: 'bishkek', ...ex }, { merge: true });
    }
    for (const d of deals) {
      const patch = { status: d.status ?? 'active' };
      if (SEED_DEAL_START[d.id]) patch.startDate = SEED_DEAL_START[d.id];
      if (d.emoji) patch.imageEmojis = [d.emoji];
      await setDoc(doc(db, 'deals', d.id), patch, { merge: true });
    }
    for (const { id, ...data } of SEED_REVIEWS) {
      await setDoc(doc(db, 'reviews', id), data, { merge: true });
    }
    await loadAll();
    toast('Демо-данные обновлены ✓', 'success');
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

// ── AUTH ──────────────────────────────────────────────────────────────────
// Доступ к панели только у пользователей с кастомным claim `admin: true`
// (выдаётся серверным скриптом scripts/set-admin-claim.js). Просто наличие
// аккаунта Firebase больше НЕ даёт доступ — этого требуют и firestore.rules.
// Возвращает 'admin' | 'denied' | 'unknown'. 'unknown' — не удалось проверить
// (сеть/офлайн): в этом случае НЕ разлогиниваем — иначе честного админа выкинет
// при кратковременном сбое сети. Сначала пробуем свежий токен, затем кэшированный.
async function checkAdmin(user) {
  if (!user) return 'denied';
  try {
    const token = await user.getIdTokenResult(true); // refresh — подхватить свежий claim
    return token.claims.admin === true ? 'admin' : 'denied';
  } catch (e) {
    try {
      const cached = await user.getIdTokenResult(false); // без сети, из кэша
      return cached.claims.admin === true ? 'admin' : 'denied';
    } catch (e2) {
      return 'unknown';
    }
  }
}

onAuthStateChanged(auth, async user => {
  const authScreen = document.getElementById('authScreen');
  const app = document.getElementById('app');
  const errEl = document.getElementById('authError');
  const status = await checkAdmin(user);
  if (status === 'admin') {
    authScreen.style.display = 'none';
    app.style.display = 'block';
    loadAll();
  } else {
    // Вышел или прав нет — снимаем все листенеры: без токена они всё равно
    // упадут с permission-denied, а при входе под другим аккаунтом дублировались бы.
    unsubscribeAll();
    if (user && status === 'denied') {
      // Вошёл, но без прав администратора — выкидываем и показываем причину.
      if (errEl) errEl.textContent = 'Недостаточно прав: аккаунт не является администратором';
      await fbSignOut(auth);
    } else if (user && status === 'unknown') {
      // Сбой проверки (сеть) — не разлогиниваем, просим повторить.
      if (errEl) errEl.textContent = 'Не удалось проверить права (сеть). Обновите страницу.';
    }
    authScreen.style.display = 'flex';
    app.style.display = 'none';
  }
});

const signIn = async () => {
  const email    = document.getElementById('authEmail').value.trim();
  const password = document.getElementById('authPassword').value;
  const errEl    = document.getElementById('authError');
  errEl.textContent = '';
  try {
    await signInWithEmailAndPassword(auth, email, password);
    // Проверку прав делает onAuthStateChanged — не-админа он тут же разлогинит.
  } catch (e) {
    errEl.textContent = 'Неверный email или пароль';
  }
};

const signOut = () => fbSignOut(auth);

// ── LOAD ──────────────────────────────────────────────────────────────────
async function loadAll() {
  // Категории — первыми: от них зависят подписи и выпадающий список в форме заведения.
  await loadCategories();
  // allSettled: сбой одной коллекции (напр. нет правил) не ломает остальные.
  // Всё ниже — живые подписки (см. «ЖИВЫЕ ПОДПИСКИ»): повторный вызов не
  // плодит листенеры, а только дожидается первого снапшота.
  await Promise.allSettled([loadVenues(), loadDeals(), loadHosts(), loadBoosts(), loadCoupons()]);
}

// ── CATEGORIES ──────────────────────────────────────────────────────────────
async function loadCategories() {
  try {
    const snap = await getDocs(collection(db, 'categories'));
    categories = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    // Первый запуск: коллекция пуста → засеваем встроенными категориями.
    if (!categories.length) {
      await Promise.allSettled(BUILTIN_CATEGORIES.map(c =>
        setDoc(doc(db, 'categories', c.slug), { ...c, enabled: true })));
      categories = BUILTIN_CATEGORIES.map(c => ({ id: c.slug, ...c, enabled: true }));
    }
  } catch (e) {
    // Нет доступа/правил — работаем на встроенных, чтобы форма не ломалась.
    categories = BUILTIN_CATEGORIES.map(c => ({ id: c.slug, ...c, enabled: true }));
  }
  categories.sort((a, b) => (a.order ?? 0) - (b.order ?? 0) || (a.name || '').localeCompare(b.name || ''));
  renderCategories();
  populateCategorySelect();
}

function renderCategories() {
  const tbody = document.getElementById('categoriesBody');
  if (!tbody) return;
  if (!categories.length) {
    tbody.innerHTML = '<tr><td colspan="7" class="empty">Категорий нет</td></tr>';
    return;
  }
  tbody.innerHTML = categories.map(c => `
    <tr style="${c.enabled === false ? 'opacity:.5' : ''}">
      <td class="emoji-cell">${escapeHtml(c.emoji ?? '🏷️')}</td>
      <td><strong>${escapeHtml(c.name ?? c.slug)}</strong></td>
      <td><small style="color:var(--muted)">${escapeHtml(c.slug)}</small></td>
      <td><small style="color:var(--muted)">${escapeHtml(c.icon ?? '—')}</small></td>
      <td>${num(c.order)}</td>
      <td><span class="badge badge-${c.enabled === false ? 'rejected' : 'approved'}">${c.enabled === false ? 'Скрыта' : 'Включена'}</span></td>
      <td>
        <div class="row-actions">
          <button class="btn btn-secondary btn-sm" data-click="openCategoryModal" data-id="${escapeHtml(c.id)}">✏️</button>
          <button class="btn btn-danger btn-sm"    data-click="askDelete" data-type="category" data-id="${escapeHtml(c.id)}">🗑</button>
        </div>
      </td>
    </tr>`).join('');
}

function populateCategorySelect() {
  const sel = document.getElementById('vCategory');
  if (!sel) return;
  const current = sel.value;
  const list = categories.filter(c => c.enabled !== false);
  sel.innerHTML = (list.length ? list : BUILTIN_CATEGORIES)
    .map(c => `<option value="${escapeHtml(c.slug)}">${escapeHtml(c.name ?? c.slug)}</option>`).join('');
  if (current) sel.value = current;
}

function catTranslit(s) {
  const map = { а:'a',б:'b',в:'v',г:'g',д:'d',е:'e',ё:'e',ж:'zh',з:'z',и:'i',й:'y',к:'k',л:'l',м:'m',
    н:'n',о:'o',п:'p',р:'r',с:'s',т:'t',у:'u',ф:'f',х:'h',ц:'c',ч:'ch',ш:'sh',щ:'sch',ъ:'',ы:'y',ь:'',
    э:'e',ю:'yu',я:'ya',' ':'-','_':'-' };
  return (s || '').toLowerCase().split('').map(ch => map[ch] ?? ch).join('')
    .replace(/[^a-z0-9-]/g, '').replace(/-+/g, '-').replace(/^-|-$/g, '');
}

const onCategoryNameInput = () => {
  // Автоподсказка кода из названия, только если поле кода ещё не трогали вручную.
  const slugEl = document.getElementById('cSlug');
  if (slugEl.dataset.touched === '1') return;
  slugEl.value = catTranslit(document.getElementById('cName').value);
};

const openCategoryModal = (id) => {
  editingCategoryId = id ?? null;
  const c = id ? categories.find(x => x.id === id) : null;
  document.getElementById('categoryModalTitle').textContent = id ? 'Изменить категорию' : 'Новая категория';
  document.getElementById('cName').value    = c?.name ?? '';
  document.getElementById('cSlug').value     = c?.slug ?? '';
  document.getElementById('cIcon').value     = c?.icon ?? 'tag.fill';
  document.getElementById('cEmoji').value    = c?.emoji ?? '';
  document.getElementById('cOrder').value    = c?.order ?? (categories.length);
  document.getElementById('cEnabled').value  = String(c?.enabled !== false);
  const slugEl = document.getElementById('cSlug');
  slugEl.dataset.touched = id ? '1' : '';       // при редактировании код не перезаписываем
  if (!slugEl.dataset.bound) {   // один слушатель на всё время жизни страницы
    slugEl.addEventListener('input', () => { slugEl.dataset.touched = '1'; });
    slugEl.dataset.bound = '1';
  }
  document.getElementById('categoryModal').classList.remove('hidden');
};

const saveCategory = async () => {
  const name = document.getElementById('cName').value.trim();
  let slug   = document.getElementById('cSlug').value.trim() || catTranslit(name);
  if (!name)  { toast('Введите название', 'error'); return; }
  if (!slug)  { toast('Введите код категории', 'error'); return; }
  const data = {
    slug,
    name,
    icon:   document.getElementById('cIcon').value.trim() || 'tag.fill',
    emoji:  document.getElementById('cEmoji').value.trim(),
    order:  Number(document.getElementById('cOrder').value) || 0,
    enabled: document.getElementById('cEnabled').value === 'true',
  };
  try {
    // id документа = slug (стабильная ссылка). При смене кода удаляем старый док.
    if (editingCategoryId && editingCategoryId !== slug) {
      await deleteDoc(doc(db, 'categories', editingCategoryId));
    }
    await setDoc(doc(db, 'categories', slug), data);
    closeModal('categoryModal');
    await loadCategories();
    toast('Категория сохранена', 'success');
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

// ── BOOSTS / PUSH ───────────────────────────────────────────────────────────
function boostStatus(c) {
  switch (c.status) {
    case 'pending':  return { label: 'На модерации', cls: 'pending' };
    case 'approved': return { label: 'Одобрено', cls: 'novelty' };
    case 'sent':     return { label: `Отправлено${c.recipients != null ? ` (${c.recipients})` : ''}`, cls: 'promo' };
    case 'rejected': return { label: 'Отклонено', cls: 'discount' };
    case 'error':    return { label: 'Ошибка', cls: 'discount' };
    default:         return { label: c.status || '—', cls: 'pending' };
  }
}

let boosts = [];
function loadBoosts() {
  return subscribe('pushCampaigns', collection(db, 'pushCampaigns'),
    snap => {
      boosts = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      setNavCount('navBoostsCount', boosts.filter(c => c.status === 'pending').length);
      renderBoosts();
    },
    e => {
      document.getElementById('boostsBody').innerHTML =
        `<tr><td colspan="5" class="spinner">Ошибка: ${escapeHtml(e.message)}</td></tr>`;
    });
}

function renderBoosts() {
  const body = document.getElementById('boostsBody');
  {
    // Ждущие решения — сверху, дальше свежие первыми.
    const rank = c => (c.status === 'pending' ? 0 : 1);
    const rows = boosts.slice()
      .sort((a, b) => rank(a) - rank(b) || (b.createdAt?.seconds || 0) - (a.createdAt?.seconds || 0));
    if (!rows.length) { body.innerHTML = '<tr><td colspan="5" class="spinner">Нет кампаний</td></tr>'; return; }
    body.innerHTML = rows.map(c => {
      const st = boostStatus(c);
      const actions = c.status === 'pending'
        ? `<button class="btn btn-success btn-sm" data-click="approveBoost" data-id="${escapeHtml(c.id)}">✓ Одобрить</button>
           <button class="btn btn-secondary btn-sm" data-click="rejectBoost" data-id="${escapeHtml(c.id)}">⨯ Отклонить</button>`
        : '';
      return `<tr>
        <td><b>${escapeHtml(c.headline || '')}</b></td>
        <td>${escapeHtml((c.body || '').slice(0, 70))}</td>
        <td>${escapeHtml(c.city || '')}</td>
        <td><span class="badge badge-${st.cls}">${escapeHtml(st.label)}</span></td>
        <td>${actions}</td>
      </tr>`;
    }).join('');
  }
}

// ── Награды глобального кошелька ────────────────────────────────────────
//
// Хранятся одним документом config/globalRewards полем items[]. Клиент
// отбрасывает награды без venueID, поэтому заведение обязательно.

let globalRewards = [];
const REWARD_TEMPLATES = [
  { id: 'disc10',  title: '−10% к любой акции',          cost: 100, emoji: '🏷️' },
  { id: 'coffee',  title: 'Бесплатный кофе у партнёра',  cost: 300, emoji: '☕️' },
  { id: 'dessert', title: 'Десерт в подарок',            cost: 400, emoji: '🍰' },
  { id: 'vip',     title: 'VIP-доступ к новинкам',       cost: 500, emoji: '⭐️' },
];

async function loadRewards() {
  const body = document.getElementById('rewardsBody');
  try {
    const snap = await getDoc(doc(db, 'config', 'globalRewards'));
    globalRewards = (snap.exists() ? (snap.data().items ?? []) : []).slice();
    // Первый заход: показываем заготовки, чтобы не набивать их руками.
    if (!globalRewards.length) globalRewards = REWARD_TEMPLATES.map(r => ({ ...r, venueID: '' }));
    renderRewards();
  } catch (e) {
    body.innerHTML = `<tr><td colspan="5" class="spinner">Ошибка: ${escapeHtml(e.message)}</td></tr>`;
  }
}

function renderRewards() {
  const body = document.getElementById('rewardsBody');
  if (!globalRewards.length) {
    body.innerHTML = '<tr><td colspan="5" class="spinner">Наград нет</td></tr>';
    return;
  }
  const options = venues.map(v => `<option value="${escapeHtml(v.id)}">${escapeHtml(v.name)}</option>`).join('');
  body.innerHTML = globalRewards.map((r, i) => `
    <tr>
      <td><input value="${escapeHtml(r.title ?? '')}" data-input="editReward" data-index="${i}" data-field="title" /></td>
      <td><input type="number" min="1" value="${num(r.cost)}" data-input="editReward" data-index="${i}" data-field="cost" style="width:110px" /></td>
      <td><input value="${escapeHtml(r.emoji ?? '')}" maxlength="4" data-input="editReward" data-index="${i}" data-field="emoji" style="width:70px" /></td>
      <td>
        <select data-change="editReward" data-index="${i}" data-field="venueID">
          <option value="">— не выбрано —</option>${options}
        </select>
        ${r.venueID ? '' : '<small style="color:#c0490f">без партнёра — не покажется</small>'}
      </td>
      <td><button class="btn btn-secondary btn-sm" data-click="removeReward" data-index="${i}">×</button></td>
    </tr>`).join('');
  // value у select проставляем после вставки: строка с кавычками в HTML ненадёжна.
  globalRewards.forEach((r, i) => {
    const sel = body.querySelectorAll('select')[i];
    if (sel) sel.value = r.venueID ?? '';
  });
}

const editReward = (i, field, value) => {
  globalRewards[i][field] = field === 'cost' ? (parseInt(value) || 0) : value;
  if (field === 'venueID') {
    globalRewards[i].venueName = venues.find(v => v.id === value)?.name ?? '';
    renderRewards();
  }
};
const addRewardRow = () => {
  globalRewards.push({ id: 'rw_' + Math.random().toString(36).slice(2, 8),
                       title: '', cost: 100, emoji: '🎁', venueID: '', venueName: '' });
  renderRewards();
};
const removeReward = (i) => { globalRewards.splice(i, 1); renderRewards(); };

const saveRewards = async () => {
  const items = globalRewards
    .filter(r => (r.title ?? '').trim() && r.venueID)
    .map(r => ({ id: r.id, title: r.title.trim(), cost: r.cost,
                 emoji: r.emoji || '🎁', venueID: r.venueID, venueName: r.venueName ?? '' }));
  const dropped = globalRewards.length - items.length;
  try {
    await setDoc(doc(db, 'config', 'globalRewards'), { items }, { merge: true });
    toast(dropped ? `Сохранено. Без партнёра пропущено: ${dropped}` : 'Награды сохранены');
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

// ── Настройки приложения (config/appSettings) ──────────────────────────
//
// Один документ на продукт. stampCooldownMinutes читает scanCoupon (ветка A,
// кэш на минуту), adPlaceholderText — оба клиента. Явный 0 сохраняется —
// это «без паузы», а не «не задано» (тот же урок, что с earnCooldownMinutes).

async function loadSettings() {
  try {
    const snap = await getDoc(doc(db, 'config', 'appSettings'));
    const s = snap.exists() ? snap.data() : {};
    document.getElementById('sStampCooldown').value = s.stampCooldownMinutes ?? 15;
    document.getElementById('sAdText').value = s.adPlaceholderText ?? '';
  } catch (e) { toast('Ошибка загрузки настроек: ' + e.message, 'error'); }
}

const saveSettings = async () => {
  // Явный 0 сохраняем; пусто/мусор → 15 (см. intOrDefault в functions).
  const raw = parseInt(document.getElementById('sStampCooldown').value, 10);
  const stampCooldownMinutes = Math.min(Math.max(Number.isFinite(raw) ? raw : 15, 0), 1440);
  const adPlaceholderText = document.getElementById('sAdText').value.trim().slice(0, 80);
  try {
    await setDoc(doc(db, 'config', 'appSettings'), { stampCooldownMinutes, adPlaceholderText }, { merge: true });
    toast(stampCooldownMinutes === 0
      ? 'Сохранено. Внимание: пауза между штампами выключена'
      : 'Настройки сохранены');
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

// ── Жалобы на отзывы ────────────────────────────────────────────────────
//
// Очередь модерации пользовательского контента (Guidelines 1.2). Жалоба не
// прячет отзыв сама по себе — решение принимает человек здесь: либо удалить
// отзыв, либо закрыть жалобу как необоснованную.

const REPORT_REASONS = { fake: 'Фейк', spam: 'Спам', offensive: 'Оскорбительное' };

// Страничная подписка: пока открыта вкладка «Жалобы», новые жалобы
// появляются сами; при уходе со страницы листенер снимается (showPage).
let reports = [];
let reportsRenderGen = 0;
function loadReports() {
  const ready = subscribe('reviewReports', collection(db, 'reviewReports'),
    snap => {
      reports = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      renderReports();
    },
    e => {
      document.getElementById('reportsBody').innerHTML =
        `<tr><td colspan="5" class="spinner">Ошибка: ${escapeHtml(e.message)}</td></tr>`;
    });
  // Чекбокс «Показывать разобранные» зовёт loadReports() — подписка уже есть,
  // просто перерисовываем из кэша.
  renderReports();
  return ready;
}

async function renderReports() {
  const body = document.getElementById('reportsBody');
  const showClosed = document.getElementById('reportsShowClosed').checked;
  // Рендер асинхронный (тексты отзывов подтягиваются отдельно): снапшот,
  // пришедший во время загрузки, не должен быть перезаписан старым рендером.
  const gen = ++reportsRenderGen;
  try {
    let rows = reports.slice();
    if (!showClosed) rows = rows.filter(r => (r.status ?? 'open') === 'open');
    rows.sort((a, b) => (b.createdAt?.seconds || 0) - (a.createdAt?.seconds || 0));
    if (!rows.length) {
      body.innerHTML = '<tr><td colspan="5" class="spinner">Жалоб нет</td></tr>';
      return;
    }
    // Тексты отзывов подтягиваем по одному: жалоб единицы, а выгружать всю
    // коллекцию отзывов ради них — та самая ошибка, из-за которой убрали
    // fetchReviews() без аргументов (docs/design/system-design.md §2, B2).
    const texts = await Promise.all(rows.map(async r => {
      if (!isDocId(r.reviewID)) return null;
      try {
        const d = await getDoc(doc(db, 'reviews', r.reviewID));
        return d.exists() ? d.data() : null;
      } catch { return null; }
    }));
    if (gen !== reportsRenderGen) return;   // пришёл более свежий снапшот
    body.innerHTML = rows.map((r, i) => {
      const rv = texts[i];
      const closed = (r.status ?? 'open') !== 'open';
      const when = r.createdAt?.seconds
        ? new Date(r.createdAt.seconds * 1000).toLocaleString('ru-RU') : '';
      // rating пишет автор отзыва: строка/огромное число не должны ни ломать
      // разметку, ни вешать вкладку на '★'.repeat(1e9).
      const stars = Math.min(Math.max(Math.trunc(num(rv?.rating)), 0), 5);
      const text = rv
        ? `<b>${escapeHtml(rv.authorName ?? '')}</b> · ${'★'.repeat(stars)}<br>
           <small>${escapeHtml(String(rv.text ?? '').slice(0, 160))}</small>`
        : '<small style="color:var(--muted)">отзыв уже удалён</small>';
      // reviewID жалобы выбирает автор жалобы (любой вошедший пользователь),
      // поэтому в разметку его не кладём: обработчик достаёт его из `reports`
      // по id жалобы.
      const actions = closed
        ? '<span class="badge">разобрано</span>'
        : `${rv ? `<button class="btn btn-danger btn-sm" data-click="deleteReportedReview" data-id="${escapeHtml(r.id)}">Удалить отзыв</button>` : ''}
           <button class="btn btn-secondary btn-sm" data-click="dismissReport" data-id="${escapeHtml(r.id)}">Отклонить жалобу</button>`;
      return `<tr>
        <td>${text}</td>
        <td>${escapeHtml(REPORT_REASONS[r.reason] ?? r.reason ?? '')}</td>
        <td>${escapeHtml(venueName(r.venueID))}</td>
        <td>${escapeHtml(when)}</td>
        <td>${actions}</td>
      </tr>`;
    }).join('');
  } catch (e) {
    if (gen === reportsRenderGen)
      body.innerHTML = `<tr><td colspan="5" class="spinner">Ошибка: ${escapeHtml(e.message)}</td></tr>`;
  }
}

function venueName(id) {
  return venues.find(v => v.id === id)?.name ?? id ?? '';
}


const deleteReportedReview = async (reportID) => {
  // id отзыва — из загруженной жалобы, не из разметки; и только одиночный
  // сегмент пути: «abc/x/y» адресовал бы чужой документ под reviews/.
  const reviewID = reports.find(r => r.id === reportID)?.reviewID;
  if (!isDocId(reviewID)) { toast('В жалобе некорректный id отзыва', 'error'); return; }
  if (!confirm('Удалить отзыв? Отменить нельзя.')) return;
  try {
    await deleteDoc(doc(db, 'reviews', reviewID));
    await setDoc(doc(db, 'reviewReports', reportID), { status: 'reviewed' }, { merge: true });
    toast('Отзыв удалён');
    loadReports();
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

const dismissReport = async (reportID) => {
  try {
    await setDoc(doc(db, 'reviewReports', reportID), { status: 'reviewed' }, { merge: true });
    toast('Жалоба отклонена');
    loadReports();
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

// Список перерисует листенер pushCampaigns — перечитывать вручную не нужно.
const approveBoost = async (id) => {
  try {
    await setDoc(doc(db, 'pushCampaigns', id), { status: 'approved' }, { merge: true });
    toast('Кампания одобрена — рассылка запущена', 'success');
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};
const rejectBoost = async (id) => {
  try {
    await setDoc(doc(db, 'pushCampaigns', id), { status: 'rejected' }, { merge: true });
    toast('Кампания отклонена', 'success');
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

let hosts = [];
function loadHosts() {
  return subscribe('hosts', collection(db, 'hosts'),
    snap => {
      hosts = snap.docs.map(d => ({ uid: d.id, ...d.data() }));
      const rank = v => (v === 'pending' ? 0 : v === 'rejected' ? 1 : 2);
      hosts.sort((a, b) => rank(a.verification) - rank(b.verification)
        || (a.businessName || '').localeCompare(b.businessName || ''));
      setNavCount('navHostsCount', hosts.filter(h => h.verification === 'pending').length);
      renderHosts();
    },
    e => {
      document.getElementById('hostsBody').innerHTML =
        `<tr><td colspan="4" class="empty">Нет доступа к коллекции hosts. Опубликуй правила: firebase deploy --only firestore:rules<br><small>${escapeHtml(e.message)}</small></td></tr>`;
    });
}

function renderHosts() {
  const tbody = document.getElementById('hostsBody');
  if (!hosts.length) {
    tbody.innerHTML = '<tr><td colspan="4" class="empty">Хостов нет</td></tr>';
    return;
  }
  const map = { pending:['На рассмотрении','pending'], verified:['Подтверждён','approved'], rejected:['Отклонён','rejected'], none:['Не запрошена','pending'] };
  tbody.innerHTML = hosts.map(h => {
    const v = h.verification || 'none';
    const [label, cls] = map[v] || [v, 'pending'];
    const btns = v === 'verified'
      ? `<button class="btn btn-secondary btn-sm" data-click="rejectHost" data-id="${escapeHtml(h.uid)}">Снять</button>`
      : `<button class="btn btn-success btn-sm" data-click="approveHost" data-id="${escapeHtml(h.uid)}">✓ Верифицировать</button>
         <button class="btn btn-secondary btn-sm" data-click="rejectHost" data-id="${escapeHtml(h.uid)}">Отклонить</button>`;
    return `
    <tr>
      <td><strong>${escapeHtml(h.businessName || '—')}</strong></td>
      <td>${escapeHtml(h.email || '')}<br><small style="color:var(--muted)">${escapeHtml(h.phone || '')}</small></td>
      <td><span class="badge badge-${escapeHtml(cls)}">${escapeHtml(label)}</span></td>
      <td><div class="row-actions">${btns}</div></td>
    </tr>`;
  }).join('');
}

async function setHostVerification(uid, status, verified) {
  await setDoc(doc(db, 'hosts', uid), { verification: status }, { merge: true });
  // Венесы хоста получают/теряют галочку «Проверено».
  const snap = await getDocs(query(collection(db, 'venues'), where('ownerID', '==', uid)));
  if (!snap.empty) {
    const batch = writeBatch(db);
    snap.forEach(d => batch.update(d.ref, { isVerified: verified }));
    await batch.commit();
  }
  await Promise.all([loadHosts(), loadVenues()]);
}

const approveHost = async (uid) => {
  try { await setHostVerification(uid, 'verified', true); toast('Хост верифицирован', 'success'); }
  catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};
const rejectHost = async (uid) => {
  try { await setHostVerification(uid, 'rejected', false); toast('Верификация отклонена', 'success'); }
  catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

// Сессионная подписка: заведение, созданное хостом, появляется в очереди
// модерации без перезагрузки. Прежние вызовы `await loadVenues()` после записи
// остаются безвредными — повторная подписка не создаётся.
function loadVenues() {
  return subscribe('venues', collection(db, 'venues'),
    snap => {
      venues = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      // На модерации — выше, затем по имени (имени может не быть у черновика).
      const rank = s => ((s || 'approved') === 'pending' ? 0 : (s === 'rejected' ? 1 : 2));
      venues.sort((a, b) => rank(a.status) - rank(b.status)
        || (a.name || '').localeCompare(b.name || ''));
      setNavCount('navVenuesCount', venues.filter(v => v.status === 'pending').length);
      renderVenues();
      populateVenueSelect();
      // Названия заведений показываются в акциях, купонах и жалобах.
      if (liveLoaded.has('deals')) renderDeals();
      if (liveLoaded.has('couponOffers')) renderCoupons();
    },
    e => {
      document.getElementById('venuesBody').innerHTML =
        `<tr><td colspan="6" class="empty">Ошибка: ${escapeHtml(e.message)}</td></tr>`;
    });
}

const setVenueStatus = async (id, status) => {
  try {
    await setDoc(doc(db, 'venues', id), { status }, { merge: true });
    toast(status === 'approved' ? 'Заведение одобрено' : 'Статус обновлён', 'success');
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

function loadDeals() {
  return subscribe('deals', collection(db, 'deals'),
    snap => {
      deals = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      deals.sort((a, b) => (a.title || '').localeCompare(b.title || ''));
      renderDeals();
    },
    e => {
      document.getElementById('dealsBody').innerHTML =
        `<tr><td colspan="7" class="empty">Ошибка: ${escapeHtml(e.message)}</td></tr>`;
    });
}

// ── RENDER VENUES ─────────────────────────────────────────────────────────
function renderVenues() {
  const tbody = document.getElementById('venuesBody');
  if (!venues.length) {
    tbody.innerHTML = '<tr><td colspan="6" class="empty">Заведений нет</td></tr>';
    return;
  }
  const q = (document.getElementById('venueSearch')?.value || '').trim().toLowerCase();
  const list = q
    ? venues.filter(v => [v.name, v.address, v.district].some(f => (f || '').toLowerCase().includes(q)))
    : venues;
  if (!list.length) {
    tbody.innerHTML = '<tr><td colspan="6" class="empty">Ничего не найдено</td></tr>';
    return;
  }
  tbody.innerHTML = list.map(v => {
    const status = v.status || 'approved';
    const statusLabel = { pending:'На модерации', approved:'Одобрено', rejected:'Отклонено' }[status] || status;
    // На модерации — обе кнопки; иначе — переход в противоположный статус.
    const vid = escapeHtml(v.id);
    const approveBtn = `<button class="btn btn-success btn-sm" data-click="setVenueStatus" data-id="${vid}" data-status="approved">✓ Одобрить</button>`;
    const rejectBtn  = `<button class="btn btn-secondary btn-sm" data-click="setVenueStatus" data-id="${vid}" data-status="rejected">⨯ Отклонить</button>`;
    const modBtns = status === 'pending' ? approveBtn + rejectBtn
                  : status === 'approved' ? rejectBtn : approveBtn;
    return `
    <tr>
      <td class="emoji-cell">${escapeHtml(v.emoji ?? '🍽')}</td>
      <td><strong>${escapeHtml(v.name ?? '')}</strong>${(v.loyaltyEnabled && !v.pointsEnabled) ? ` <span class="badge" style="background:#fff0e8;color:#c0490f" title="${escapeHtml(v.loyaltyGoal ?? 6)} визитов → ${escapeHtml(v.loyaltyReward ?? '')}">🎟 Лояльность</span>` : ''}<br><small style="color:var(--muted)">${escapeHtml(v.address ?? '')}</small></td>
      <td><span class="badge badge-${escapeHtml(v.category)}">${escapeHtml(categoryLabel(v.category))}</span></td>
      <td>${escapeHtml(v.district ?? '')}</td>
      <td><span class="badge badge-${escapeHtml(status)}">${escapeHtml(statusLabel)}</span></td>
      <td>
        <div class="row-actions">
          ${modBtns}
          <button class="btn btn-secondary btn-sm" data-click="openVenueModal" data-id="${vid}">✏️</button>
          <button class="btn btn-danger btn-sm"    data-click="askDelete" data-type="venue" data-id="${vid}">🗑</button>
        </div>
      </td>
    </tr>`;
  }).join('');
}

// ── RENDER DEALS ──────────────────────────────────────────────────────────
function renderDeals() {
  const tbody = document.getElementById('dealsBody');
  if (!deals.length) {
    tbody.innerHTML = '<tr><td colspan="7" class="empty">Предложений нет</td></tr>';
    return;
  }
  tbody.innerHTML = deals.map(d => {
    const venue   = venues.find(v => v.id === d.venueID);
    const until   = toDate(d.validUntil);
    const expired = until ? until < new Date() : false;
    return `
    <tr style="${expired ? 'opacity:.45' : ''}">
      <td class="emoji-cell">${escapeHtml(d.emoji ?? '🔥')}</td>
      <td><strong>${escapeHtml(d.title ?? '')}</strong></td>
      <td><span class="badge badge-${escapeHtml(d.type)}">${escapeHtml(typeLabel(d.type))}</span></td>
      <td>${escapeHtml(venue ? (venue.name ?? '') : (d.venueID ?? ''))}</td>
      <td>${num(d.discountPercent) ? '−' + num(d.discountPercent) + '%' : (num(d.newPrice) ? num(d.newPrice) + ' сом' : '—')}</td>
      <td>${until ? escapeHtml(until.toLocaleDateString('ru-RU')) : '—'}${expired ? ' ⚠️' : ''}</td>
      <td>
        <div class="row-actions">
          <button class="btn btn-secondary btn-sm" data-click="openDealModal" data-id="${escapeHtml(d.id)}">✏️ Изменить</button>
          <button class="btn btn-danger btn-sm"    data-click="askDelete" data-type="deal" data-id="${escapeHtml(d.id)}">🗑</button>
        </div>
      </td>
    </tr>`}).join('');
}

function populateVenueSelect() {
  // Поисковый список названий (datalist) — можно печатать с клавиатуры.
  document.getElementById('dVenueList').innerHTML =
    venues.map(v => `<option value="${escapeHtml(v.name)}"></option>`).join('');
}

// ── VENUE MODAL ───────────────────────────────────────────────────────────
const openVenueModal = (id) => {
  editingVenueId = id ?? null;
  document.getElementById('venueModalTitle').textContent = id ? 'Изменить заведение' : 'Новое заведение';
  const v = id ? venues.find(x => x.id === id) : null;
  document.getElementById('vName').value         = v?.name ?? '';
  populateCategorySelect();
  document.getElementById('vCategory').value     = v?.category ?? (categories[0]?.slug ?? 'cafe');
  document.getElementById('vDistrict').value     = v?.district ?? '';
  document.getElementById('vAddress').value      = v?.address ?? '';
  document.getElementById('vPhone').value        = v?.phone ?? '';
  document.getElementById('vEmoji').value        = v?.emoji ?? '';
  document.getElementById('vGradientFrom').value = v?.gradientFrom ?? '#E65C00';
  document.getElementById('vGradientTo').value   = v?.gradientTo ?? '#F9D423';
  document.getElementById('vImageURL').value     = v?.imageURL ?? '';
  document.getElementById('vTodaySpecial').value = v?.todaySpecial ?? '';
  document.getElementById('vLatitude').value     = v?.latitude ?? '';
  document.getElementById('vLongitude').value    = v?.longitude ?? '';
  // Часы по дням: из weekHours, иначе из legacy openHour/closeHour.
  const oh = v?.openHour ?? 9, ch = v?.closeHour ?? 22;
  const week = (Array.isArray(v?.weekHours) && v.weekHours.length === 7)
    ? v.weekHours
    : WEEKDAYS.map(() => ({ closed:false, open:oh*60, close:ch*60 }));
  renderWeekHours(week);
  document.getElementById('vPdfMenuURL').value   = v?.pdfMenuURL ?? '';
  document.getElementById('vWhatsapp').value     = v?.whatsapp ?? '';
  document.getElementById('vInstagram').value    = v?.instagram ?? '';
  document.getElementById('vTelegram').value     = v?.telegram ?? '';
  document.getElementById('vLoyaltyEnabled').value = String(v?.loyaltyEnabled ?? false);
  document.getElementById('vLoyaltyGoal').value  = v?.loyaltyGoal ?? 6;
  document.getElementById('vLoyaltyReward').value = v?.loyaltyReward ?? '';
  document.getElementById('vLoyaltyTitle').value = v?.loyaltyTitle ?? '';
  currentStampCards = Array.isArray(v?.stampCards)
    ? v.stampCards.map(c => ({ id: c.id || '', title: c.title || '', goal: c.goal ?? 6,
        reward: c.reward || '', active: c.active !== false }))
    : [];
  renderStampCards();
  // Баллы САН (программа заведения).
  document.getElementById('vPointsEnabled').value      = String(v?.pointsEnabled ?? false);
  document.getElementById('vPointsMode').value         = v?.pointsMode ?? 'flat';
  document.getElementById('vPointsFlat').value         = v?.pointsFlat ?? '';
  document.getElementById('vCashbackPercent').value    = v?.cashbackPercent ?? '';
  document.getElementById('vRedeemMode').value         = v?.redeemMode ?? 'staffScan';
  document.getElementById('vPointsExpiryMonths').value = v?.pointsExpiryMonths ?? 6;
  document.getElementById('vEarnCooldown').value       = v?.earnCooldownMinutes ?? 60;
  currentPointsBands = Array.isArray(v?.pointsBands)
    ? v.pointsBands.map(b => ({ id: b.id || 'bd_' + Math.random().toString(36).slice(2, 10),
        maxAmount: b.maxAmount ?? 0, points: b.points ?? 0 }))
    : [];
  renderPointsBands();
  currentPointsRewards = Array.isArray(v?.pointsRewards)
    ? v.pointsRewards.map(r => ({ id: r.id || 'rw_' + Math.random().toString(36).slice(2, 10),
        type: r.type || 'item', title: r.title || '', cost: r.cost ?? 0,
        ratio: r.ratio ?? 1, active: r.active !== false }))
    : [];
  renderPointsRewards();
  updatePointsUI();
  document.getElementById('vVerified').value     = String(v?.isVerified ?? false);
  document.getElementById('vModeration').value   = v?.status ?? 'approved';
  document.getElementById('vActive').value       = String((v?.isPaused ? false : (v?.active ?? true)));
  currentItems = Array.isArray(v?.items) ? v.items.map(it => ({ ...it })) : [];
  renderVenueItems();
  currentBranches = Array.isArray(v?.branches)
    ? v.branches.map(b => ({ id: b.id || 'br_' + Math.random().toString(36).slice(2, 10), ...b }))
    : [];
  renderVenueBranches();
  document.getElementById('venueModal').classList.remove('hidden');
  setTimeout(initVenueMap, 150);   // карта рисуется после показа модалки
};

// ── Карта-выбор точки (Leaflet + OpenStreetMap, бесплатно) ────────────────
let venueMap = null, venueMarker = null;
function initVenueMap() {
  if (typeof L === 'undefined') return;   // Leaflet не загрузился
  const lat = parseFloat(document.getElementById('vLatitude').value) || 42.8746;
  const lng = parseFloat(document.getElementById('vLongitude').value) || 74.5698;
  if (!venueMap) {
    venueMap = L.map('vMap').setView([lat, lng], 14);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
      { maxZoom: 19, attribution: '© OpenStreetMap' }).addTo(venueMap);
    venueMarker = L.marker([lat, lng], { draggable: true }).addTo(venueMap);
    venueMap.on('click', (e) => setVenueMarker(e.latlng.lat, e.latlng.lng));
    venueMarker.on('dragend', () => {
      const p = venueMarker.getLatLng();
      setVenueMarker(p.lat, p.lng);
    });
  } else {
    venueMap.setView([lat, lng], 14);
    venueMarker.setLatLng([lat, lng]);
  }
  venueMap.invalidateSize();
}
function setVenueMarker(lat, lng) {
  venueMarker.setLatLng([lat, lng]);
  document.getElementById('vLatitude').value  = lat.toFixed(6);
  document.getElementById('vLongitude').value = lng.toFixed(6);
}

// ── Часы работы по дням ───────────────────────────────────────────────────
const WEEKDAYS = ['Понедельник','Вторник','Среда','Четверг','Пятница','Суббота','Воскресенье'];
function minToHHMM(m) { if (m == null) m = 0; const h = Math.floor(m/60)%24, mm = m%60;
  return String(h).padStart(2,'0') + ':' + String(mm).padStart(2,'0'); }
function hhmmToMin(s) { if (!s) return 0; const p = s.split(':'); return (+p[0]||0)*60 + (+p[1]||0); }

function renderWeekHours(week) {
  document.getElementById('vWeekHours').innerHTML = WEEKDAYS.map((name, i) => {
    const d = week[i] || { closed:false, open:540, close:1320 };
    return `<div class="wh-row" data-day="${i}"
        style="display:flex;align-items:center;gap:10px;margin-bottom:6px;flex-wrap:wrap;">
      <span style="width:110px;">${escapeHtml(name)}</span>
      <label style="display:flex;align-items:center;gap:4px;font-weight:400;">
        <input type="checkbox" class="wh-closed" ${d.closed?'checked':''} data-change="toggleWhRow" data-index="${i}"/> выходной
      </label>
      <input type="time" class="wh-open"  value="${escapeHtml(minToHHMM(num(d.open, 540)))}"  ${d.closed?'disabled':''}/>
      <input type="time" class="wh-close" value="${escapeHtml(minToHHMM(num(d.close, 1320)))}" ${d.closed?'disabled':''}/>
    </div>`;
  }).join('');
}
const toggleWhRow = (i) => {
  const row = document.querySelector(`.wh-row[data-day="${i}"]`);
  const closed = row.querySelector('.wh-closed').checked;
  row.querySelector('.wh-open').disabled = closed;
  row.querySelector('.wh-close').disabled = closed;
};
const applyMondayToAll = () => {
  const m = collectWeekHours()[0];
  renderWeekHours(Array.from({length:7}, () => ({ ...m })));
};
function collectWeekHours() {
  return [...document.querySelectorAll('.wh-row')].map(row => ({
    closed: row.querySelector('.wh-closed').checked,
    open:   hhmmToMin(row.querySelector('.wh-open').value),
    close:  hhmmToMin(row.querySelector('.wh-close').value),
  }));
}

// Геокодинг адреса → координаты (бесплатно, OpenStreetMap Nominatim).
const geocodeAddress = async () => {
  const addr = document.getElementById('vAddress').value.trim();
  if (!addr) { toast('Сначала впиши адрес', 'error'); return; }
  try {
    const q = encodeURIComponent(addr + ', Бишкек, Кыргызстан');
    const res = await fetch(`https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${q}`,
      { headers: { 'Accept-Language': 'ru' } });
    const data = await res.json();
    if (!data.length) { toast('Адрес не найден — поставь метку вручную', 'error'); return; }
    const lat = parseFloat(data[0].lat), lng = parseFloat(data[0].lon);
    if (venueMap) { venueMap.setView([lat, lng], 16); }
    setVenueMarker(lat, lng);
    toast('Координаты найдены', 'success');
  } catch (e) {
    toast('Не удалось найти адрес', 'error');
  }
};

const saveVenue = async () => {
  const num = v => { const n = Number(v); return v === '' || isNaN(n) ? null : n; };
  // Целое из поля с СОХРАНЕНИЕМ явного нуля: `parseInt(x) || fallback` съедает 0,
  // а для кулдауна ноль осмыслен («выключен»). Зеркалит intOrDefault на сервере.
  const intOr = (id, fallback) => {
    const n = parseInt(document.getElementById(id).value, 10);
    return Number.isFinite(n) ? n : fallback;
  };
  const data = {
    name:         document.getElementById('vName').value.trim(),
    category:     document.getElementById('vCategory').value,
    district:     document.getElementById('vDistrict').value.trim(),
    address:      document.getElementById('vAddress').value.trim(),
    phone:        document.getElementById('vPhone').value.trim(),
    emoji:        document.getElementById('vEmoji').value.trim(),
    gradientFrom: document.getElementById('vGradientFrom').value,
    gradientTo:   document.getElementById('vGradientTo').value,
    city:         'bishkek',
    isVerified:   document.getElementById('vVerified').value === 'true',
    active:       document.getElementById('vActive').value === 'true',
    isPaused:     document.getElementById('vActive').value !== 'true',
    status:       document.getElementById('vModeration').value,
    items:        currentItems,
    branches:     currentBranches,
    imageURL:     document.getElementById('vImageURL').value.trim(),
    todaySpecial: document.getElementById('vTodaySpecial').value.trim(),
    latitude:     num(document.getElementById('vLatitude').value),
    longitude:    num(document.getElementById('vLongitude').value),
    weekHours:    collectWeekHours(),
    pdfMenuURL:   document.getElementById('vPdfMenuURL').value.trim(),
    whatsapp:     document.getElementById('vWhatsapp').value.trim(),
    instagram:    document.getElementById('vInstagram').value.trim(),
    telegram:     document.getElementById('vTelegram').value.trim(),
    loyaltyEnabled: document.getElementById('vLoyaltyEnabled').value === 'true',
    // Первая карта — без верхнего предела, как на сервере и в приложении
    // (activeStampCards / StampCards.firstGoal); 0 и мусор — «не задано» (6).
    loyaltyGoal:  Math.max(parseInt(document.getElementById('vLoyaltyGoal').value) || 6, 2),
    loyaltyReward: document.getElementById('vLoyaltyReward').value.trim() || 'Награда за лояльность',
    loyaltyTitle:  document.getElementById('vLoyaltyTitle').value.trim().slice(0, 30),
    stampCards:    collectStampCards(),
    // Баллы САН — программа заведения (гардрейлы дублируют серверные).
    pointsEnabled: document.getElementById('vPointsEnabled').value === 'true',
    pointsMode:    document.getElementById('vPointsMode').value,
    pointsFlat:    Math.min(Math.max(parseInt(document.getElementById('vPointsFlat').value) || 0, 0), 10000),
    cashbackPercent: Math.min(Math.max(Number(document.getElementById('vCashbackPercent').value) || 0, 0), 20),
    pointsBands: currentPointsBands.slice().sort((a, b) => a.maxAmount - b.maxAmount)
                   .map(b => ({ maxAmount: b.maxAmount, points: b.points })),
    pointsRewards: currentPointsRewards.map(r => ({
      id: r.id, type: r.type, title: r.title, cost: r.cost, ratio: r.ratio ?? 1, active: r.active !== false })),
    pointsExpiryMonths: Math.min(Math.max(parseInt(document.getElementById('vPointsExpiryMonths').value) || 6, 1), 36),
    redeemMode: document.getElementById('vRedeemMode').value,
    // 0 = кулдаун выключен (начисление на каждый скан); пусто/мусор = дефолтные 60 мин.
    earnCooldownMinutes: Math.min(Math.max(intOr('vEarnCooldown', 60), 0), 1440),
  };
  if (!data.name) return toast('Укажи название', 'error');
  // Ссылки уходят в приложения как есть: только https (не javascript:, не http:).
  if (data.imageURL && !safeUrl(data.imageURL)) return toast('Обложка — только ссылка https://', 'error');
  if (data.pdfMenuURL && !safeUrl(data.pdfMenuURL)) return toast('PDF-меню — только ссылка https://', 'error');
  // Пустые координаты по умолчанию — центр Бишкека.
  if (data.latitude === null)  data.latitude  = 42.8746;
  if (data.longitude === null) data.longitude = 74.5698;
  // Пустой специал/PDF — удаляем поле, чтобы убрать его из карточки.
  const toDelete = [];
  if (!data.todaySpecial) { delete data.todaySpecial; toDelete.push('todaySpecial'); }
  if (!data.pdfMenuURL)   { delete data.pdfMenuURL;   toDelete.push('pdfMenuURL'); }
  // Убираем оставшиеся null-поля (необязательные часы).
  Object.keys(data).forEach(k => data[k] === null && delete data[k]);
  try {
    if (editingVenueId) {
      await setDoc(doc(db, 'venues', editingVenueId), data, { merge: true });
      // Явно стираем очищенные поля.
      if (toDelete.length) {
        const patch = Object.fromEntries(toDelete.map(k => [k, deleteField()]));
        await setDoc(doc(db, 'venues', editingVenueId), patch, { merge: true });
      }
    } else {
      await addDoc(collection(db, 'venues'), data);
    }
    closeModal('venueModal');
    await loadVenues();
    toast(editingVenueId ? 'Заведение обновлено' : 'Заведение добавлено', 'success');
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

// ── DEAL MODAL ────────────────────────────────────────────────────────────
const openDealModal = (id) => {
  editingDealId = id ?? null;
  document.getElementById('dealModalTitle').textContent = id ? 'Изменить предложение' : 'Новое предложение';
  const d = id ? deals.find(x => x.id === id) : null;
  document.getElementById('dTitle').value           = d?.title ?? '';
  document.getElementById('dType').value            = d?.type ?? 'discount';
  document.getElementById('dVenueID').value         =
    (venues.find(v => v.id === d?.venueID)?.name) ?? (venues[0]?.name ?? '');
  document.getElementById('dDetails').value         = d?.details ?? '';
  document.getElementById('dTerms').value           = (d?.terms ?? []).join('\n');
  document.getElementById('dEmoji').value           = d?.emoji ?? '';
  document.getElementById('dOldPrice').value        = d?.oldPrice ?? '';
  document.getElementById('dNewPrice').value        = d?.newPrice ?? '';
  document.getElementById('dDiscountPercent').value = d?.discountPercent ?? '';
  document.getElementById('dImageURL').value        = d?.imageURL ?? '';
  document.getElementById('dStatus').value          = d?.status ?? 'active';
  const until = d?.validUntil?.toDate ? d.validUntil.toDate() : new Date();
  if (!id) until.setDate(until.getDate() + 14);
  const noExpiry = until.getFullYear() >= 2090;   // далёкая дата = бессрочно
  document.getElementById('dValidUntil').value = until.toISOString().slice(0, 10);
  document.getElementById('dNoExpiry').checked = noExpiry;
  document.getElementById('dValidUntil').disabled = noExpiry;
  document.getElementById('dealModal').classList.remove('hidden');
};

const saveDeal = async () => {
  const title = document.getElementById('dTitle').value.trim();
  const until = document.getElementById('dValidUntil').value;
  const noExpiry = document.getElementById('dNoExpiry').checked;
  if (!title) return toast('Укажи название', 'error');
  if (!noExpiry && !until) return toast('Укажи дату окончания или отметь «Бессрочно»', 'error');

  // Заведение выбрано по названию → находим id.
  const venueName = document.getElementById('dVenueID').value.trim();
  const venueID = (venues.find(v => v.name === venueName)?.id) ?? '';
  if (!venueID) return toast('Выбери заведение из списка', 'error');
  const dImage = document.getElementById('dImageURL').value.trim();
  if (dImage && !safeUrl(dImage)) return toast('Фото — только ссылка https://', 'error');

  const num = v => { const n = Number(v); return isNaN(n) || v === '' ? null : n; };
  const data = {
    title,
    type:            document.getElementById('dType').value,
    venueID,
    details:         document.getElementById('dDetails').value.trim(),
    // Массив строк, по строке на пункт (домен: `Deal.terms`). Пустые
    // строки выбрасываем — пустой буллет в ленте ведёт в никуда.
    terms:           document.getElementById('dTerms').value
                       .split('\n').map(t => t.trim()).filter(Boolean),
    emoji:           document.getElementById('dEmoji').value.trim(),
    status:          document.getElementById('dStatus').value,
    imageURL:        document.getElementById('dImageURL').value.trim(),
    validUntil:      Timestamp.fromDate(noExpiry ? new Date('2099-12-31T23:59:59')
                                                 : new Date(until + 'T23:59:59')),
    oldPrice:        num(document.getElementById('dOldPrice').value),
    newPrice:        num(document.getElementById('dNewPrice').value),
    discountPercent: num(document.getElementById('dDiscountPercent').value),
  };
  // Strip nulls
  Object.keys(data).forEach(k => data[k] === null && delete data[k]);

  try {
    if (editingDealId) {
      await setDoc(doc(db, 'deals', editingDealId), data, { merge: true });
    } else {
      await addDoc(collection(db, 'deals'), data);
    }
    closeModal('dealModal');
    await loadDeals();
    toast(editingDealId ? 'Предложение обновлено' : 'Предложение добавлено', 'success');
  } catch (e) { toast('Ошибка: ' + e.message, 'error'); }
};

// ── DELETE ────────────────────────────────────────────────────────────────
const askDelete = (type, id) => {
  // Названия пишет хост — в разметку кнопки их не кладём, а берём по id.
  // Тип — из белого списка: data-type задаёт только наш код, но коллекция,
  // в которой удаляют документ, не должна зависеть от строки из DOM.
  if (!['venue', 'deal', 'category'].includes(type) || !isDocId(id)) return;
  const name = (type === 'venue'    ? venues.find(v => v.id === id)?.name
              : type === 'deal'     ? deals.find(d => d.id === id)?.title
              : (c => c?.name ?? c?.slug)(categories.find(c => c.id === id))) ?? id;
  document.getElementById('confirmText').textContent = `«${name}» будет удалено безвозвратно.`;
  const coll = type === 'venue' ? 'venues' : (type === 'category' ? 'categories' : 'deals');
  pendingDeleteFn = async () => {
    await deleteDoc(doc(db, coll, id));
    closeModal('confirmModal');
    if (type === 'venue')         { await loadVenues();     toast('Заведение удалено', 'success'); }
    else if (type === 'category') { await loadCategories(); toast('Категория удалена', 'success'); }
    else                          { await loadDeals();      toast('Предложение удалено', 'success'); }
  };
  document.getElementById('confirmModal').classList.remove('hidden');
};
const confirmDelete = () => pendingDeleteFn?.();

// ── HELPERS ───────────────────────────────────────────────────────────────
const closeModal = id => document.getElementById(id).classList.add('hidden');

const showPage = (page) => {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('nav button:not(#signOutBtn)').forEach(b => b.classList.remove('active'));
  document.getElementById('page' + page.charAt(0).toUpperCase() + page.slice(1)).classList.add('active');
  document.getElementById('nav'  + page.charAt(0).toUpperCase() + page.slice(1)).classList.add('active');
  // Страничные листенеры других вкладок снимаем, чтобы не держать их фоном.
  for (const [p, keys] of Object.entries(PAGE_SUBS)) {
    if (p !== page) keys.forEach(unsubscribe);
  }
  // Сессионные подписки: если листенер упал (напр. сеть/правила), заход на
  // вкладку переподписывает; если жив — ничего не делает.
  if (page === 'venues') loadVenues();
  if (page === 'deals') loadDeals();
  if (page === 'hosts') loadHosts();
  if (page === 'boosts') loadBoosts();
  if (page === 'reports') loadReports();
  if (page === 'coupons') loadCoupons();
  if (page === 'rewards') loadRewards();
  if (page === 'settings') loadSettings();
  if (page === 'categories') loadCategories();
};

// ── Купоны заведений ───────────────────────────────────────────────────────
// Модерация: админ решает, можно ли продавать. Цену и текст задаёт заведение —
// сюда они приходят только на проверку, править их отсюда незачем.
//
// Живая подписка на всю коллекцию `couponOffers` (без where/orderBy: документ
// без поля, по которому сортирует запрос, Firestore молча выкидывает — поэтому
// сортируем и фильтруем на клиенте). Имена полей — те же, что в
// FS.CouponOfferDoc (AyantData/.../FirestoreSchema.swift): venueID, venueName,
// title, details, emoji, imageURL, cost, stock, soldCount, expiresAt, status,
// isPaused, ownerID, city. Панель пишет ТОЛЬКО `status`: soldCount считает
// сервер при покупке, остальное принадлежит заведению.
let couponOffers = [];

function loadCoupons() {
  return subscribe('couponOffers', collection(db, 'couponOffers'),
    snap => {
      couponOffers = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      setNavCount('navCouponsCount',
        couponOffers.filter(r => (r.status ?? 'pending') === 'pending').length);
      const live = document.getElementById('couponsLive');
      if (live) live.textContent = '● обновлено ' + new Date().toLocaleTimeString('ru-RU');
      renderCoupons();
    },
    e => {
      document.getElementById('couponsBody').innerHTML =
        `<tr><td colspan="7" class="spinner">Ошибка: ${escapeHtml(e.message)}</td></tr>`;
      const live = document.getElementById('couponsLive');
      if (live) live.textContent = 'нет связи — откройте вкладку ещё раз';
    });
}

const COUPON_STATUS = {
  pending:  { label: 'На модерации', cls: 'badge-pending',  rank: 0 },
  approved: { label: 'Одобрен',      cls: 'badge-approved', rank: 1 },
  rejected: { label: 'Отклонён',     cls: 'badge-rejected', rank: 2 },
};

function renderCoupons() {
  const body = document.getElementById('couponsBody');
  if (!body) return;
  const filter = document.getElementById('couponsFilter')?.value || 'all';
  const statusOf = r => (COUPON_STATUS[r.status] ? r.status : 'pending');
  let rows = couponOffers.slice();
  if (filter !== 'all') rows = rows.filter(r => statusOf(r) === filter);
  // Непроверенные сверху: очередь модерации, а не каталог. Дальше — по
  // заведению и названию, чтобы строки не прыгали при каждом снапшоте.
  const vName = r => r.venueName || venueName(r.venueID) || '';
  rows.sort((a, b) => COUPON_STATUS[statusOf(a)].rank - COUPON_STATUS[statusOf(b)].rank
    || vName(a).localeCompare(vName(b))
    || (a.title || '').localeCompare(b.title || '')
    || a.id.localeCompare(b.id));
  if (!rows.length) {
    const empty = filter === 'pending' ? 'Всё проверено' : 'Купонов нет';
    body.innerHTML = `<tr><td colspan="7" class="spinner">${empty}</td></tr>`;
    return;
  }
  const now = new Date();
  body.innerHTML = rows.map(r => {
    const status = statusOf(r);
    const st = COUPON_STATUS[status];
    const sold = Number(r.soldCount) || 0;
    const stock = (r.stock === null || r.stock === undefined) ? null : Number(r.stock);
    const left = stock === null ? null : Math.max(0, stock - sold);
    const expires = toDate(r.expiresAt);
    const expired = expires ? expires < now : false;
    // Почему купон сейчас не продаётся, даже если одобрен.
    const flags = [];
    if (r.isPaused) flags.push('<span class="badge badge-muted">снят заведением</span>');
    if (left === 0) flags.push('<span class="badge badge-muted">распродан</span>');
    if (expired)    flags.push('<span class="badge badge-muted">срок истёк</span>');
    const selling = status === 'approved' && !r.isPaused && left !== 0 && !expired;
    const venueLabel = r.venueName || venueName(r.venueID) || '—';
    return `
      <tr style="${(expired || r.isPaused) ? 'opacity:.6' : ''}">
        <td>${escapeHtml(r.emoji ?? '')} <strong>${escapeHtml(r.title ?? '(без названия)')}</strong>
          <div style="color:var(--muted);font-size:12px">${escapeHtml(r.details ?? '')}</div></td>
        <td>${escapeHtml(venueLabel)}</td>
        <td>${num(r.cost)}</td>
        <td>${left === null ? '∞' : num(left)}${stock !== null ? ` из ${num(stock)}` : ''}
          <div style="color:var(--muted);font-size:12px">продано ${num(sold)}</div></td>
        <td>${expires ? escapeHtml(expires.toLocaleDateString('ru-RU')) : 'бессрочно'}</td>
        <td><span class="badge ${st.cls}">${st.label}</span>
          ${selling ? '<div style="color:var(--success);font-size:12px">продаётся</div>' : ''}
          ${flags.length ? `<div style="margin-top:4px;display:flex;gap:4px;flex-wrap:wrap">${flags.join('')}</div>` : ''}</td>
        <td style="white-space:nowrap">
          ${status !== 'approved' ? `<button class="btn btn-success btn-sm" data-click="setCouponStatus" data-id="${escapeHtml(r.id)}" data-status="approved">✓ Одобрить</button>` : ''}
          ${status !== 'rejected' ? `<button class="btn btn-secondary btn-sm" data-click="setCouponStatus" data-id="${escapeHtml(r.id)}" data-status="rejected">⨯ Отклонить</button>` : ''}
        </td>
      </tr>`;
  }).join('');
}

// Пишем только status (правила: заведение его менять не может, админ — может).
// Таблицу перерисует листенер.
const setCouponStatus = async (id, status) => {
  try {
    await updateDoc(doc(db, 'couponOffers', id), { status });
    toast(status === 'approved' ? 'Купон одобрен — теперь он продаётся' : 'Купон отклонён', 'success');
  } catch (e) {
    toast('Не удалось сохранить: ' + e.message, 'error');
  }
};

function categoryLabel(c) {
  const found = categories.find(x => x.slug === c || x.id === c);
  if (found) return found.name ?? found.slug;
  // Фолбэк на встроенные, если категории ещё не загрузились.
  return { cafe:'Кафе', coffee:'Кофейня', fastfood:'Фастфуд',
           restaurant:'Ресторан', teahouse:'Чайхана', bakery:'Пекарня' }[c] ?? c;
}
function typeLabel(t) {
  return { discount:'Скидка', promo:'Акция', novelty:'Новинка', announcement:'Объявление' }[t] ?? t;
}

let toastTimer;
function toast(msg, type = 'success') {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.className = 'show ' + type;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.className = '', 3000);
}

// Close modals on overlay click
document.querySelectorAll('.modal-overlay').forEach(overlay => {
  overlay.addEventListener('click', e => {
    if (e.target === overlay) overlay.classList.add('hidden');
  });
});

// ── ДЕЙСТВИЯ ──────────────────────────────────────────────────────────────
// Вместо inline-обработчиков: элемент несёт data-click / data-input /
// data-change с ИМЕНЕМ действия и параметры в data-id, data-index, data-field,
// data-status, data-type…; три слушателя на document находят ближайший такой
// элемент и вызывают действие из белого списка ниже. Значения data-* — всегда
// строки, через escapeHtml в разметке; сюда приходят уже раскодированными.
// Новая кнопка = новая строка здесь, а не inline-обработчик в разметке.
const idx = el => {
  const n = Number(el.dataset.index);
  return Number.isInteger(n) && n >= 0 ? n : -1;
};
// Текстовые поля — по input; галка/селект — только по change (они шлют и input).
const STAMP_CARD_FIELDS = new Set(['title', 'goal', 'reward']);
const REWARD_FIELDS = new Set(['title', 'cost', 'emoji']);
const MODALS = new Set(['venueModal', 'dealModal', 'categoryModal', 'confirmModal']);
const PAGES = new Set(['venues', 'deals', 'categories', 'hosts', 'boosts', 'reports',
                       'coupons', 'rewards', 'settings']);
const UPLOAD_TARGETS = new Set(['vImageURL', 'vItemImageURL', 'dImageURL']);
const STATUSES = new Set(['approved', 'rejected']);

const ACTIONS = {
  click: {
    signIn:            () => signIn(),
    signOut:           () => signOut(),
    showPage:          el => { if (PAGES.has(el.dataset.page)) showPage(el.dataset.page); },
    closeModal:        el => { if (MODALS.has(el.dataset.modal)) closeModal(el.dataset.modal); },
    seedDemo:          () => seedDemo(),
    openVenueModal:    el => openVenueModal(el.dataset.id),
    openDealModal:     el => openDealModal(el.dataset.id),
    openCategoryModal: el => openCategoryModal(el.dataset.id),
    addRewardRow:      () => addRewardRow(),
    saveRewards:       () => saveRewards(),
    removeReward:      el => { const i = idx(el); if (i >= 0) removeReward(i); },
    saveSettings:      () => saveSettings(),
    geocodeAddress:    () => geocodeAddress(),
    geocodeBranch:     () => geocodeBranch(),
    addVenueBranch:    () => addVenueBranch(),
    removeVenueBranch: el => removeVenueBranch(el.dataset.id),
    applyMondayToAll:  () => applyMondayToAll(),
    addStampCard:      () => addStampCard(),
    removeStampCard:   el => { const i = idx(el); if (i >= 0) removeStampCard(i); },
    addPointsBand:     () => addPointsBand(),
    removePointsBand:  el => removePointsBand(el.dataset.id),
    addPointsReward:   () => addPointsReward(),
    removePointsReward: el => removePointsReward(el.dataset.id),
    addVenueItem:      () => addVenueItem(),
    removeVenueItem:   el => removeVenueItem(el.dataset.id),
    saveVenue:         () => saveVenue(),
    saveDeal:          () => saveDeal(),
    saveCategory:      () => saveCategory(),
    askDelete:         el => askDelete(el.dataset.type, el.dataset.id),
    confirmDelete:     () => confirmDelete(),
    approveBoost:      el => { if (isDocId(el.dataset.id)) approveBoost(el.dataset.id); },
    rejectBoost:       el => { if (isDocId(el.dataset.id)) rejectBoost(el.dataset.id); },
    approveHost:       el => { if (isDocId(el.dataset.id)) approveHost(el.dataset.id); },
    rejectHost:        el => { if (isDocId(el.dataset.id)) rejectHost(el.dataset.id); },
    setVenueStatus:    el => {
      if (isDocId(el.dataset.id) && STATUSES.has(el.dataset.status)) setVenueStatus(el.dataset.id, el.dataset.status);
    },
    setCouponStatus:   el => {
      if (isDocId(el.dataset.id) && STATUSES.has(el.dataset.status)) setCouponStatus(el.dataset.id, el.dataset.status);
    },
    deleteReportedReview: el => { if (isDocId(el.dataset.id)) deleteReportedReview(el.dataset.id); },
    dismissReport:     el => { if (isDocId(el.dataset.id)) dismissReport(el.dataset.id); },
  },
  input: {
    renderVenues:        () => renderVenues(),
    onCategoryNameInput: () => onCategoryNameInput(),
    editStampCard: el => {
      const i = idx(el);
      if (i >= 0 && STAMP_CARD_FIELDS.has(el.dataset.field)) editStampCard(i, el.dataset.field, el.value);
    },
    editReward: el => {
      const i = idx(el);
      if (i >= 0 && REWARD_FIELDS.has(el.dataset.field) && globalRewards[i]) editReward(i, el.dataset.field, el.value);
    },
  },
  change: {
    loadReports:    () => loadReports(),
    renderCoupons:  () => renderCoupons(),
    updatePointsUI: () => updatePointsUI(),
    toggleNoExpiry: el => { document.getElementById('dValidUntil').disabled = el.checked; },
    uploadImage:    el => { if (UPLOAD_TARGETS.has(el.dataset.target)) uploadImage(el, el.dataset.target); },
    toggleWhRow:    el => { const i = idx(el); if (i >= 0 && i < 7) toggleWhRow(i); },
    editStampCard: el => {
      const i = idx(el);
      if (i >= 0 && el.dataset.field === 'active') editStampCard(i, 'active', el.checked);
    },
    editReward: el => {
      const i = idx(el);
      if (i >= 0 && el.dataset.field === 'venueID' && globalRewards[i]) editReward(i, 'venueID', el.value);
    },
  },
};

for (const type of Object.keys(ACTIONS)) {
  document.addEventListener(type, e => {
    const el = e.target instanceof Element ? e.target.closest(`[data-${type}]`) : null;
    if (!el) return;
    const fn = Object.prototype.hasOwnProperty.call(ACTIONS[type], el.dataset[type])
      ? ACTIONS[type][el.dataset[type]] : null;
    if (!fn) { console.warn(`[admin] неизвестное действие ${type}:${el.dataset[type]}`); return; }
    fn(el, e);
  });
}

// Enter в поле пароля — вход (раньше формы не было, и Enter ничего не делал).
document.getElementById('authPassword')?.addEventListener('keydown', e => {
  if (e.key === 'Enter') signIn();
});
