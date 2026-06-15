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

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

const DAY_MS = 86400000;
const DAILY_CAP = 1;
const WEEKLY_CAP = 3;

exports.sendPushCampaign = onDocumentCreated("pushCampaigns/{id}", async (event) => {
  const snap = event.data;
  if (!snap) return;

  const c = snap.data() || {};
  if (c.status && c.status !== "queued") return;

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
    await snap.ref.update({ status: "sent", recipients: 0, sentAt: new Date(),
      note: "no eligible tokens (frequency cap or no subscribers)" });
    return;
  }

  const base = {
    notification: { title: c.headline || "САН", body: c.body || "" },
    data: { type: "ad", venueID: String(c.venueID || ""), campaignId: event.params.id },
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

  await snap.ref.update({ status: "sent", recipients: success, sentAt: new Date() });
  console.log(`✅ push sent to ${success}/${eligible.length} eligible tokens (city=${city || "all"})`);
});
