"use strict";

/**
 * Повторы на денежных путях и потолки из env (аудит 2026-10-01):
 *  • повтор скана отдаётся ДО переписывания QR и проверок конфига — ретрай
 *    после смены механики/выключения карты получает исходный ответ;
 *  • QR списания с nonce: любой повторный скан того же QR — воспроизведение;
 *  • env-потолки кошелька и рефералки прижаты сверху.
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeHarness, makeReq, makeRes, createdEvent } = require("./helpers/harness");

const HOST = "host-uid";
const TOKEN = "host-token";
const GUEST = "guest-uid";
const GUEST_TOKEN = "guest-token";
const VENUE = "v1";

function harness(opts = {}) {
  return makeHarness({ tokens: { [TOKEN]: HOST, [GUEST_TOKEN]: GUEST }, ...opts });
}

async function call(h, name, body, token = TOKEN) {
  const res = makeRes();
  await h.mod[name](makeReq({ method: "POST", headers: { Authorization: `Bearer ${token}` }, body }), res);
  return res;
}

function ledgerOf(h, card) {
  const out = [];
  for (const [path, data] of h.db.store.entries()) {
    if (path.startsWith(`venuePoints/${card}/ledger/`)) out.push(data);
  }
  return out;
}

/** Загрузить модуль с env-переменными (константы читаются при загрузке). */
function withEnv(env, fn) {
  const saved = {};
  for (const k of Object.keys(env)) { saved[k] = process.env[k]; process.env[k] = env[k]; }
  return Promise.resolve().then(fn).finally(() => {
    for (const k of Object.keys(env)) {
      if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k];
    }
  });
}

/* ═══════════════ scanCoupon: повтор до проверок конфига ═══════════════════ */

test("CARD: ретрай после выключения лояльности — исходный ответ, не loyalty_off", async () => {
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", loyaltyEnabled: true, loyaltyGoal: 6, loyaltyReward: "Кофе" });
  const body = { code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "k-card" };
  const first = await call(h, "scanCoupon", body);
  assert.equal(first.statusCode, 200);
  assert.equal(first.body.stamps, 1);

  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", loyaltyEnabled: false });
  const retry = await call(h, "scanCoupon", body);
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.body.replayed, true);
  assert.equal(retry.body.stamps, 1);
  assert.equal(h.read(`loyaltyCards/u1_${VENUE}`).stamps, 1, "второго штампа нет");
});

test("CARD→PTS: заведение переключилось на баллы — ретрай отдаёт штамп, баллы не начисляет", async () => {
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", loyaltyEnabled: true, loyaltyGoal: 6, loyaltyReward: "Кофе" });
  const body = { code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "k-switch" };
  await call(h, "scanCoupon", body);

  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", loyaltyEnabled: true, pointsEnabled: true,
    pointsMode: "flat", pointsFlat: 50 });
  const retry = await call(h, "scanCoupon", body);
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.body.loyalty, true);
  assert.equal(retry.body.replayed, true);
  assert.equal(h.read(`venuePoints/u1_${VENUE}`), undefined, "баллы за тот же визит не начислены");
});

test("PTS: ретрай после выключения баллов — исходный ответ, не points_off", async () => {
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", pointsEnabled: true, pointsMode: "flat", pointsFlat: 40 });
  const body = { code: "AYANT-PTS:u1", venueID: VENUE, idempotencyKey: "k-pts" };
  const first = await call(h, "scanCoupon", body);
  assert.equal(first.body.awarded, 40);

  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", pointsEnabled: false });
  const retry = await call(h, "scanCoupon", body);
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.body.replayed, true);
  assert.equal(retry.body.awarded, 40);
});

test("PTS: ретрай после смены режима на cashback — исходный ответ, не missing_amount", async () => {
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", pointsEnabled: true, pointsMode: "flat", pointsFlat: 40 });
  const body = { code: "AYANT-PTS:u1", venueID: VENUE, idempotencyKey: "k-mode" };
  await call(h, "scanCoupon", body);

  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", pointsEnabled: true, pointsMode: "cashback", cashbackPercent: 5 });
  const retry = await call(h, "scanCoupon", body);
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.body.replayed, true);
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 40);
});

