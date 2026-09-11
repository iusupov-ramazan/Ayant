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
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, DocumentReference } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getAuth } from "firebase-admin/auth";
import * as fs from "fs";
import * as path from "path";
import type {
  Numeric,
  VenueDoc,
  CouponDoc,
  VenuePointsDoc,
  PushCampaignDoc,
  PointsBand,
  PointsReward,
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
} as const;

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
const DAILY_CAP = capFromEnv(process.env.PUSH_DAILY_CAP, 1);
const WEEKLY_CAP = capFromEnv(process.env.PUSH_WEEKLY_CAP, 3);

// Награды за рефералку (бонусы).
const REFERRAL_REWARD = 100;
// Анти-фарм: потолок реферальных наград на одного пригласившего. Без него можно
// нафармить бонусы, создав N аккаунтов, каждый из которых указывает твой userID
// пригласившим (Sybil). Настраивается через env REFERRAL_MAX_REWARDS.
const REFERRAL_MAX_REWARDS = capFromEnv(process.env.REFERRAL_MAX_REWARDS, 20);

// ── Баллы САН (per-venue ledger, System 1) ──────────────────────────────────
// 1 балл = 1 сом при погашении. Гардрейлы (даже при self-serve конфиге хоста):
const DEFAULT_EARN_COOLDOWN_MIN = 60;   // не чаще 1 начисления баллов на гостя/заведение
// Штампы: не чаще одного на гостя/заведение за это окно. Дефолт 15 мин;
// на время тестирования переопределяется через env STAMP_COOLDOWN_MIN
// (0 — без паузы). В продакшене переменную не задавать.
const DEFAULT_STAMP_COOLDOWN_MIN = capFromEnv(process.env.STAMP_COOLDOWN_MIN, 15);
const DEFAULT_EXPIRY_MONTHS = 6;        // баллы сгорают после N мес. без активности
const MAX_CASHBACK_PERCENT = 20;        // потолок кэшбэка (защита от опечатки «50%»)
const MAX_POINTS_PER_EARN = 10000;      // потолок за одно начисление

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

