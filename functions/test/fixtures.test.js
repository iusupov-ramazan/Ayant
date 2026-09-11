"use strict";

/**
 * Прогон общего фикстура `specs/fixtures/points-fixtures.json` через НАСТОЯЩИЕ
 * обработчики `scanCoupon` (ветка C) и `redeemVenuePoints`.
 *
 * Тот же файл гоняют iOS (`SANTests/PointsFixtureTests.swift`) и Android
 * (`PointsFixtureTest.kt`) — там он проверяет клиентский `PointsMath`, который
 * только предсказывает результат для UI. Здесь — авторитетный расчёт. Расхождение
 * между ними означает обещание в приложении, которое сервер не выполнит.
 *
 * Специально НЕ вынесено в отдельную чистую функцию: тест должен ловить дрейф
 * того кода, который реально задеплоен, а не его копии.
 *
 * Новый кейс добавляется в JSON, а не сюда.
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { makeHarness, makeReq, makeRes } = require("./helpers/harness");

const FIXTURE_PATH = path.join(__dirname, "..", "..", "specs", "fixtures", "points-fixtures.json");
const fixture = JSON.parse(fs.readFileSync(FIXTURE_PATH, "utf8"));

const HOST = "host-uid";
const TOKEN = "host-token";
const USER = "u1";
const VENUE = "v1";

function harness() {
  return makeHarness({ tokens: { [TOKEN]: HOST } });
}

function bearer() {
  return { Authorization: `Bearer ${TOKEN}` };
}

/** Заведение хоста с конфигурацией баллов из кейса. */
function seedVenue(h, config) {
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе", ...config });
}

/** Карта баллов гостя. lastEarnAt — как Timestamp-подобный объект (как в Firestore). */
function seedCard(h, { balance = 0, lastEarnAtMs = null } = {}) {
  const card = { userID: USER, venueID: VENUE, balance };
  if (lastEarnAtMs !== null) card.lastEarnAt = { toMillis: () => lastEarnAtMs };
  h.seed(`venuePoints/${USER}_${VENUE}`, card);
}

async function scan(h, body) {
  const res = makeRes();
  await h.mod.scanCoupon(makeReq({ method: "POST", headers: bearer(), body }), res);
  return res;
}

async function redeem(h, body) {
  const res = makeRes();
  await h.mod.redeemVenuePoints(makeReq({ method: "POST", headers: bearer(), body }), res);
  return res;
}

/* ═══════════════════════════ Начисление ════════════════════════════════════ */

assert.ok(fixture.award.length > 0, "В фикстуре нет кейсов начисления");

for (const c of fixture.award) {
  test(`фикстур/начисление: ${c.name}`, async () => {
    const h = harness();
    seedVenue(h, c.config);
    const body = { code: `AYANT-PTS:${USER}`, venueID: VENUE };
    if (c.billAmount !== null && c.billAmount !== undefined) body.billAmount = c.billAmount;
    if (c.bandIndex !== null && c.bandIndex !== undefined) body.bandIndex = c.bandIndex;

    const res = await scan(h, body);

    if (c.expect.error) {
      assert.equal(res.body.error, c.expect.error, `ожидался отказ ${c.expect.error}`);
    } else {
      assert.equal(res.statusCode, 200, `ожидалось начисление, получено ${JSON.stringify(res.body)}`);
      assert.equal(res.body.awarded, c.expect.points);
      // Баланс новой карты равен начислению — начисление реально записано.
      assert.equal(h.read(`venuePoints/${USER}_${VENUE}`).balance, c.expect.points);
    }
  });
}

/* ═══════════════════════════ Кулдаун ═══════════════════════════════════════ */

assert.ok(fixture.cooldown.length > 0, "В фикстуре нет кейсов кулдауна");

for (const c of fixture.cooldown) {
  test(`фикстур/кулдаун: ${c.name}`, async () => {
    const h = harness();
    seedVenue(h, {
      pointsEnabled: true, pointsMode: "flat", pointsFlat: 5,
      earnCooldownMinutes: c.earnCooldownMinutes,
    });
    if (c.minutesSinceLastEarn !== null && c.minutesSinceLastEarn !== undefined) {
      seedCard(h, { balance: 5, lastEarnAtMs: Date.now() - c.minutesSinceLastEarn * 60000 });
    }

    const res = await scan(h, { code: `AYANT-PTS:${USER}`, venueID: VENUE });

    if (c.expect.canEarn) {
      assert.equal(res.statusCode, 200, `начисление должно было пройти, получено ${JSON.stringify(res.body)}`);
      assert.equal(res.body.awarded, 5);
    } else {
      assert.equal(res.statusCode, 429, `кулдаун должен был заблокировать, получено ${JSON.stringify(res.body)}`);
      assert.equal(res.body.error, "cooldown");
    }
  });
}

/* ═══════════════════════════ Списание ══════════════════════════════════════ */

assert.ok(fixture.redeem.length > 0, "В фикстуре нет кейсов списания");

for (const c of fixture.redeem) {
  test(`фикстур/списание: ${c.name}`, async () => {
    const h = harness();
    seedVenue(h, { redeemMode: "staffScan", pointsRewards: c.rewards });
    seedCard(h, { balance: c.balance });

    const res = await redeem(h, {
      venueID: VENUE, userID: USER, rewardId: c.rewardId, pointsToSpend: c.pointsToSpend,
    });

    if (c.expect.error) {
      assert.equal(res.body.error, c.expect.error, `ожидался отказ ${c.expect.error}`);
      if (c.expect.minRedeem !== undefined) assert.equal(res.body.minRedeem, c.expect.minRedeem);
      // Баланс не тронут.
      assert.equal(h.read(`venuePoints/${USER}_${VENUE}`).balance, c.balance);
    } else {
      assert.equal(res.statusCode, 200, `ожидалось списание, получено ${JSON.stringify(res.body)}`);
      assert.equal(res.body.redeemed, c.expect.cost);
      assert.equal(res.body.balance, c.expect.newBalance);
      assert.equal(res.body.somOff, c.expect.somOff);
      assert.equal(h.read(`venuePoints/${USER}_${VENUE}`).balance, c.expect.newBalance);
    }
  });
}
