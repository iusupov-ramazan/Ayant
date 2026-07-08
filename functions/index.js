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
const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");

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
function addIcons(pass, imgDir, fs, path) {
  for (const f of ["icon.png", "icon@2x.png", "icon@3x.png"]) {
    const p = path.join(imgDir, f);
    if (fs.existsSync(p)) pass.addBuffer(f, fs.readFileSync(p));
  }
}

let _fontsReady = false;
function ensureFonts() {
  if (_fontsReady) return;
  try {
    const { GlobalFonts } = require("@napi-rs/canvas");
    const path = require("path");
    const dir = path.join(__dirname, "assets", "fonts");
    GlobalFonts.registerFromPath(path.join(dir, "LiberationSans-Bold.ttf"), "AyantB");
    GlobalFonts.registerFromPath(path.join(dir, "LiberationSans-Regular.ttf"), "AyantR");
  } catch (e) { /* system fonts fallback */ }
  _fontsReady = true;
}

// Рисует «шапку-билет» как в приложении (пилюли + заголовок + место + вырезы)
// и возвращает PNG-буферы strip для всех масштабов. Заголовок ужимается по ширине.
// rightPill — текст правой пилюли; rightCheck=true рисует галочку перед ним.
function buildHeaderStrip({ title, subtitle, rightPill, rightCheck, stampsGrid }) {
  const { createCanvas } = require("@napi-rs/canvas");
  ensureFonts();
  const W = 1125, H = 372, body = "#1C1C1E";
  const c = createCanvas(W, H), ctx = c.getContext("2d");
  const g = ctx.createLinearGradient(0, 0, W, H);
  g.addColorStop(0, "#FF4D29"); g.addColorStop(1, "#FFB300");
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);

  const rr = (x, y, w, h, r) => { ctx.beginPath(); ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath(); };
  const checkmark = (cx, cy, s) => { ctx.strokeStyle = "#fff"; ctx.lineWidth = s * 0.16;
    ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.beginPath();
    ctx.moveTo(cx - s * 0.42, cy + s * 0.02); ctx.lineTo(cx - s * 0.12, cy + s * 0.32);
    ctx.lineTo(cx + s * 0.45, cy - s * 0.34); ctx.stroke(); };

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

  const scale = (w, h) => { const cc = createCanvas(w, h), cx = cc.getContext("2d");
    cx.drawImage(c, 0, 0, w, h); return cc.toBuffer("image/png"); };
  return {
    "strip.png": scale(375, 124),
    "strip@2x.png": scale(750, 248),
    "strip@3x.png": c.toBuffer("image/png"),
  };
}

function addHeaderStrip(pass, opts) {
  try {
    const strip = buildHeaderStrip(opts);
    for (const [name, buf] of Object.entries(strip)) pass.addBuffer(name, buf);
  } catch (e) { console.error("strip render failed:", e.message); }
}

