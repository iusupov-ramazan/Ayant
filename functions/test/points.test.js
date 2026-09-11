"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeHarness, makeReq, makeRes } = require("./helpers/harness");

const HOST = "host-uid";
const GUEST = "guest-uid";
const TOKEN = "host-token";       // → HOST
const GUEST_TOKEN = "guest-token"; // → GUEST
const VENUE = "v1";

function harness() {
  return makeHarness({ tokens: { [TOKEN]: HOST, [GUEST_TOKEN]: GUEST } });
}

// Заведение хоста с произвольной конфигурацией баллов.
function seedVenue(h, extra = {}) {
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", ...extra });
}

function bearer(token) {
  return { Authorization: `Bearer ${token}` };
}

// Собрать записи ledger карты (venuePoints/{card}/ledger/*).
function ledgerOf(h, card) {
  const out = [];
  for (const [path, data] of h.db.store.entries()) {
    if (path.startsWith(`venuePoints/${card}/ledger/`)) out.push(data);
  }
  return out;
}

/* ═══════════════════════ Ветка C scanCoupon: начисление баллов ═══════════════ */

async function scan(h, body) {
  const res = makeRes();
  await h.mod.scanCoupon(makeReq({ method: "POST", headers: bearer(TOKEN), body }), res);
  return res;
}

test("PTS: начисляет flat-баллы новой карте", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "flat", pointsFlat: 5 });
  const res = await scan(h, { code: `AYANT-PTS:u1`, venueID: VENUE });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.points, true);
  assert.equal(res.body.awarded, 5);
  assert.equal(res.body.balance, 5);
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 5);
});

test("PTS: cashback = round(bill × pct%)", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "cashback", cashbackPercent: 10 });
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE, billAmount: 1000 });
  assert.equal(res.body.awarded, 100); // 1000 * 10%
});

test("PTS: cashback capped at MAX_CASHBACK_PERCENT (20%)", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "cashback", cashbackPercent: 50 }); // опечатка «50%»
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE, billAmount: 1000 });
  assert.equal(res.body.awarded, 200); // капнуто на 20% → 200, не 500
});

test("PTS: cashback без суммы → 400 missing_amount", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "cashback", cashbackPercent: 10 });
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE, billAmount: 0 });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, "missing_amount");
});

test("PTS: bands по индексу кнопки", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "bands",
    pointsBands: [{ points: 3 }, { points: 7 }] });
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE, bandIndex: 1 });
  assert.equal(res.body.awarded, 7);
});

test("PTS: неверный индекс band → 400 bad_band", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "bands", pointsBands: [{ points: 3 }] });
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE, bandIndex: 9 });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, "bad_band");
});

test("PTS: баллы выключены → 409 points_off", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: false, pointsMode: "flat", pointsFlat: 5 });
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "points_off");
});

test("PTS: пустой userID в коде → 400 bad_code", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "flat", pointsFlat: 5 });
  const res = await scan(h, { code: "AYANT-PTS:", venueID: VENUE });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, "bad_code");
});

test("PTS: нулевое начисление → 409 no_points", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "flat", pointsFlat: 0 });
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "no_points");
});

test("PTS: начисление капается на MAX_POINTS_PER_EARN (10000)", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "flat", pointsFlat: 999999 });
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE });
  assert.equal(res.body.awarded, 10000);
});

test("PTS: кулдаун блокирует повторный скан → 429", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "flat", pointsFlat: 5, earnCooldownMinutes: 60 });
  h.seed(`venuePoints/u1_${VENUE}`, {
    userID: "u1", venueID: VENUE, balance: 5,
    lastEarnAt: { toMillis: () => Date.now() }, // только что начисляли
  });
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE });
  assert.equal(res.statusCode, 429);
  assert.equal(res.body.error, "cooldown");
  assert.ok(res.body.retryAfterSec > 0);
});

test("PTS: копит баланс и пишет ledger", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "flat", pointsFlat: 10 });
  h.seed(`venuePoints/u1_${VENUE}`, {
    userID: "u1", venueID: VENUE, balance: 50, lifetimeEarned: 50,
    lastEarnAt: { toMillis: () => 0 }, // давно → кулдаун пройден
  });
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE });
  assert.equal(res.body.balance, 60);
  const card = h.read(`venuePoints/u1_${VENUE}`);
  assert.equal(card.balance, 60);
  assert.equal(card.lifetimeEarned, 60);
  const ledger = ledgerOf(h, `u1_${VENUE}`);
  assert.equal(ledger.length, 1);
  assert.equal(ledger[0].type, "earn");
  assert.equal(ledger[0].points, 10);
});