test("ранний повтор: ключ ищется под картой этого гостя; другая форма QR того же гостя — повтор", async () => {
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", pointsEnabled: true, pointsMode: "flat", pointsFlat: 40 });
  await call(h, "scanCoupon", { code: "AYANT-PTS:u1", venueID: VENUE, idempotencyKey: "k-x" });
  // Ключ лежит под картой u1; у u2 его нет — это просто новый скан.
  const other = await call(h, "scanCoupon", { code: "AYANT-PTS:u2", venueID: VENUE, idempotencyKey: "k-x" });
  assert.equal(other.statusCode, 200);
  assert.equal(other.body.replayed, false);
  // А тот же ключ с QR карты u1 (другая форма того же гостя) — повтор, не коллизия.
  const same = await call(h, "scanCoupon", { code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "k-x" });
  assert.equal(same.statusCode, 200);
  assert.equal(same.body.replayed, true);
});

/* ═══════════════ redeemVenuePoints: nonce QR ═════════════════════════════ */

const ITEM = { id: "r1", type: "item", title: "Кофе", cost: 100, active: true };

test("RDM nonce: второй скан того же QR (новый ключ сканера) — повтор, баллы списаны один раз", async () => {
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", redeemMode: "staffScan", pointsRewards: [ITEM] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 250 });
  const nonce = "abcdef1234567890";
  const first = await call(h, "redeemVenuePoints",
    { venueID: VENUE, rewardId: "r1", userID: "u1", idempotencyKey: "scan-1", nonce });
  assert.equal(first.statusCode, 200);
  assert.equal(first.body.replayed, false);
  assert.equal(first.body.balance, 150);

  const second = await call(h, "redeemVenuePoints",
    { venueID: VENUE, rewardId: "r1", userID: "u1", idempotencyKey: "scan-2", nonce });
  assert.equal(second.statusCode, 200);
  assert.equal(second.body.replayed, true);
  assert.equal(second.body.receiptCode, first.body.receiptCode);
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 150);
  assert.equal(ledgerOf(h, `u1_${VENUE}`).length, 1);
  assert.ok(h.read(`venuePoints/u1_${VENUE}/redeemKeys/rdm_${nonce}`), "ключ — rdm_<nonce>");
});

test("RDM nonce: другой QR (новый nonce) — новое списание", async () => {
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", redeemMode: "staffScan", pointsRewards: [ITEM] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 250 });
  await call(h, "redeemVenuePoints", { venueID: VENUE, rewardId: "r1", userID: "u1", nonce: "nonceAAAAAAAAAAA" });
  const second = await call(h, "redeemVenuePoints", { venueID: VENUE, rewardId: "r1", userID: "u1", nonce: "nonceBBBBBBBBBBB" });
  assert.equal(second.body.replayed, false);
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 50);
});

test("RDM nonce: короткий/кривой nonce игнорируется — работает ключ сканера", async () => {
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", redeemMode: "staffScan", pointsRewards: [ITEM] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 250 });
  const res = await call(h, "redeemVenuePoints",
    { venueID: VENUE, rewardId: "r1", userID: "u1", idempotencyKey: "scan-1", nonce: "short" });
  assert.equal(res.statusCode, 200);
  assert.ok(h.read(`venuePoints/u1_${VENUE}/redeemKeys/scan-1`));
  assert.equal(h.read(`venuePoints/u1_${VENUE}/redeemKeys/rdm_short`), undefined);
});

test("RDM nonce: у гостя (не владелец) nonce не подменяет его ключ", async () => {
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", redeemMode: "customerInitiated", pointsRewards: [ITEM] });
  h.seed(`venuePoints/${GUEST}_${VENUE}`, { userID: GUEST, venueID: VENUE, balance: 250 });
  const res = await call(h, "redeemVenuePoints",
    { venueID: VENUE, rewardId: "r1", idempotencyKey: "guest-key", nonce: "abcdef1234567890" }, GUEST_TOKEN);
  assert.equal(res.statusCode, 200);
  assert.ok(h.read(`venuePoints/${GUEST}_${VENUE}/redeemKeys/guest-key`));
});

test("RDM без nonce (старый QR) — как раньше, по ключу сканера", async () => {
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", redeemMode: "staffScan", pointsRewards: [ITEM] });
  h.seed(`venuePoints/u1_${VENUE}`, { userID: "u1", venueID: VENUE, balance: 250 });
  const body = { venueID: VENUE, rewardId: "r1", userID: "u1", idempotencyKey: "legacy" };
  await call(h, "redeemVenuePoints", body);
  const again = await call(h, "redeemVenuePoints", body);
  assert.equal(again.body.replayed, true);
  assert.equal(h.read(`venuePoints/u1_${VENUE}`).balance, 150);
});

