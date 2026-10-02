/**
 * Cloud Functions — рассылка рекламных push-кампаний (САН) с частотным лимитом.
 *
 * Триггер: создание документа в `pushCampaigns` (его пишет хост-приложение).
 * Рассылка идёт АДРЕСНО по FCM-токенам (коллекция `userTokens`) — это позволяет
 * соблюдать лимит из спецификации: не более 1 push в день и 3 в неделю на пользователя
 * (история в коллекции `pushLog/{token}`).
 *
 * Деплой:
 *   npm --prefix functions run build && firebase deploy --only functions
 */

import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, DocumentReference, AggregateField, FieldPath } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getAuth } from "firebase-admin/auth";
import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";
import type {
  Numeric,
  AppSettingsDoc,
  VenueDoc,
  CouponDoc,
  VenuePointsDoc,
  PushCampaignDoc,
  PointsBand,
  PointsReward,
  IgAccountDoc,
  IgAuthStateDoc,
} from "./types";

/* ───────────────────────────────────────────────────────────────────────────
 * Регион. База Firestore живёт в `nam5` (мульти-регион США) — это проверено и
 * зафиксировано осознанно, см. docs/design/system-design.md §5.5. Функции
 * должны стоять РЯДОМ с данными: транзакция в `scanCoupon` делает несколько
 * обращений к Firestore, и функция в другом регионе оплачивала бы RTT на
 * каждом из них. Раньше регион не задавался — деплой молча брал дефолт
 * (us-central1), и смена дефолта в firebase-tools увела бы функции от данных.
 * Теперь он записан явно.
 * ─────────────────────────────────────────────────────────────────────────── */
const REGION = "us-central1";
setGlobalOptions({ region: REGION });

/* Денежный путь (скан QR у стойки, списание баллов). Замер с реального
 * устройства: тёплый вызов — TTFB ~100 мс, первый после простоя — 2.73 с.
 * Разница в 27× — это холодный старт, а не география.
 *
 * `minInstances: 1` (один прогретый инстанс на функцию, ≈$11/мес за обе)
 * снят на время запуска: заведений мало, сканов ещё меньше, и первый
 * медленный скан после простоя дешевле фиксированного счёта. Вернуть
 * `minInstances: 1`, когда денежный путь станет по-настоящему занятым.
 * concurrency=80 — эти хендлеры почти всё время ждут Firestore, не CPU. */
const MONEY_PATH_OPTS = {
  cors: true,
  concurrency: 80,
  // Потолок стоимости (аудит запуска 2026-10-01): бот или петля в клиенте не
  // должны раздувать счёт без предела. 20 × 80 = 1600 одновременных запросов —
  // на порядок выше ожидаемой нагрузки 10k пользователей.
  maxInstances: 20,
} as const;

/** Обычные HTTPS-функции (не денежный путь): тот же потолок стоимости. */
const HTTP_OPTS = { cors: true, maxInstances: 20 } as const;

initializeApp();
const db = getFirestore();

const DAY_MS = 86400000;
// Частотные лимиты из спецификации (анти-спам): не более 1 push в день и 3 в неделю
// на пользователя. Для локального теста можно временно поднять через переменные
// окружения PUSH_DAILY_CAP / PUSH_WEEKLY_CAP — в продакшене они не задаются.
// Разбор с сохранением явного 0 (отключить пуши в тесте): пустое/нечисловое → дефолт.
function capFromEnv(raw: string | undefined, fallback: number): number {
  if (raw === undefined || raw === "") return fallback;
  const n = Number(raw);
  return Number.isFinite(n) ? n : fallback;
}
/**
 * Число из env, прижатое к разумным границам. Опечатка в `functions/.env`
 * («BONUS_DAILY_EARN_CAP=20000», лишний ноль) не должна превращать потолок в
 * его отсутствие: значение вне [min, max] прижимается, мусор — дефолт.
 */
export function clampedCapFromEnv(raw: string | undefined, fallback: number, min: number, max: number): number {
  const n = capFromEnv(raw, fallback);
  return Math.min(Math.max(Math.floor(n), min), max);
}
const DAILY_CAP = capFromEnv(process.env.PUSH_DAILY_CAP, 1);
const WEEKLY_CAP = capFromEnv(process.env.PUSH_WEEKLY_CAP, 3);

// Награды за рефералку (бонусы). env REFERRAL_REWARD / REFERRAL_WELCOME,
// не больше 1000: награда за приглашение — тоже деньги заведений.
const REFERRAL_REWARD = clampedCapFromEnv(process.env.REFERRAL_REWARD, 100, 0, 1000);
// Приветственный бонус тому, кого пригласили.
const REFERRAL_WELCOME = clampedCapFromEnv(process.env.REFERRAL_WELCOME, 100, 0, 1000);
// Анти-фарм: потолок реферальных наград на одного пригласившего. Без него можно
// нафармить бонусы, создав N аккаунтов, каждый из которых указывает твой userID
// пригласившим (Sybil). Настраивается через env REFERRAL_MAX_REWARDS.
// Прижат к [0, 200]: опечатка в env не отключает анти-Sybil потолок.
const REFERRAL_MAX_REWARDS = clampedCapFromEnv(process.env.REFERRAL_MAX_REWARDS, 20, 0, 200);
// Приглашённым считается только НОВЫЙ аккаунт: иначе любой старый аккаунт можно
// задним числом «пригласить». 30 дней, а не сутки: гость может неделями ходить
// анонимно и войти позже — привязка входа сохраняет дату создания аккаунта.
const REFERRAL_MAX_INVITEE_AGE_MS = 30 * 24 * 3600 * 1000;

// ── Баллы САН (per-venue ledger, System 1) ──────────────────────────────────
// 1 балл = 1 сом при погашении. Гардрейлы (даже при self-serve конфиге хоста):
const DEFAULT_EARN_COOLDOWN_MIN = 60;   // не чаще 1 начисления баллов на гостя/заведение
// Штампы: не чаще одного на гостя/заведение за это окно. Дефолт 15 мин;
// значение правит администратор в панели («Настройки» →
// config/appSettings.stampCooldownMinutes, 0 — без паузы), см. `stampCooldownMinutes`.
// Env-переключатель STAMP_COOLDOWN_MIN убран намеренно: два источника правды
// для одной константы — это «забытый тестовый ноль в проде».
const DEFAULT_STAMP_COOLDOWN_MIN = 15;
const MAX_STAMP_COOLDOWN_MIN = 1440;
const DEFAULT_EXPIRY_MONTHS = 6;        // баллы сгорают после N мес. без активности
const MAX_CASHBACK_PERCENT = 20;        // потолок кэшбэка (защита от опечатки «50%»)
const MAX_POINTS_PER_EARN = 10000;      // потолок за одно начисление

/* ── Несколько карт штампов у заведения ────────────────────────────────────
 * Первая карта — скалярные поля заведения (`loyaltyGoal`/`loyaltyReward`,
 * id "default"), её штампы — в прежнем `loyaltyCards/{user}_{venue}`.
 * Остальные — массив `stampCards`, их штампы — в ОТДЕЛЬНОЙ коллекции
 * `extraLoyaltyCards/{user}_{venue}_{card}`. Отдельной — потому что Android и
 * уже выпущенные сборки iOS читают `loyaltyCards where userID == uid` и
 * склеивают карты по заведению: документ второй карты в той же коллекции
 * затёр бы у них первую.
 * Скан без `cardID` ставит штамп на первую карту: так работают клиенты, не
 * знающие о картах. Правила — зеркало `StampCards.swift`, общие случаи —
 * `specs/fixtures/stamp-cards-fixtures.json` (гоняют обе стороны).
 * ─────────────────────────────────────────────────────────────────────────── */
export const DEFAULT_STAMP_CARD_ID = "default";
export const EXTRA_LOYALTY_CARDS = "extraLoyaltyCards";
const STAMP_CARD_ID_RE = /^[A-Za-z0-9-]{1,32}$/;
const STAMP_CARDS_MAX = 5;             // всего карт, считая первую
const STAMP_CARD_TITLE_MAX = 30;
const STAMP_CARD_REWARD_MAX = 60;
const DEFAULT_STAMP_REWARD = "Награда за лояльность";
/** Обрезка по кодовым точкам (как `StampCards.clip` — по скалярам Unicode):
 *  `.slice` режет по UTF-16 и может разрезать эмодзи пополам. */
const clipCP = (s: string, n: number) => Array.from(s).slice(0, n).join("");

export interface ResolvedStampCard { id: string; title: string; goal: number; reward: string; }

/**
 * Карты, которые сейчас принимают штампы; первая — впереди.
 *
 * Цель: ноль, мусор и отрицательное — «не задано» → 6 (`|| 6` намеренно, в
 * отличие от earnCooldownMinutes: карта на 0 штампов смысла не имеет).
 * У первой карты верхнего предела нет — его не было и до нескольких карт,
 * а Android пишет цель свободным числом; у дополнительных — 2…12.
 */
export function activeStampCards(venue: VenueDoc): ResolvedStampCard[] {
  if (venue.loyaltyEnabled !== true) return [];
  const goalOf = (g: Numeric, cap: number) => {
    const n = parseInt(String(g), 10);
    return n > 0 ? Math.min(Math.max(n, 2), cap) : 6;
  };
  const first: ResolvedStampCard = {
    id: DEFAULT_STAMP_CARD_ID,
    title: clipCP(String(venue.loyaltyTitle || "").trim(), STAMP_CARD_TITLE_MAX),
    goal: goalOf(venue.loyaltyGoal, Number.MAX_SAFE_INTEGER),
    reward: String(venue.loyaltyReward || "").trim() || DEFAULT_STAMP_REWARD,
  };
  // Отбор — как `StampCards.sanitizedExtras`: недопустимый id, пустая награда,
  // чужой "default" и дубль id отбрасываются; выключенная карта занимает свой
  // id и место в пределе, но штампы не принимает.
  const seen = new Set<string>([DEFAULT_STAMP_CARD_ID]);
  const extras: ResolvedStampCard[] = [];
  let kept = 0;
  for (const c of Array.isArray(venue.stampCards) ? venue.stampCards : []) {
    if (kept >= STAMP_CARDS_MAX - 1) break;
    const id = String((c && c.id) || "");
    const reward = clipCP(String((c && c.reward) || "").trim(), STAMP_CARD_REWARD_MAX);
    if (!STAMP_CARD_ID_RE.test(id) || seen.has(id) || !reward) continue;
    seen.add(id);
    kept += 1;
    if (c.active === false) continue;
    extras.push({
      id, reward, goal: goalOf(c.goal, 12),
      title: clipCP(String(c.title || "").trim(), STAMP_CARD_TITLE_MAX),
    });
  }
  return [first, ...extras];
}

/** id документа штампов. Первая карта — прежний документ без суффикса. */
export function stampCardDocID(userID: string, venueID: string, cardID: string): string {
  return !cardID || cardID === DEFAULT_STAMP_CARD_ID
    ? `${userID}_${venueID}` : `${userID}_${venueID}_${cardID}`;
}

/** Коллекция документа штампов: первая карта — `loyaltyCards`, остальные — отдельно. */
export function stampCardCollection(cardID: string): string {
  return !cardID || cardID === DEFAULT_STAMP_CARD_ID ? "loyaltyCards" : EXTRA_LOYALTY_CARDS;
}

/**
 * Разбор числового поля конфига заведения **с сохранением явного нуля**.
 *
 * `parseInt(x) || fallback` для таких полей не годится: 0 — falsy, и осознанно
 * выставленный ноль («кулдаун выключен») молча превращался бы в дефолт. Отсутствие
 * поля и мусор в нём по-прежнему дают fallback. Ср. `capFromEnv` выше — та же идея.
 *
 * Применяем там, где 0 — ОСМЫСЛЕННОЕ значение. Для `loyaltyGoal` (минимум 2 визита)
 * и `pointsExpiryMonths` (минимум 1 мес.) ноль смысла не имеет — там `|| default`
 * оставлен намеренно, иначе ноль в конфиге упирался бы в нижний клэмп (цель в
 * 2 штампа / сгорание через месяц) вместо документированного дефолта.
 */
function intOrDefault(raw: Numeric, fallback: number): number {
  const n = parseInt(String(raw), 10);
  return Number.isFinite(n) ? n : fallback;
}

// ── Глобальные настройки (config/appSettings) ───────────────────────────────
// Читаются на горячем пути скана, поэтому кэшируются на минуту на инстанс:
// правка в панели доезжает не мгновенно, зато нет лишнего чтения на каждый скан.
const APP_SETTINGS_TTL_MS = 60 * 1000;
let appSettingsCache: { at: number; data: AppSettingsDoc } | null = null;

async function loadAppSettings(): Promise<AppSettingsDoc> {
  const now = Date.now();
  if (appSettingsCache && now - appSettingsCache.at < APP_SETTINGS_TTL_MS) return appSettingsCache.data;
  let data: AppSettingsDoc = {};
  try {
    const snap = await db.collection("config").doc("appSettings").get();
    if (snap.exists) data = (snap.data() || {}) as AppSettingsDoc;
  } catch (e) {
    // Нет документа/прав — работаем на дефолтах: скан не должен падать из-за настроек.
    console.warn("appSettings read failed, using defaults", e);
  }
  appSettingsCache = { at: now, data };
  return data;
}

/** Пауза между штампами из настроек: явный 0 сохраняется (см. `intOrDefault`), клэмп 0…1440. */
function stampCooldownMinutes(settings: AppSettingsDoc): number {
  return Math.min(Math.max(intOrDefault(settings.stampCooldownMinutes, DEFAULT_STAMP_COOLDOWN_MIN), 0),
    MAX_STAMP_COOLDOWN_MIN);
}

// Метрики телеметрии, которые клиент может логировать (redemptions — только через
// countRedemption, клиенту недоступна). Всё, что вне списка, отбрасывается.
const ANALYTICS_METRICS = ["views", "saves", "calls", "maps", "dealTaps"];

function dayKey(d: Date = new Date()): string {
  return d.toISOString().slice(0, 10); // yyyy-MM-dd (UTC) — как в приложении
}

// Ayant — приложение для Бишкека (UTC+6, без перехода на летнее время). Клиент
// логирует местный час/день недели; сервер повторяет то же для однородности лога.
const BISHKEK_OFFSET_MS = 6 * 3600 * 1000;
function localHourWeekday(now: Date = new Date()): { hour: number; weekday: number } {
  const t = new Date(now.getTime() + BISHKEK_OFFSET_MS);
  return { hour: t.getUTCHours(), weekday: (t.getUTCDay() + 6) % 7 }; // 0 = понедельник
}

/**
 * Пишет серверную (авторитетную) метку погашения в журнал ранжирования
 * (learning-to-rank). Кросс-платформенно: срабатывает на реальном скане купона
 * заведением, независимо от платформы гостя — закрывает пробел, что клиентский
 * redeem логировался только на iOS. Схема совпадает с клиентской (`RankingEvent`):
 * sessionID/renderID/platform = "server", т.к. серверу неизвестен клиентский рендер.
 * Fire-and-forget: не должно ломать ответ на скан.
 */
async function logServerRedeem(p: {
  userID: string; dealID?: string; venueID: string; citySlug?: string;
}): Promise<void> {
  const { hour, weekday } = localHourWeekday();
  const doc: Record<string, unknown> = {
    type: "redeem", userID: p.userID, sessionID: "server", renderID: "server",
    platform: "server", citySlug: p.citySlug || "", hour, weekday,
    clientTs: Date.now(), createdAt: new Date(), venueID: p.venueID,
  };
  if (p.dealID) doc.dealID = p.dealID;
  await db.collection("rankingEvents").add(doc);
}

/**
 * Проверяет Firebase ID-токен из заголовка `Authorization: Bearer <token>`.
 * Возвращает uid при успехе, иначе null. Общий помощник для HTTP-функций.
 */
async function verifyBearer(req: { get: (h: string) => string | undefined }): Promise<string | null> {
  const authz = String(req.get("Authorization") || "");
  const idToken = authz.startsWith("Bearer ") ? authz.slice(7) : "";
  if (!idToken) return null;
  try { return (await getAuth().verifyIdToken(idToken)).uid; }
  catch { return null; }
}

/**
 * App Check для onRequest-функций. Автоматический enforcement Firebase покрывает
 * только callable/Firestore, но НЕ onRequest — здесь разбираем заголовок
 * `X-Firebase-AppCheck` вручную. Режим задаётся env APPCHECK_MODE:
 *   off (по умолчанию) — не проверяем (нулевой оверхед, поведение как раньше);
 *   monitor            — проверяем и логируем провалы, но ПРОПУСКАЕМ (сбор сигнала);
 *   enforce            — блокируем (вызывающий получит 401 app_check_failed).
 * Возвращает true, если запрос можно продолжать. Порядок раскатки: off→monitor→enforce
 * (одним env-флагом, без передеплоя кода). SDK грузим лениво — тесты его не трогают.
 */
async function checkAppCheck(req: { get: (h: string) => string | undefined }, label: string): Promise<boolean> {
  const mode = process.env.APPCHECK_MODE || "off";
  if (mode === "off") return true;
  const token = req.get("X-Firebase-AppCheck");
  let ok = false;
  if (token) {
    try {
      const { getAppCheck } = require("firebase-admin/app-check");
      await getAppCheck().verifyToken(token);
      ok = true;
    } catch { ok = false; }
  }
  if (!ok) {
    console.warn(`⚠️ app-check ${token ? "invalid" : "missing"} on ${label} (mode=${mode})`);
    if (mode === "enforce") return false;
  }
  return true;
}

/** Время Firestore → миллисекунды (0, если ещё не сериализовано). */
function toMillis(v: unknown): number {
  return v && typeof (v as { toMillis?: () => number }).toMillis === "function"
    ? (v as { toMillis: () => number }).toMillis()
    : 0;
}

/**
 * Дневной счётчик заведения (`analytics/{venueID}/days/{day}`): несколько
 * метрик одной записью. Не роняет ответ на скан, но и не молчит при ошибке.
 * Здесь считаются ВСЕ серверные события лояльности — штампы, награды, баллы —
 * иначе хост видел бы только купоны, а стамп-карта и баллы оставались невидимыми.
 */
function bumpAnalytics(venueID: string, inc: Record<string, number>): Promise<void> {
  const day = dayKey();
  const data: Record<string, unknown> = { date: day };
  for (const [k, v] of Object.entries(inc)) if (v > 0) data[k] = FieldValue.increment(v);
  if (Object.keys(data).length === 1) return Promise.resolve();
  return db.collection("analytics").doc(venueID).collection("days").doc(day)
    .set(data, { merge: true })
    .then(() => undefined)
    .catch((e) => console.warn(`⚠️ analytics increment failed: venue=${venueID}`, e));
}

/** Код купона-награды за заполненную карту — тот же формат, что у купонов акций. */
function newCouponCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let s = "";
  for (const b of crypto.randomBytes(6)) s += alphabet[b % alphabet.length];
  return `AYANT-${s}`;
}

// Рассылка идёт только после одобрения админом (status: "approved") и один раз
// (флаг delivered). Хост создаёт кампанию как "pending" → админ одобряет в панели.
//
// Рассылка по всем токенам города — долгая: таймаут 540 с и 512 МБ. Перед
// отправкой кампания атомарно переводится в "sending": повторная доставка
// события (триггеры — «хотя бы один раз») или ретрай после падения
// посередине больше не разошлют её второй раз. Застрявшую в "sending"
// кампанию админ видит в панели и решает сам.
export const sendPushCampaign = onDocumentWritten(
  { document: "pushCampaigns/{id}", timeoutSeconds: 540, memory: "512MiB" },
  async (event) => {
  const snap = event.data && event.data.after;
  if (!snap || !snap.exists) return;

  const pre = (snap.data() || {}) as PushCampaignDoc;
  if (pre.status !== "approved" || pre.delivered) return;

  // Захват кампании: только один запуск переводит approved → sending.
  let claimed = false;
  let c: PushCampaignDoc = pre;
  await db.runTransaction(async (tx) => {
    const cur = await tx.get(snap.ref);
    const d = (cur.data() || {}) as PushCampaignDoc;
    if (!cur.exists || d.status !== "approved" || d.delivered) return;
    tx.set(snap.ref, { status: "sending", sendingAt: new Date() }, { merge: true });
    c = d;
    claimed = true;
  });
  if (!claimed) return;

  const now = Date.now();
  const city = c.city || "";
  const headline = clipPush(c.headline || "САН", PUSH_TITLE_MAX);
  const bodyText = clipPush(c.body || "", PUSH_BODY_MAX);

  // Токены целевого города (или все, если город не указан).
  let q: FirebaseFirestore.Query = db.collection("userTokens");
  if (city) q = q.where("city", "==", city);
  const tokensSnap = await q.get();

  // Отбираем токены, не превысившие лимит, и готовим обновления истории.
  // История читается пачками getAll (≤500) — раньше по одному чтению на токен
  // последовательно, и на 10k токенов функция не укладывалась в таймаут.
  const eligible: string[] = [];
  const logUpdates: { ref: DocumentReference; sends: number[] }[] = [];
  const tokenIDs = tokensSnap.docs.map((d) => d.id).filter((t) => t.length > 0);
  for (let i = 0; i < tokenIDs.length; i += 500) {
    const chunk = tokenIDs.slice(i, i + 500);
    const refs = chunk.map((t) => db.collection("pushLog").doc(t));
    const logs = await db.getAll(...refs);
    logs.forEach((logSnap, idx) => {
      const raw = logSnap.exists ? (logSnap.data() || {}).sends : null;
      let sends: number[] = Array.isArray(raw) ? raw : [];
      sends = sends.filter((t) => now - t < 7 * DAY_MS); // только за последнюю неделю
      const dayCount = sends.filter((t) => now - t < DAY_MS).length;
      if (dayCount < DAILY_CAP && sends.length < WEEKLY_CAP) {
        eligible.push(chunk[idx]);
        logUpdates.push({ ref: refs[idx], sends: sends.concat(now) });
      }
    });
  }

  if (eligible.length === 0) {
    // Фолбэк: рассылка по топику ВСЕХ пользователей. Каждое устройство
    // подписывается на all_users при запуске (без авторизации и без привязки
    // к городу) — поэтому буст доходит до всех, даже без userTokens.
    const topic = "all_users";
    try {
      await getMessaging().send({
        topic,
        notification: { title: headline, body: bodyText },
        data: {
          type: c.dealID ? "deal" : "ad",
          venueID: String(c.venueID || ""),
          dealID: String(c.dealID || ""),
          campaignId: event.params.id,
        },
        apns: { payload: { aps: { sound: "default", badge: 1 } } },
        android: { notification: { sound: "default" }, priority: "high" },
      });
      await snap.ref.update({
        status: "sent", recipients: 0, delivery: "topic",
        delivered: true, sentAt: new Date(), note: `sent to topic ${topic}`,
      });
    } catch (e) {
      await snap.ref.update({ status: "error", delivered: true, note: String(e) });
    }
    return;
  }

  const base = {
    notification: { title: headline, body: bodyText },
    data: {
      type: c.dealID ? "deal" : "ad",
      venueID: String(c.venueID || ""),
      dealID: String(c.dealID || ""),
      campaignId: event.params.id,
    },
    apns: { payload: { aps: { sound: "default", badge: 1 } } },
    android: { notification: { sound: "default" }, priority: "high" as const },
  };

  // Рассылка чанками по 500 (лимит multicast).
  let success = 0;
  const stale: DocumentReference[] = [];
  for (let i = 0; i < eligible.length; i += 500) {
    const chunk = eligible.slice(i, i + 500);
    const res = await getMessaging().sendEachForMulticast({ ...base, tokens: chunk });
    success += res.successCount;
    res.responses.forEach((r, idx) => {
      if (!r.success && r.error &&
          r.error.code === "messaging/registration-token-not-registered") {
        stale.push(db.collection("userTokens").doc(chunk[idx]));
      }
    });
  }
  // Протухшие токены — дожидаемся удаления (раньше fire-and-forget обрывался
  // вместе с функцией, и мёртвые токены копились).
  await deleteInChunks(stale).catch((e) => console.warn("stale token cleanup failed", e));

  // Сохраняем историю отправок (чанками по 450 — лимит batch).
  for (let i = 0; i < logUpdates.length; i += 450) {
    const batch = db.batch();
    logUpdates.slice(i, i + 450).forEach((u) => batch.set(u.ref, { sends: u.sends }, { merge: true }));
    await batch.commit();
  }

  await snap.ref.update({ status: "sent", recipients: success, delivered: true, sentAt: new Date() });
  console.log(`✅ push sent to ${success}/${eligible.length} eligible tokens (city=${city || "all"})`);
});