/* ═══════════════════════ redeemVenuePoints: списание баллов ═════════════════ */

async function redeem(h, token, body) {
  const res = makeRes();
  await h.mod.redeemVenuePoints(makeReq({ method: "POST", headers: bearer(token), body }), res);
  return res;
}

const ITEM_REWARD = { id: "r1", type: "item", cost: 100, title: "Кофе в подарок", active: true };

test("redeem: не-POST → 405", async () => {
  const h = harness();
  const res = makeRes();
  await h.mod.redeemVenuePoints(makeReq({ method: "GET" }), res);
  assert.equal(res.statusCode, 405);
});

test("redeem: без токена → 401", async () => {
  const h = harness();
  const res = makeRes();
  await h.mod.redeemVenuePoints(makeReq({ method: "POST", body: { venueID: VENUE, rewardId: "r1" } }), res);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "no_token");
});

test("redeem: без venueID/rewardId → 400 missing_params", async () => {
  const h = harness();
  const res = await redeem(h, TOKEN, { venueID: "", rewardId: "" });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, "missing_params");
});

test("redeem: заведение не найдено → 404", async () => {
  const h = harness();
  const res = await redeem(h, TOKEN, { venueID: VENUE, rewardId: "r1", userID: "u1" });
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error, "venue_not_found");
});

test("redeem: владелец гасит item-награду гостя (staffScan)", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan", pointsRewards: [ITEM_REWARD] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 150 });
  const res = await redeem(h, TOKEN, { venueID: VENUE, rewardId: "r1", userID: "u1" });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.redeemed, 100);
  assert.equal(res.body.balance, 50);
  assert.equal(res.body.rewardTitle, "Кофе в подарок");
  const ledger = ledgerOf(h, `u1_${VENUE}`);
  assert.equal(ledger[0].type, "redeem");
  assert.equal(ledger[0].points, -100);
});

test("redeem: недостаточно баллов → 409 insufficient", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan", pointsRewards: [ITEM_REWARD] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 50 });
  const res = await redeem(h, TOKEN, { venueID: VENUE, rewardId: "r1", userID: "u1" });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "insufficient");
});

test("redeem: владелец без userID → 400 missing_user", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan", pointsRewards: [ITEM_REWARD] });
  const res = await redeem(h, TOKEN, { venueID: VENUE, rewardId: "r1" });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, "missing_user");
});

test("redeem: гость гасит сам при customerInitiated", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "customerInitiated", pointsRewards: [ITEM_REWARD] });
  h.seed(`venuePoints/${GUEST}_${VENUE}`, { userID: GUEST, venueID: VENUE, balance: 200 });
  const res = await redeem(h, GUEST_TOKEN, { venueID: VENUE, rewardId: "r1" });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.balance, 100);
});

test("redeem: посторонний при staffScan → 403 redeem_not_allowed", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan", pointsRewards: [ITEM_REWARD] });
  const res = await redeem(h, GUEST_TOKEN, { venueID: VENUE, rewardId: "r1", userID: GUEST });
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "redeem_not_allowed");
});

test("redeem: money-награда ниже минимума → 400 below_min", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan",
    pointsRewards: [{ id: "m1", type: "money", cost: 50, ratio: 1, title: "Скидка", active: true }] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 200 });
  const res = await redeem(h, TOKEN, { venueID: VENUE, rewardId: "m1", userID: "u1", pointsToSpend: 30 });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, "below_min");
  assert.equal(res.body.minRedeem, 50);
});

test("redeem: money-награда списывает pointsToSpend и считает somOff", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan",
    pointsRewards: [{ id: "m1", type: "money", cost: 50, ratio: 1, title: "Скидка", active: true }] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 200 });
  const res = await redeem(h, TOKEN, { venueID: VENUE, rewardId: "m1", userID: "u1", pointsToSpend: 100 });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.redeemed, 100);
  assert.equal(res.body.balance, 100);
  assert.equal(res.body.somOff, 100); // cost * ratio(1)
});

test("redeem: неизвестная награда → 404 reward_not_found", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan", pointsRewards: [ITEM_REWARD] });
  const res = await redeem(h, TOKEN, { venueID: VENUE, rewardId: "nope", userID: "u1" });
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error, "reward_not_found");
});