// Рассылка идёт только после одобрения админом (status: "approved") и один раз
// (флаг delivered). Хост создаёт кампанию как "pending" → админ одобряет в панели.
export const sendPushCampaign = onDocumentWritten("pushCampaigns/{id}", async (event) => {
  const snap = event.data && event.data.after;
  if (!snap || !snap.exists) return;

  const c = (snap.data() || {}) as PushCampaignDoc;
  if (c.status !== "approved" || c.delivered) return;

  const now = Date.now();
  const city = c.city || "";

  // Токены целевого города (или все, если город не указан).
  let q: FirebaseFirestore.Query = db.collection("userTokens");
  if (city) q = q.where("city", "==", city);
  const tokensSnap = await q.get();

  // Отбираем токены, не превысившие лимит, и готовим обновления истории.
  const eligible: string[] = [];
  const logUpdates: { ref: DocumentReference; sends: number[] }[] = [];
  for (const tdoc of tokensSnap.docs) {
    const token = tdoc.id;
    const logRef = db.collection("pushLog").doc(token);
    const logSnap = await logRef.get();
    let sends: number[] =
      logSnap.exists && Array.isArray(logSnap.data()!.sends) ? logSnap.data()!.sends : [];
    sends = sends.filter((t) => now - t < 7 * DAY_MS); // только за последнюю неделю
    const dayCount = sends.filter((t) => now - t < DAY_MS).length;
    if (dayCount < DAILY_CAP && sends.length < WEEKLY_CAP) {
      eligible.push(token);
      logUpdates.push({ ref: logRef, sends: sends.concat(now) });
    }
  }

  if (eligible.length === 0) {
    // Фолбэк: рассылка по топику ВСЕХ пользователей. Каждое устройство
    // подписывается на all_users при запуске (без авторизации и без привязки
    // к городу) — поэтому буст доходит до всех, даже без userTokens.
    const topic = "all_users";
    try {
      await getMessaging().send({
        topic,
        notification: { title: c.headline || "САН", body: c.body || "" },
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
    notification: { title: c.headline || "САН", body: c.body || "" },
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
  for (let i = 0; i < eligible.length; i += 500) {
    const chunk = eligible.slice(i, i + 500);
    const res = await getMessaging().sendEachForMulticast({ ...base, tokens: chunk });
    success += res.successCount;
    res.responses.forEach((r, idx) => {
      if (!r.success && r.error &&
          r.error.code === "messaging/registration-token-not-registered") {
        db.collection("userTokens").doc(chunk[idx]).delete().catch(() => {});
      }
    });
  }

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
export const notifyOnNewDeal = onDocumentCreated("deals/{id}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const deal = snap.data() || {};
  if ((deal.status || "active") !== "active") return;       // только активные
  const venueID = String(deal.venueID || "");
  if (!venueID) return;

  // Имя заведения для текста уведомления.
  let venueName = "заведение";
  try {
    const vdoc = await db.collection("venues").doc(venueID).get();
    if (vdoc.exists && vdoc.data()!.name) venueName = vdoc.data()!.name;
  } catch (_) {}

  const typeLabel =
    ({ discount: "Скидка", promo: "Акция", novelty: "Новинка", announcement: "Объявление" } as Record<string, string>)[deal.type] ||
    "Новинка";

  await getMessaging().send({
    topic: `venue_${venueID}`,
    notification: { title: `${typeLabel} · ${venueName}`, body: deal.title || "Новое предложение" },
    data: { type: "deal", dealID: event.params.id, venueID },
    apns: { payload: { aps: { sound: "default", badge: 1 } } },
    android: { notification: { sound: "default" }, priority: "high" },
  });
  console.log(`🔔 new-deal push → venue_${venueID} (${venueName})`);
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
export const countAnalyticsEvent = onDocumentCreated("analyticsEvents/{id}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const e = snap.data() || {};
  const venueID = String(e.venueID || "");
  const metric = String(e.metric || "");
  if (venueID && ANALYTICS_METRICS.includes(metric)) {
    const day = dayKey();
    await db.collection("analytics").doc(venueID)
      .collection("days").doc(day)
      .set({ [metric]: FieldValue.increment(1), date: day }, { merge: true });
  }
  await snap.ref.delete().catch(() => {}); // событие обработано — чистим
});

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

/** Защита от неограниченного чтения, если у заведения аномально много отзывов. */
const MAX_REVIEWS_PER_RECOUNT = 3000;

export async function recomputeVenueRating(venueID: string): Promise<void> {
  if (!venueID) return;

  const snap = await db.collection("reviews")
    .where("venueID", "==", venueID)
    .limit(MAX_REVIEWS_PER_RECOUNT)
    .get();

  if (snap.size >= MAX_REVIEWS_PER_RECOUNT) {
    console.warn(`ALERT review_recount_truncated venue=${venueID} cap=${MAX_REVIEWS_PER_RECOUNT}`);
  }

  // Гистограмма 1★…5★ — её читает карточка заведения, чтобы не тянуть отзывы
  // ради одной полоски. Ключи 1…5 присутствуют всегда, включая нули.
  const histogram: Record<string, number> = { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0 };
  let sum = 0;
  let count = 0;
  for (const doc of snap.docs) {
    const r = Number((doc.data() || {}).rating);
    if (!Number.isFinite(r) || r < 1 || r > 5) continue;   // мусорная оценка не портит агрегат
    const star = String(Math.round(r));
    histogram[star] = (histogram[star] || 0) + 1;
    sum += r;
    count += 1;
  }

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
export const rewardReferral = onDocumentCreated("referrals/{inviteeID}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data() || {};
  const referrerID = String(data.referrerID || "");
  const inviteeID = event.params.inviteeID;
  if (!referrerID || referrerID === inviteeID) return;
  if (data.rewarded) return;                                 // идемпотентность

  // Анти-фарм: не выдаём больше REFERRAL_MAX_REWARDS наград одному пригласившему.
  // Один where по userID (без составного индекса — как в клиентском claimBonusGrants),
  // reason считаем в коде. Реферал всё равно помечаем rewarded, чтобы не переобрабатывать.
  const priorSnap = await db.collection("bonusGrants").where("userID", "==", referrerID).get();
  const priorReferrals = priorSnap.docs.filter((d) => (d.data() || {}).reason === "referral").length;
  if (priorReferrals >= REFERRAL_MAX_REWARDS) {
    await snap.ref.set({ rewarded: true, rewardedAt: new Date(), capped: true }, { merge: true });
    console.log(`🚫 referral cap (${REFERRAL_MAX_REWARDS}) reached for ${referrerID} — no grant`);
    return;
  }

  await db.collection("bonusGrants").add({
    userID: referrerID,
    amount: REFERRAL_REWARD,
    reason: "referral",
    inviteeID,
    claimed: false,
    createdAt: new Date(),
  });
  await snap.ref.set({ rewarded: true, rewardedAt: new Date() }, { merge: true });
  console.log(`🎁 referral reward queued for ${referrerID} (invited ${inviteeID})`);
});

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

export const generateLoyaltyPass = onRequest({ cors: true }, async (req, res) => {
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

    const code = String((req.body && req.body.code) || "").trim();
    const venueID = String((req.body && req.body.venueID) || "").trim();
    if (!code || !venueID) { res.status(400).json({ error: "missing_params" }); return; }

    // 2) Заведение должно принадлежать хосту.
    const venueSnap = await db.collection("venues").doc(venueID).get();
    if (!venueSnap.exists) { res.status(404).json({ error: "venue_not_found" }); return; }
    const venue = (venueSnap.data() || {}) as VenueDoc;
    if (String(venue.ownerID || "") !== uid) { res.status(403).json({ error: "not_owner" }); return; }

    // `|| 6` здесь намеренно (в отличие от earnCooldownMinutes): цель карты < 2 штампов
    // смысла не имеет, поэтому ноль трактуем как «не задано» → дефолт.
    // Идемпотентность скана. Ключ генерирует хост-приложение ОДИН раз на
    // распознанный QR и повторяет при ретрае. Проверяем его ПЕРЕД кулдауном:
    // иначе повтор внутри окна получил бы 429 вместо исходного результата —
    // ровно тот случай, ради которого ключ и нужен.
    const idempotencyKey = String((req.body && req.body.idempotencyKey) || "").trim().slice(0, 128);

    const goal = Math.max(parseInt(String(venue.loyaltyGoal), 10) || 6, 2);
    const reward = String(venue.loyaltyReward || "Награда за лояльность");
    const venueName = String(venue.name || "Заведение");

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

      const nowMs = Date.now();
      const cooldownMin = DEFAULT_STAMP_COOLDOWN_MIN;   // штампы: 15 мин по умолчанию (отдельно от баллов)
      const cardRef = db.collection("loyaltyCards").doc(`${cardUser}_${venueID}`);
      const keyRef = idempotencyKey ? cardRef.collection("scanKeys").doc(idempotencyKey) : null;

      // Повтор того же скана — отдаём сохранённый результат, ничего не начисляя.
      if (keyRef) {
        const prior = await keyRef.get();
        if (prior.exists) {
          const p = prior.data() || {};
          if (String(p.code || "") !== code) { res.status(409).json({ error: "key_reused" }); return; }
          res.status(200).json({
            ok: true, loyalty: true,
            title: p.rewardIssued ? "Карта заполнена!" : "Штамп начислен",
            stamps: parseInt(String(p.stamps), 10) || 0, goal,
            rewardIssued: p.rewardIssued === true,
            rewardTitle: p.rewardIssued === true ? reward : "",
            replayed: true,
          });
          return;
        }
      }

      // Анти-мультискан: не чаще 1 штампа на гостя/заведение в пределах кулдауна
      // (иначе сотрудник мог бы просканировать карту несколько раз подряд).
      const pre = (await cardRef.get()).data() || {};
      const preLast = toMillis(pre.lastStampAt);
      if (cooldownMin > 0 && nowMs - preLast < cooldownMin * 60000) {
        res.status(429).json({ error: "cooldown",
          retryAfterSec: Math.ceil((cooldownMin * 60000 - (nowMs - preLast)) / 1000) });
        return;
      }

      let stamps = 0, rewardIssued = false;
      await db.runTransaction(async (tx) => {
        // Все чтения до записей (требование транзакций Firestore).
        const priorTx = keyRef ? await tx.get(keyRef) : null;
        const cur = (await tx.get(cardRef)).data() || {};
        if (priorTx && priorTx.exists) {   // гонка двух одинаковых сканов
          const p = priorTx.data() || {};
          stamps = parseInt(String(p.stamps), 10) || 0;
          rewardIssued = p.rewardIssued === true;
          return;
        }
        const curLast = toMillis(cur.lastStampAt);
        if (cooldownMin > 0 && nowMs - curLast < cooldownMin * 60000) throw new Error("cooldown");
        let s = (parseInt(String(cur.stamps), 10) || 0) + 1;
        let rounds = parseInt(String(cur.completedRounds), 10) || 0;
        if (s >= goal) { s = 0; rounds += 1; rewardIssued = true; }   // карта заполнена → награда сегодня
        tx.set(cardRef, {
          userID: cardUser, venueID, venueName, goal, reward,
          stamps: s, completedRounds: rounds, lastStampAt: new Date(nowMs), updatedAt: new Date(),
        }, { merge: true });
        if (keyRef) tx.set(keyRef, { code, stamps: s, rewardIssued, at: new Date(nowMs) });
        stamps = s;
      });
      res.status(200).json({
        ok: true, loyalty: true,
        title: rewardIssued ? "Карта заполнена!" : "Штамп начислен",
        stamps, goal, rewardIssued, rewardTitle: rewardIssued ? reward : "",
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
          res.status(200).json({
            ok: true, points: true,
            awarded: parseInt(String(p.awarded), 10) || 0,
            balance: parseInt(String(p.balance), 10) || 0,
            venueName, replayed: true,
          });
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

      let balance = 0;
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

      res.status(200).json({ ok: true, points: true, awarded, balance, venueName, replayed: false });
      return;
    }

    // ── Ветка B: КУПОН акции → только погашение (штамп НЕ начисляется).
    const q = await db.collection("coupons").where("code", "==", code).limit(1).get();
    if (q.empty) { res.status(404).json({ error: "coupon_not_found" }); return; }
    const couponRef = q.docs[0].ref;
    const coupon = (q.docs[0].data() || {}) as CouponDoc;
    if (String(coupon.venueID || "") !== venueID) { res.status(409).json({ error: "wrong_venue" }); return; }
    if (coupon.used === true) { res.status(409).json({ error: "already_used", title: coupon.title || "" }); return; }

    await db.runTransaction(async (tx) => {
      const cSnap = await tx.get(couponRef);
      if ((cSnap.data() || {}).used === true) throw new Error("already_used");
      tx.update(couponRef, { used: true, usedAt: new Date(), usedByVenue: venueID });
    });

    const day = dayKey();
    db.collection("analytics").doc(venueID).collection("days").doc(day)
      .set({ redemptions: FieldValue.increment(1) }, { merge: true }).catch(() => {});

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
    console.error("scanCoupon error:", e);
    res.status(500).json({ error: "scan_failed" });
  }
});

/* ───────────────────────────────────────────────────────────────────────────
 * 6b) Списание баллов САН (System 1) → погашение награды из каталога заведения.
 *     POST /redeemVenuePoints  body: { venueID, userID?, rewardId, pointsToSpend? }
 *     Header: Authorization: Bearer <Firebase ID token>
 *
 *     Кто инициирует зависит от venue.redeemMode:
 *       staffScan          — гасит владелец, userID берётся из QR гостя (AYANT-RDM);
 *       customerInitiated  — гость гасит сам (uid == userID).
 *     Владелец может гасить всегда (это его деньги). Награда — item (фикс. cost)
 *     или money (списываем pointsToSpend ≥ cost=minRedeem). Атомарно, анти-чит.
 * ─────────────────────────────────────────────────────────────────────────── */
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
    const rewardId = String((req.body && req.body.rewardId) || "").trim();
    const userID = String((req.body && req.body.userID) || "").trim();
    const pointsToSpend = Math.max(0, parseInt(String(req.body && req.body.pointsToSpend), 10) || 0);
    if (!venueID || !rewardId) { res.status(400).json({ error: "missing_params" }); return; }

    const venueSnap = await db.collection("venues").doc(venueID).get();
    if (!venueSnap.exists) { res.status(404).json({ error: "venue_not_found" }); return; }
    const venue = (venueSnap.data() || {}) as VenueDoc;
    const redeemMode = String(venue.redeemMode || "staffScan");
    const isOwner = String(venue.ownerID || "") === uid;

    // Определяем, чья это карта, и кто вправе гасить.
    let cardUser: string;
    if (isOwner) {
      cardUser = userID;                          // владелец гасит по QR гостя
      if (!cardUser) { res.status(400).json({ error: "missing_user" }); return; }
    } else if (redeemMode === "customerInitiated") {
      cardUser = uid;                             // гость гасит сам
    } else {
      res.status(403).json({ error: "redeem_not_allowed" }); return;
    }

    const rewards: PointsReward[] = Array.isArray(venue.pointsRewards) ? venue.pointsRewards : [];
    const reward = rewards.find((r) => String(r.id) === rewardId);
    if (!reward || reward.active === false) { res.status(404).json({ error: "reward_not_found" }); return; }

    const type = String(reward.type || "item");
    const ratio = Number(reward.ratio) > 0 ? Number(reward.ratio) : 1;
    let cost: number;
    if (type === "money") {
      const minRedeem = Math.max(parseInt(String(reward.cost), 10) || 1, 1);
      if (pointsToSpend < minRedeem) { res.status(400).json({ error: "below_min", minRedeem }); return; }
      cost = pointsToSpend;
    } else {
      cost = Math.max(parseInt(String(reward.cost), 10) || 0, 0);
      if (cost <= 0) { res.status(409).json({ error: "bad_reward" }); return; }
    }

    const cardRef = db.collection("venuePoints").doc(`${cardUser}_${venueID}`);

    // Идемпотентность. Клиент генерирует ключ ОДИН раз на попытку списания и
    // переиспользует его при повторной отправке (таймаут сети, второй тап по
    // кнопке). Первый запрос списывает и запоминает результат под этим ключом;
    // все следующие с тем же ключом возвращают тот же ответ, НЕ списывая снова.
    // Ключ живёт под картой гостя, поэтому чужим ключом воспользоваться нельзя.
    const idempotencyKey = String((req.body && req.body.idempotencyKey) || "").trim().slice(0, 128);
    const keyRef = idempotencyKey ? cardRef.collection("redeemKeys").doc(idempotencyKey) : null;

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
        replayed = true;
        return;
      }

      const cur = (await tx.get(cardRef)).data() || {};
      const bal = parseInt(String(cur.balance), 10) || 0;
      if (bal < cost) throw new Error("insufficient");
      balance = bal - cost;
      tx.set(cardRef, {
        balance,
        lifetimeRedeemed: (parseInt(String(cur.lifetimeRedeemed), 10) || 0) + cost,
        lastActivityAt: new Date(), updatedAt: new Date(),
      }, { merge: true });
      tx.set(cardRef.collection("ledger").doc(), {
        type: "redeem", points: -cost, rewardId, byVenue: isOwner, at: new Date(),
      });
      if (keyRef) tx.set(keyRef, { rewardId, redeemed: cost, balance, at: new Date() });
    });

    res.status(200).json({
      ok: true, redeemed: cost, balance,
      rewardTitle: String(reward.title || ""),
      somOff: type === "money" ? Math.round(cost * ratio) : null,
      // true — запрос уже выполнялся ранее с этим же ключом, баллы НЕ списаны повторно.
      replayed,
    });
  } catch (e: any) {
    if (String(e.message) === "insufficient") { res.status(409).json({ error: "insufficient" }); return; }
    if (String(e.message) === "key_reused") { res.status(409).json({ error: "key_reused" }); return; }
    console.error("redeemVenuePoints error:", e);
    res.status(500).json({ error: "redeem_failed" });
  }
});