/* ───────────────────────────────────────────────────────────────────────────
 * 2) Новое предложение → push подписчикам заведения (topic venue_<id>).
 *    Приложение подписывает устройство на topic при сохранении заведения.
 * ─────────────────────────────────────────────────────────────────────────── */
/** Не больше одного пуша «новая акция» на заведение за это окно. */
export const NEW_DEAL_PUSH_WINDOW_MS = DAY_MS;
/** Пушей владельцу о новых отзывах на одно заведение в сутки. */
export const REVIEW_PUSH_DAILY_CAP = 10;
const PUSH_TITLE_MAX = 60;
const PUSH_BODY_MAX = 140;

/** Обрезка текста пуша по кодовым точкам (эмодзи не режется пополам). */
function clipPush(s: unknown, n: number): string {
  const cps = Array.from(String(s || "").replace(/\s+/g, " ").trim());
  return cps.length > n ? cps.slice(0, n - 1).join("") + "…" : cps.join("");
}

/**
 * Атомарно «занимает» окно пуша по ключу в `pushThrottle/{id}` (только сервер).
 * Возвращает false, если окно ещё не прошло: тогда пуш не шлём. Раньше
 * каждая созданная акция (а создать её мог любой вошедший — правила не
 * проверяли владение заведением) уходила пушем всем подписчикам заведения.
 */
async function claimPushSlot(id: string, windowMs: number, nowMs: number, maxPerWindow = 1): Promise<boolean> {
  const ref = db.collection("pushThrottle").doc(id);
  let ok = false;
  await db.runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data() || {};
    const since = toMillis(cur.windowStart);
    const inWindow = since > 0 && nowMs - since < windowMs;
    const count = inWindow ? intOf(cur.count) : 0;
    if (count >= maxPerWindow) { ok = false; return; }
    tx.set(ref, {
      windowStart: inWindow ? cur.windowStart : new Date(nowMs),
      count: count + 1, lastPushAt: new Date(nowMs),
    }, { merge: true });
    ok = true;
  });
  return ok;
}

export const notifyOnNewDeal = onDocumentCreated("deals/{id}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const deal = snap.data() || {};
  if ((deal.status || "active") !== "active") return;       // только активные
  const venueID = String(deal.venueID || "");
  if (!venueID) return;

  // Пуш уходит только по настоящей акции настоящего заведения: заведение есть,
  // одобрено (нет поля = одобрено, старые записи сида), и акцию создал его
  // владелец. Правила теперь требуют того же, а здесь — на случай записи в
  // обход (админ-скрипт, старые правила).
  const vdoc = await db.collection("venues").doc(venueID).get();
  if (!vdoc.exists) return;
  const venue = (vdoc.data() || {}) as VenueDoc;
  const venueOwner = String(venue.ownerID || "");
  if (!venueOwner || String(deal.ownerID || "") !== venueOwner) {
    console.log(`🔕 new-deal push skipped: owner mismatch deal=${event.params.id}`);
    return;
  }
  if (String(venue.status || "approved") !== "approved") return;
  if (venue.isPaused === true) return;

  // Не больше одного пуша на заведение в сутки: иначе пачка акций подряд —
  // это пачка пушей всем подписчикам.
  if (!(await claimPushSlot(`deal_${venueID}`, NEW_DEAL_PUSH_WINDOW_MS, Date.now()))) {
    console.log(`🔕 new-deal push throttled: venue=${venueID}`);
    return;
  }

  const venueName = String(venue.name || "заведение");
  const typeLabel =
    ({ discount: "Скидка", promo: "Акция", novelty: "Новинка", announcement: "Объявление" } as Record<string, string>)[deal.type] ||
    "Новинка";

  await getMessaging().send({
    topic: `venue_${venueID}`,
    notification: {
      title: clipPush(`${typeLabel} · ${venueName}`, PUSH_TITLE_MAX),
      body: clipPush(deal.title || "Новое предложение", PUSH_BODY_MAX),
    },
    data: { type: "deal", dealID: event.params.id, venueID },
    apns: { payload: { aps: { sound: "default", badge: 1 } } },
    android: { notification: { sound: "default" }, priority: "high" },
  });
  console.log(`🔔 new-deal push → venue_${venueID} (${venueName})`);
});

/* ───────────────────────────────────────────────────────────────────────────
 * 2b) Новый отзыв → push владельцу заведения.
 *     Адресно по FCM-токенам владельца (`userTokens` с uid == ownerID), без
 *     частотного лимита: это не реклама, а событие по его же заведению. Свой
 *     отзыв на своё заведение не уведомляем.
 * ─────────────────────────────────────────────────────────────────────────── */
export const notifyHostOnReview = onDocumentCreated("reviews/{id}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const review = snap.data() || {};
  const venueID = String(review.venueID || "");
  if (!venueID) return;

  const vdoc = await db.collection("venues").doc(venueID).get();
  if (!vdoc.exists) return;
  const venue = vdoc.data() || {};
  const ownerID = String(venue.ownerID || "");
  if (!ownerID || ownerID === String(review.authorID || "")) return;

  // Не больше REVIEW_PUSH_DAILY_CAP пушей о новых отзывах на заведение в сутки:
  // волна отзывов (или накрутка) не должна превращаться в волну уведомлений.
  if (!(await claimPushSlot(`review_${venueID}`, DAY_MS, Date.now(), REVIEW_PUSH_DAILY_CAP))) {
    console.log(`🔕 review push throttled: venue=${venueID}`);
    return;
  }

  const tokensSnap = await db.collection("userTokens").where("uid", "==", ownerID).get();
  const tokens = tokensSnap.docs.map((d) => d.id).filter((t) => t.length > 0);
  if (tokens.length === 0) { console.log(`🔕 review push: no tokens for owner ${ownerID}`); return; }

  const rating = Math.max(0, Math.min(5, parseInt(String(review.rating), 10) || 0));
  const stars = rating > 0 ? "★".repeat(rating) + "☆".repeat(5 - rating) + " " : "";
  const author = String(review.authorName || "Гость");
  const text = String(review.text || "").trim();
  const body = `${stars}${author}${text ? ": " + (text.length > 120 ? text.slice(0, 117) + "…" : text) : ""}`;

  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: clipPush(`Новый отзыв · ${String(venue.name || "заведение")}`, PUSH_TITLE_MAX), body: clipPush(body, PUSH_BODY_MAX) },
    data: { type: "review", reviewID: event.params.id, venueID },
    apns: { payload: { aps: { sound: "default", badge: 1 } } },
    android: { notification: { sound: "default" }, priority: "high" },
  });
  console.log(`🔔 review push → owner ${ownerID}: ${res.successCount}/${tokens.length} delivered`);
});

/* ───────────────────────────────────────────────────────────────────────────
 * 2c) Владелец ответил на отзыв → push автору отзыва.
 *     Срабатывает один раз — когда `hostReply` появился (или текст сменился).
 * ─────────────────────────────────────────────────────────────────────────── */
export const notifyGuestOnHostReply = onDocumentWritten("reviews/{id}", async (event) => {
  const before = event.data?.before?.data() || null;
  const after = event.data?.after?.data() || null;
  if (!after) return;
  const replyAfter = String((after.hostReply || {}).text || "").trim();
  const replyBefore = String(((before || {}).hostReply || {}).text || "").trim();
  if (!replyAfter || replyAfter === replyBefore) return;

  const authorID = String(after.authorID || "");
  const venueID = String(after.venueID || "");
  if (!authorID || !venueID) return;

  const tokensSnap = await db.collection("userTokens").where("uid", "==", authorID).get();
  const tokens = tokensSnap.docs.map((d) => d.id).filter((t) => t.length > 0);
  if (tokens.length === 0) return;

  let venueName = "Заведение";
  try {
    const v = await db.collection("venues").doc(venueID).get();
    if (v.exists && v.data()!.name) venueName = String(v.data()!.name);
  } catch (_) {}

  const body = replyAfter.length > 120 ? replyAfter.slice(0, 117) + "…" : replyAfter;
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: `${venueName} ответили на ваш отзыв`, body },
    data: { type: "hostReply", reviewID: event.params.id, venueID },
    apns: { payload: { aps: { sound: "default", badge: 1 } } },
    android: { notification: { sound: "default" }, priority: "high" },
  });
  console.log(`🔔 host-reply push → ${authorID}: ${res.successCount}/${tokens.length}`);
});

/* ───────────────────────────────────────────────────────────────────────────
 * 3) Погашение купона → серверный авторитетный счётчик (analytics) + анти-абуз.
 *    Приложение пишет redemptions/{userID}_{dealID} (детерминированный id ⇒
 *    повторное погашение не создаёт новый документ). Здесь увеличиваем счётчик.
 * ─────────────────────────────────────────────────────────────────────────── */
export const countRedemption = onDocumentCreated("redemptions/{id}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const r = snap.data() || {};
  const venueID = String(r.venueID || "");
  if (!venueID) return;
  // Те же условия, что в правилах: настоящая акция этого заведения. Правила
  // отсекают запись раньше, здесь — на случай документа, записанного в обход
  // (старые правила, админ-скрипт).
  const dealID = String(r.dealID || "");
  const deal = dealID ? await db.collection("deals").doc(dealID).get() : null;
  if (!deal || !deal.exists || String((deal.data() || {}).venueID || "") !== venueID) {
    await snap.ref.set({ status: "rejected", countedAt: new Date() }, { merge: true });
    return;
  }

  const day = dayKey();
  await db.collection("analytics").doc(venueID)
    .collection("days").doc(day)
    .set({ redemptions: FieldValue.increment(1), date: day }, { merge: true });

  await snap.ref.set({ status: "counted", countedAt: new Date() }, { merge: true });
  console.log(`🎟️ redemption counted: venue=${venueID} deal=${r.dealID}`);
});

/* ───────────────────────────────────────────────────────────────────────────
 * 3b) Телеметрия заведений → серверный авторитетный счётчик (analytics).
 *     Клиент пишет analyticsEvents/{id} = { venueID, metric }; правила запрещают
 *     ему писать в analytics/* напрямую. Здесь инкрементируем нужную метрику и
 *     удаляем событие-триггер (документы не копятся). Метрика вне белого списка
 *     (в т.ч. "redemptions") игнорируется — счётчики нельзя подделать.
 * ─────────────────────────────────────────────────────────────────────────── */
//
// Дневной документ заведения — горячая точка (лимит ~1 запись/с на документ):
// популярное заведение с рекламой ловит десятки событий в секунду. Пока
// шардирования нет (его читают iOS, Android и админ-панель — см. claude-notes),
// инкремент повторяется с экспоненциальной паузой, а событие удаляется в
// finally — даже при провале счётчика документы не копятся.
export const countAnalyticsEvent = onDocumentCreated("analyticsEvents/{id}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  try {
    const e = snap.data() || {};
    const venueID = String(e.venueID || "");
    const metric = String(e.metric || "");
    if (venueID && venueID.length <= 128 && !venueID.includes("/") && ANALYTICS_METRICS.includes(metric)) {
      const day = dayKey();
      const ref = db.collection("analytics").doc(venueID).collection("days").doc(day);
      await withRetry(() => ref.set({ [metric]: FieldValue.increment(1), date: day }, { merge: true }),
        ANALYTICS_RETRIES);
    }
  } catch (err) {
    console.warn(`⚠️ analytics event dropped: ${event.params.id}`, err);
  } finally {
    await snap.ref.delete().catch(() => {}); // событие обработано — чистим
  }
});

const ANALYTICS_RETRIES = 4;

/** Повтор с экспоненциальной паузой (50, 100, 200 мс…) для конфликтов записи. */
export async function withRetry<T>(fn: () => Promise<T>, attempts: number, baseMs = 50): Promise<T> {
  let last: unknown;
  for (let i = 0; i < attempts; i++) {
    try { return await fn(); }
    catch (e) {
      last = e;
      if (i < attempts - 1) await new Promise((r) => setTimeout(r, baseMs * 2 ** i + Math.random() * baseMs));
    }
  }
  throw last;
}

/* ───────────────────────────────────────────────────────────────────────────
 * 3в) Отзыв → денормализованный агрегат рейтинга на документе заведения.
 *
 *     ЗАЧЕМ. Раньше клиент на КАЖДОМ холодном старте выгружал всю коллекцию
 *     `reviews` целиком и считал рейтинги на устройстве. На 41 заведении это
 *     нормально; на каталоге в 1000 бизнесов это ~150 000 чтений за один запуск
 *     приложения и главная статья расходов Firestore (см. docs/design/system-design.md §2, B2).
 *     Теперь рейтинг считает сервер и кладёт его прямо в `venues/{id}` —
 *     лента читает готовое число, а сами отзывы грузятся только на карточке
 *     заведения и постранично.
 *
 *     ПОЧЕМУ ПОЛНЫЙ ПЕРЕСЧЁТ, А НЕ ИНКРЕМЕНТ. Инкремент (+1 к счётчику, +оценка
 *     к сумме) дешевле, но накапливает расхождение при любом пропущенном или
 *     повторно доставленном событии, а триггеры Firestore доставляются
 *     «хотя бы один раз». Пересчёт запросом идемпотентен: сколько раз ни
 *     выполни — результат один и тот же, и его же можно запустить для бэкфилла.
 *     Цена — один запрос по индексу (venueID) на запись отзыва; отзывы пишутся
 *     редко (сотни в день), так что это доли цента.
 *
 *     ВАЖНО: seed-значения (`rating`/`reviewCount` из скрипта наполнения)
 *     перезаписываются только когда у заведения появился хотя бы один реальный
 *     отзыв. Пока их нет — на документе остаётся seed, и клиентский фолбэк
 *     показывает именно его (как и до этой правки).
 * ─────────────────────────────────────────────────────────────────────────── */

/**
 * Пересчёт агрегатами Firestore (`count()` по каждой звезде) вместо чтения
 * всех отзывов: раньше каждая запись отзыва читала до 3000 документов, а
 * агрегат стоит одно чтение на 1000 записей индекса. Свойства те же —
 * идемпотентно, мусорная оценка (вне 1…5) не учитывается, — но без потолка
 * «3000 отзывов». Оценки целые (правила требуют int 1…5), поэтому сумма —
 * Σ звезда × количество. Запрос равенства по двум полям обслуживается
 * слиянием одиночных индексов, составной индекс не нужен.
 */
export async function recomputeVenueRating(venueID: string): Promise<void> {
  if (!venueID) return;

  // Гистограмма 1★…5★ — её читает карточка заведения, чтобы не тянуть отзывы
  // ради одной полоски. Ключи 1…5 присутствуют всегда, включая нули.
  const histogram: Record<string, number> = { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0 };
  const counts = await Promise.all([1, 2, 3, 4, 5].map(async (star) => {
    const agg = await db.collection("reviews")
      .where("venueID", "==", venueID).where("rating", "==", star)
      .count().get();
    return Number(agg.data().count) || 0;
  }));
  let sum = 0;
  let count = 0;
  counts.forEach((n, i) => {
    histogram[String(i + 1)] = n;
    sum += (i + 1) * n;
    count += n;
  });

  // Ни одного валидного отзыва — seed на документе не трогаем.
  if (count === 0) return;

  await db.collection("venues").doc(venueID).set({
    rating: sum / count,
    reviewCount: count,
    ratingHistogram: histogram,
    ratingUpdatedAt: new Date(),
  }, { merge: true });
}

export const aggregateReviewRating = onDocumentWritten("reviews/{id}", async (event) => {
  const before = event.data?.before?.data() || null;
  const after = event.data?.after?.data() || null;

  // Отзыв мог переехать между заведениями (правка venueID) — пересчитываем оба.
  const affected = new Set<string>();
  if (before?.venueID) affected.add(String(before.venueID));
  if (after?.venueID) affected.add(String(after.venueID));

  // Ответ владельца (hostReply) рейтинг не меняет — не тратим на него запрос.
  if (before && after &&
      String(before.venueID) === String(after.venueID) &&
      Number(before.rating) === Number(after.rating)) {
    return;
  }

  for (const venueID of affected) {
    await recomputeVenueRating(venueID).catch((e) =>
      console.error(`review aggregate failed venue=${venueID}: ${e}`));
  }
});

/* ───────────────────────────────────────────────────────────────────────────
 * 4) Реферал → награда пригласившему. Приложение пишет referrals/{inviteeID}
 *    = { referrerID }. Здесь начисляем бонус пригласившему через bonusGrants,
 *    которые приложение «забирает» при следующем запуске.
 *    (Приглашённый получает приветственный бонус на своём устройстве сразу.)
 * ─────────────────────────────────────────────────────────────────────────── */
/**
 * Настоящий ли это человек для рефералки: аккаунт есть и вход не анонимный.
 * Анонимный вход доступен любому скрипту (ключ веб-API публичный) — по той же
 * причине кошелёк отклоняет анонимные токены (`walletUser`).
 */
async function referralAccount(uid: string): Promise<{ createdMs: number; emailUnverified: boolean } | null> {
  try {
    const user = await getAuth().getUser(uid);
    const providers = (user.providerData || []);
    if (providers.length === 0) return null;                   // анонимный
    const created = Date.parse(String(user.metadata && user.metadata.creationTime));
    const createdMs = Number.isFinite(created) ? created : 0;
    // Только почта+пароль и почта не подтверждена (Apple/Google подтверждены
    // провайдером) — и аккаунт новее BONUS_VERIFY_CUTOFF.
    const passwordOnly = providers.every((p: any) => String(p && p.providerId) === "password");
    const emailUnverified = passwordOnly && user.emailVerified !== true && createdMs >= BONUS_VERIFY_CUTOFF_MS;
    return { createdMs, emailUnverified };
  } catch { return null; }                                     // аккаунта нет
}

export const rewardReferral = onDocumentCreated("referrals/{inviteeID}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  await processReferral(snap.ref, event.params.inviteeID, snap.data() || {});
});

/**
 * Награда за реферал. Зовётся триггером на создание `referrals/{invitee}` и —
 * для приглашённого с неподтверждённой почтой — ещё раз из bonusWalletSync,
 * когда он подтвердил почту (`pendingVerification`): реферал создаётся сразу
 * при регистрации, раньше подтверждения, и отклонять его навсегда нельзя.
 */
