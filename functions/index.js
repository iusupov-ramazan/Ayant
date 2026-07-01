/**
 * Cloud Function — рассылка рекламных push-кампаний (САН) с частотным лимитом.
 *
 * Триггер: создание документа в `pushCampaigns` (его пишет хост-приложение).
 * Рассылка идёт АДРЕСНО по FCM-токенам (коллекция `userTokens`) — это позволяет
 * соблюдать лимит из спецификации: не более 1 push в день и 3 в неделю на пользователя
 * (история в коллекции `pushLog/{token}`).
 *
 * Деплой:
 *   firebase deploy --only functions
 */

const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

const DAY_MS = 86400000;
// ⚠️ На время теста лимиты подняты. Для продакшена верни 1 и 3 (анти-спам из спеки).
const DAILY_CAP = 20;
const WEEKLY_CAP = 100;

// Награды за рефералку (бонусы).
const REFERRAL_REWARD = 100;

function dayKey(d = new Date()) {
  return d.toISOString().slice(0, 10); // yyyy-MM-dd (UTC) — как в приложении
}

// Рассылка идёт только после одобрения админом (status: "approved") и один раз
// (флаг delivered). Хост создаёт кампанию как "pending" → админ одобряет в панели.
exports.sendPushCampaign = onDocumentWritten("pushCampaigns/{id}", async (event) => {
  const snap = event.data && event.data.after;
  if (!snap || !snap.exists) return;

  const c = snap.data() || {};
  if (c.status !== "approved" || c.delivered) return;

  const now = Date.now();
  const city = c.city || "";

  // Токены целевого города (или все, если город не указан).
  let q = db.collection("userTokens");
  if (city) q = q.where("city", "==", city);
  const tokensSnap = await q.get();

  // Отбираем токены, не превысившие лимит, и готовим обновления истории.
  const eligible = [];
  const logUpdates = [];
  for (const tdoc of tokensSnap.docs) {
    const token = tdoc.id;
    const logRef = db.collection("pushLog").doc(token);
    const logSnap = await logRef.get();
    let sends = logSnap.exists && Array.isArray(logSnap.data().sends) ? logSnap.data().sends : [];
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
        data: { type: c.dealID ? "deal" : "ad", venueID: String(c.venueID || ""),
                dealID: String(c.dealID || ""), campaignId: event.params.id },
        apns: { payload: { aps: { sound: "default", badge: 1 } } },
        android: { notification: { sound: "default" }, priority: "high" },
      });
      await snap.ref.update({ status: "sent", recipients: 0, delivery: "topic",
        delivered: true, sentAt: new Date(), note: `sent to topic ${topic}` });
    } catch (e) {
      await snap.ref.update({ status: "error", delivered: true, note: String(e) });
    }
    return;
  }

  const base = {
    notification: { title: c.headline || "САН", body: c.body || "" },
    data: { type: c.dealID ? "deal" : "ad", venueID: String(c.venueID || ""),
            dealID: String(c.dealID || ""), campaignId: event.params.id },
    apns: { payload: { aps: { sound: "default", badge: 1 } } },
    android: { notification: { sound: "default" }, priority: "high" },
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
exports.notifyOnNewDeal = onDocumentCreated("deals/{id}", async (event) => {
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
    if (vdoc.exists && vdoc.data().name) venueName = vdoc.data().name;
  } catch (_) {}

  const typeLabel = { discount: "Скидка", promo: "Акция", novelty: "Новинка", announcement: "Объявление" }[deal.type] || "Новинка";

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
exports.countRedemption = onDocumentCreated("redemptions/{id}", async (event) => {
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
 * 4) Реферал → награда пригласившему. Приложение пишет referrals/{inviteeID}
 *    = { referrerID }. Здесь начисляем бонус пригласившему через bonusGrants,
 *    которые приложение «забирает» при следующем запуске.
 *    (Приглашённый получает приветственный бонус на своём устройстве сразу.)
 * ─────────────────────────────────────────────────────────────────────────── */
exports.rewardReferral = onDocumentCreated("referrals/{inviteeID}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data() || {};
  const referrerID = String(data.referrerID || "");
  const inviteeID = event.params.inviteeID;
  if (!referrerID || referrerID === inviteeID) return;
  if (data.rewarded) return;                                 // идемпотентность

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