exports.generateLoyaltyPass = onRequest({ cors: true }, async (req, res) => {
  try {
    const venue = String(req.query.venue || "");
    const userID = String(req.query.user || "");
    const name = String(req.query.name || "Заведение");
    const stamps = parseInt(String(req.query.stamps || "0"), 10) || 0;
    const goal = parseInt(String(req.query.goal || "6"), 10) || 6;
    const reward = String(req.query.reward || "Награда");
    if (!venue || !userID) { res.status(400).send("missing venue/user"); return; }

    // Сертификаты ещё не настроены — мягкий отказ (приложение это учитывает).
    if (WALLET_CONFIGURED !== "1") {
      res.status(503).json({ error: "wallet_not_configured" });
      return;
    }

    // Ленивая загрузка, чтобы деплой не падал, если пакет ещё не установлен.
    const { PKPass } = require("passkit-generator");
    const fs = require("fs");
    const path = require("path");
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
    addIcons(pass, path.join(certDir, "images"), fs, path);
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
exports.scanCoupon = onRequest({ cors: true }, async (req, res) => {
  try {
    if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }

    // 1) Аутентификация хоста по ID-токену.
    const authz = String(req.get("Authorization") || "");
    const idToken = authz.startsWith("Bearer ") ? authz.slice(7) : "";
    if (!idToken) { res.status(401).json({ error: "no_token" }); return; }
    let uid;
    try { uid = (await getAuth().verifyIdToken(idToken)).uid; }
    catch (e) { res.status(401).json({ error: "bad_token" }); return; }

    const code = String((req.body && req.body.code) || "").trim();
    const venueID = String((req.body && req.body.venueID) || "").trim();
    if (!code || !venueID) { res.status(400).json({ error: "missing_params" }); return; }

    // 2) Заведение должно принадлежать хосту.
    const venueSnap = await db.collection("venues").doc(venueID).get();
    if (!venueSnap.exists) { res.status(404).json({ error: "venue_not_found" }); return; }
    const venue = venueSnap.data() || {};
    if (String(venue.ownerID || "") !== uid) { res.status(403).json({ error: "not_owner" }); return; }

    const goal = Math.max(parseInt(venue.loyaltyGoal, 10) || 6, 2);
    const reward = String(venue.loyaltyReward || "Награда за лояльность");
    const venueName = String(venue.name || "Заведение");

    // ── Ветка A: КАРТА ЛОЯЛЬНОСТИ (QR = AYANT-CARD:userID:venueID) → +1 штамп.
    //    Никак не связано с акциями/купонами — карта у заведения, у гостя.
    if (code.startsWith("AYANT-CARD:")) {
      if (venue.loyaltyEnabled !== true) { res.status(409).json({ error: "loyalty_off" }); return; }
      const parts = code.split(":");            // ["AYANT-CARD", userID, venueID]
      const cardUser = String(parts[1] || ""), cardVenue = String(parts[2] || "");
      if (!cardUser || cardVenue !== venueID) { res.status(409).json({ error: "wrong_venue" }); return; }

      let stamps = 0, rewardIssued = false;
      await db.runTransaction(async (tx) => {
        const cardRef = db.collection("loyaltyCards").doc(`${cardUser}_${venueID}`);
        const cur = (await tx.get(cardRef)).data() || {};
        let s = (parseInt(cur.stamps, 10) || 0) + 1;
        let rounds = parseInt(cur.completedRounds, 10) || 0;
        if (s >= goal) { s = 0; rounds += 1; rewardIssued = true; }   // карта заполнена → награда сегодня
        tx.set(cardRef, {
          userID: cardUser, venueID, venueName, goal, reward,
          stamps: s, completedRounds: rounds, updatedAt: new Date(),
        }, { merge: true });
        stamps = s;
      });
      res.status(200).json({
        ok: true, loyalty: true,
        title: rewardIssued ? "Карта заполнена!" : "Штамп начислен",
        stamps, goal, rewardIssued, rewardTitle: rewardIssued ? reward : "",
      });
      return;
    }

    // ── Ветка B: КУПОН акции → только погашение (штамп НЕ начисляется).
    const q = await db.collection("coupons").where("code", "==", code).limit(1).get();
    if (q.empty) { res.status(404).json({ error: "coupon_not_found" }); return; }
    const couponRef = q.docs[0].ref;
    const coupon = q.docs[0].data() || {};
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

    res.status(200).json({
      ok: true, loyalty: false, title: coupon.title || "",
      stamps: 0, goal, rewardIssued: false, rewardTitle: "",
    });
  } catch (e) {
    if (String(e.message) === "already_used") { res.status(409).json({ error: "already_used" }); return; }
    console.error("scanCoupon error:", e);
    res.status(500).json({ error: "scan_failed" });
  }
});

/* ───────────────────────────────────────────────────────────────────────────
 * 7) Купон в Apple Wallet (.pkpass со сканируемым QR = code).
 *    GET /generateCouponPass?code=<code>&title=<title>&venue=<venueName>
 * ─────────────────────────────────────────────────────────────────────────── */
exports.generateCouponPass = onRequest({ cors: true }, async (req, res) => {
  try {
    const code = String(req.query.code || "");
    const title = String(req.query.title || "Купон");
    const venue = String(req.query.venue || "Ayant");
    if (!code) { res.status(400).send("missing code"); return; }
    if (WALLET_CONFIGURED !== "1") { res.status(503).json({ error: "wallet_not_configured" }); return; }

    const { PKPass } = require("passkit-generator");
    const fs = require("fs");
    const path = require("path");
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

    addIcons(pass, path.join(certDir, "images"), fs, path);
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