/* ───────────────────────────────────────────────────────────────────────────
 * 6c) Сгорание баллов САН по неактивности (System 1). Ежедневно.
 *     Обнуляет баланс карт, где lastActivityAt старше venue.pointsExpiryMonths,
 *     и пишет строку ledger type:"expire". Порог берётся из конфига заведения.
 * ─────────────────────────────────────────────────────────────────────────── */
export const expireVenuePoints = onSchedule("every 24 hours", async () => {
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

    await db.runTransaction(async (tx) => {
      const cur = (await tx.get(doc.ref)).data() || {};
      const b = parseInt(String(cur.balance), 10) || 0;
      if (b <= 0) return;
      tx.set(doc.ref, { balance: 0, updatedAt: new Date() }, { merge: true });
      tx.set(doc.ref.collection("ledger").doc(), {
        type: "expire", points: -b, byVenue: false, at: new Date(),
      });
    });
    expired++;
  }

  console.log(`⌛ venuePoints expired: ${expired}`);
  // Пульс задачи: ночная сверка проверит, что она отработала (см. reconcileVenuePoints).
  await db.collection("ops").doc("heartbeats")
    .set({ expireVenuePoints: new Date(), expireVenuePointsCount: expired }, { merge: true });
  // TODO(System 1, warn-pass): за ~14 дней до сгорания слать предупреждающий push
  //   («твои баллы в {venue} скоро сгорят»). Нужен per-user канал доставки
  //   (userTokens по userID) — вынесено в отдельную задачу, не блокирует Phase 1.
});