/* ═══════════════ env-потолки ══════════════════════════════════════════════ */

function bishkekDay(ms = Date.now()) {
  return new Date(ms + 6 * 3600000).toISOString().slice(0, 10);
}

test("clampedCapFromEnv: мусор — дефолт, вне границ — прижимается, явный 0 — 0", () => {
  const h = harness();
  const f = h.mod.clampedCapFromEnv;
  assert.equal(f(undefined, 30, 0, 500), 30);
  assert.equal(f("", 30, 0, 500), 30);
  assert.equal(f("abc", 30, 0, 500), 30);
  assert.equal(f("0", 30, 0, 500), 0);
  assert.equal(f("99999", 30, 0, 500), 500);
  assert.equal(f("-5", 30, 0, 500), 0);
  assert.equal(f("12.7", 30, 0, 500), 12);
});

test("env BONUS_DIAMOND_DAILY_CAP: потолок Diamond настраивается", async () => {
  await withEnv({ BONUS_DIAMOND_DAILY_CAP: "10" }, async () => {
    const h = makeHarness({ tokens: { [GUEST_TOKEN]: GUEST } });
    h.seed(`bonusWallets/${GUEST}`, { balance: 0, earnDay: bishkekDay(), earnedToday: 0 });
    const res = await call(h, "earnBonus", { amount: 25, source: "game:diamond", idempotencyKey: "d1" }, GUEST_TOKEN);
    assert.equal(res.body.granted, 10);
  });
});

test("env BONUS_DIAMOND_DAILY_CAP: опечатка сверх 500 прижимается к 500", async () => {
  await withEnv({ BONUS_DIAMOND_DAILY_CAP: "100000", BONUS_DAILY_EARN_CAP: "2000" }, async () => {
    const h = makeHarness({ tokens: { [GUEST_TOKEN]: GUEST } });
    h.seed(`bonusWallets/${GUEST}`, { balance: 0, earnDay: bishkekDay(), earnedToday: 0,
      earnedBySource: { "game:diamond": 499 } });
    const res = await call(h, "earnBonus", { amount: 50, source: "game:diamond", idempotencyKey: "d2" }, GUEST_TOKEN);
    assert.equal(res.body.granted, 1);
  });
});

test("env BONUS_DAILY_EARN_CAP: лишний ноль не снимает потолок — не больше 2000", async () => {
  await withEnv({ BONUS_DAILY_EARN_CAP: "200000" }, async () => {
    const h = makeHarness({ tokens: { [GUEST_TOKEN]: GUEST } });
    h.seed(`bonusWallets/${GUEST}`, { balance: 0, earnDay: bishkekDay(), earnedToday: 1990 });
    const res = await call(h, "earnBonus", { amount: 50, source: "game:snake", idempotencyKey: "e1" }, GUEST_TOKEN);
    assert.equal(res.body.granted, 10);
  });
});

test("env BONUS_TIME_DAILY_CAP: не больше 100", async () => {
  await withEnv({ BONUS_TIME_DAILY_CAP: "5000" }, async () => {
    const h = makeHarness({ tokens: { [GUEST_TOKEN]: GUEST } });
    h.seed(`bonusWallets/${GUEST}`, { balance: 0, earnDay: bishkekDay(), earnedToday: 0,
      earnedBySource: { time: 95 } });
    const res = await call(h, "earnBonus", { amount: 50, source: "time", idempotencyKey: "t1" }, GUEST_TOKEN);
    assert.equal(res.body.granted, 5);
  });
});

test("env REFERRAL_REWARD / REFERRAL_WELCOME: суммы грантов из env, с потолком 1000", async () => {
  await withEnv({ REFERRAL_REWARD: "250", REFERRAL_WELCOME: "99999" }, async () => {
    const h = makeHarness({ createdAt: { "invitee-9": new Date().toUTCString() } });
    h.seed("referrals/invitee-9", { referrerID: "referrer-9" });
    await h.mod.rewardReferral.run(createdEvent(h, "referrals/invitee-9", { referrerID: "referrer-9" },
      { inviteeID: "invitee-9" }));
    const grants = [...h.db.store.entries()].filter(([p]) => p.startsWith("bonusGrants/")).map(([, g]) => g);
    assert.equal(grants.find((g) => g.reason === "referral").amount, 250);
    assert.equal(grants.find((g) => g.reason === "welcome").amount, 1000);
  });
});