async function processReferral(ref: DocumentReference, inviteeID: string, data: Record<string, any>): Promise<void> {
  const snap = { ref };
  const referrerID = String(data.referrerID || "");
  if (!referrerID || referrerID === inviteeID) return;
  if (data.rewarded) return;                                 // идемпотентность

  // Анти-фарм (аудит 2026-10-01): раньше награду приносил любой аккаунт, в том
  // числе анонимный, созданный скриптом за один вызов, — 100 бонусов
  // пригласившему и 100 «приглашённому» за каждую запись referrals.
  const invitee = await referralAccount(inviteeID);
  const referrer = await referralAccount(referrerID);
  const reject = !invitee ? "invitee_anonymous"
    : !referrer ? "referrer_invalid"
    : Date.now() - invitee.createdMs > REFERRAL_MAX_INVITEE_AGE_MS ? "invitee_not_new"
    : "";
  if (reject) {
    await snap.ref.set({ rewarded: true, rewardedAt: new Date(), rejected: reject }, { merge: true });
    console.log(`🚫 referral ${inviteeID} → ${referrerID} rejected: ${reject}`);
    return;
  }
  // Почта не подтверждена (аккаунт с почтой и паролем после
  // BONUS_VERIFY_CUTOFF): регистрации без подтверждения — дешёвая ферма
  // рефералов. Не отклоняем, а откладываем: bonusWalletSync приглашённого
  // доведёт реферал, когда почта подтверждена.
  if (invitee!.emailUnverified) {
    await snap.ref.set({ pendingVerification: true }, { merge: true });
    console.log(`⏳ referral ${inviteeID} → ${referrerID} waits for email verification`);
    return;
  }

  // Потолок — счётчиком в транзакции. Раньше он был запросом и `add` без
  // транзакции: сотня рефералов разом запускала сотню триггеров, каждый видел
  // «меньше 20», и потолок не держал. Счётчик впервые заводится из уже
  // выданных грантов — старые награды тоже считаются к лимиту.
  const counterRef = db.collection("referralCounts").doc(referrerID);
  const priorQuery = db.collection("bonusGrants").where("userID", "==", referrerID);
  let outcome = "done" as "granted" | "capped" | "done";
  await db.runTransaction(async (tx) => {
    const cur = await tx.get(snap.ref);
    if (!cur.exists || (cur.data() || {}).rewarded) { outcome = "done"; return; }
    const counter = await tx.get(counterRef);
    let count: number;
    if (counter.exists) {
      count = intOf((counter.data() || {}).rewarded);
    } else {
      const prior = await tx.get(priorQuery);
      count = prior.docs.filter((d: any) => (d.data() || {}).reason === "referral").length;
    }
    const now = new Date();
    if (count >= REFERRAL_MAX_REWARDS) {
      tx.set(counterRef, { rewarded: count, updatedAt: now }, { merge: true });
      tx.set(snap.ref, { rewarded: true, rewardedAt: now, capped: true }, { merge: true });
      outcome = "capped";
      return;
    }
    tx.set(counterRef, { rewarded: count + 1, updatedAt: now }, { merge: true });
    tx.set(db.collection("bonusGrants").doc(`referral_${inviteeID}`), {
      userID: referrerID,
      amount: REFERRAL_REWARD,
      reason: "referral",
      inviteeID,
      claimed: false,
      createdAt: now,
    });
    // Приветственный бонус приглашённому — тоже грантом: с серверным кошельком
    // клиент больше не начисляет его сам (это было бы число на телефоне).
    // Документ с фиксированным id — повторный запуск триггера его не удвоит.
    // Под потолком пригласившего не выдаётся: иначе фарм аккаунтами (Sybil)
    // приносил бы по 100 бонусов за каждый новый аккаунт.
    tx.set(db.collection("bonusGrants").doc(`welcome_${inviteeID}`), {
      userID: inviteeID,
      amount: REFERRAL_WELCOME,
      reason: "welcome",
      referrerID,
      claimed: false,
      createdAt: now,
    });
    tx.set(snap.ref, { rewarded: true, rewardedAt: now, pendingVerification: false }, { merge: true });
    outcome = "granted";
  });
  if (outcome === "capped") console.log(`🚫 referral cap (${REFERRAL_MAX_REWARDS}) reached for ${referrerID} — no grant`);
  if (outcome === "granted") console.log(`🎁 referral reward queued for ${referrerID} (invited ${inviteeID})`);
}

/* ───────────────────────────────────────────────────────────────────────────
 * 5) Карта лояльности → .pkpass для Apple Wallet.
 *    GET /generateLoyaltyPass?venue=<id>&name=<name>&stamps=<n>&goal=<n>
 *    Возвращает подписанный .pkpass (Content-Type application/vnd.apple.pkpass).
 *
 *    ТРЕБУЕТ настройки сертификатов Apple (см. WALLET_SETUP.md). Пока сертификаты
 *    не заданы (env WALLET_CONFIGURED != "1"), функция отвечает 503 — приложение
 *    показывает мягкое сообщение «Apple Wallet скоро», ничего не ломая.
 * ─────────────────────────────────────────────────────────────────────────── */
const {
  WALLET_CONFIGURED,      // "1" когда сертификаты загружены
  PASS_TYPE_ID,           // pass.com.yourcompany.san.loyalty
  PASS_TEAM_ID,           // R6W6JK63KU
  PASS_ORG_NAME,          // Ayant
} = process.env;

// Кладёт в pass все изображения из certs/images: иконку, лого и брендовый
// strip-градиент (фон под полями — даёт «фирменный» вид как в приложении).
// icon.png обязателен для валидности pass (на лице карты не виден).
function addIcons(pass: any, imgDir: string): void {
  for (const f of ["icon.png", "icon@2x.png", "icon@3x.png"]) {
    const p = path.join(imgDir, f);
    if (fs.existsSync(p)) pass.addBuffer(f, fs.readFileSync(p));
  }
}

let _fontsReady = false;
function ensureFonts(): void {
  if (_fontsReady) return;
  try {
    const { GlobalFonts } = require("@napi-rs/canvas");
    const dir = path.join(__dirname, "assets", "fonts");
    GlobalFonts.registerFromPath(path.join(dir, "LiberationSans-Bold.ttf"), "AyantB");
    GlobalFonts.registerFromPath(path.join(dir, "LiberationSans-Regular.ttf"), "AyantR");
  } catch (e) { /* system fonts fallback */ }
  _fontsReady = true;
}

interface StripOpts {
  title: string;
  subtitle?: string;
  rightPill?: string;
  rightCheck?: boolean;
  stampsGrid?: { stamps: number; goal: number };
}

// Рисует «шапку-билет» как в приложении (пилюли + заголовок + место + вырезы)
// и возвращает PNG-буферы strip для всех масштабов. Заголовок ужимается по ширине.
// rightPill — текст правой пилюли; rightCheck=true рисует галочку перед ним.
function buildHeaderStrip({ title, subtitle, rightPill, rightCheck, stampsGrid }: StripOpts): Record<string, Buffer> {
  const { createCanvas } = require("@napi-rs/canvas");
  ensureFonts();
  const W = 1125, H = 372, body = "#1C1C1E";
  const c = createCanvas(W, H), ctx = c.getContext("2d");
  const g = ctx.createLinearGradient(0, 0, W, H);
  g.addColorStop(0, "#FF4D29"); g.addColorStop(1, "#FFB300");
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);

  const rr = (x: number, y: number, w: number, h: number, r: number) => {
    ctx.beginPath(); ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  };
  const checkmark = (cx: number, cy: number, s: number) => {
    ctx.strokeStyle = "#fff"; ctx.lineWidth = s * 0.16;
    ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.beginPath();
    ctx.moveTo(cx - s * 0.42, cy + s * 0.02); ctx.lineTo(cx - s * 0.12, cy + s * 0.32);
    ctx.lineTo(cx + s * 0.45, cy - s * 0.34); ctx.stroke();
  };

  const pf = 32, ph = pf * 1.85, padX = pf * 0.65, py = 34;
  ctx.font = `${pf}px AyantB`; ctx.textBaseline = "middle"; ctx.textAlign = "left";
  const lt = "A Y A N T", ltw = ctx.measureText(lt).width;
  ctx.fillStyle = "rgba(255,255,255,0.24)"; rr(64, py, ltw + padX * 2, ph, ph / 2); ctx.fill();
  ctx.fillStyle = "#fff"; ctx.fillText(lt, 64 + padX, py + ph / 2 + 2);
  if (rightPill) {
    const cg = rightCheck ? pf * 1.3 : 0;               // место под галочку
    const rtw = ctx.measureText(rightPill).width, rw = rtw + padX * 2 + cg, rx = W - 64 - rw;
    ctx.fillStyle = "rgba(255,255,255,0.24)"; rr(rx, py, rw, ph, ph / 2); ctx.fill();
    if (rightCheck) checkmark(rx + padX + pf * 0.42, py + ph / 2, pf * 0.9);
    ctx.fillStyle = "#fff"; ctx.fillText(rightPill, rx + padX + cg, py + ph / 2 + 2);
  }

  ctx.textAlign = "center";
  let ts = 86; const maxW = W - 120;
  do { ctx.font = `${ts}px AyantB`; if (ctx.measureText(title).width <= maxW) break; ts -= 3; } while (ts > 36);
  ctx.fillStyle = "#fff";
  ctx.fillText(title, W / 2, subtitle ? 212 : 250);

  if (subtitle) {
    ctx.font = "42px AyantR";
    const sw = ctx.measureText(subtitle).width, s = 42, px = W / 2 - sw / 2 - 36, pyy = 300;
    ctx.fillStyle = "#fff";
    ctx.beginPath(); ctx.arc(px, pyy - s * 0.15, s * 0.45, Math.PI, 0, false);
    ctx.lineTo(px, pyy + s * 0.55); ctx.closePath(); ctx.fill();
    ctx.fillStyle = "#E8531F"; ctx.beginPath(); ctx.arc(px, pyy - s * 0.15, s * 0.16, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = "rgba(255,255,255,0.96)"; ctx.fillText(subtitle, W / 2 + 20, 303);
  }

  // Сетка штампов (квадратики): заполненные = собранные.
  if (stampsGrid) {
    const goal = Math.max(stampsGrid.goal, 1), got = Math.max(0, Math.min(stampsGrid.stamps, goal));
    const perRow = Math.min(goal, 6), rows = Math.ceil(goal / perRow);
    const box = rows > 1 ? 66 : 78, gap = 22, r = 14, rowH = box + gap;
    const startY = 296 - (rows - 1) * rowH / 2;
    for (let i = 0; i < goal; i++) {
      const row = Math.floor(i / perRow), col = i % perRow;
      const inRow = Math.min(perRow, goal - row * perRow);
      const rowW = inRow * box + (inRow - 1) * gap, x0 = W / 2 - rowW / 2;
      const x = x0 + col * (box + gap), y = startY + row * rowH - box / 2;
      rr(x, y, box, box, r);
      if (i < got) {
        ctx.fillStyle = "#fff"; ctx.fill();
        ctx.strokeStyle = "#E8531F"; ctx.lineWidth = box * 0.1; ctx.lineCap = "round"; ctx.lineJoin = "round";
        ctx.beginPath();
        ctx.moveTo(x + box * 0.28, y + box * 0.52);
        ctx.lineTo(x + box * 0.44, y + box * 0.68);
        ctx.lineTo(x + box * 0.74, y + box * 0.32);
        ctx.stroke();
      } else {
        ctx.fillStyle = "rgba(255,255,255,0.18)"; ctx.fill();
        ctx.strokeStyle = "rgba(255,255,255,0.6)"; ctx.lineWidth = 4; ctx.stroke();
      }
    }
  }

  ctx.fillStyle = body;
  ctx.beginPath(); ctx.arc(0, H, 42, 0, Math.PI * 2); ctx.fill();
  ctx.beginPath(); ctx.arc(W, H, 42, 0, Math.PI * 2); ctx.fill();

  const scale = (w: number, h: number): Buffer => {
    const cc = createCanvas(w, h), cx = cc.getContext("2d");
    cx.drawImage(c, 0, 0, w, h); return cc.toBuffer("image/png");
  };
  return {
    "strip.png": scale(375, 124),
    "strip@2x.png": scale(750, 248),
    "strip@3x.png": c.toBuffer("image/png"),
  };
}

function addHeaderStrip(pass: any, opts: StripOpts): void {
  try {
    const strip = buildHeaderStrip(opts);
    for (const [name, buf] of Object.entries(strip)) pass.addBuffer(name, buf);
  } catch (e: any) { console.error("strip render failed:", e.message); }
}

export const generateLoyaltyPass = onRequest(HTTP_OPTS, async (req, res) => {
  try {
    const venue = String(req.query.venue || "");
    const userID = String(req.query.user || "");
    const name = String(req.query.name || "Заведение");
    const stamps = parseInt(String(req.query.stamps || "0"), 10) || 0;
    const goal = parseInt(String(req.query.goal || "6"), 10) || 6;
    const reward = String(req.query.reward || "Награда");
    if (!venue || !userID) { res.status(400).send("missing venue/user"); return; }
    if (!(await checkAppCheck(req, "generateLoyaltyPass"))) { res.status(401).json({ error: "app_check_failed" }); return; }

    // Аутентификация: карту можно сгенерировать только для СВОЕГО userID.
    // Закрывает анонимный DoS (подпись + рендер canvas) и генерацию чужих карт.
    const uid = await verifyBearer(req);
    if (!uid) { res.status(401).json({ error: "no_token" }); return; }
    if (uid !== userID) { res.status(403).json({ error: "not_owner" }); return; }

    // Сертификаты ещё не настроены — мягкий отказ (приложение это учитывает).
    if (WALLET_CONFIGURED !== "1") {
      res.status(503).json({ error: "wallet_not_configured" });
      return;
    }

    // Ленивая загрузка, чтобы деплой не падал, если пакет ещё не установлен.
    const { PKPass } = require("passkit-generator");
    const certDir = path.join(__dirname, "certs");

    const pass = new PKPass(
      {}, // модель добавим ниже вручную (buffers), поэтому шаблон пустой
      {
        wwdr: fs.readFileSync(path.join(certDir, "wwdr.pem")),
        signerCert: fs.readFileSync(path.join(certDir, "signerCert.pem")),
        signerKey: fs.readFileSync(path.join(certDir, "signerKey.pem")),
        signerKeyPassphrase: process.env.PASS_KEY_PASSPHRASE || undefined,
      },
      {
        passTypeIdentifier: PASS_TYPE_ID,
        teamIdentifier: PASS_TEAM_ID,
        organizationName: PASS_ORG_NAME || "Ayant",
        serialNumber: `loyal-${userID}-${venue}`,
        description: `Карта лояльности · ${name}`,
        foregroundColor: "rgb(255,255,255)",
        backgroundColor: "rgb(28,28,30)",
        labelColor: "rgb(190,190,195)",
      }
    );

    pass.type = "storeCard";
    // QR карты лояльности — его сканирует заведение, чтобы начислить штамп.
    pass.setBarcodes({
      message: `AYANT-CARD:${userID}:${venue}`,
      format: "PKBarcodeFormatQR",
      messageEncoding: "iso-8859-1",
      altText: `${stamps}/${goal}`,
    });

    const full = stamps >= goal;
    addIcons(pass, path.join(certDir, "images"));
    addHeaderStrip(pass, {
      title: name,
      rightPill: full ? "готово" : `${stamps}/${goal}`,
      rightCheck: full,
      stampsGrid: { stamps, goal },
    });

    const buffer = pass.getAsBuffer();
    res.set("Content-Type", "application/vnd.apple.pkpass");
    res.set("Content-Disposition", `attachment; filename="loyalty-${venue}.pkpass"`);
    res.status(200).send(buffer);
  } catch (e) {
    console.error("generateLoyaltyPass error:", e);
    res.status(500).json({ error: "pass_generation_failed" });
  }
});

/* ───────────────────────────────────────────────────────────────────────────
 * 6) Сканирование купона заведением → погашение + штамп лояльности.
 *    POST /scanCoupon  body: { code, venueID }
 *    Header: Authorization: Bearer <Firebase ID token хоста>
 *
 *    Атомарно: проверяет что купон принадлежит этому заведению и не погашен,
 *    помечает used, начисляет 1 штамп в карту лояльности гостя, на goal-м —
 *    выдаёт купон-награду. Всё серверно (admin SDK) — анти-чит.
 * ─────────────────────────────────────────────────────────────────────────── */
/**
 * Курс денежной награды (сомов за балл) с серверной страховкой.
 *
 * Потолок кэшбэка 20% обходился курсом: «20% баллами + 1 балл = 5 сом» — это
 * скидка 100%. В режиме cashback эффективная скидка — процент × курс, поэтому
 * курс режется до `MAX_CASHBACK_PERCENT / процент` (но не ниже 1 — проект
 * задуман как «1 балл = 1 сом»). В flat/bands курс — лишь масштаб того, что
 * заведение и так могло задать числом баллов за визит, и не режется.
 * Зеркало — `PointsMath.effectiveRatio` на клиентах (общий фикстур).
 */
function effectiveMoneyRatio(venue: VenueDoc, reward: PointsReward): number {
  const ratio = Number(reward.ratio) > 0 ? Number(reward.ratio) : 1;
  if (String(venue.pointsMode || "flat") !== "cashback") return ratio;
  const pct = Math.min(Math.max(Number(venue.cashbackPercent) || 0, 0), MAX_CASHBACK_PERCENT);
  if (pct <= 0) return ratio;
  return Math.min(ratio, Math.max(1, MAX_CASHBACK_PERCENT / pct));
}

/** Короткий код чека погашения: 4 цифры, читается вслух у кассы. */
function newReceiptCode(): string {
  return String(crypto.randomInt(0, 10000)).padStart(4, "0");
}

/**
 * Ответ на повтор скана — из записи ключа (`scanKeys/{key}`), без начисления.
 * Ищется ДО переписывания QR и проверок конфига (loyalty_off, points_off,
 * missing_amount, card_not_found…): ретрай после того, как заведение
 * переключило механику или выключило карту, обязан получить исходный ответ —
 * штамп/баллы уже начислены. Ключ ищется в обоих местах, где его мог оставить
 * первый скан: под картой штампов и под картой баллов этого гостя здесь.
 */
async function earlyScanReplay(
  rawCode: string, venueID: string, venue: VenueDoc, key: string, cardID: string,
  goal: number, venueName: string,
): Promise<{ status: number; body: Record<string, unknown> } | null> {
  const parts = rawCode.split(":");
  const qrUser = String(parts[1] || "");
  if (!qrUser) return null;
  if (rawCode.startsWith("AYANT-CARD:")) {
    if (String(parts[2] || "") !== venueID) return null;
  } else if (!rawCode.startsWith("AYANT-PTS:")) {
    return null;
  }
  const cardCode = `AYANT-CARD:${qrUser}:${venueID}`;
  const ptsCode = `AYANT-PTS:${qrUser}`;

  const stampKey = await db.collection("loyaltyCards")
    .doc(stampCardDocID(qrUser, venueID, DEFAULT_STAMP_CARD_ID)).collection("scanKeys").doc(key).get();
  if (stampKey.exists) {
    const p = stampKey.data() || {};
    if (String(p.code || "") !== cardCode || String(p.cardID || DEFAULT_STAMP_CARD_ID) !== cardID) {
      return { status: 409, body: { error: "key_reused" } };
    }
    return { status: 200, body: stampReplayBody(p, venue, cardID, goal) };
  }
  const ptsKey = await db.collection("venuePoints").doc(`${qrUser}_${venueID}`)
    .collection("scanKeys").doc(key).get();
  if (ptsKey.exists) {
    const p = ptsKey.data() || {};
    if (String(p.code || "") !== ptsCode) return { status: 409, body: { error: "key_reused" } };
    return { status: 200, body: pointsReplayBody(p, venueName) };
  }
  return null;
}

function stampReplayBody(p: any, venue: VenueDoc, cardID: string, goal: number): Record<string, unknown> {
  const fallback = activeStampCards(venue).find((c) => c.id === cardID);
  const rGoal = parseInt(String(p.goal), 10) || (fallback ? fallback.goal : goal);
  const rReward = String(p.reward || (fallback ? fallback.reward : ""));
  return {
    ok: true, loyalty: true,
    title: p.rewardIssued ? "Карта заполнена!" : "Штамп начислен",
    stamps: parseInt(String(p.stamps), 10) || 0, goal: rGoal,
    rewardIssued: p.rewardIssued === true,
    rewardTitle: p.rewardIssued === true ? rReward : "",
    cardID, cardTitle: String(p.cardTitle ?? (fallback ? fallback.title : "")),
    replayed: true,
  };
}

function pointsReplayBody(p: any, venueName: string): Record<string, unknown> {
  return {
    ok: true, points: true,
    awarded: parseInt(String(p.awarded), 10) || 0,
    balance: parseInt(String(p.balance), 10) || 0,
    venueName, replayed: true,
  };
}