/* ───────────────────────────────────────────────────────────────────────────
 * 7) Купон в Apple Wallet (.pkpass со сканируемым QR = code).
 *    GET /generateCouponPass?code=<code>&title=<title>&venue=<venueName>
 * ─────────────────────────────────────────────────────────────────────────── */
export const generateCouponPass = onRequest({ cors: true }, async (req, res) => {
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

type AlertKind = "balance_mismatch" | "job_stale" | "issuance_spike";

async function raiseAlert(kind: AlertKind, detail: Record<string, unknown>): Promise<void> {
  console.error(`ALERT ${kind}`, JSON.stringify(detail));
  await db.collection("ops").doc("alerts").collection("items").add({
    kind, detail, at: new Date(), resolved: false,
  }).catch((e) => console.error("alert write failed:", e));
}

export const reconcileVenuePoints = onSchedule("every 24 hours", async () => {
  const nowMs = Date.now();
  const DAY = 24 * 60 * 60 * 1000;

  // ── 2. Пульс задачи сгорания ───────────────────────────────────────────────
  const beat = (await db.collection("ops").doc("heartbeats").get()).data() || {};
  const lastExpire = toMillis(beat.expireVenuePoints);
  if (lastExpire === 0 || nowMs - lastExpire > HEARTBEAT_STALE_HOURS * 60 * 60 * 1000) {
    await raiseAlert("job_stale", {
      job: "expireVenuePoints",
      lastRunAt: lastExpire ? new Date(lastExpire).toISOString() : null,
      staleHours: lastExpire ? Math.round((nowMs - lastExpire) / 3600000) : null,
    });
  }

  // ── 1 + 3. Сверка балансов и эмиссия по заведениям ────────────────────────
  const cards = await db.collection("venuePoints").get();
  /** venueID → { today, prior7 } — начислено за сутки и за предыдущие 7 дней. */
  const issuance = new Map<string, { today: number; prior7: number }>();
  let checked = 0, mismatches = 0;

  for (const card of cards.docs) {
    const data = card.data() || {};
    const balance = parseInt(String(data.balance), 10) || 0;
    const venueID = String(data.venueID || "");

    const ledger = await card.ref.collection("ledger").get();
    let sum = 0;
    for (const entry of ledger.docs) {
      const e = entry.data() || {};
      const points = parseInt(String(e.points), 10) || 0;
      sum += points;

      if (String(e.type) === "earn" && venueID) {
        const at = toMillis(e.at);
        if (at === 0) continue;
        const age = nowMs - at;
        const bucket = issuance.get(venueID) || { today: 0, prior7: 0 };
        if (age <= DAY) bucket.today += points;
        else if (age <= 8 * DAY) bucket.prior7 += points;
        issuance.set(venueID, bucket);
      }
    }

    checked++;
    // Пустой ledger при нулевом балансе — нормальная новая карта, не расхождение.
    if (sum !== balance && !(ledger.empty && balance === 0)) {
      mismatches++;
      if (mismatches <= MAX_ALERTS_PER_RUN) {
        await raiseAlert("balance_mismatch", {
          card: card.id, userID: String(data.userID || ""), venueID,
          balance, ledgerSum: sum, delta: balance - sum, ledgerEntries: ledger.size,
        });
      }
    }
  }

  // ── 3. Аномальная эмиссия ─────────────────────────────────────────────────
  for (const [venueID, { today, prior7 }] of issuance) {
    const dailyMean = prior7 / 7;
    // Заведению без истории порог не применяем — иначе первый же день даёт алерт.
    if (dailyMean <= 0 || today <= dailyMean * ISSUANCE_SPIKE_FACTOR) continue;
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
 * Владелец заведений НЕ удаляется автоматически: снос живого каталога в один
 * тап необратим и задевает чужие данные (отзывы гостей, их баллы). Такой
 * аккаунт получает 409 и инструкцию сначала передать заведения — это
 * осознанное ограничение, а не недоделка.
 * ─────────────────────────────────────────────────────────────────────────── */
export const deleteAccount = onRequest({ cors: true }, async (req, res) => {
  try {
    if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
    const uid = await verifyBearer(req);
    if (!uid) { res.status(401).json({ error: "no_token" }); return; }

    // 1) Владелец заведений — отказ с понятной причиной.
    const owned = await db.collection("venues").where("ownerID", "==", uid).limit(1).get();
    if (!owned.empty) {
      res.status(409).json({
        error: "owns_venues",
        message: "Аккаунт управляет заведениями. Напишите в поддержку, чтобы передать их, — после этого удалим аккаунт.",
      });
      return;
    }

    // 2) Документы, чей id начинается с uid: `{uid}_{venueID}`.
    for (const name of ["venuePoints", "loyaltyCards"]) {
      const snap = await db.collection(name)
        .where("userID", "==", uid).get();
      for (const doc of snap.docs) {
        // Подколлекции (ledger, scanKeys, redeemKeys) — рекурсивно.
        await db.recursiveDelete(doc.ref);
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
    ];
    for (const [name, field] of byField) {
      const snap = await db.collection(name).where(field, "==", uid).get();
      await deleteInChunks(snap.docs.map((d) => d.ref));
    }

    // 4) Документы с uid в качестве id.
    await db.collection("referrals").doc(uid).delete().catch(() => undefined);
    await db.collection("hosts").doc(uid).delete().catch(() => undefined);

    // 5) Сама запись Auth — последней: пока она есть, вызов можно повторить.
    await getAuth().deleteUser(uid);

    console.log(`🗑 account deleted: ${uid}`);
    res.json({ ok: true });
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