/* ═══════════════════════ expireVenuePoints: сгорание баллов ═════════════════ */

const MONTH_MS = 30 * 86400000;

test("expire: обнуляет карту с истёкшей активностью и пишет ledger", async () => {
  const h = harness();
  seedVenue(h, { pointsExpiryMonths: 6 });
  h.seed(`venuePoints/u1_${VENUE}`, {
    userID: "u1", venueID: VENUE, balance: 80,
    lastActivityAt: { toMillis: () => Date.now() - 7 * MONTH_MS }, // 7 мес > 6
  });
  await h.mod.expireVenuePoints.run({});
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 0);
  const ledger = ledgerOf(h, `u1_${VENUE}`);
  assert.equal(ledger[0].type, "expire");
  assert.equal(ledger[0].points, -80);
});

test("expire: свежую карту не трогает", async () => {
  const h = harness();
  seedVenue(h, { pointsExpiryMonths: 6 });
  h.seed(`venuePoints/u1_${VENUE}`, {
    userID: "u1", venueID: VENUE, balance: 80,
    lastActivityAt: { toMillis: () => Date.now() - 1 * MONTH_MS }, // 1 мес < 6
  });
  await h.mod.expireVenuePoints.run({});
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 80);
  assert.equal(ledgerOf(h, `u1_${VENUE}`).length, 0);
});

test("expire: уважает per-venue порог pointsExpiryMonths", async () => {
  const h = harness();
  seedVenue(h, { pointsExpiryMonths: 1 }); // короткий порог
  h.seed(`venuePoints/u1_${VENUE}`, {
    userID: "u1", venueID: VENUE, balance: 40,
    lastActivityAt: { toMillis: () => Date.now() - 40 * 86400000 }, // 40 дней > 1 мес
  });
  await h.mod.expireVenuePoints.run({});
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 0);
});

/* ═══════════════════════ redeemVenuePoints: идемпотентность ════════════════ */
//
// Ключ генерирует клиент один раз на попытку списания и повторяет при ретрае.
// Второй запрос с тем же ключом обязан вернуть ТОТ ЖЕ ответ и НЕ списать снова —
// иначе таймаут сети или второй тап по кнопке стоят гостю двойных баллов.

const IDEM = { id: "r1", type: "item", cost: 100, title: "Кофе в подарок", active: true };

test("redeem: повтор с тем же idempotencyKey не списывает второй раз", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan", pointsRewards: [IDEM] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 250 });

  const body = { venueID: VENUE, rewardId: "r1", userID: "u1", idempotencyKey: "key-abc" };
  const first = await redeem(h, TOKEN, body);
  assert.equal(first.statusCode, 200);
  assert.equal(first.body.redeemed, 100);
  assert.equal(first.body.balance, 150);
  assert.equal(first.body.replayed, false);

  const second = await redeem(h, TOKEN, body);
  assert.equal(second.statusCode, 200);
  assert.equal(second.body.redeemed, 100);       // тот же ответ…
  assert.equal(second.body.balance, 150);
  assert.equal(second.body.replayed, true);
  // …и баланс не тронут повторно.
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 150);
  assert.equal(ledgerOf(h, `u1_${VENUE}`).length, 1);   // одна строка ledger, не две
});

test("redeem: разные ключи списывают дважды (это разные списания)", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan", pointsRewards: [IDEM] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 250 });

  await redeem(h, TOKEN, { venueID: VENUE, rewardId: "r1", userID: "u1", idempotencyKey: "k1" });
  const second = await redeem(h, TOKEN, { venueID: VENUE, rewardId: "r1", userID: "u1", idempotencyKey: "k2" });
  assert.equal(second.body.balance, 50);
  assert.equal(ledgerOf(h, `u1_${VENUE}`).length, 2);
});

test("redeem: тот же ключ на другую награду → 409 key_reused", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan", pointsRewards: [
    IDEM, { id: "r2", type: "item", cost: 50, title: "Десерт", active: true },
  ] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 250 });

  await redeem(h, TOKEN, { venueID: VENUE, rewardId: "r1", userID: "u1", idempotencyKey: "same" });
  const clash = await redeem(h, TOKEN, { venueID: VENUE, rewardId: "r2", userID: "u1", idempotencyKey: "same" });
  assert.equal(clash.statusCode, 409);
  assert.equal(clash.body.error, "key_reused");
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 150);   // r2 не списан
});