export const scanCoupon = onRequest(MONEY_PATH_OPTS, async (req, res) => {
  try {
    if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
    if (!(await checkAppCheck(req, "scanCoupon"))) { res.status(401).json({ error: "app_check_failed" }); return; }

    // 1) Аутентификация хоста по ID-токену.
    const authz = String(req.get("Authorization") || "");
    const idToken = authz.startsWith("Bearer ") ? authz.slice(7) : "";
    if (!idToken) { res.status(401).json({ error: "no_token" }); return; }
    let uid: string;
    try { uid = (await getAuth().verifyIdToken(idToken)).uid; }
    catch (e) { res.status(401).json({ error: "bad_token" }); return; }

    let code = String((req.body && req.body.code) || "").trim();
    const venueID = String((req.body && req.body.venueID) || "").trim();
    if (!code || !venueID) { res.status(400).json({ error: "missing_params" }); return; }

    // 2) Заведение должно принадлежать хосту.
    const venueSnap = await db.collection("venues").doc(venueID).get();
    if (!venueSnap.exists) { res.status(404).json({ error: "venue_not_found" }); return; }
    const venue = (venueSnap.data() || {}) as VenueDoc;
    if (String(venue.ownerID || "") !== uid) { res.status(403).json({ error: "not_owner" }); return; }

    // Идемпотентность скана. Ключ генерирует хост-приложение ОДИН раз на
    // распознанный QR и повторяет при ретрае. Проверяем его ПЕРЕД кулдауном:
    // иначе повтор внутри окна получил бы 429 вместо исходного результата —
    // ровно тот случай, ради которого ключ и нужен.
    const idempotencyKey = String((req.body && req.body.idempotencyKey) || "").trim().slice(0, 128);

    // Цель первой карты — только для поля `goal` в ответе ветки B (купон).
    // Ветка A берёт цель и награду у выбранной карты (`activeStampCards`).
    const goal = Math.max(parseInt(String(venue.loyaltyGoal), 10) || 6, 2);
    const venueName = String(venue.name || "Заведение");

    // Повтор скана — до переписывания QR и проверок конфига (см. earlyScanReplay).
    if (idempotencyKey) {
      const requestedCard = String((req.body && req.body.cardID) || "").trim() || DEFAULT_STAMP_CARD_ID;
      const replay = await earlyScanReplay(code, venueID, venue, idempotencyKey, requestedCard, goal, venueName);
      if (replay) { res.status(replay.status).json(replay.body); return; }
    }

    // Один QR гостя на все заведения (аудит 2026-10-01). Раньше у гостя было
    // два кода: «Мой QR» (AYANT-PTS) для баллов и QR карты (AYANT-CARD) для
    // штампов, и показать «не тот» значило получить отказ у кассы. Механика у
    // заведения одна (баллы ИЛИ штампы, приоритет у баллов), поэтому сервер
    // сам направляет любой из двух кодов туда, где у этого заведения лояльность.
    // Переписанный код детерминирован — ключ идемпотентности сверяется с ним же.
    {
      const qrUser = String(code.split(":")[1] || "");
      if (qrUser && code.startsWith("AYANT-PTS:")
          && venue.pointsEnabled !== true && venue.loyaltyEnabled === true) {
        code = `AYANT-CARD:${qrUser}:${venueID}`;
      } else if (qrUser && code.startsWith("AYANT-CARD:") && venue.pointsEnabled === true
          && String(code.split(":")[2] || "") === venueID) {
        code = `AYANT-PTS:${qrUser}`;
      }
    }

    // ── Ветка A: КАРТА ЛОЯЛЬНОСТИ (QR = AYANT-CARD:userID:venueID) → +1 штамп.
    //    Никак не связано с акциями/купонами — карта у заведения, у гостя.
    if (code.startsWith("AYANT-CARD:")) {
      if (venue.loyaltyEnabled !== true) { res.status(409).json({ error: "loyalty_off" }); return; }
      // ОДНА механика лояльности на заведение (домен: `LoyaltyKind`). Если
      // включены баллы САН — штампы не начисляются, даже когда флаг штампов
      // остался с прошлой настройки: иначе один визит оплачивался бы дважды, а
      // гость не понимал бы, что ему начислили. Приоритет у баллов.
      if (venue.pointsEnabled === true) { res.status(409).json({ error: "loyalty_is_points" }); return; }
      const parts = code.split(":");            // ["AYANT-CARD", userID, venueID]
      const cardUser = String(parts[1] || ""), cardVenue = String(parts[2] || "");
      if (!cardUser || cardVenue !== venueID) { res.status(409).json({ error: "wrong_venue" }); return; }

      // Какую карту выбрал сотрудник. Нет `cardID` — первая карта (старые клиенты).
      const cardID = String((req.body && req.body.cardID) || "").trim() || DEFAULT_STAMP_CARD_ID;

      const nowMs = Date.now();
      // Штампы: окно из настроек панели (дефолт 15 мин; отдельно от 60-мин паузы баллов).
      const cooldownMin = stampCooldownMinutes(await loadAppSettings());
      // Ключи скана ВСЕХ карт гостя в этом заведении — в одном месте, под
      // документом первой карты, и помнят свою карту: тот же ключ с другой
      // картой — коллизия (409), а не тихий штамп на вторую.
      const baseRef = db.collection("loyaltyCards").doc(stampCardDocID(cardUser, venueID, DEFAULT_STAMP_CARD_ID));
      const cardRef = cardID === DEFAULT_STAMP_CARD_ID
        ? baseRef
        : db.collection(stampCardCollection(cardID)).doc(stampCardDocID(cardUser, venueID, cardID));
      const keyRef = idempotencyKey ? baseRef.collection("scanKeys").doc(idempotencyKey) : null;

      // Повтор того же скана — отдаём сохранённый результат, ничего не начисляя.
      // Проверяется ДО поиска карты: ретрай должен вернуть исходный результат,
      // даже если карту за это время выключили.
      if (keyRef) {
        const prior = await keyRef.get();
        if (prior.exists) {
          const p = prior.data() || {};
          const priorCard = String(p.cardID || DEFAULT_STAMP_CARD_ID);
          if (String(p.code || "") !== code || priorCard !== cardID) {
            res.status(409).json({ error: "key_reused" }); return;
          }
          res.status(200).json(stampReplayBody(p, venue, cardID, goal));
          return;
        }
      }

      // Неизвестная или выключенная карта — отказ, а не молчаливый штамп не
      // на ту карту.
      const stampCard = activeStampCards(venue).find((c) => c.id === cardID);
      if (!stampCard) { res.status(409).json({ error: "card_not_found" }); return; }
      const cardGoal = stampCard.goal, reward = stampCard.reward, cardTitle = stampCard.title;

      // Анти-мультискан: не чаще 1 штампа на гостя/заведение в пределах кулдауна
      // (иначе сотрудник мог бы просканировать карту несколько раз подряд).
      const pre = (await cardRef.get()).data() || {};
      const preLast = toMillis(pre.lastStampAt);
      if (cooldownMin > 0 && nowMs - preLast < cooldownMin * 60000) {
        res.status(429).json({ error: "cooldown",
          retryAfterSec: Math.ceil((cooldownMin * 60000 - (nowMs - preLast)) / 1000) });
        return;
      }

      let stamps = 0, rewardIssued = false, applied = false;
      await db.runTransaction(async (tx) => {
        // Все чтения до записей (требование транзакций Firestore).
        const priorTx = keyRef ? await tx.get(keyRef) : null;
        const cur = (await tx.get(cardRef)).data() || {};
        if (priorTx && priorTx.exists) {   // гонка двух одинаковых сканов
          const p = priorTx.data() || {};
          // Тот же ключ, но другой QR или другая карта — коллизия, а не повтор.
          if (String(p.code || "") !== code || String(p.cardID || DEFAULT_STAMP_CARD_ID) !== cardID) {
            throw new Error("key_reused");
          }
          stamps = parseInt(String(p.stamps), 10) || 0;
          rewardIssued = p.rewardIssued === true;
          return;
        }
        const curLast = toMillis(cur.lastStampAt);
        if (cooldownMin > 0 && nowMs - curLast < cooldownMin * 60000) throw new Error("cooldown");
        let s = (parseInt(String(cur.stamps), 10) || 0) + 1;
        let rounds = parseInt(String(cur.completedRounds), 10) || 0;
        if (s >= cardGoal) { s = 0; rounds += 1; rewardIssued = true; }   // карта заполнена → награда сегодня
        tx.set(cardRef, {
          userID: cardUser, venueID, venueName, goal: cardGoal, reward, cardID, title: cardTitle,
          stamps: s, completedRounds: rounds, lastStampAt: new Date(nowMs), updatedAt: new Date(),
        }, { merge: true });
        if (rewardIssued) {
          // Награда — купон гостю: виден в «Мои купоны» и сканируется как
          // обычный купон (ветка B) сразу или в следующий визит. Раньше награда
          // существовала только в словах сотрудника и нигде не записывалась.
          tx.set(db.collection("coupons").doc(), {
            userID: cardUser, venueID, venueName, title: reward,
            code: newCouponCode(), kind: "loyalty", dealID: "",
            used: false, createdAt: new Date(nowMs), source: "loyaltyCard", cardID,
          });
        }
        if (keyRef) {
          tx.set(keyRef, { code, cardID, stamps: s, rewardIssued, goal: cardGoal, reward,
            cardTitle, at: new Date(nowMs) });
        }
        stamps = s;
        applied = true;
      });
      if (applied) await bumpAnalytics(venueID, { stamps: 1, rewardsIssued: rewardIssued ? 1 : 0 });
      res.status(200).json({
        ok: true, loyalty: true,
        title: rewardIssued ? "Карта заполнена!" : "Штамп начислен",
        stamps, goal: cardGoal, rewardIssued, rewardTitle: rewardIssued ? reward : "",
        cardID, cardTitle,
        replayed: false,
      });
      return;
    }

    // ── Ветка C: БАЛЛЫ САН (QR = AYANT-PTS:userID) → начисление баллов.
    //    Режим начисления настраивает заведение (self-serve):
    //      flat     — фикс. pointsFlat за визит (билл не нужен);
    //      bands    — по кнопке-диапазону: pointsBands[bandIndex].points;
    //      cashback — round(billAmount * cashbackPercent / 100).
    //    Кулдаун защищает от перескана постоянного гостя. Всё серверно (анти-чит).
    if (code.startsWith("AYANT-PTS:")) {
      if (venue.pointsEnabled !== true) { res.status(409).json({ error: "points_off" }); return; }
      const ptsUser = String(code.split(":")[1] || "");
      if (!ptsUser) { res.status(400).json({ error: "bad_code" }); return; }

      const mode = String(venue.pointsMode || "flat");
      const billAmount = Math.max(0, parseInt(String(req.body && req.body.billAmount), 10) || 0);
      const bandIndex = parseInt(String(req.body && req.body.bandIndex), 10);

      let awarded = 0;
      if (mode === "cashback") {
        const pct = Math.min(Math.max(Number(venue.cashbackPercent) || 0, 0), MAX_CASHBACK_PERCENT);
        if (billAmount <= 0) { res.status(400).json({ error: "missing_amount" }); return; }
        awarded = Math.round(billAmount * pct / 100);
      } else if (mode === "bands") {
        const bands: PointsBand[] = Array.isArray(venue.pointsBands) ? venue.pointsBands : [];
        if (!Number.isInteger(bandIndex) || bandIndex < 0 || bandIndex >= bands.length) {
          res.status(400).json({ error: "bad_band" }); return;
        }
        awarded = parseInt(String(bands[bandIndex].points), 10) || 0;
      } else { // flat
        awarded = parseInt(String(venue.pointsFlat), 10) || 0;
      }
      awarded = Math.min(Math.max(awarded, 0), MAX_POINTS_PER_EARN);
      if (awarded <= 0) { res.status(409).json({ error: "no_points" }); return; }

      const nowMs = Date.now();
      // 0 = кулдаун ВЫКЛЮЧЕН (осознанный выбор заведения), как и любое отрицательное
      // значение; поле отсутствует / мусор → дефолтные 60 мин. См. `intOrDefault`.
      const cooldownMin = Math.max(intOrDefault(venue.earnCooldownMinutes, DEFAULT_EARN_COOLDOWN_MIN), 0);
      const cardRef = db.collection("venuePoints").doc(`${ptsUser}_${venueID}`);
      const keyRef = idempotencyKey ? cardRef.collection("scanKeys").doc(idempotencyKey) : null;

      // Повтор того же скана — отдаём сохранённый результат, ничего не начисляя.
      // Проверка идёт ДО кулдауна: иначе ретрай внутри окна получил бы 429.
      if (keyRef) {
        const prior = await keyRef.get();
        if (prior.exists) {
          const p = prior.data() || {};
          if (String(p.code || "") !== code) { res.status(409).json({ error: "key_reused" }); return; }
          res.status(200).json(pointsReplayBody(p, venueName));
          return;
        }
      }

      // Пред-проверка кулдауна (чистый 429); повторно проверяем в транзакции.
      const pre = (await cardRef.get()).data() || {};
      const preLast = toMillis(pre.lastEarnAt);
      if (cooldownMin > 0 && nowMs - preLast < cooldownMin * 60000) {
        res.status(429).json({ error: "cooldown",
          retryAfterSec: Math.ceil((cooldownMin * 60000 - (nowMs - preLast)) / 1000) });
        return;
      }

      let balance = 0, appliedEarn = false;
      await db.runTransaction(async (tx) => {
        // Все чтения до записей (требование транзакций Firestore).
        const priorTx = keyRef ? await tx.get(keyRef) : null;
        const cur = (await tx.get(cardRef)).data() || {};
        if (priorTx && priorTx.exists) {   // гонка двух одинаковых сканов
          const p = priorTx.data() || {};
          awarded = parseInt(String(p.awarded), 10) || 0;
          balance = parseInt(String(p.balance), 10) || 0;
          return;
        }
        const curLast = toMillis(cur.lastEarnAt);
        if (cooldownMin > 0 && nowMs - curLast < cooldownMin * 60000) throw new Error("cooldown");
        appliedEarn = true;
        balance = (parseInt(String(cur.balance), 10) || 0) + awarded;
        tx.set(cardRef, {
          userID: ptsUser, venueID, venueName,
          balance,
          lifetimeEarned: (parseInt(String(cur.lifetimeEarned), 10) || 0) + awarded,
          lastEarnAt: new Date(nowMs), lastActivityAt: new Date(nowMs), updatedAt: new Date(),
        }, { merge: true });
        tx.set(cardRef.collection("ledger").doc(), {
          type: "earn", points: awarded, billAmount: billAmount || null,
          byVenue: true, at: new Date(nowMs),
        });
        if (keyRef) tx.set(keyRef, { code, awarded, balance, at: new Date(nowMs) });
      });

      if (appliedEarn) await bumpAnalytics(venueID, { pointsEarned: awarded });
      res.status(200).json({ ok: true, points: true, awarded, balance, venueName, replayed: false });
      return;
    }

    // ── Ветка B: КУПОН акции → только погашение (штамп НЕ начисляется).
    // Сначала — купон ЭТОГО заведения с таким кодом. Поиск по одному коду
    // находил первый попавшийся документ, и клиент мог подложить свой
    // непривязанный купон (`venueID == ''` — их правила ещё разрешают) с
    // чужим кодом: настоящий купон гостя тогда отвечал бы `wrong_venue`.
    let q = await db.collection("coupons")
      .where("code", "==", code).where("venueID", "==", venueID).limit(1).get();
    if (q.empty) {
      // Купона этого заведения нет — второй запрос только ради понятного
      // ответа сотруднику: «для другого заведения» или «не найден».
      const any = await db.collection("coupons").where("code", "==", code).limit(1).get();
      if (any.empty) { res.status(404).json({ error: "coupon_not_found" }); return; }
      res.status(409).json({ error: "wrong_venue" }); return;
    }
    const couponRef = q.docs[0].ref;
    const coupon = (q.docs[0].data() || {}) as CouponDoc;
    if (coupon.used === true) { res.status(409).json({ error: "already_used", title: coupon.title || "" }); return; }
    // «Действует до» — срок купона, а не только продажи: раньше проданный купон
    // не сгорал никогда, и обязательство заведения не кончалось.
    const couponExpires = toMillis(coupon.expiresAt);
    if (couponExpires > 0 && couponExpires < Date.now()) {
      res.status(409).json({ error: "coupon_expired", title: coupon.title || "" }); return;
    }

    await db.runTransaction(async (tx) => {
      const cSnap = await tx.get(couponRef);
      if ((cSnap.data() || {}).used === true) throw new Error("already_used");
      tx.update(couponRef, { used: true, usedAt: new Date(), usedByVenue: venueID });
    });

    await bumpAnalytics(venueID, { redemptions: 1 });

    // Авторитетная метка погашения для обучения весов выдачи (кросс-платформенно).
    // Нужен userID купона для склейки с impression/tap; иначе метка бесполезна.
    if (coupon.userID) {
      logServerRedeem({
        userID: String(coupon.userID),
        dealID: coupon.dealID ? String(coupon.dealID) : undefined,
        venueID,
        citySlug: venue.citySlug ? String(venue.citySlug) : undefined,
      }).catch(() => {});
    }

    res.status(200).json({
      ok: true, loyalty: false, title: coupon.title || "",
      stamps: 0, goal, rewardIssued: false, rewardTitle: "",
    });
  } catch (e: any) {
    if (String(e.message) === "already_used") { res.status(409).json({ error: "already_used" }); return; }
    if (String(e.message) === "cooldown") { res.status(429).json({ error: "cooldown" }); return; }
    if (String(e.message) === "key_reused") { res.status(409).json({ error: "key_reused" }); return; }
    console.error("scanCoupon error:", e);
    res.status(500).json({ error: "scan_failed" });
  }
});

/* ───────────────────────────────────────────────────────────────────────────
 * 6b) Списание баллов САН (System 1) → погашение награды из каталога заведения.
 *     POST /redeemVenuePoints  body: { venueID, userID?, rewardId, pointsToSpend?, idempotencyKey?, nonce? }
 *     Header: Authorization: Bearer <Firebase ID token>
 *
 *     Кто инициирует зависит от venue.redeemMode:
 *       staffScan          — гасит владелец, userID берётся из QR гостя (AYANT-RDM);
 *       customerInitiated  — гость гасит сам (uid == userID).
 *     Владелец может гасить всегда (это его деньги). Награда — item (фикс. cost)
 *     или money (списываем pointsToSpend ≥ cost=minRedeem). Атомарно, анти-чит.
 * ─────────────────────────────────────────────────────────────────────────── */
/** Nonce QR списания — как `RedeemQR.isValidNonce` на клиенте. */
const REDEEM_NONCE_RE = /^[A-Za-z0-9_-]{12,64}$/;

/* ── Токен списания (QR `AYANT-RDT:<token>`) ───────────────────────────────
 * Раньше QR списания нёс uid гостя (`AYANT-RDM:<uid>:<reward>:…`): кто знал
 * чужой uid (а он стоит и в QR начисления), мог сгенерировать QR и списать
 * чужие баллы у любой стойки, где у него есть сотрудник-сообщник. Теперь гость
 * просит у сервера одноразовый токен на конкретную награду и заведение;
 * QR несёт только его. Токен живёт 3 минуты, гасится один раз, и угадать
 * его (120 бит) нельзя.
 *
 * Старые сборки гостя по-прежнему показывают uid-QR. Путь для них остаётся,
 * пока env REDEEM_REQUIRE_TOKEN не "true": переключить, когда сборка с
 * токенами разойдётся (см. claude-notes / деплой). */
export const REDEEM_TOKEN_TTL_MS = 3 * 60 * 1000;
const REDEEM_TOKEN_RE = /^[A-Za-z0-9_-]{20,64}$/;

function redeemRequiresToken(): boolean {
  return String(process.env.REDEEM_REQUIRE_TOKEN || "false").toLowerCase() === "true";
}

/** 24 случайных байта → 32 символа base64url (192 бита). */
function newRedeemToken(): string {
  return crypto.randomBytes(24).toString("base64url");
}

/**
 * Стоимость награды в баллах по серверному конфигу — общая для превью
 * (`issueRedeemToken`) и списания (`redeemVenuePoints`). Ошибка — объект
 * с кодом ответа: item без цены, money ниже минимума, нет награды.
 */
function rewardCost(venue: VenueDoc, rewardId: string, pointsToSpend: number):
  { ok: true; reward: PointsReward; cost: number; type: string; ratio: number }
  | { ok: false; status: number; body: Record<string, unknown> } {
  const rewards: PointsReward[] = Array.isArray(venue.pointsRewards) ? venue.pointsRewards : [];
  const reward = rewards.find((r) => String(r.id) === rewardId);
  if (!reward || reward.active === false) return { ok: false, status: 404, body: { error: "reward_not_found" } };
  const type = String(reward.type || "item");
  const ratio = effectiveMoneyRatio(venue, reward);
  if (type === "money") {
    const minRedeem = Math.max(parseInt(String(reward.cost), 10) || 1, 1);
    if (pointsToSpend < minRedeem) return { ok: false, status: 400, body: { error: "below_min", minRedeem } };
    return { ok: true, reward, cost: pointsToSpend, type, ratio };
  }
  const cost = Math.max(parseInt(String(reward.cost), 10) || 0, 0);
  if (cost <= 0) return { ok: false, status: 409, body: { error: "bad_reward" } };
  return { ok: true, reward, cost, type, ratio };
}

/**
 * Пользователь из Bearer-токена: метод → App Check → токен → не анонимный.
 * null — ответ клиенту уже отправлен. Общий вход для новых функций
 * (issueRedeemToken, signCloudinaryUpload).
 */
async function requireRealUser(req: any, res: any, label: string): Promise<string | null> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return null; }
  if (!(await checkAppCheck(req, label))) { res.status(401).json({ error: "app_check_failed" }); return null; }
  const authz = String(req.get("Authorization") || "");
  const idToken = authz.startsWith("Bearer ") ? authz.slice(7) : "";
  if (!idToken) { res.status(401).json({ error: "no_token" }); return null; }
  let decoded: any;
  try { decoded = await getAuth().verifyIdToken(idToken); }
  catch { res.status(401).json({ error: "bad_token" }); return null; }
  if (decoded && decoded.firebase && decoded.firebase.sign_in_provider === "anonymous") {
    res.status(403).json({ error: "anonymous_not_allowed" }); return null;
  }
  return String(decoded.uid);
}

/* POST /issueRedeemToken  body: { venueID, rewardId, pointsToSpend? }
 * → { token, expiresAt (мс), ttlSec, cost }. Баланс проверяется для превью
 * (честный отказ «не хватает» сразу у гостя); списание всё равно проверяет
 * его заново в транзакции. */
export const issueRedeemToken = onRequest(MONEY_PATH_OPTS, async (req, res) => {
  try {
    const uid = await requireRealUser(req, res, "issueRedeemToken");
    if (!uid) return;
    const venueID = String((req.body && req.body.venueID) || "").trim();
    const rewardId = String((req.body && req.body.rewardId) || "").trim();
    const pointsToSpend = Math.max(0, parseInt(String(req.body && req.body.pointsToSpend), 10) || 0);
    if (!venueID || !rewardId) { res.status(400).json({ error: "missing_params" }); return; }

    const venueSnap = await db.collection("venues").doc(venueID).get();
    if (!venueSnap.exists) { res.status(404).json({ error: "venue_not_found" }); return; }
    const venue = (venueSnap.data() || {}) as VenueDoc;
    if (venue.pointsEnabled !== true) { res.status(409).json({ error: "points_off" }); return; }
    const priced = rewardCost(venue, rewardId, pointsToSpend);
    if (!priced.ok) { res.status(priced.status).json(priced.body); return; }

    const card = (await db.collection("venuePoints").doc(`${uid}_${venueID}`).get()).data() || {};
    if (intOf(card.balance) < priced.cost) { res.status(409).json({ error: "insufficient" }); return; }

    const token = newRedeemToken();
    const nowMs = Date.now();
    const expiresAt = nowMs + REDEEM_TOKEN_TTL_MS;
    await db.collection("redeemTokens").doc(token).set({
      uid, venueID, rewardId,
      points: priced.type === "money" ? priced.cost : 0,
      cost: priced.cost,
      used: false,
      createdAt: new Date(nowMs),
      // Поле для TTL-политики Firestore (удаление протухших токенов).
      expiresAt: new Date(expiresAt),
    });
    res.status(200).json({ ok: true, token, expiresAt, ttlSec: Math.round(REDEEM_TOKEN_TTL_MS / 1000), cost: priced.cost });
  } catch (e) {
    console.error("issueRedeemToken error:", e);
    res.status(500).json({ error: "issue_failed" });
  }
});

