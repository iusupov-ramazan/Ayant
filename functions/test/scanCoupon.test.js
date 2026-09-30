"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeHarness, makeReq, makeRes } = require("./helpers/harness");

const HOST = "host-uid";
const TOKEN = "good-token";
const VENUE = "v1";

// Заведение, принадлежащее хосту, с включённой лояльностью.
function seedVenue(h, extra = {}) {
  h.seed(`venues/${VENUE}`, {
    ownerID: HOST,
    name: "Кафе",
    loyaltyEnabled: true,
    loyaltyGoal: 6,
    loyaltyReward: "Кофе в подарок",
    ...extra,
  });
}

// Успешно аутентифицированный POST-запрос с телом.
function post(body) {
  return makeReq({
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}` },
    body,
  });
}

async function call(h, req) {
  const res = makeRes();
  await h.mod.scanCoupon(req, res);
  return res;
}

// Найти документ дневной аналитики заведения (дата зависит от UTC-времени прогона).
function analyticsDay(h, venue) {
  for (const [path, data] of h.db.store.entries()) {
    if (path.startsWith(`analytics/${venue}/days/`)) return data;
  }
  return undefined;
}

/* ── Аутентификация и валидация ─────────────────────────────────────────── */

test("отклоняет не-POST", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  const res = await call(h, makeReq({ method: "GET" }));
  assert.equal(res.statusCode, 405);
  assert.equal(res.body.error, "method_not_allowed");
});

test("без заголовка Authorization → 401 no_token", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  const res = await call(h, makeReq({ method: "POST", body: { code: "X", venueID: VENUE } }));
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "no_token");
});

test("невалидный ID-токен → 401 bad_token", async () => {
  const h = makeHarness({ tokens: {} }); // ни один токен не проходит
  const req = makeReq({ method: "POST", headers: { Authorization: "Bearer nope" }, body: { code: "X", venueID: VENUE } });
  const res = await call(h, req);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "bad_token");
});

test("без code/venueID → 400 missing_params", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  const res = await call(h, post({ code: "", venueID: "" }));
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, "missing_params");
});

/* ── Владение заведением ─────────────────────────────────────────────────── */

test("заведение не найдено → 404", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  const res = await call(h, post({ code: "ABC", venueID: VENUE }));
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error, "venue_not_found");
});

test("хост не владелец заведения → 403 not_owner", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { ownerID: "someone-else" });
  const res = await call(h, post({ code: "ABC", venueID: VENUE }));
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "not_owner");
});

/* ── Ветка A: карта лояльности (AYANT-CARD) ─────────────────────────────── */

test("лояльность выключена → 409 loyalty_off", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { loyaltyEnabled: false });
  const res = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE }));
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "loyalty_off");
});

test("баллы включены → штамп не начисляется (одна механика на заведение)", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  // Оба флага сразу: так выглядит заведение, где штампы остались с прошлой
  // настройки, а потом включили баллы САН. Штамп начисляться не должен —
  // иначе один визит оплачивается дважды.
  seedVenue(h, { loyaltyEnabled: true, pointsEnabled: true });
  const res = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE }));
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "loyalty_is_points");
});

test("карта другого заведения → 409 wrong_venue", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  const res = await call(h, post({ code: "AYANT-CARD:u1:OTHER", venueID: VENUE }));
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "wrong_venue");
});

test("начисляет штамп на новую карту (0 → 1)", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  const res = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE }));
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
  assert.equal(res.body.loyalty, true);
  assert.equal(res.body.rewardIssued, false);
  assert.equal(res.body.stamps, 1);
  assert.equal(res.body.title, "Штамп начислен");

  const card = h.read(`loyaltyCards/u1_${VENUE}`);
  assert.equal(card.stamps, 1);
  assert.equal(card.completedRounds || 0, 0);
});

test("на цели карта обнуляется и выдаёт награду", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h); // goal = 6
  h.seed(`loyaltyCards/u1_${VENUE}`, { userID: "u1", venueID: VENUE, stamps: 5, completedRounds: 0 });
  const res = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE }));
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.rewardIssued, true);
  assert.equal(res.body.stamps, 0);
  assert.equal(res.body.rewardTitle, "Кофе в подарок");
  assert.equal(res.body.title, "Карта заполнена!");

  const card = h.read(`loyaltyCards/u1_${VENUE}`);
  assert.equal(card.stamps, 0);
  assert.equal(card.completedRounds, 1);
});

/* ── Пауза между штампами: config/appSettings.stampCooldownMinutes ─────── */

test("CARD: без настроек повторный скан внутри 15 мин → 429 cooldown", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  const first = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "cd-1" }));
  assert.equal(first.statusCode, 200);
  // Другой ключ = другой скан (не ретрай) → окно действует.
  const again = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "cd-2" }));
  assert.equal(again.statusCode, 429);
  assert.equal(again.body.error, "cooldown");
  assert.ok(again.body.retryAfterSec > 0 && again.body.retryAfterSec <= 15 * 60);
  assert.equal(h.read(`loyaltyCards/u1_${VENUE}`).stamps, 1);
});

test("CARD: stampCooldownMinutes: 0 в настройках → штамп на каждый скан", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  h.seed("config/appSettings", { stampCooldownMinutes: 0 });
  const first = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "z-1" }));
  const again = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "z-2" }));
  assert.equal(first.statusCode, 200);
  assert.equal(again.statusCode, 200);
  assert.equal(again.body.stamps, 2);
});

test("CARD: окно берётся из настроек панели (30 мин)", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  h.seed("config/appSettings", { stampCooldownMinutes: 30 });
  await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "w-1" }));
  const again = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "w-2" }));
  assert.equal(again.statusCode, 429);
  // Больше дефолтных 15 минут — значит, прочитано именно значение из настроек.
  assert.ok(again.body.retryAfterSec > 15 * 60 && again.body.retryAfterSec <= 30 * 60);
});

test("CARD: мусор в настройках → дефолтные 15 мин, скан не падает", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  h.seed("config/appSettings", { stampCooldownMinutes: "abc" });
  const first = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "g-1" }));
  assert.equal(first.statusCode, 200);
  const again = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "g-2" }));
  assert.equal(again.statusCode, 429);
  assert.ok(again.body.retryAfterSec <= 15 * 60);
});

test("CARD: тот же ключ на другую карту → 409 key_reused, штамп не начисляется", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  h.seed("config/appSettings", { stampCooldownMinutes: 0 });
  const first = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "same" }));
  assert.equal(first.statusCode, 200);
  // Ключ живёт на карте u1: тот же ключ с другим кодом на ЭТОЙ карте — коллизия.
  h.seed(`loyaltyCards/u1_${VENUE}/scanKeys/same`, { code: "AYANT-CARD:u9:OTHER", stamps: 7, rewardIssued: false });
  const clash = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "same" }));
  assert.equal(clash.statusCode, 409);
  assert.equal(clash.body.error, "key_reused");
  assert.equal(h.read(`loyaltyCards/u1_${VENUE}`).stamps, 1);
});

test("CARD: окно из настроек клэмпится сверху до 1440 мин", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  h.seed("config/appSettings", { stampCooldownMinutes: 999999 });
  await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "c-1" }));
  const again = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "c-2" }));
  assert.equal(again.statusCode, 429);
  assert.ok(again.body.retryAfterSec > 30 * 60 && again.body.retryAfterSec <= 1440 * 60);
});

test("CARD: ретрай с тем же ключом внутри окна возвращает исходный результат, не 429", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  const first = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "r-1" }));
  const retry = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "r-1" }));
  assert.equal(first.statusCode, 200);
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.body.replayed, true);
  assert.equal(h.read(`loyaltyCards/u1_${VENUE}`).stamps, 1);
});

/* ── Несколько карт штампов (stampCards) ─────────────────────────────────
 * Первая карта — скалярные поля заведения, её документ — прежний
 * loyaltyCards/{user}_{venue}; остальные — loyaltyCards/{user}_{venue}_{card}.
 * Скан без cardID (Android, старый iOS) — всегда первая карта. */

const PIZZA = { id: "pizza", title: "Пицца", goal: 3, reward: "Пицца в подарок", active: true };

test("CARDS: без cardID штамп ложится на первую карту, как раньше", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { loyaltyTitle: "Кофе", stampCards: [PIZZA] });
  const res = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "m-1" }));
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.cardID, "default");
  assert.equal(res.body.cardTitle, "Кофе");
  assert.equal(h.read(`loyaltyCards/u1_${VENUE}`).stamps, 1);
  assert.equal(h.read(`extraLoyaltyCards/u1_${VENUE}_pizza`), undefined);
});

test("CARDS: штамп на выбранную карту — свой документ, своя цель и награда", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { stampCards: [PIZZA] });
  h.seed(`extraLoyaltyCards/u1_${VENUE}_pizza`, {
    userID: "u1", venueID: VENUE, cardID: "pizza", stamps: 2, completedRounds: 0,
    lastStampAt: { toMillis: () => 0 },
  });
  const res = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "m-2", cardID: "pizza" }));
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.goal, 3, "цель — у карты пиццы, а не у первой (6)");
  assert.equal(res.body.rewardIssued, true);
  assert.equal(res.body.rewardTitle, "Пицца в подарок");
  assert.equal(res.body.cardTitle, "Пицца");
  const card = h.read(`extraLoyaltyCards/u1_${VENUE}_pizza`);
  assert.equal(card.cardID, "pizza");
  assert.equal(card.title, "Пицца");
  assert.equal(card.completedRounds, 1);
  assert.equal(h.read(`loyaltyCards/u1_${VENUE}`), undefined, "первая карта не тронута");
  const coupons = couponsOf(h);
  assert.equal(coupons.length, 1);
  assert.equal(coupons[0].title, "Пицца в подарок");
  assert.equal(coupons[0].cardID, "pizza");
});

test("CARDS: пауза между штампами — у каждой карты своя", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { stampCards: [PIZZA] });
  // Кофе и пицца в одном визите — оба штампа законны.
  const coffee = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "p-1" }));
  const pizza = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "p-2", cardID: "pizza" }));
  assert.equal(coffee.statusCode, 200);
  assert.equal(pizza.statusCode, 200);
  // А второй штамп на ту же пиццу внутри окна — нет.
  const again = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "p-3", cardID: "pizza" }));
  assert.equal(again.statusCode, 429);
  assert.equal(h.read(`extraLoyaltyCards/u1_${VENUE}_pizza`).stamps, 1);
});

test("CARDS: неизвестная или выключенная карта → 409 card_not_found, штампа нет", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { stampCards: [PIZZA, { id: "tea", title: "Чай", goal: 5, reward: "Чай", active: false }] });
  for (const cardID of ["nope", "tea"]) {
    const res = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: `x-${cardID}`, cardID }));
    assert.equal(res.statusCode, 409);
    assert.equal(res.body.error, "card_not_found");
  }
  assert.equal(h.read(`extraLoyaltyCards/u1_${VENUE}_tea`), undefined);
});

test("CARDS: ретрай с тем же ключом на той же карте — повтор, не второй штамп", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { stampCards: [PIZZA] });
  const first = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "rr", cardID: "pizza" }));
  const retry = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "rr", cardID: "pizza" }));
  assert.equal(first.statusCode, 200);
  assert.equal(retry.body.replayed, true);
  assert.equal(retry.body.cardTitle, "Пицца");
  assert.equal(h.read(`extraLoyaltyCards/u1_${VENUE}_pizza`).stamps, 1);
});

test("CARDS: тот же ключ с другой картой → 409 key_reused, вторая карта не тронута", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { stampCards: [PIZZA] });
  const coffee = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "kk" }));
  assert.equal(coffee.statusCode, 200);
  const pizza = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "kk", cardID: "pizza" }));
  assert.equal(pizza.statusCode, 409);
  assert.equal(pizza.body.error, "key_reused");
  assert.equal(h.read(`extraLoyaltyCards/u1_${VENUE}_pizza`), undefined);
});

test("CARDS: ретрай после выключения карты возвращает исходный результат, не card_not_found", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { stampCards: [PIZZA] });
  const first = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "off", cardID: "pizza" }));
  assert.equal(first.statusCode, 200);
  seedVenue(h, { stampCards: [{ ...PIZZA, active: false }] });
  const retry = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "off", cardID: "pizza" }));
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.body.replayed, true);
  assert.equal(retry.body.goal, 3);
  assert.equal(retry.body.cardTitle, "Пицца");
});

test("CARDS: документы дополнительных карт — не в loyaltyCards (их читают Android и старые iOS)", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { stampCards: [PIZZA] });
  await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "sep", cardID: "pizza" }));
  const legacy = [...h.db.store.keys()].filter((k) => /^loyaltyCards\/[^/]+$/.test(k));
  assert.deepEqual(legacy, [], "в loyaltyCards нет ни одного документа карты");
  assert.equal(h.read(`extraLoyaltyCards/u1_${VENUE}_pizza`).stamps, 1);
});

// Правила отбора карт и id документа — в общем фикстуре
// specs/fixtures/stamp-cards-fixtures.json (stampCardsFixture.test.js).

/* ── Ветка B: купон акции (погашение) ───────────────────────────────────── */

test("купон не найден → 404 coupon_not_found", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  const res = await call(h, post({ code: "NOPE", venueID: VENUE }));
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error, "coupon_not_found");
});

test("купон другого заведения → 409 wrong_venue", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  h.seed("coupons/c1", { code: "ABC", venueID: "other-venue", used: false, title: "Скидка" });
  const res = await call(h, post({ code: "ABC", venueID: VENUE }));
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "wrong_venue");
});

test("уже погашенный купон → 409 already_used (идемпотентность)", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  h.seed("coupons/c1", { code: "ABC", venueID: VENUE, used: true, title: "Скидка" });
  const res = await call(h, post({ code: "ABC", venueID: VENUE }));
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "already_used");
});

test("гасит валидный купон и инкрементит аналитику", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  h.seed("coupons/c1", { code: "ABC", venueID: VENUE, used: false, title: "Скидка 20%" });
  const res = await call(h, post({ code: "ABC", venueID: VENUE }));
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
  assert.equal(res.body.loyalty, false);
  assert.equal(res.body.title, "Скидка 20%");

  // Купон помечен использованным (серверный анти-чит).
  assert.equal(h.read("coupons/c1").used, true);
  // Погашение засчитано в дневную аналитику заведения.
  assert.equal(analyticsDay(h, VENUE).redemptions, 1);
});

// Найти событие журнала ранжирования (rankingEvents/<auto-id>).
function rankingEvent(h) {
  for (const [path, data] of h.db.store.entries()) {
    if (path.startsWith("rankingEvents/")) return data;
  }
  return undefined;
}

test("скан купона пишет серверную метку redeem в rankingEvents (кросс-платформенно)", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { citySlug: "bishkek" });
  h.seed("coupons/c1", {
    code: "ABC", venueID: VENUE, used: false, title: "Скидка 20%",
    userID: "guest-42", dealID: "deal-7",
  });
  const res = await call(h, post({ code: "ABC", venueID: VENUE }));
  assert.equal(res.statusCode, 200);

  const ev = rankingEvent(h);
  assert.ok(ev, "ожидали событие в rankingEvents");
  assert.equal(ev.type, "redeem");        // целевая метка обучения
  assert.equal(ev.userID, "guest-42");    // ключ склейки с impression/tap
  assert.equal(ev.dealID, "deal-7");
  assert.equal(ev.venueID, VENUE);
  assert.equal(ev.citySlug, "bishkek");
  assert.equal(ev.platform, "server");
  assert.equal(ev.sessionID, "server");   // серверу неизвестен клиентский рендер
});

test("скан купона без userID не пишет метку (нечего склеивать)", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  h.seed("coupons/c1", { code: "ABC", venueID: VENUE, used: false, title: "Скидка" });
  await call(h, post({ code: "ABC", venueID: VENUE }));
  assert.equal(rankingEvent(h), undefined);
});

/* ── Заполненная карта → купон-награда + серверная аналитика ────────────── */

function couponsOf(h) {
  const out = [];
  for (const [path, data] of h.db.store.entries()) if (path.startsWith("coupons/")) out.push(data);
  return out;
}

test("CARD: штамп считается в аналитике заведения", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  const res = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "k-1" }));
  assert.equal(res.statusCode, 200);
  assert.equal(analyticsDay(h, VENUE).stamps, 1);
  assert.equal(analyticsDay(h, VENUE).rewardsIssued, undefined);
  assert.equal(couponsOf(h).length, 0, "до заполнения купона нет");
});

test("CARD: заполненная карта выдаёт купон-награду и считает награду", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h, { loyaltyGoal: 3, loyaltyReward: "Кофе в подарок" });
  h.seed(`loyaltyCards/u1_${VENUE}`, {
    userID: "u1", venueID: VENUE, stamps: 2, completedRounds: 0, lastStampAt: { toMillis: () => 0 },
  });
  const res = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "k-2" }));
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.rewardIssued, true);
  assert.equal(h.read(`loyaltyCards/u1_${VENUE}`).stamps, 0);

  const coupons = couponsOf(h);
  assert.equal(coupons.length, 1);
  assert.equal(coupons[0].userID, "u1");
  assert.equal(coupons[0].venueID, VENUE);
  assert.equal(coupons[0].kind, "loyalty");
  assert.equal(coupons[0].title, "Кофе в подарок");
  assert.equal(coupons[0].used, false);
  assert.match(coupons[0].code, /^AYANT-[A-Z2-9]{6}$/);

  assert.equal(analyticsDay(h, VENUE).stamps, 1);
  assert.equal(analyticsDay(h, VENUE).rewardsIssued, 1);

  // Повтор того же скана: ни второго купона, ни второй награды в аналитике.
  const again = await call(h, post({ code: `AYANT-CARD:u1:${VENUE}`, venueID: VENUE, idempotencyKey: "k-2" }));
  assert.equal(again.body.replayed, true);
  assert.equal(couponsOf(h).length, 1);
  assert.equal(analyticsDay(h, VENUE).rewardsIssued, 1);
});

test("купон-награда сканируется как обычный купон и считается в «Погашено»", async () => {
  const h = makeHarness({ tokens: { [TOKEN]: HOST } });
  seedVenue(h);
  h.seed("coupons/c-loyalty", { userID: "u1", venueID: VENUE, title: "Кофе в подарок",
                                code: "AYANT-ABC234", kind: "loyalty", dealID: "", used: false });
  const res = await call(h, post({ code: "AYANT-ABC234", venueID: VENUE }));
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.title, "Кофе в подарок");
  assert.equal(h.read("coupons/c-loyalty").used, true);
  assert.equal(analyticsDay(h, VENUE).redemptions, 1);
});