test("redeem: без ключа работает как раньше (ключ необязателен)", async () => {
  const h = harness();
  seedVenue(h, { redeemMode: "staffScan", pointsRewards: [IDEM] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 250 });
  const res = await redeem(h, TOKEN, { venueID: VENUE, rewardId: "r1", userID: "u1" });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.replayed, false);
});

/* ═══════════════════ scanCoupon: идемпотентность начисления ════════════════ */
//
// Кулдаун защищает от случайного перескана, но НЕ от ретрая: если ответ не дошёл,
// повтор внутри окна раньше получал 429 (гость не получил баллы, хост считает, что
// начислил), а повтор после окна начислял второй раз. Ключ закрывает оба случая —
// поэтому он проверяется РАНЬШЕ кулдауна.

test("PTS: повтор скана с тем же ключом не начисляет второй раз", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "flat", pointsFlat: 10, earnCooldownMinutes: 60 });
  const body = { code: "AYANT-PTS:u1", venueID: VENUE, idempotencyKey: "scan-1" };

  const first = await scan(h, body);
  assert.equal(first.statusCode, 200);
  assert.equal(first.body.awarded, 10);
  assert.equal(first.body.balance, 10);
  assert.equal(first.body.replayed, false);

  // Ретрай приходит ВНУТРИ кулдауна — раньше это был бы 429.
  const retry = await scan(h, body);
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.body.awarded, 10);
  assert.equal(retry.body.balance, 10);
  assert.equal(retry.body.replayed, true);

  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 10);
  assert.equal(ledgerOf(h, `u1_${VENUE}`).length, 1);   // одна строка, не две
});

test("PTS: другой ключ внутри кулдауна по-прежнему 429 (кулдаун жив)", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "flat", pointsFlat: 10, earnCooldownMinutes: 60 });

  // Начисляем НАСТОЯЩИМ сканом — lastEarnAt пишет сама функция. Это и проверяет,
  // что ключ идемпотентности стоит ПЕРЕД кулдауном: с тем же ключом пройдёт
  // повтор (тест выше), с другим — упрётся в кулдаун.
  const first = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE, idempotencyKey: "scan-1" });
  assert.equal(first.statusCode, 200);

  const other = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE, idempotencyKey: "scan-2" });
  assert.equal(other.statusCode, 429);
  assert.equal(other.body.error, "cooldown");
  assert.ok(other.body.retryAfterSec > 0);
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 10);   // второй раз не начислили
});

test("PTS: без ключа поведение прежнее", async () => {
  const h = harness();
  seedVenue(h, { pointsEnabled: true, pointsMode: "flat", pointsFlat: 10 });
  const res = await scan(h, { code: "AYANT-PTS:u1", venueID: VENUE });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.replayed, false);
});

test("CARD: повтор скана с тем же ключом не ставит второй штамп", async () => {
  const h = harness();
  seedVenue(h, { loyaltyEnabled: true, loyaltyGoal: 6 });
  const body = { code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "stamp-1" };

  const first = await scan(h, body);
  assert.equal(first.statusCode, 200);
  assert.equal(first.body.stamps, 1);
  assert.equal(first.body.replayed, false);

  const retry = await scan(h, body);
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.body.stamps, 1);      // не 2
  assert.equal(retry.body.replayed, true);
  assert.equal(h.read(`loyaltyCards/u1_${VENUE}`).stamps, 1);
});

test("CARD: ключ хранит выданную награду, повтор её не выдаёт заново", async () => {
  const h = harness();
  seedVenue(h, { loyaltyEnabled: true, loyaltyGoal: 2, loyaltyReward: "Кофе" });
  h.seed(`loyaltyCards/u1_${VENUE}`, {
    userID: "u1", venueID: VENUE, stamps: 1, completedRounds: 0,
    lastStampAt: { toMillis: () => 0 },
  });
  const body = { code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "final" };

  const first = await scan(h, body);
  assert.equal(first.body.rewardIssued, true);
  assert.equal(first.body.stamps, 0);              // карта обнулилась
  assert.equal(h.read(`loyaltyCards/u1_${VENUE}`).completedRounds, 1);

  const retry = await scan(h, body);
  assert.equal(retry.body.rewardIssued, true);     // тот же ответ…
  assert.equal(retry.body.replayed, true);
  assert.equal(h.read(`loyaltyCards/u1_${VENUE}`).completedRounds, 1);   // …но круг один
});