export const redeemVenuePoints = onRequest(MONEY_PATH_OPTS, async (req, res) => {
  try {
    if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
    if (!(await checkAppCheck(req, "redeemVenuePoints"))) { res.status(401).json({ error: "app_check_failed" }); return; }

    const authz = String(req.get("Authorization") || "");
    const idToken = authz.startsWith("Bearer ") ? authz.slice(7) : "";
    if (!idToken) { res.status(401).json({ error: "no_token" }); return; }
    let uid: string;
    try { uid = (await getAuth().verifyIdToken(idToken)).uid; }
    catch (e) { res.status(401).json({ error: "bad_token" }); return; }

    const venueID = String((req.body && req.body.venueID) || "").trim();
    const redeemToken = String((req.body && req.body.token) || "").trim();
    let rewardId = String((req.body && req.body.rewardId) || "").trim();
    const userID = String((req.body && req.body.userID) || "").trim();
    let pointsToSpend = Math.max(0, parseInt(String(req.body && req.body.pointsToSpend), 10) || 0);
    if (!venueID || (!rewardId && !redeemToken)) { res.status(400).json({ error: "missing_params" }); return; }

    const venueSnap = await db.collection("venues").doc(venueID).get();
    if (!venueSnap.exists) { res.status(404).json({ error: "venue_not_found" }); return; }
    const venue = (venueSnap.data() || {}) as VenueDoc;
    const redeemMode = String(venue.redeemMode || "staffScan");
    const isOwner = String(venue.ownerID || "") === uid;

    // Токен из QR гостя (`AYANT-RDT:<token>`): чья карта, какая награда и
    // сколько баллов — только из серверной записи токена, не из запроса.
    const tokenRef = redeemToken ? db.collection("redeemTokens").doc(redeemToken) : null;
    if (redeemToken) {
      if (!isOwner) { res.status(403).json({ error: "not_owner" }); return; }
      if (!REDEEM_TOKEN_RE.test(redeemToken)) { res.status(404).json({ error: "token_not_found" }); return; }
    }
    let tokenUser = "";
    if (tokenRef) {
      const t = await tokenRef.get();
      if (!t.exists) { res.status(404).json({ error: "token_not_found" }); return; }
      const td = t.data() || {};
      // Токен другого заведения: QR показали не у той стойки. Не гасим и не
      // раскрываем, чей он.
      if (String(td.venueID || "") !== venueID) { res.status(409).json({ error: "wrong_venue" }); return; }
      tokenUser = String(td.uid || "");
      rewardId = String(td.rewardId || "");
      pointsToSpend = Math.max(0, intOf(td.points));
      if (!tokenUser || !rewardId) { res.status(404).json({ error: "token_not_found" }); return; }
    }

    // Определяем, чья это карта, и кто вправе гасить.
    let cardUser: string;
    if (tokenRef) {
      cardUser = tokenUser;                       // владелец гасит по токену гостя
    } else if (isOwner) {
      // Старый QR с uid гостя. После выхода сборки с токенами — выключить
      // (REDEEM_REQUIRE_TOKEN=true): uid в QR позволяет списать чужие баллы.
      if (redeemRequiresToken()) { res.status(400).json({ error: "token_required" }); return; }
      cardUser = userID;                          // владелец гасит по QR гостя
      if (!cardUser) { res.status(400).json({ error: "missing_user" }); return; }
    } else if (redeemMode === "customerInitiated") {
      cardUser = uid;                             // гость гасит сам
    } else {
      res.status(403).json({ error: "redeem_not_allowed" }); return;
    }

    const cardRef = db.collection("venuePoints").doc(`${cardUser}_${venueID}`);

    // Идемпотентность. Клиент генерирует ключ ОДИН раз на попытку списания и
    // переиспользует его при повторной отправке (таймаут сети, второй тап по
    // кнопке). Первый запрос списывает и запоминает результат под этим ключом;
    // все следующие с тем же ключом возвращают тот же ответ, НЕ списывая снова.
    // Ключ живёт под картой гостя, поэтому чужим ключом воспользоваться нельзя.
    // Токен (`rdm_<token>`) и nonce старого QR (`rdm_<nonce>`) задают ключ
    // сами, а не сканер: сканер мог выдать новый ключ на каждый скан, и один
    // и тот же QR гасился дважды (второй сотрудник, повторный тап, скриншот).
    // Теперь любой повтор того же QR — воспроизведение первого списания.
    const rawNonce = String((req.body && req.body.nonce) || "").trim();
    const nonce = isOwner && !tokenRef && REDEEM_NONCE_RE.test(rawNonce) ? rawNonce : "";
    const idempotencyKey = tokenRef
      ? `rdm_${redeemToken}`
      : nonce
        ? `rdm_${nonce}`
        : String((req.body && req.body.idempotencyKey) || "").trim().slice(0, 128);
    const keyRef = idempotencyKey ? cardRef.collection("redeemKeys").doc(idempotencyKey) : null;

    // Повтор отдаётся ДО поиска награды и до проверки срока токена — как в
    // ветке A скана: если заведение за это время выключило или переоценило
    // награду или токен истёк, ретрай всё равно должен получить исходный
    // ответ, ведь баллы уже списаны.
    if (keyRef) {
      const prior = await keyRef.get();
      if (prior.exists) {
        const p = prior.data() || {};
        if (String(p.rewardId || "") !== rewardId) { res.status(409).json({ error: "key_reused" }); return; }
        res.status(200).json({
          ok: true, redeemed: intOf(p.redeemed), balance: intOf(p.balance),
          rewardTitle: String(p.rewardTitle || ""),
          somOff: p.somOff === undefined ? null : p.somOff,
          receiptCode: String(p.receiptCode || ""), redeemedAt: toMillis(p.at),
          replayed: true,
        });
        return;
      }
    }

    const priced = rewardCost(venue, rewardId, pointsToSpend);
    if (!priced.ok) { res.status(priced.status).json(priced.body); return; }
    const { reward, type, ratio } = priced;
    let cost = priced.cost;

    const somOff = type === "money" ? Math.round(cost * ratio) : null;
    const rewardTitle = String(reward.title || "");
    // Код чека: гость показывает экран «погашено» с этим кодом и временем, и
    // сотрудник отличает свежее погашение от старого скриншота. Код же лежит
    // в ledger — его видно в истории карты.
    let receiptCode = newReceiptCode();
    let redeemedAt = Date.now();

    let balance = 0;
    let replayed = false;
    await db.runTransaction(async (tx) => {
      // ВСЕ чтения до записей — требование транзакций Firestore.
      const priorSnap = keyRef ? await tx.get(keyRef) : null;
      if (priorSnap && priorSnap.exists) {
        const prior = priorSnap.data() || {};
        // Тот же ключ на другую награду — не наш повтор, а коллизия: отказываем.
        if (String(prior.rewardId || "") !== rewardId) throw new Error("key_reused");
        balance = parseInt(String(prior.balance), 10) || 0;
        cost = parseInt(String(prior.redeemed), 10) || 0;
        receiptCode = String(prior.receiptCode || "");
        redeemedAt = toMillis(prior.at);
        replayed = true;
        return;
      }

      // Токен — одноразовый и короткоживущий; проверяется В транзакции, чтобы
      // два сотрудника с одним QR не погасили его оба.
      const tokSnap = tokenRef ? await tx.get(tokenRef) : null;
      const cur = (await tx.get(cardRef)).data() || {};
      if (tokSnap) {
        const td = tokSnap.data() || {};
        if (!tokSnap.exists) throw new Error("token_not_found");
        if (td.used === true) throw new Error("token_used");
        if (toMillis(td.expiresAt) < redeemedAt) throw new Error("token_expired");
      }
      const bal = parseInt(String(cur.balance), 10) || 0;
      if (bal < cost) throw new Error("insufficient");
      balance = bal - cost;
      if (tokenRef) tx.set(tokenRef, { used: true, usedAt: new Date(redeemedAt), usedBy: uid }, { merge: true });
      tx.set(cardRef, {
        balance,
        lifetimeRedeemed: (parseInt(String(cur.lifetimeRedeemed), 10) || 0) + cost,
        lastActivityAt: new Date(), updatedAt: new Date(),
      }, { merge: true });
      const at = new Date(redeemedAt);
      tx.set(cardRef.collection("ledger").doc(), {
        type: "redeem", points: -cost, rewardId, byVenue: isOwner, receiptCode, at,
      });
      if (keyRef) tx.set(keyRef, { rewardId, redeemed: cost, balance, rewardTitle, somOff, receiptCode, at });
    });

    if (!replayed) await bumpAnalytics(venueID, { pointsRedeemed: cost, rewardsIssued: 1 });
    res.status(200).json({
      ok: true, redeemed: cost, balance,
      rewardTitle,
      somOff,
      receiptCode, redeemedAt,
      // true — запрос уже выполнялся ранее с этим же ключом, баллы НЕ списаны повторно.
      replayed,
    });
  } catch (e: any) {
    const m = String(e.message);
    if (m === "insufficient" || m === "key_reused" || m === "token_used" || m === "token_expired") {
      res.status(409).json({ error: m }); return;
    }
    if (m === "token_not_found") { res.status(404).json({ error: m }); return; }
    console.error("redeemVenuePoints error:", e);
    res.status(500).json({ error: "redeem_failed" });
  }
});

/**
 * Ночные проходы читают ВСЕ карты и их ledger по очереди. С таймаутом по
 * умолчанию (60 с у v2) они начали бы молча обрываться, как только данных
 * станет побольше, — и сверка, призванная ловить потерю денег, перестала бы
 * работать незаметно. 540 с — максимум для расписания; когда и его станет
 * мало, проход нужно будет делить на страницы.
 */
const NIGHTLY_JOB = { schedule: "every 24 hours", timeoutSeconds: 540, memory: "512MiB" as const };
/** Страница ночных сверок (карты баллов, кошельки). */
const RECONCILE_PAGE = 300;

/* ───────────────────────────────────────────────────────────────────────────
 * 6c) Сгорание баллов САН по неактивности (System 1). Ежедневно.
 *     Обнуляет баланс карт, где lastActivityAt старше venue.pointsExpiryMonths,
 *     и пишет строку ledger type:"expire". Порог берётся из конфига заведения.
 * ─────────────────────────────────────────────────────────────────────────── */
export const expireVenuePoints = onSchedule(NIGHTLY_JOB, async () => {
  const nowMs = Date.now();
  const venueMonths = new Map<string, number>();       // кэш порога по заведению
  const snap = await db.collection("venuePoints").where("balance", ">", 0).get();
  let expired = 0;

  for (const doc of snap.docs) {
    const c = (doc.data() || {}) as VenuePointsDoc;
    const venueID = String(c.venueID || "");
    if (!venueID) continue;

    let months = venueMonths.get(venueID);
    if (months === undefined) {
      const v = await db.collection("venues").doc(venueID).get();
      // `|| DEFAULT_EXPIRY_MONTHS` намеренно (в отличие от earnCooldownMinutes): ноль
      // месяцев не значит «не сгорают» — сгорание не отключается, а нижний клэмп всё
      // равно 1 мес., так что ноль безопаснее трактовать как «не задано» → дефолт.
      months = Math.max(parseInt(String((v.data() || {}).pointsExpiryMonths), 10) || DEFAULT_EXPIRY_MONTHS, 1);
      venueMonths.set(venueID, months);
    }

    const lastMs = toMillis(c.lastActivityAt);
    if (lastMs === 0) continue;
    if (nowMs - lastMs < months * 30 * DAY_MS) continue;   // месяц ≈ 30 дней

    let didExpire = false;
    await db.runTransaction(async (tx) => {
      const cur = (await tx.get(doc.ref)).data() || {};
      const b = parseInt(String(cur.balance), 10) || 0;
      if (b <= 0) return;
      // Порог перепроверяется по свежему документу: гость мог получить баллы
      // между запросом и транзакцией, и тогда сгорели бы только что
      // начисленные — порог, решённый по старому снимку, уже неверен.
      const freshLast = toMillis(cur.lastActivityAt);
      if (freshLast === 0 || nowMs - freshLast < months! * 30 * DAY_MS) return;
      didExpire = true;
      tx.set(doc.ref, { balance: 0, updatedAt: new Date() }, { merge: true });
      tx.set(doc.ref.collection("ledger").doc(), {
        type: "expire", points: -b, byVenue: false, at: new Date(),
      });
    });
    if (didExpire) expired++;
  }

  console.log(`⌛ venuePoints expired: ${expired}`);
  // Пульс задачи: ночная сверка проверит, что она отработала (см. reconcileVenuePoints).
  await db.collection("ops").doc("heartbeats")
    .set({ expireVenuePoints: new Date(), expireVenuePointsCount: expired }, { merge: true });
});

/* ───────────────────────────────────────────────────────────────────────────
 * 6b) Предупреждение о сгорании: за EXPIRY_WARN_DAYS до порога — push гостю
 *     «баллы в {venue} сгорят через N дней». Один раз на окно: отметка
 *     `expiryWarnedAt` на карте; новая активность сдвигает порог, и предупреждение
 *     сможет уйти снова только для нового окна.
 * ─────────────────────────────────────────────────────────────────────────── */
const EXPIRY_WARN_DAYS = 7;

export const warnExpiringPoints = onSchedule(NIGHTLY_JOB, async () => {
  const nowMs = Date.now();
  const venueCache = new Map<string, { months: number; name: string }>();
  const snap = await db.collection("venuePoints").where("balance", ">", 0).get();
  let warned = 0;

  for (const doc of snap.docs) {
    const c = (doc.data() || {}) as VenuePointsDoc & { expiryWarnedAt?: unknown; userID?: string };
    const venueID = String(c.venueID || "");
    const userID = String(c.userID || "");
    if (!venueID || !userID) continue;

    let venue = venueCache.get(venueID);
    if (!venue) {
      const v = (await db.collection("venues").doc(venueID).get()).data() || {};
      venue = {
        months: Math.max(parseInt(String(v.pointsExpiryMonths), 10) || DEFAULT_EXPIRY_MONTHS, 1),
        name: String(v.name || "заведение"),
      };
      venueCache.set(venueID, venue);
    }

    const lastMs = toMillis(c.lastActivityAt);
    if (lastMs === 0) continue;
    const expiresAt = lastMs + venue.months * 30 * DAY_MS;
    const daysLeft = Math.ceil((expiresAt - nowMs) / DAY_MS);
    if (daysLeft <= 0 || daysLeft > EXPIRY_WARN_DAYS) continue;
    // Уже предупреждали в этом окне (после последней активности) — молчим.
    if (toMillis(c.expiryWarnedAt) > lastMs) continue;

    const tokensSnap = await db.collection("userTokens").where("uid", "==", userID).get();
    const tokens = tokensSnap.docs.map((d) => d.id).filter((t) => t.length > 0);
    await doc.ref.set({ expiryWarnedAt: new Date(nowMs) }, { merge: true });
    if (tokens.length === 0) continue;

    const balance = parseInt(String(c.balance), 10) || 0;
    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: `Баллы в ${venue.name} скоро сгорят`,
        body: `${balance} баллов пропадут через ${daysLeft} дн. — загляните и потратьте их на награду.`,
      },
      data: { type: "pointsExpiring", venueID },
      apns: { payload: { aps: { sound: "default" } } },
      android: { notification: { sound: "default" }, priority: "high" },
    });
    warned++;
  }
  console.log(`⏳ expiry warnings sent: ${warned}`);
});

/* ───────────────────────────────────────────────────────────────────────────
 * 7) Купон в Apple Wallet (.pkpass со сканируемым QR = code).
 *    GET /generateCouponPass?code=<code>&title=<title>&venue=<venueName>
 * ─────────────────────────────────────────────────────────────────────────── */
export const generateCouponPass = onRequest(HTTP_OPTS, async (req, res) => {
  try {
    const code = String(req.query.code || "");
    const title = String(req.query.title || "Купон");
    const venue = String(req.query.venue || "Ayant");
    if (!code) { res.status(400).send("missing code"); return; }
    if (!(await checkAppCheck(req, "generateCouponPass"))) { res.status(401).json({ error: "app_check_failed" }); return; }

    // Аутентификация: только вошедшему пользователю (анти-DoS подписи/рендера).
    // Владение конкретным купоном не проверяем — подарочные купоны лежат в
    // giftCoupons, а не в coupons текущего пользователя.
    const uid = await verifyBearer(req);
    if (!uid) { res.status(401).json({ error: "no_token" }); return; }

    if (WALLET_CONFIGURED !== "1") { res.status(503).json({ error: "wallet_not_configured" }); return; }

    const { PKPass } = require("passkit-generator");
    const certDir = path.join(__dirname, "certs");

    const pass = new PKPass({}, {
      wwdr: fs.readFileSync(path.join(certDir, "wwdr.pem")),
      signerCert: fs.readFileSync(path.join(certDir, "signerCert.pem")),
      signerKey: fs.readFileSync(path.join(certDir, "signerKey.pem")),
      signerKeyPassphrase: process.env.PASS_KEY_PASSPHRASE || undefined,
    }, {
      passTypeIdentifier: PASS_TYPE_ID,
      teamIdentifier: PASS_TEAM_ID,
      organizationName: PASS_ORG_NAME || "Ayant",
      serialNumber: `coupon-${code}`,
      description: title,
      foregroundColor: "rgb(255,255,255)",
      backgroundColor: "rgb(28,28,30)",
      labelColor: "rgb(190,190,195)",
    });
    pass.type = "coupon";
    pass.setBarcodes({
      message: code, format: "PKBarcodeFormatQR",
      messageEncoding: "iso-8859-1", altText: code,
    });

    addIcons(pass, path.join(certDir, "images"));
    addHeaderStrip(pass, { title, subtitle: venue, rightPill: "активен", rightCheck: true });
    const buffer = pass.getAsBuffer();
    res.set("Content-Type", "application/vnd.apple.pkpass");
    res.set("Content-Disposition", `attachment; filename="coupon-${code}.pkpass"`);
    res.status(200).send(buffer);
  } catch (e) {
    console.error("generateCouponPass error:", e);
    res.status(500).json({ error: "pass_generation_failed" });
  }
});

/* ───────────────────────────────────────────────────────────────────────────
 * 6d) Ночные проверки целостности баллов (System 1).
 *
 *     Тестов на клиенте здесь мало по проекту (см. docs — «алерты вместо тестов»):
 *     тест ловит ошибку до релиза, алерт — в течение суток после, и находит то,
 *     что тестом не поймать вовсе (порча данных, не выполнившаяся джоба, аномальная
 *     эмиссия у конкретного заведения).
 *
 *     Одним проходом по venuePoints/{card}/ledger считаем сразу три вещи:
 *       1. Сверка: balance == сумма ledger.points. Расхождение = потерянные
 *          или задвоенные баллы, то есть прямые деньги.
 *       2. Пульс expireVenuePoints: не отработала за сутки — баллы не сгорают,
 *          обязательства заведений растут молча.
 *       3. Аномалия эмиссии: заведение начислило за сутки больше 3× своего
 *          среднего за предыдущую неделю — похоже на настройку «50% кэшбэк»
 *          вместо 5% или на злоупотребление сотрудника.
 *
 *     Алерт пишется в `ops/alerts/{auto}` (видно в консоли Firestore) и в лог с
 *     префиксом ALERT — по нему настраивается log-based alert в Cloud Monitoring.
 * ─────────────────────────────────────────────────────────────────────────── */

/** Заведение, начислившее больше этого множителя к своему недельному среднему. */
const ISSUANCE_SPIKE_FACTOR = 3;
/** Порог «джоба не отработала», ч. Сутки + запас на дрейф расписания. */
const HEARTBEAT_STALE_HOURS = 26;
/** Не заваливаем алертами: в один прогон пишем не больше стольких расхождений. */
const MAX_ALERTS_PER_RUN = 50;

type AlertKind = "balance_mismatch" | "job_stale" | "issuance_spike" | "issuance_new_venue"
  | "wallet_mismatch" | "wallet_cap_hit";

/** Заведение без недельной истории, начислившее за сутки больше этого. Спайк
 *  по среднему на нём не срабатывает (среднего нет), а новое заведение с
 *  «0 мин кулдауна» и щедрым кэшбэком — ровно тот случай, который нужно
 *  увидеть в первый же день. */
const NEW_VENUE_DAILY_ISSUANCE_ALERT = 5000;

/** Проверка пульса другой ночной задачи. Сверки проверяют друг друга и
 *  сгорание: задача, которая молча перестала запускаться, иначе не видна. */
async function checkHeartbeat(beat: Record<string, unknown>, job: string, nowMs: number): Promise<void> {
  const last = toMillis(beat[job]);
  if (last !== 0 && nowMs - last <= HEARTBEAT_STALE_HOURS * 60 * 60 * 1000) return;
  await raiseAlert("job_stale", {
    job,
    lastRunAt: last ? new Date(last).toISOString() : null,
    staleHours: last ? Math.round((nowMs - last) / 3600000) : null,
  });
}

async function raiseAlert(kind: AlertKind, detail: Record<string, unknown>): Promise<void> {
  console.error(`ALERT ${kind}`, JSON.stringify(detail));
  await db.collection("ops").doc("alerts").collection("items").add({
    kind, detail, at: new Date(), resolved: false,
  }).catch((e) => console.error("alert write failed:", e));
}

export const reconcileVenuePoints = onSchedule(NIGHTLY_JOB, async () => {
  const nowMs = Date.now();
  const DAY = 24 * 60 * 60 * 1000;

  // ── 2. Пульс задачи сгорания и сверки кошельков бонусов ───────────────────
  const beat = (await db.collection("ops").doc("heartbeats").get()).data() || {};
  await checkHeartbeat(beat, "expireVenuePoints", nowMs);
  await checkHeartbeat(beat, "reconcileBonusWallets", nowMs);

  // ── 1 + 3. Сверка балансов и эмиссия по заведениям ────────────────────────
  // Карты — постранично, сумма ledger — агрегатом sum() (одно чтение на 1000
  // записей вместо чтения каждой). Начисления за 8 дней читаются только у
  // карт с недавним начислением (lastEarnAt) и только за это окно.
  /** venueID → { today, prior7 } — начислено за сутки и за предыдущие 7 дней. */
  const issuance = new Map<string, { today: number; prior7: number }>();
  let checked = 0, mismatches = 0;
  const windowStart = nowMs - 8 * DAY;

  let cursor: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  for (;;) {
    let page = db.collection("venuePoints").orderBy(FieldPath.documentId()).limit(RECONCILE_PAGE);
    if (cursor) page = page.startAfter(cursor);
    const cards = await page.get();
    if (cards.empty) break;
    for (const card of cards.docs) {
      const data = card.data() || {};
      const balance = parseInt(String(data.balance), 10) || 0;
      const venueID = String(data.venueID || "");

      const agg = await card.ref.collection("ledger")
        .aggregate({ sum: AggregateField.sum("points"), n: AggregateField.count() }).get();
      const sum = Number(agg.data().sum) || 0;
      const entries = Number(agg.data().n) || 0;

      const lastEarn = toMillis(data.lastEarnAt);
      if (venueID && (lastEarn === 0 || lastEarn >= windowStart)) {
        const recent = await card.ref.collection("ledger").where("at", ">=", new Date(windowStart)).get();
        for (const entry of recent.docs) {
          const e = entry.data() || {};
          if (String(e.type) !== "earn") continue;
          const at = toMillis(e.at);
          if (at === 0) continue;
          const points = parseInt(String(e.points), 10) || 0;
          const age = nowMs - at;
          const bucket = issuance.get(venueID) || { today: 0, prior7: 0 };
          if (age <= DAY) bucket.today += points;
          else if (age <= 8 * DAY) bucket.prior7 += points;
          issuance.set(venueID, bucket);
        }
      }

      checked++;
      // Пустой ledger при нулевом балансе — нормальная новая карта, не расхождение.
      if (sum !== balance && !(entries === 0 && balance === 0)) {
        mismatches++;
        if (mismatches <= MAX_ALERTS_PER_RUN) {
          await raiseAlert("balance_mismatch", {
            card: card.id, userID: String(data.userID || ""), venueID,
            balance, ledgerSum: sum, delta: balance - sum, ledgerEntries: entries,
          });
        }
      }
    }
    if (cards.size < RECONCILE_PAGE) break;
    cursor = cards.docs[cards.docs.length - 1] as FirebaseFirestore.QueryDocumentSnapshot;
  }

  // ── 3. Аномальная эмиссия ─────────────────────────────────────────────────
  for (const [venueID, { today, prior7 }] of issuance) {
    const dailyMean = prior7 / 7;
    // Заведению без истории множитель не применяем — иначе первый же день даёт
    // алерт; вместо него — абсолютный порог.
    if (dailyMean <= 0) {
      if (today > NEW_VENUE_DAILY_ISSUANCE_ALERT) {
        await raiseAlert("issuance_new_venue", {
          venueID, issuedToday: today, threshold: NEW_VENUE_DAILY_ISSUANCE_ALERT,
        });
      }
      continue;
    }
    if (today <= dailyMean * ISSUANCE_SPIKE_FACTOR) continue;
    await raiseAlert("issuance_spike", {
      venueID, issuedToday: today,
      trailingDailyMean: Math.round(dailyMean * 100) / 100,
      factor: Math.round((today / dailyMean) * 100) / 100,
      threshold: ISSUANCE_SPIKE_FACTOR,
    });
  }

  if (mismatches > MAX_ALERTS_PER_RUN) {
    console.error(`ALERT balance_mismatch_flood ${mismatches} расхождений, записано ${MAX_ALERTS_PER_RUN}`);
  }
  console.log(`🧮 reconcile: карт ${checked}, расхождений ${mismatches}, заведений с эмиссией ${issuance.size}`);

  await db.collection("ops").doc("heartbeats")
    .set({ reconcileVenuePoints: new Date(), reconcileMismatches: mismatches }, { merge: true });
});

/* ───────────────────────────────────────────────────────────────────────────
 * deleteAccount — полное удаление аккаунта по требованию пользователя.
 *
 * Клиент («Профиль → Удалить аккаунт») раньше просто выходил из сессии:
 * запись в Firebase Auth и все документы оставались жить. Здесь настоящее
 * удаление, и делать его обязан сервер — правила запрещают клиенту трогать
 * `venuePoints`/`coupons`/`loyaltyCards`, а чужие документы он не найдёт.
 *
 * Порядок: сначала данные, потом сама запись Auth. Если упасть посередине,
 * пользователь сможет повторить вызов — все шаги идемпотентны.
 *
 * Владелец заведений (аудит запуска 2026-10-01): раньше получал 409 и не мог
 * удалить аккаунт сам — нарушение правил App Store (5.1.1(v)). Теперь его
 * заведения СНИМАЮТСЯ С ПУБЛИКАЦИИ, а не удаляются: status "pending",
 * isPaused, ownerDeleted — данные остаются (отзывы гостей, их баллы и штампы
 * — чужие данные, сносить их одним тапом нельзя), и админ может передать
 * заведение новому владельцу. Акции и купоны заведения удаляются: продавать и
 * рекламировать от имени удалённого аккаунта некому.
 * ─────────────────────────────────────────────────────────────────────────── */
export const deleteAccount = onRequest(HTTP_OPTS, async (req, res) => {
  try {
    if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
    const uid = await verifyBearer(req);
    if (!uid) { res.status(401).json({ error: "no_token" }); return; }

    // 1) Заведения владельца — снимаем с публикации, данные оставляем.
    const owned = await db.collection("venues").where("ownerID", "==", uid).get();
    const nowDate = new Date();
    for (let i = 0; i < owned.docs.length; i += 400) {
      const batch = db.batch();
      for (const v of owned.docs.slice(i, i + 400)) {
        batch.set(v.ref, {
          status: "pending", isPaused: true, ownerDeleted: true, ownerDeletedAt: nowDate,
        }, { merge: true });
      }
      await batch.commit();
    }
    // Акции и купоны заведений владельца — по ownerID и (на случай записей
    // админа без ownerID) по venueID его заведений.
    for (const name of ["deals", "couponOffers"]) {
      const refs = new Map<string, DocumentReference>();
      for (const d of (await db.collection(name).where("ownerID", "==", uid).get()).docs) refs.set(d.ref.path, d.ref);
      for (const v of owned.docs) {
        for (const d of (await db.collection(name).where("venueID", "==", v.id).get()).docs) refs.set(d.ref.path, d.ref);
      }
      await deleteInChunks([...refs.values()]);
    }

    // 2) Документы, чей id начинается с uid: `{uid}_{venueID}`.
    for (const name of ["venuePoints", "loyaltyCards", EXTRA_LOYALTY_CARDS]) {
      const snap = await db.collection(name)
        .where("userID", "==", uid).get();
      for (const doc of snap.docs) {
        // Подколлекции (ledger, scanKeys, redeemKeys) — рекурсивно.
        await db.recursiveDelete(doc.ref);
        // Ключи скана дополнительных карт лежат под документом ПЕРВОЙ карты,
        // а его может и не быть (гость копил только на «пиццу»).
        if (name === EXTRA_LOYALTY_CARDS) {
          const d = doc.data() || {};
          await db.recursiveDelete(db.collection("loyaltyCards")
            .doc(stampCardDocID(uid, String(d.venueID || ""), DEFAULT_STAMP_CARD_ID)));
        }
      }
    }

    // 3) Документы, найденные по полю userID/authorID.
    const byField: Array<[string, string]> = [
      ["coupons", "userID"],
      ["bonusGrants", "userID"],
      ["redemptions", "userID"],
      ["reviews", "authorID"],
      ["userTokens", "uid"],
      ["rankingEvents", "userID"],
      ["reviewReports", "reporterID"],
      ["pushCampaigns", "ownerID"],
      ["igAccounts", "ownerID"],
      ["igConnections", "ownerID"],
      ["redeemTokens", "uid"],
    ];
    for (const [name, field] of byField) {
      try {
        const snap = await db.collection(name).where(field, "==", uid).get();
        await deleteInChunks(snap.docs.map((d) => d.ref));
      } catch (e) {
        // rankingEvents.userID намеренно не индексирован (firestore.indexes.json,
        // fieldOverrides — экономия на записи телеметрии), и запрос по нему
        // падает FAILED_PRECONDITION. Раньше это роняло ВСЁ удаление аккаунта
        // в 500. Телеметрию пропускаем с алертом в логах; остальное — ошибка.
        if (name !== "rankingEvents") throw e;
        console.warn(`ALERT delete_account_ranking_events_skipped uid=${uid}`, e);
      }
    }
    // Незабранные подарки, купленные этим аккаунтом. Забранные — уже купон
    // получателя (его данные), их не трогаем.
    const gifts = await db.collection("giftCoupons").where("fromUserID", "==", uid).get();
    await deleteInChunks(gifts.docs.filter((d) => (d.data() || {}).claimed !== true).map((d) => d.ref));
    // analyticsEvents не хранят пользователя (и удаляются сразу после
    // подсчёта) — чистить там нечего.

    // 4) Документы с uid в качестве id.
    await db.collection("referrals").doc(uid).delete().catch(() => undefined);
    await db.collection("hosts").doc(uid).delete().catch(() => undefined);
    await db.collection("referralCounts").doc(uid).delete().catch(() => undefined);
    // Сохранённые заведения, избранное и скрытые авторы (ProfileStore).
    await db.collection("userLibraries").doc(uid).delete().catch(() => undefined);
    // Кошелёк бонусов вместе с ledger и ключами идемпотентности.
    try { await db.recursiveDelete(db.collection("bonusWallets").doc(uid)); } catch { /* кошелька нет */ }

    // 5) Сама запись Auth — последней: пока она есть, вызов можно повторить.
    await getAuth().deleteUser(uid);

    console.log(`🗑 account deleted: ${uid} (venues unpublished: ${owned.size})`);
    res.json({ ok: true, venuesUnpublished: owned.size });
  } catch (e) {
    console.error("deleteAccount failed:", e);
    res.status(500).json({ error: "internal" });
  }
});

/** Пакетное удаление: в один batch помещается не больше 500 операций. */
async function deleteInChunks(refs: DocumentReference[]): Promise<void> {
  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    for (const ref of refs.slice(i, i + 400)) batch.delete(ref);
    await batch.commit();
  }
}

/* ───────────────────────────────────────────────────────────────────────────
 * INSTAGRAM: подключение аккаунта заведения и импорт постов в акции.
 *
 * Зачем на сервере. Секрет приложения Meta и токен доступа заведения не
 * должны попадать в клиент вообще никогда — значит обмен `code` → токен,
 * хранение, обновление и походы в Graph API живут здесь. Клиент ходит сюда по
 * своему Firebase ID-токену и получает только обезличенные посты.
 *
 * Что важно знать, прежде чем это править:
 *
 *  1. Личные аккаунты подключить НЕЛЬЗЯ. Basic Display API Meta закрыла
 *     4 декабря 2024-го; работает только Instagram API with Instagram Login,
 *     и только для профессиональных аккаунтов (Business/Creator).
 *  2. Ссылки `media_url` с CDN инстаграма ПРОТУХАЮТ за часы. Поэтому при
 *     импорте картинка перезаливается к нам (`rehostToCDN`), и в акцию идёт
 *     постоянная ссылка. Положить в акцию ссылку инстаграма — значит получить
 *     каталог с битыми фото на следующий день, причём молча.
 *  3. Длинный токен живёт 60 дней и обновляется (`refreshInstagramTokens`).
 *     Обновить можно токен не моложе 24 часов и ещё не протухший — отсюда и
 *     окно обновления, и флаг `needsReauth` при провале.
 *  4. Scope `instagram_business_basic` требует App Review. До одобрения
 *     подключиться могут только аккаунты из ролей приложения Meta.
 *
 * Конфигурация: INSTAGRAM_APP_ID / INSTAGRAM_REDIRECT_URI / INSTAGRAM_RETURN_URL
 * в functions/.env, INSTAGRAM_APP_SECRET — в Secret Manager:
 *   firebase functions:secrets:set INSTAGRAM_APP_SECRET
 * ─────────────────────────────────────────────────────────────────────────── */

const IG_APP_SECRET = defineSecret("INSTAGRAM_APP_SECRET");
const IG_APP_ID = process.env.INSTAGRAM_APP_ID || "";
const IG_REDIRECT_URI = process.env.INSTAGRAM_REDIRECT_URI
  || `https://${REGION}-san-25d32.cloudfunctions.net/instagramAuthCallback`;
/**
 * Куда вернуть браузер после входа. Схема приложения (`san://`), а не https:
 * вход идёт в `ASWebAuthenticationSession`, и он ловит возврат именно по
 * схеме — так сессия закрывается сама и кабинет сразу знает результат.
 */
const IG_RETURN_URL = process.env.INSTAGRAM_RETURN_URL || "san://ig/connected";
const IG_SCOPES = "instagram_business_basic";
/** Тот же аккаунт Cloudinary, что и у iOS-приложения и админ-панели. */
const CLOUDINARY_CLOUD = process.env.CLOUDINARY_CLOUD_NAME || process.env.CLOUDINARY_CLOUD || "dsb14gwxw";
const CLOUDINARY_PRESET = process.env.CLOUDINARY_PRESET || "Ayant_ios";
/**
 * Подписанные загрузки (аудит запуска 2026-10-01). Неподписанный пресет
 * Cloudinary — публичный: любой, кто вытащил его имя из приложения, льёт
 * файлы на наш счёт. Подпись выдаёт сервер только настоящему пользователю.
 * Секрет — в Secret Manager:
 *   firebase functions:secrets:set CLOUDINARY_API_SECRET
 * ключ — CLOUDINARY_API_KEY в functions/.env. Пока их нет — 503 not_configured,
 * и клиент откатывается на неподписанный пресет.
 */
const CLOUDINARY_SECRET = defineSecret("CLOUDINARY_API_SECRET");
/** Папки, куда клиент вправе грузить (iOS: фото и документы — меню/прайсы). */
const CLOUDINARY_FOLDERS = new Set(["ayant/images", "ayant/documents"]);
/** Типы загрузки: `image` → /image/upload, `auto` (PDF меню) → /auto/upload. */
const CLOUDINARY_RESOURCE_TYPES = new Set(["image", "auto"]);

/** Ключ и секрет, если подписанные загрузки настроены; иначе null. */
function cloudinarySigning(): { apiKey: string; secret: string } | null {
  const apiKey = String(process.env.CLOUDINARY_API_KEY || "").trim();
  let secret = "";
  try { secret = String(CLOUDINARY_SECRET.value() || "").trim(); } catch { secret = ""; }
  return apiKey && secret ? { apiKey, secret } : null;
}

/**
 * Подпись Cloudinary: SHA-1 от параметров (кроме file/cloud_name/
 * resource_type/api_key), отсортированных по имени, `k=v` через `&`, плюс
 * секрет. Экспортирована для теста.
 */
export function cloudinarySignature(params: Record<string, string | number>, secret: string): string {
  const base = Object.keys(params).sort()
    .filter((k) => params[k] !== "" && params[k] !== undefined)
    .map((k) => `${k}=${params[k]}`).join("&");
  return crypto.createHash("sha1").update(base + secret).digest("hex");
}

/* POST /signCloudinaryUpload  body: { folder, resourceType: "image" | "auto" }
 * → { cloudName, apiKey, timestamp, signature, folder, resourceType }.
 * Клиент шлёт в Cloudinary (`/v1_1/<cloud>/<resourceType>/upload`) ровно эти
 * folder и timestamp + api_key и signature: подпись покрывает folder и
 * timestamp (Cloudinary принимает её час). Папки — закрытый список. */
export const signCloudinaryUpload = onRequest(
  { ...HTTP_OPTS, secrets: [CLOUDINARY_SECRET] },
  async (req, res) => {
    try {
      const uid = await requireRealUser(req, res, "signCloudinaryUpload");
      if (!uid) return;
      const folder = String((req.body && req.body.folder) || "").trim();
      const resourceType = String((req.body && req.body.resourceType) || "image").trim();
      if (!CLOUDINARY_FOLDERS.has(folder)) { res.status(400).json({ error: "bad_folder" }); return; }
      if (!CLOUDINARY_RESOURCE_TYPES.has(resourceType)) { res.status(400).json({ error: "bad_resource_type" }); return; }
      const signing = cloudinarySigning();
      if (!signing) { res.status(503).json({ error: "not_configured" }); return; }
      const timestamp = Math.floor(Date.now() / 1000);
      const signature = cloudinarySignature({ folder, timestamp }, signing.secret);
      res.status(200).json({
        ok: true, cloudName: CLOUDINARY_CLOUD, apiKey: signing.apiKey,
        timestamp, signature, folder, resourceType,
      });
    } catch (e) {
      console.error("signCloudinaryUpload error:", e);
      res.status(500).json({ error: "sign_failed" });
    }
  });
/** Сколько постов отдаём за одну синхронизацию и сколько фото тянем из карусели. */
const IG_MEDIA_LIMIT = 25;
const IG_CAROUSEL_LIMIT = 5;
/** Жизнь одноразового `state` OAuth. */
const IG_STATE_TTL_MS = 10 * 60 * 1000;
/** За сколько до протухания обновляем токен. */
const IG_REFRESH_WINDOW_MS = 10 * 24 * 60 * 60 * 1000;

const igOptions = { cors: true, secrets: [IG_APP_SECRET], maxInstances: 10 };

function igDocID(ownerID: string, venueID: string): string { return `${ownerID}_${venueID}`; }

/**
 * Хост + его заведение по запросу. Возвращает null, ОТВЕТИВ клиенту, — вызов
 * после этого должен просто выйти. Один и тот же порядок проверок, что и в
 * `scanCoupon`: метод → App Check → токен → владение заведением.
 */
async function igRequireOwner(
  req: { method: string; get: (h: string) => string | undefined; body?: Record<string, unknown> },
  res: { status: (c: number) => { json: (b: unknown) => void } },
  label: string,
): Promise<{ uid: string; venueID: string } | null> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return null; }
  if (!(await checkAppCheck(req, label))) { res.status(401).json({ error: "app_check_failed" }); return null; }
  const uid = await verifyBearer(req);
  if (!uid) { res.status(401).json({ error: "bad_token" }); return null; }
  const venueID = String((req.body && req.body.venueID) || "").trim();
  if (!venueID) { res.status(400).json({ error: "missing_params" }); return null; }
  const snap = await db.collection("venues").doc(venueID).get();
  if (!snap.exists) { res.status(404).json({ error: "venue_not_found" }); return null; }
  if (String((snap.data() as VenueDoc).ownerID || "") !== uid) {
    res.status(403).json({ error: "not_owner" }); return null;
  }
  return { uid, venueID };
}

/** Токен заведения. null — аккаунт не подключён либо требует повторного входа. */
async function igLoadToken(ownerID: string, venueID: string): Promise<string | null> {
  const snap = await db.collection("igAccounts").doc(igDocID(ownerID, venueID)).get();
  if (!snap.exists) return null;
  const acc = snap.data() as IgAccountDoc;
  if (acc.needsReauth === true) return null;
  return String(acc.accessToken || "") || null;
}

/**
 * Токен больше не принимают. Помечаем оба документа, чтобы кабинет показал
 * «войдите заново», а не молча пустой список — молчание тут читается как
 * «постов нет», и хост идёт жаловаться, что интеграция «не работает».
 */
async function igMarkReauth(ownerID: string, venueID: string): Promise<void> {
  const id = igDocID(ownerID, venueID);
  await Promise.all([
    db.collection("igAccounts").doc(id).set({ needsReauth: true }, { merge: true }),
    db.collection("igConnections").doc(id).set({ needsReauth: true }, { merge: true }),
  ]).catch((e) => console.warn("⚠️ ig reauth flag failed", e));
}

/**
 * Ответ обмена `code` на короткий токен. Instagram Login отдаёт его ЗАВЁРНУТЫМ
 * в массив (`{"data":[{access_token, user_id, permissions}]}`), а старый Basic
 * Display отдавал те же поля плоско. Разбираем оба вида: угадать «тот самый»
 * по документации нельзя — он уже менялся, а цена ошибки здесь равна
 * «подключение не работает вообще», причём только на живом аккаунте.
 */
function igShortToken(payload: unknown): { access_token?: string; user_id?: string | number } {
  const p = payload as {
    access_token?: string;
    user_id?: string | number;
    data?: Array<{ access_token?: string; user_id?: string | number }>;
  };
  const first = Array.isArray(p?.data) ? p.data[0] : undefined;
  return {
    access_token: p?.access_token || first?.access_token,
    user_id: p?.user_id ?? first?.user_id,
  };
}

/** Ошибка протухшего/отозванного токена в Graph API. */
function igIsAuthError(payload: unknown): boolean {
  const err = (payload as { error?: { code?: number; type?: string } })?.error;
  return !!err && (err.code === 190 || err.code === 104 || err.type === "OAuthException");
}

/**
 * Перезаливает картинку по внешней ссылке на наш CDN и возвращает постоянный
 * URL. Cloudinary скачивает файл сам — байты через функцию не идут.
 */
async function rehostToCDN(remoteURL: string): Promise<string | null> {
  try {
    // Подписанная загрузка, если настроена; иначе — прежний неподписанный пресет.
    const signing = cloudinarySigning();
    let body: URLSearchParams;
    if (signing) {
      const timestamp = Math.floor(Date.now() / 1000);
      const signed = { folder: "instagram", timestamp };
      body = new URLSearchParams({
        file: remoteURL, folder: "instagram", timestamp: String(timestamp),
        api_key: signing.apiKey, signature: cloudinarySignature(signed, signing.secret),
      });
    } else {
      body = new URLSearchParams({
        file: remoteURL,
        upload_preset: CLOUDINARY_PRESET,
        folder: "instagram",
      });
    }
    const r = await fetch(`https://api.cloudinary.com/v1_1/${CLOUDINARY_CLOUD}/image/upload`,
      { method: "POST", body });
    const j = (await r.json()) as { secure_url?: string };
    return j.secure_url || null;
  } catch (e) {
    console.warn("⚠️ cloudinary rehost failed", e);
    return null;
  }
}

/** Сырой ответ Graph API по медиа. */
interface IgMediaNode {
  id?: string;
  caption?: string;
  media_type?: string;
  media_url?: string;
  thumbnail_url?: string;
  permalink?: string;
  timestamp?: string;
  children?: { data?: IgMediaNode[] };
}

const IG_MEDIA_FIELDS =
  "id,caption,media_type,media_url,thumbnail_url,permalink,timestamp," +
  "children{id,media_type,media_url,thumbnail_url}";

/** Картинки поста: для видео — обложка, для карусели — кадры детей. */
function igImages(node: IgMediaNode): string[] {
  const kids = node.children?.data || [];
  if (kids.length) {
    return kids
      .map((k) => (String(k.media_type || "").toUpperCase() === "VIDEO" ? k.thumbnail_url : k.media_url))
      .filter((u): u is string => !!u)
      .slice(0, IG_CAROUSEL_LIMIT);
  }
  const single = String(node.media_type || "").toUpperCase() === "VIDEO"
    ? node.thumbnail_url : node.media_url;
  return single ? [single] : [];
}

/** Пост наружу — без единого поля, которого клиенту знать не нужно. */
function igPublicPost(node: IgMediaNode): Record<string, unknown> {
  const images = igImages(node);
  return {
    id: String(node.id || ""),
    caption: String(node.caption || ""),
    mediaType: String(node.media_type || "IMAGE"),
    previewURL: images[0] || "",
    imageURLs: images,
    permalink: String(node.permalink || ""),
    timestamp: String(node.timestamp || ""),
  };
}

/* ── Шаг 1: ссылка входа ──────────────────────────────────────────────────
 * `state` одноразовый и лежит в Firestore: без него callback нельзя отличить
 * от подделанного, и чужой аккаунт можно было бы привязать к чужому заведению.
 */
export const instagramAuthStart = onRequest(igOptions, async (req, res) => {
  try {
    const owner = await igRequireOwner(req, res, "instagramAuthStart");
    if (!owner) return;
    if (!IG_APP_ID) { res.status(500).json({ error: "not_configured" }); return; }

    const nonce = crypto.randomBytes(24).toString("hex");
    await db.collection("igAuthStates").doc(nonce).set({
      ownerID: owner.uid, venueID: owner.venueID, createdAt: new Date(),
    });

    // `force_reauth=1` — не «лишняя строгость», а защита от привязки НЕ ТОГО
    // аккаунта. Без него Instagram молча берёт сессию, уже открытую в браузере:
    // у владельца заведения это чаще личный профиль, а не профиль кафе. Ошибку
    // видно не сразу — она всплывает постами из чужого инстаграма в ленте
    // заведения, и чинится только переподключением.
    const authURL = "https://www.instagram.com/oauth/authorize?" + new URLSearchParams({
      client_id: IG_APP_ID,
      redirect_uri: IG_REDIRECT_URI,
      response_type: "code",
      scope: IG_SCOPES,
      state: nonce,
      force_reauth: "1",
    }).toString();
    res.status(200).json({ authURL });
  } catch (e) {
    console.error("instagramAuthStart", e);
    res.status(500).json({ error: "internal" });
  }
});

/* ── Шаг 2: возврат из Instagram ──────────────────────────────────────────
 * Публичная точка (сюда редиректит Meta). Всё доверие — в одноразовом
 * `state`: он и говорит, чьё это заведение.
 */
export const instagramAuthCallback = onRequest(
  { cors: false, secrets: [IG_APP_SECRET], maxInstances: 10 },
  async (req, res) => {
    const back = (status: string, venueID = "") =>
      res.redirect(302, `${IG_RETURN_URL}?status=${encodeURIComponent(status)}`
        + (venueID ? `&venue=${encodeURIComponent(venueID)}` : ""));
    try {
      const code = String(req.query.code || "");
      const state = String(req.query.state || "");
      if (req.query.error || !code || !state) { back("denied"); return; }

      const stateRef = db.collection("igAuthStates").doc(state);
      const stateSnap = await stateRef.get();
      if (!stateSnap.exists) { back("bad_state"); return; }
      const st = stateSnap.data() as IgAuthStateDoc;
      await stateRef.delete().catch(() => undefined);   // одноразовый
      if (Date.now() - toMillis(st.createdAt) > IG_STATE_TTL_MS) { back("expired_state"); return; }

      const ownerID = String(st.ownerID || ""), venueID = String(st.venueID || "");
      if (!ownerID || !venueID) { back("bad_state"); return; }

      // code → короткий токен
      const shortRes = await fetch("https://api.instagram.com/oauth/access_token", {
        method: "POST",
        body: new URLSearchParams({
          client_id: IG_APP_ID,
          client_secret: IG_APP_SECRET.value(),
          grant_type: "authorization_code",
          redirect_uri: IG_REDIRECT_URI,
          code,
        }),
      });
      const short = igShortToken(await shortRes.json());
      if (!short.access_token) { console.warn("ig: short token failed", short); back("auth_failed"); return; }

      // короткий → длинный (60 дней)
      const longRes = await fetch("https://graph.instagram.com/access_token?" + new URLSearchParams({
        grant_type: "ig_exchange_token",
        client_secret: IG_APP_SECRET.value(),
        access_token: short.access_token,
      }).toString());
      const long = (await longRes.json()) as { access_token?: string; expires_in?: number };
      const token = long.access_token || short.access_token;
      const ttlSec = Number(long.expires_in || 0) || 60 * 24 * 3600;

      const meRes = await fetch("https://graph.instagram.com/me?" + new URLSearchParams({
        fields: "id,username",
        access_token: token,
      }).toString());
      const me = (await meRes.json()) as { id?: string; username?: string };

      const now = new Date();
      const id = igDocID(ownerID, venueID);
      await db.collection("igAccounts").doc(id).set({
        ownerID, venueID,
        // Именно `user_id` из обмена кода, а не `id` из /me: в колбэк
        // деавторизации Meta присылает первый, и по нему мы ищем подключение.
        igUserID: String(short.user_id || me.id || ""),
        username: String(me.username || ""),
        accessToken: token,
        tokenExpiresAt: new Date(now.getTime() + ttlSec * 1000),
        lastRefreshAt: now,
        connectedAt: now,
        needsReauth: false,
      }, { merge: true });
      await db.collection("igConnections").doc(id).set({
        ownerID, venueID,
        username: String(me.username || ""),
        connectedAt: now,
        needsReauth: false,
      }, { merge: true });

      back("ok", venueID);
    } catch (e) {
      console.error("instagramAuthCallback", e);
      back("internal");
    }
  });

/* ── Кнопка «Синхронизировать»: последние посты ─────────────────────────── */
export const instagramMedia = onRequest(igOptions, async (req, res) => {
  try {
    const owner = await igRequireOwner(req, res, "instagramMedia");
    if (!owner) return;
    const token = await igLoadToken(owner.uid, owner.venueID);
    if (!token) { res.status(409).json({ error: "not_connected" }); return; }

    const limit = Math.min(Math.max(parseInt(String(req.body?.limit ?? ""), 10) || IG_MEDIA_LIMIT, 1),
      IG_MEDIA_LIMIT);
    const r = await fetch("https://graph.instagram.com/me/media?" + new URLSearchParams({
      fields: IG_MEDIA_FIELDS, limit: String(limit), access_token: token,
    }).toString());
    const payload = (await r.json()) as { data?: IgMediaNode[]; error?: unknown };
    if (igIsAuthError(payload)) {
      await igMarkReauth(owner.uid, owner.venueID);
      res.status(409).json({ error: "reauth_required" }); return;
    }
    if (!r.ok || !payload.data) { res.status(502).json({ error: "instagram_unavailable" }); return; }

    await db.collection("igConnections").doc(igDocID(owner.uid, owner.venueID))
      .set({ lastSyncAt: new Date() }, { merge: true }).catch(() => undefined);

    res.status(200).json({ posts: payload.data.map(igPublicPost) });
  } catch (e) {
    console.error("instagramMedia", e);
    res.status(500).json({ error: "internal" });
  }
});

/* ── Импорт поста: фото переезжают на наш CDN ─────────────────────────────
 * Саму акцию создаёт клиент обычным путём (`HostRepository.saveDeal`) — так
 * импорт не проходит мимо модерации и правил владения.
 */
export const instagramImportMedia = onRequest({ ...igOptions, secrets: [IG_APP_SECRET, CLOUDINARY_SECRET] }, async (req, res) => {
  try {
    const owner = await igRequireOwner(req, res, "instagramImportMedia");
    if (!owner) return;
    const postID = String(req.body?.postID || "").trim();
    if (!postID) { res.status(400).json({ error: "missing_params" }); return; }
    const token = await igLoadToken(owner.uid, owner.venueID);
    if (!token) { res.status(409).json({ error: "not_connected" }); return; }

    // Токен принадлежит аккаунту заведения — Graph отдаст чужой пост только
    // как ошибку, поэтому отдельной проверки владения постом не нужно.
    const r = await fetch(`https://graph.instagram.com/${encodeURIComponent(postID)}?`
      + new URLSearchParams({ fields: IG_MEDIA_FIELDS, access_token: token }).toString());
    const node = (await r.json()) as IgMediaNode & { error?: unknown };
    if (igIsAuthError(node)) {
      await igMarkReauth(owner.uid, owner.venueID);
      res.status(409).json({ error: "reauth_required" }); return;
    }
    if (!r.ok || !node.id) { res.status(404).json({ error: "post_not_found" }); return; }

    const sources = igImages(node);
    if (!sources.length) { res.status(409).json({ error: "no_image" }); return; }
    const hosted = (await Promise.all(sources.map(rehostToCDN))).filter((u): u is string => !!u);
    if (!hosted.length) { res.status(502).json({ error: "upload_failed" }); return; }

    res.status(200).json({
      postID: String(node.id),
      imageURLs: hosted,
      caption: String(node.caption || ""),
      permalink: String(node.permalink || ""),
    });
  } catch (e) {
    console.error("instagramImportMedia", e);
    res.status(500).json({ error: "internal" });
  }
});

/* ── Отключение аккаунта хостом ──────────────────────────────────────────── */
export const instagramDisconnect = onRequest(igOptions, async (req, res) => {
  try {
    const owner = await igRequireOwner(req, res, "instagramDisconnect");
    if (!owner) return;
    const id = igDocID(owner.uid, owner.venueID);
    await Promise.all([
      db.collection("igAccounts").doc(id).delete(),
      db.collection("igConnections").doc(id).delete(),
    ]);
    res.status(200).json({ ok: true });
  } catch (e) {
    console.error("instagramDisconnect", e);
    res.status(500).json({ error: "internal" });
  }
});

/* ── Продление токенов ────────────────────────────────────────────────────
 * Длинный токен живёт 60 дней. Обновляем всё, чему осталось меньше 10 дней:
 * запас на случай, если прогон не отработает пару раз подряд.
 */
export const refreshInstagramTokens = onSchedule(
  { schedule: "every 24 hours", secrets: [IG_APP_SECRET] },
  async () => {
    const deadline = new Date(Date.now() + IG_REFRESH_WINDOW_MS);
    const snap = await db.collection("igAccounts")
      .where("tokenExpiresAt", "<", deadline).limit(200).get();
    let ok = 0, failed = 0;
    for (const doc of snap.docs) {
      const acc = doc.data() as IgAccountDoc;
      if (acc.needsReauth === true || !acc.accessToken) continue;
      try {
        const r = await fetch("https://graph.instagram.com/refresh_access_token?"
          + new URLSearchParams({
            grant_type: "ig_refresh_token", access_token: String(acc.accessToken),
          }).toString());
        const j = (await r.json()) as { access_token?: string; expires_in?: number };
        if (!r.ok || !j.access_token) throw new Error(JSON.stringify(j).slice(0, 200));
        const now = new Date();
        await doc.ref.set({
          accessToken: j.access_token,
          tokenExpiresAt: new Date(now.getTime() + (Number(j.expires_in) || 60 * 24 * 3600) * 1000),
          lastRefreshAt: now,
          needsReauth: false,
        }, { merge: true });
        ok++;
      } catch (e) {
        failed++;
        console.warn(`⚠️ ig refresh failed for ${doc.id}`, e);
        await igMarkReauth(String(acc.ownerID || ""), String(acc.venueID || ""));
      }
    }
    console.log(`ig refresh: ok=${ok} failed=${failed} of ${snap.size}`);
  });

/* ── Обязательные для App Review точки Meta ───────────────────────────────
 * Deauthorize вызывается, когда пользователь отключает приложение у себя в
 * инстаграме, Data Deletion — когда просит удалить данные. Оба приходят с
 * `signed_request`, подписанным секретом приложения.
 */
function igParseSignedRequest(signed: string, secret: string): { user_id?: string } | null {
  const [sigPart, payloadPart] = String(signed).split(".");
  if (!sigPart || !payloadPart) return null;
  const expected = crypto.createHmac("sha256", secret).update(payloadPart).digest();
  const given = Buffer.from(sigPart.replace(/-/g, "+").replace(/_/g, "/"), "base64");
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
  try {
    return JSON.parse(Buffer.from(payloadPart.replace(/-/g, "+").replace(/_/g, "/"), "base64")
      .toString("utf8"));
  } catch { return null; }
}

/** Удаляет все подключения инстаграм-пользователя. Возвращает число удалённых. */
async function igPurgeUser(igUserID: string): Promise<number> {
  const snap = await db.collection("igAccounts").where("igUserID", "==", igUserID).get();
  const refs: DocumentReference[] = [];
  for (const d of snap.docs) {
    refs.push(d.ref);
    refs.push(db.collection("igConnections").doc(d.id));
  }
  await deleteInChunks(refs);
  return snap.size;
}

export const instagramDeauthorize = onRequest(igOptions, async (req, res) => {
  const parsed = igParseSignedRequest(String(req.body?.signed_request || ""), IG_APP_SECRET.value());
  if (!parsed?.user_id) { res.status(400).json({ error: "bad_signature" }); return; }
  const n = await igPurgeUser(String(parsed.user_id));
  console.log(`ig deauthorize: purged ${n} connection(s)`);
  res.status(200).json({ ok: true });
});

export const instagramDataDeletion = onRequest(igOptions, async (req, res) => {
  const parsed = igParseSignedRequest(String(req.body?.signed_request || ""), IG_APP_SECRET.value());
  if (!parsed?.user_id) { res.status(400).json({ error: "bad_signature" }); return; }
  const userID = String(parsed.user_id);
  const n = await igPurgeUser(userID);
  console.log(`ig data deletion: purged ${n} connection(s)`);
  // Формат ответа задан Meta: страница статуса + код обращения.
  const code = crypto.createHash("sha256").update(userID).digest("hex").slice(0, 16);
  res.status(200).json({ url: `https://ayant.kg/ig/deletion?code=${code}`, confirmation_code: code });
});

/* ───────────────────────────────────────────────────────────────────────────
 * 9) ГЛОБАЛЬНЫЙ КОШЕЛЁК БОНУСОВ — на сервере.
 *
 *    Раньше баланс жил только на телефоне (`@AppStorage("san.bonus.balance")`).
 *    Пока бонусы покупали награды, которые нельзя погасить, это ничего не
 *    стоило; с купонами заведений, которые отдаются по-настоящему, число на
 *    телефоне стало генератором бесплатного кофе. Теперь источник правды —
 *    `bonusWallets/{uid}` (читает только владелец, пишут только функции):
 *
 *    • bonusWalletSync — один раз переносит баланс с устройства (с потолком
 *      BONUS_MIGRATION_CAP) и зачисляет незабранные `bonusGrants` (рефералка).
 *    • earnBonus — начисление за игры и время в приложении. Проверить игру
 *      сервер не может, поэтому держит потолки: за вызов и за сутки.
 *    • buyCoupon — покупка купона заведения (`couponOffers`) или награды из
 *      каталога (`config/globalRewards`), в том числе подарком. Одна
 *      транзакция: доступность → баланс → списание → soldCount → купон.
 *
 *    Все три идемпотентны по ключу клиента — как scanCoupon/redeemVenuePoints:
 *    повтор с тем же ключом возвращает исходный ответ, не начисляя/не списывая
 *    второй раз; тот же ключ на другую покупку — 409 key_reused.
 * ─────────────────────────────────────────────────────────────────────────── */

// Потолок одного начисления: самая щедрая партия (2048 до 2048, долгая Змейка)
// приносит десятки бонусов, не сотни.
const BONUS_EARN_MAX_PER_CALL = 100;
// Потолок в сутки на пользователя по всем источникам. Дневного лимита у игр
// нет по решению владельца (2026-09-22) — но это лимит для ЧЕЛОВЕКА. Сервер не
// видит игру, только сумму, поэтому этот потолок — всё, что отделяет скрипт с
// настоящим аккаунтом от денег заведения. Было 1000 (~16 ч игры): по аудиту
// 2026-10-01 это три купона в день с каждого аккаунта-фермы. 200 при
// GameEconomy.minutesPerBonus = 1 — больше трёх часов игры: живой игрок не
// упирается, ферма зарабатывает впятеро меньше.
const BONUS_DAILY_EARN_CAP = clampedCapFromEnv(process.env.BONUS_DAILY_EARN_CAP, 200, 0, 2000);
// Сколько баланса с устройства сервер принимает на веру при переносе. Число на
// телефоне ничем не подтверждено — поправленное вручную «99999» не должно
// стать настоящими деньгами.
// Прижат к [0, 5000]: «BONUS_MIGRATION_CAP=100000» не должен стать переносом
// без потолка.
const BONUS_MIGRATION_CAP = clampedCapFromEnv(process.env.BONUS_MIGRATION_CAP, 1000, 0, 5000);
// Перенос баланса устройства — только для аккаунтов, созданных ДО серверного
// кошелька. Иначе каждый новый аккаунт приносил бы BONUS_MIGRATION_CAP бонусов
// одним вызовом — фабрика бонусов из регистраций.
const BONUS_MIGRATION_CUTOFF_MS = Date.parse(
  process.env.BONUS_MIGRATION_CUTOFF || "2026-10-01T00:00:00+06:00");
// Подтверждение почты для денег (аудит запуска 2026-10-01): аккаунт с почтой
// и паролем, созданный после этой даты, без подтверждённой почты не получает и
// не тратит бонусы (403 email_not_verified) и не приносит реферальную награду.
// Регистрация на чужую/одноразовую почту — бесплатная ферма аккаунтов.
// Apple/Google подтверждают почту сами. Старые аккаунты не трогаем.
const BONUS_VERIFY_CUTOFF_MS = Date.parse(
  process.env.BONUS_VERIFY_CUTOFF || "2026-10-02T00:00:00+06:00");
// Источники начисления — закрытый список. Раньше принимался любой
// «game:<id>», и потолок Diamond обходился сменой подписи: «game:diamond»
// упёрся в 30 — шлём «game:snake» или «game:x». Новая игра = новая строка здесь
// (иначе её начисления получат 400 bad_source, и клиент их выбросит).
// «game» без id — очередь начислений старых сборок.
const BONUS_EARN_SOURCES = new Set([
  "time", "game", "game:snake", "game:tetris", "game:2048", "game:diamond",
]);
// Дневные потолки отдельных источников — зеркало клиентских правил, которым
// сервер не может верить на слово. Общий BONUS_DAILY_EARN_CAP действует поверх
// них: сумма источников его не превышает.
//  • «time» — BonusEngine.rewardPerGoal (1) × dailyGoalCap (4): время в
//    приложении приносит не больше 4 в сутки. Без этой строки «time» был
//    самым дешёвым путём к общему потолку.
//  • «game:diamond» (бывшая «Три в ряд») бесконечна и платит не больше
//    GameEconomy.endlessDailyBonusCap в сутки.
// Потолок «time» — env BONUS_TIME_DAILY_CAP: курс времени настраивается в
// Remote Config (ios_bonus_time_reward × ios_bonus_time_goals_per_day), и
// поднять его без этого env нельзя — сервер зачислит не больше.
// Потолок Diamond — env BONUS_DIAMOND_DAILY_CAP (по умолчанию 30, как
// GameEconomy.endlessDailyBonusCap и Remote Config ios_bonus_diamond_daily_cap).
// Все env-потолки прижаты сверху: time ≤ 100, diamond ≤ 500.
const BONUS_SOURCE_DAILY_CAPS: Record<string, number> = {
  "time": clampedCapFromEnv(process.env.BONUS_TIME_DAILY_CAP, 4, 0, 100),
  "game:diamond": clampedCapFromEnv(process.env.BONUS_DIAMOND_DAILY_CAP, 30, 0, 500),
};

/** Чей потолок урезал начисление `earnBonus`; `null` — не урезано. */
type EarnCapReason = "daily" | "source" | "per_call" | null;

/**
 * Какой потолок оказался связывающим. При равенстве побеждает более строгий:
 * общий дневной (сегодня не платит ничего) → источника → за вызов.
 */
export function earnCapReason(amount: number, granted: number, dailyLeft: number, sourceLeft: number): EarnCapReason {
  if (granted >= amount) return null;
  if (dailyLeft <= granted) return "daily";
  if (sourceLeft <= granted) return "source";
  return "per_call";
}

function earnCapReasonOf(raw: unknown): EarnCapReason {
  return raw === "daily" || raw === "source" || raw === "per_call" ? raw : null;
}

/** Сутки кошелька — по Бишкеку: «сегодня» у гостя, а не у сервера в США. */
function bishkekDayKey(ms: number): string {
  return new Date(ms + 6 * 3600000).toISOString().slice(0, 10);   // UTC+6, без перехода на летнее
}

/** uid из Bearer-токена или ответ 401. Общий вход для трёх функций кошелька. */
async function walletUser(req: any, res: any, label: string): Promise<string | null> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return null; }
  if (!(await checkAppCheck(req, label))) { res.status(401).json({ error: "app_check_failed" }); return null; }
  const authz = String(req.get("Authorization") || "");
  const idToken = authz.startsWith("Bearer ") ? authz.slice(7) : "";
  if (!idToken) { res.status(401).json({ error: "no_token" }); return null; }
  let decoded: any;
  try { decoded = await getAuth().verifyIdToken(idToken); }
  catch { res.status(401).json({ error: "bad_token" }); return null; }
  // Анонимный вход доступен любому скрипту (ключ веб-API публичный): кошелёк
  // на таком аккаунте — это бонусы без человека. Приложение гостям кошелёк и
  // так не даёт; здесь то же правило, но уже для всех.
  if (decoded && decoded.firebase && decoded.firebase.sign_in_provider === "anonymous") {
    res.status(403).json({ error: "anonymous_not_allowed" }); return null;
  }
  if (await emailNotVerified(decoded)) {
    res.status(403).json({ error: "email_not_verified" }); return null;
  }
  return String(decoded.uid);
}

/**
 * Вход почтой и паролем, почта не подтверждена, аккаунт новее
 * BONUS_VERIFY_CUTOFF. Флаг в ID-токене может отставать (подтвердил почту, а
 * токен старый), поэтому при `false` перепроверяем по записи Auth.
 */
async function emailNotVerified(decoded: any): Promise<boolean> {
  if (!decoded || !decoded.firebase || decoded.firebase.sign_in_provider !== "password") return false;
  if (decoded.email_verified === true) return false;
  try {
    const user = await getAuth().getUser(String(decoded.uid));
    if (user.emailVerified === true) return false;
    const created = Date.parse(String(user.metadata && user.metadata.creationTime));
    return !Number.isFinite(created) || created >= BONUS_VERIFY_CUTOFF_MS;
  } catch { return true; }
}

/** Создан ли аккаунт до серверного кошелька (право на перенос баланса). */
async function createdBeforeWallet(uid: string): Promise<boolean> {
  try {
    const user = await getAuth().getUser(uid);
    const created = Date.parse(String(user.metadata && user.metadata.creationTime));
    return Number.isFinite(created) && created < BONUS_MIGRATION_CUTOFF_MS;
  } catch { return false; }
}

function walletKey(req: any): string {
  return String((req.body && req.body.idempotencyKey) || "").trim().slice(0, 128);
}

function intOf(v: unknown): number { return parseInt(String(v), 10) || 0; }

/** Код подарка: «GIFT-» + 8 символов без похожих (0/O, 1/I). */
function newGiftCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let s = "";
  for (const b of crypto.randomBytes(8)) s += alphabet[b % alphabet.length];
  return `GIFT-${s}`;
}

export const bonusWalletSync = onRequest(MONEY_PATH_OPTS, async (req, res) => {
  try {
    const uid = await walletUser(req, res, "bonusWalletSync");
    if (!uid) return;
    // Реферал, отложенный до подтверждения почты: сюда доходит только
    // подтверждённый аккаунт (walletUser), значит, его пора довести.
    try {
      const refSnap = await db.collection("referrals").doc(uid).get();
      const rd = refSnap.exists ? (refSnap.data() || {}) : null;
      if (rd && rd.pendingVerification === true && !rd.rewarded) await processReferral(refSnap.ref, uid, rd);
    } catch (e) { console.warn("pending referral failed", e); }
    const eligible = await createdBeforeWallet(uid);
    const localBalance = eligible ? Math.max(0, intOf(req.body && req.body.localBalance)) : 0;
    const walletRef = db.collection("bonusWallets").doc(uid);

    // Незабранные награды (рефералка) — запросом ВНЕ транзакции (в ней нет
    // запросов), а внутри каждую перечитываем: забранную параллельно не
    // зачислим второй раз.
    const grantsSnap = await db.collection("bonusGrants").where("userID", "==", uid).get();
    const grantRefs = grantsSnap.docs
      .filter((d) => (d.data() || {}).claimed !== true)
      .map((d) => d.ref);

    let balance = 0;
    let migrated = 0;
    let granted = 0;
    await db.runTransaction(async (tx) => {
      const walletSnap = await tx.get(walletRef);
      const grants = await Promise.all(grantRefs.map((r) => tx.get(r)));
      const cur = walletSnap.exists ? (walletSnap.data() || {}) : null;
      balance = cur ? intOf(cur.balance) : 0;
      let lifetimeEarned = cur ? intOf(cur.lifetimeEarned) : 0;
      const now = new Date();

      if (!cur) {
        // Первый вход с серверным кошельком: переносим то, что было на телефоне.
        migrated = Math.min(localBalance, BONUS_MIGRATION_CAP);
        balance += migrated;
        lifetimeEarned += migrated;
        if (migrated > 0) {
          tx.set(walletRef.collection("ledger").doc(), {
            type: "migrate", amount: migrated, claimed: localBalance, at: now,
          });
        }
      }
      for (const g of grants) {
        const d = g.data() || {};
        if (!g.exists || d.claimed === true) continue;
        const amount = Math.max(0, intOf(d.amount));
        granted += amount;
        tx.set(g.ref, { claimed: true, claimedAt: now, claimedBy: "wallet" }, { merge: true });
        tx.set(walletRef.collection("ledger").doc(), {
          type: "grant", amount, reason: String(d.reason || ""), grantID: g.ref.id, at: now,
        });
      }
      balance += granted;
      lifetimeEarned += granted;
      tx.set(walletRef, {
        balance, lifetimeEarned,
        lifetimeSpent: cur ? intOf(cur.lifetimeSpent) : 0,
        ...(cur ? {} : { createdAt: now }),
        updatedAt: now,
      }, { merge: true });
    });
    res.status(200).json({ ok: true, balance, migrated, granted });
  } catch (e: any) {
    console.error("bonusWalletSync error:", e);
    res.status(500).json({ error: "sync_failed" });
  }
});

export const earnBonus = onRequest(MONEY_PATH_OPTS, async (req, res) => {
  try {
    const uid = await walletUser(req, res, "earnBonus");
    if (!uid) return;
    const amount = intOf(req.body && req.body.amount);
    const source = String((req.body && req.body.source) || "").trim();
    const key = walletKey(req);
    if (!key) { res.status(400).json({ error: "missing_key" }); return; }
    if (amount <= 0) { res.status(400).json({ error: "bad_amount" }); return; }
    if (!BONUS_EARN_SOURCES.has(source)) { res.status(400).json({ error: "bad_source" }); return; }

    const walletRef = db.collection("bonusWallets").doc(uid);
    const keyRef = walletRef.collection("earnKeys").doc(key);
    const nowMs = Date.now();
    const day = bishkekDayKey(nowMs);

    let granted = 0;
    let balance = 0;
    let replayed = false;
    let capReason: EarnCapReason = null;
    let dailyLeft = 0;
    let sourceLeftAfter: number | null = null;
    const sourceCap = BONUS_SOURCE_DAILY_CAPS[source];
    await db.runTransaction(async (tx) => {
      const prior = await tx.get(keyRef);
      const walletSnap = await tx.get(walletRef);
      if (prior.exists) {
        const p = prior.data() || {};
        if (intOf(p.requested) !== amount || String(p.source || "") !== source) throw new Error("key_reused");
        granted = intOf(p.granted);
        const w = walletSnap.data() || {};
        balance = intOf(w.balance);
        // Причина — из записи ключа (её не пересчитать задним числом); остатки —
        // текущие: клиенту важно, что можно заработать сейчас.
        capReason = earnCapReasonOf(p.capReason);
        const wSameDay = String(w.earnDay || "") === day;
        dailyLeft = Math.max(0, BONUS_DAILY_EARN_CAP - (wSameDay ? intOf(w.earnedToday) : 0));
        sourceLeftAfter = sourceCap === undefined ? null
          : Math.max(0, sourceCap - (wSameDay && w.earnedBySource ? intOf(w.earnedBySource[source]) : 0));
        replayed = true;
        return;
      }
      // Кошелёк заводит bonusWalletSync: начисление раньше переноса затёрло бы
      // баланс устройства нулём. Клиент держит начисление в очереди и повторит.
      if (!walletSnap.exists) throw new Error("no_wallet");
      const cur = walletSnap.data() || {};
      const sameDay = String(cur.earnDay || "") === day;
      const earnedToday = sameDay ? intOf(cur.earnedToday) : 0;
      const bySource: Record<string, number> = sameDay && cur.earnedBySource ? { ...cur.earnedBySource } : {};
      const sourceLeft = sourceCap === undefined ? Infinity : sourceCap - intOf(bySource[source]);
      const dailyLeftBefore = BONUS_DAILY_EARN_CAP - earnedToday;
      granted = Math.max(0, Math.min(amount, BONUS_EARN_MAX_PER_CALL, dailyLeftBefore, sourceLeft));
      capReason = earnCapReason(amount, granted, dailyLeftBefore, sourceLeft);
      dailyLeft = Math.max(0, dailyLeftBefore - granted);
      sourceLeftAfter = sourceCap === undefined ? null : Math.max(0, sourceLeft - granted);
      bySource[source] = intOf(bySource[source]) + granted;
      balance = intOf(cur.balance) + granted;
      const now = new Date(nowMs);
      tx.set(walletRef, {
        balance,
        lifetimeEarned: intOf(cur.lifetimeEarned) + granted,
        earnDay: day, earnedToday: earnedToday + granted, earnedBySource: bySource,
        updatedAt: now,
      }, { merge: true });
      if (granted > 0) {
        tx.set(walletRef.collection("ledger").doc(), {
          type: "earn", amount: granted, requested: amount, source, at: now,
        });
      }
      tx.set(keyRef, { requested: amount, source, granted, capReason, at: now });
    });
    // `granted` может быть меньше запрошенного (потолок) — клиент показывает его.
    // `capReason` говорит, ЧЕЙ потолок урезал: общий («daily») — сегодня не
    // платит ничто; источника («source») — только эта игра/время; «per_call» —
    // не потолок дня, просто слишком крупный вызов. Клиент не гадает.
    res.status(200).json({ ok: true, granted, balance, replayed, capReason, dailyLeft, sourceLeft: sourceLeftAfter });
  } catch (e: any) {
    const m = String(e.message);
    if (m === "key_reused" || m === "no_wallet") { res.status(409).json({ error: m }); return; }
    console.error("earnBonus error:", e);
    res.status(500).json({ error: "earn_failed" });
  }
});

export const buyCoupon = onRequest(MONEY_PATH_OPTS, async (req, res) => {
  try {
    const uid = await walletUser(req, res, "buyCoupon");
    if (!uid) return;
    const offerID = String((req.body && req.body.offerID) || "").trim();
    const rewardID = String((req.body && req.body.rewardID) || "").trim();
    const asGift = req.body && req.body.asGift === true;
    const fromName = String((req.body && req.body.fromName) || "").trim().slice(0, 80);
    const key = walletKey(req);
    if (!key) { res.status(400).json({ error: "missing_key" }); return; }
    if (!offerID === !rewardID) { res.status(400).json({ error: "missing_params" }); return; }
    // Подарок — только награда каталога: купон заведения привязан к гостю,
    // который его купил, передавать его — значит продавать мимо остатка.
    if (asGift && !rewardID) { res.status(400).json({ error: "gift_not_allowed" }); return; }
    const ref = offerID ? `offer:${offerID}` : `reward:${rewardID}${asGift ? ":gift" : ""}`;

    const walletRef = db.collection("bonusWallets").doc(uid);
    const keyRef = walletRef.collection("buyKeys").doc(key);
    const offerRef = offerID ? db.collection("couponOffers").doc(offerID) : null;
    const catalogRef = db.collection("config").doc("globalRewards");
    const nowMs = Date.now();

    // Каталог наград и владелец заведения купона читаются ВНЕ транзакции
    // (аудит запуска: горячая точка). Оба меняет только админ/владелец и
    // редко; держать их в каждой транзакции покупки значит конфликтовать с
    // любой правкой каталога. venueID купона правила менять не дают, а в
    // транзакции он сверяется с прочитанным здесь.
    const catalogPre = rewardID ? await catalogRef.get() : null;
    const offerPre = offerRef ? await offerRef.get() : null;
    const preVenueID = offerPre && offerPre.exists ? String((offerPre.data() || {}).venueID || "") : "";
    const offerVenuePre = preVenueID ? await db.collection("venues").doc(preVenueID).get() : null;

    let out: Record<string, unknown> = {};
    await db.runTransaction(async (tx) => {
      // ВСЕ чтения — до записей.
      const prior = await tx.get(keyRef);
      const walletSnap = await tx.get(walletRef);
      const offerSnap = offerRef ? await tx.get(offerRef) : null;
      const catalogSnap = catalogPre;
      const offerVenueSnap = offerVenuePre;
      const buysRef = offerID ? walletRef.collection("offerBuys").doc(offerID) : null;
      const buysSnap = buysRef ? await tx.get(buysRef) : null;

      if (prior.exists) {
        const p = prior.data() || {};
        if (String(p.ref || "") !== ref) throw new Error("key_reused");
        out = { ...(p.response || {}), replayed: true };
        return;
      }
      if (!walletSnap.exists) throw new Error("no_wallet");
      const wallet = walletSnap.data() || {};

      // Что покупаем и за сколько — только из серверных данных, не из запроса.
      let cost = 0;
      let title = "";
      let venueID = "";
      let venueName = "";
      let couponExpiresAt: unknown = null;
      if (offerSnap) {
        if (!offerSnap.exists) throw new Error("not_found");
        const o = offerSnap.data() || {};
        const stock = o.stock === null || o.stock === undefined ? null : intOf(o.stock);
        const sold = intOf(o.soldCount);
        const expires = toMillis(o.expiresAt);
        // Те же четыре причины отказа, что в `CouponOffer.isAvailable(at:)`.
        if (String(o.status || "") !== "approved" || o.isPaused === true) throw new Error("unavailable");
        if (expires > 0 && expires < nowMs) throw new Error("unavailable");
        if (stock !== null && sold >= stock) throw new Error("sold_out");
        // Лимит в одни руки: без него один игрок (или скрипт) выкупал весь
        // остаток. 0 / нет поля — без лимита (купоны до 2026-10-01).
        const perGuest = intOf(o.perGuestLimit);
        if (perGuest > 0 && intOf((buysSnap && buysSnap.data() || {}).count) >= perGuest) {
          throw new Error("limit_reached");
        }
        // Купон гасится у заведения из `venueID`. Если это заведение не
        // принадлежит владельцу купона, купон перенацелили на чужую стойку —
        // не продаём.
        const venueOwner = String(((offerVenueSnap && offerVenueSnap.data()) || {}).ownerID || "");
        if (!venueOwner || venueOwner !== String(o.ownerID || "")) throw new Error("unavailable");
        if (String(o.venueID || "") !== preVenueID) throw new Error("unavailable");
        cost = intOf(o.cost);
        title = String(o.title || "");
        venueID = String(o.venueID || "");
        venueName = String(o.venueName || "");
        if (expires > 0) couponExpiresAt = o.expiresAt;
      } else {
        const items: any[] = ((catalogSnap && catalogSnap.data()) || {}).items || [];
        const item = items.find((i) => String(i && i.id) === rewardID);
        // Награда без заведения-партнёра не гасится у стойки (wrong_venue) —
        // продавать её не за что.
        if (!item || !String(item.venueID || "")) throw new Error("not_found");
        cost = intOf(item.cost);
        title = String(item.title || "");
        venueID = String(item.venueID || "");
        venueName = String(item.venueName || "");
      }
      if (cost <= 0 || !venueID) throw new Error("unavailable");

      const bal = intOf(wallet.balance);
      if (bal < cost) throw new Error("insufficient");
      const balance = bal - cost;
      const now = new Date(nowMs);

      tx.set(walletRef, {
        balance, lifetimeSpent: intOf(wallet.lifetimeSpent) + cost, updatedAt: now,
      }, { merge: true });
      if (offerRef) tx.set(offerRef, { soldCount: intOf((offerSnap!.data() || {}).soldCount) + 1 }, { merge: true });
      if (buysRef) {
        tx.set(buysRef, { count: intOf((buysSnap && buysSnap.data() || {}).count) + 1, updatedAt: now }, { merge: true });
      }

      if (asGift) {
        // Подарок — документ giftCoupons, как раньше создавал клиент; забирает
        // получатель по коду из ссылки.
        const giftCode = newGiftCode();
        tx.set(db.collection("giftCoupons").doc(giftCode), {
          title, code: giftCode, fromName, fromUserID: uid, claimed: false, createdAt: now,
          venueID, venueName, rewardID,
        });
        out = { ok: true, gift: true, giftCode, title, cost, balance };
      } else {
        const couponRef = db.collection("coupons").doc();
        const code = newCouponCode();
        tx.set(couponRef, {
          userID: uid, venueID, venueName, title, code,
          kind: offerID ? "offer" : "reward", dealID: "",
          used: false, createdAt: now,
          source: offerID ? "couponOffer" : "globalReward", refID: offerID || rewardID,
          ...(couponExpiresAt ? { expiresAt: couponExpiresAt } : {}),
        });
        const expiresAtMs = couponExpiresAt ? toMillis(couponExpiresAt) : 0;
        out = { ok: true, couponID: couponRef.id, code, title, venueID, venueName, cost, balance,
          ...(expiresAtMs > 0 ? { expiresAt: expiresAtMs } : {}) };
      }
      tx.set(walletRef.collection("ledger").doc(), {
        type: "spend", amount: -cost, ref, at: now,
      });
      tx.set(keyRef, { ref, response: out, at: now });
      out = { ...out, replayed: false };
    });
    res.status(200).json(out);
  } catch (e: any) {
    const m = String(e.message);
    if (m === "not_found") { res.status(404).json({ error: m }); return; }
    if (["insufficient", "sold_out", "unavailable", "key_reused", "no_wallet", "limit_reached"].includes(m)) {
      res.status(409).json({ error: m }); return;
    }
    console.error("buyCoupon error:", e);
    res.status(500).json({ error: "buy_failed" });
  }
});

/* Забрать подарок. Раньше получатель помечал `giftCoupons/{code}` сам и
 * клал себе купон БЕЗ заведения — такой купон не гасится у стойки, и
 * бонусы дарителя пропадали. Теперь купон создаёт сервер, с заведением из
 * подарка (его записал buyCoupon), в одной транзакции с пометкой claimed.
 * Подарки старых сборок (без fromUserID — создавал клиент) забираются как
 * раньше: купон без заведения, чтобы не превращать клиентскую запись в
 * гасимый товар. */
export const claimGift = onRequest(MONEY_PATH_OPTS, async (req, res) => {
  try {
    const uid = await walletUser(req, res, "claimGift");
    if (!uid) return;
    const code = String((req.body && req.body.code) || "").trim().slice(0, 64);
    if (!code) { res.status(400).json({ error: "missing_code" }); return; }
    const giftRef = db.collection("giftCoupons").doc(code);
    let out: Record<string, unknown> = {};
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(giftRef);
      if (!snap.exists) throw new Error("not_found");
      const g = snap.data() || {};
      if (g.claimed === true) {
        // Повтор тем же получателем — отдаём тот же купон.
        if (String(g.claimedBy || "") === uid && g.couponID) {
          out = { ok: true, replayed: true, couponID: g.couponID, code: g.couponCode,
            title: g.title, venueID: g.venueID || "", venueName: g.venueName || "" };
          return;
        }
        throw new Error("already_claimed");
      }
      if (String(g.fromUserID || "") === uid) throw new Error("own_gift");
      const serverMade = !!String(g.fromUserID || "");
      const venueID = serverMade ? String(g.venueID || "") : "";
      const venueName = serverMade ? String(g.venueName || "") : "";
      const couponRef = db.collection("coupons").doc();
      const couponCode = newCouponCode();
      const now = new Date();
      tx.set(couponRef, {
        userID: uid, venueID, venueName, title: String(g.title || ""), code: couponCode,
        kind: "gift", dealID: "", used: false, createdAt: now, source: "gift", refID: code,
      });
      tx.set(giftRef, { claimed: true, claimedBy: uid, claimedAt: now,
        couponID: couponRef.id, couponCode }, { merge: true });
      out = { ok: true, couponID: couponRef.id, code: couponCode, title: String(g.title || ""),
        venueID, venueName, replayed: false };
    });
    res.status(200).json(out);
  } catch (e: any) {
    const m = String(e.message);
    if (m === "not_found") { res.status(404).json({ error: m }); return; }
    if (m === "already_claimed" || m === "own_gift") { res.status(409).json({ error: m }); return; }
    console.error("claimGift error:", e);
    res.status(500).json({ error: "claim_failed" });
  }
});

/* Ночная сверка кошельков бонусов — как reconcileVenuePoints для баллов.
 * Проверить игру сервер не может, поэтому это единственный детектор фарма
 * «после факта»: баланс ≠ сумме ledger (деньги потеряны или напечатаны) и
 * аккаунты, упёршиеся в дневной потолок начисления. */
export const reconcileBonusWallets = onSchedule(NIGHTLY_JOB, async () => {
  const nowMs = Date.now();
  const today = bishkekDayKey(nowMs);
  // Счётчик дня в кошельке один — за последний день начислений. Проход идёт
  // в случайный час суток, и рано утром «сегодня» почти пусто: вчерашний
  // фармер упёрся в потолок вчера. Поэтому смотрим оба дня.
  const yesterday = bishkekDayKey(nowMs - 24 * 3600000);
  const beat = (await db.collection("ops").doc("heartbeats").get()).data() || {};
  await checkHeartbeat(beat, "reconcileVenuePoints", nowMs);
  let checked = 0, mismatches = 0, capped = 0;
  // Кошельки — постранично, сумма ledger — агрегатом sum() (см. reconcileVenuePoints).
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  for (;;) {
    let page = db.collection("bonusWallets").orderBy(FieldPath.documentId()).limit(RECONCILE_PAGE);
    if (cursor) page = page.startAfter(cursor);
    const wallets = await page.get();
    if (wallets.empty) break;
    for (const w of wallets.docs) {
      const data = w.data() || {};
      const balance = intOf(data.balance);
      const agg = await w.ref.collection("ledger").aggregate({ sum: AggregateField.sum("amount") }).get();
      const sum = Number(agg.data().sum) || 0;
      checked++;
      if (sum !== balance) {
        mismatches++;
        if (mismatches <= MAX_ALERTS_PER_RUN) {
          await raiseAlert("wallet_mismatch", { userID: w.id, balance, ledgerSum: sum });
        }
      }
      const earnDay = String(data.earnDay || "");
      if ((earnDay === today || earnDay === yesterday) && intOf(data.earnedToday) >= BONUS_DAILY_EARN_CAP) {
        capped++;
        if (capped <= MAX_ALERTS_PER_RUN) {
          await raiseAlert("wallet_cap_hit", { userID: w.id, day: earnDay, earnedToday: intOf(data.earnedToday) });
        }
      }
    }
    if (wallets.size < RECONCILE_PAGE) break;
    cursor = wallets.docs[wallets.docs.length - 1] as FirebaseFirestore.QueryDocumentSnapshot;
  }
  if (mismatches > MAX_ALERTS_PER_RUN || capped > MAX_ALERTS_PER_RUN) {
    console.error(`ALERT wallet_alert_flood mismatches=${mismatches} capped=${capped}, записано не больше ${MAX_ALERTS_PER_RUN} каждого`);
  }
  console.log(`🧾 wallets reconciled: ${checked}, mismatches: ${mismatches}, at cap: ${capped}`);
  await db.collection("ops").doc("heartbeats")
    .set({ reconcileBonusWallets: new Date(), walletMismatches: mismatches, walletsAtCap: capped }, { merge: true });
});
