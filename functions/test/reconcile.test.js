"use strict";

/**
 * Ночная сверка баллов (`reconcileVenuePoints`).
 *
 * Проверяем именно то, ради чего она существует: расхождение баланса с ledger,
 * не отработавшую задачу сгорания и аномальную эмиссию заведения — каждое из
 * этих событий тестом до релиза не поймать, только алертом после.
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeHarness } = require("./helpers/harness");

const DAY = 24 * 60 * 60 * 1000;

function harness() {
  return makeHarness({ tokens: {} });
}

/** Свежий пульс задачи сгорания — чтобы не ловить лишний job_stale. */
function seedFreshHeartbeat(h) {
  h.seed("ops/heartbeats", { expireVenuePoints: { toMillis: () => Date.now() } });
}

/** Алерты, записанные прогоном. */
function alertsOf(h, kind) {
  const out = [];
  for (const [path, data] of h.db.store.entries()) {
    if (path.startsWith("ops/alerts/items/") && (!kind || data.kind === kind)) out.push(data);
  }
  return out;
}

function seedCard(h, id, { balance, venueID = "v1", userID = "u1" }) {
  h.seed(`venuePoints/${id}`, { userID, venueID, balance });
}

function seedLedger(h, card, entries) {
  entries.forEach((e, i) => {
    h.seed(`venuePoints/${card}/ledger/e${i}`, {
      type: e.type, points: e.points,
      at: { toMillis: () => e.atMs ?? Date.now() },
    });
  });
}

async function run(h) {
  await h.mod.reconcileVenuePoints.run({});
}

test("сверка: баланс сходится с ledger → алертов нет", async () => {
  const h = harness();
  seedFreshHeartbeat(h);
  seedCard(h, "u1_v1", { balance: 30 });
  seedLedger(h, "u1_v1", [
    { type: "earn", points: 50 },
    { type: "redeem", points: -20 },
  ]);
  await run(h);
  assert.equal(alertsOf(h, "balance_mismatch").length, 0);
});

test("сверка: расхождение балансa и ledger → alert balance_mismatch", async () => {
  const h = harness();
  seedFreshHeartbeat(h);
  seedCard(h, "u1_v1", { balance: 100 });      // а по ledger должно быть 30
  seedLedger(h, "u1_v1", [
    { type: "earn", points: 50 },
    { type: "redeem", points: -20 },
  ]);
  await run(h);
  const alerts = alertsOf(h, "balance_mismatch");
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].detail.balance, 100);
  assert.equal(alerts[0].detail.ledgerSum, 30);
  assert.equal(alerts[0].detail.delta, 70);
});

test("сверка: новая пустая карта с нулём — это не расхождение", async () => {
  const h = harness();
  seedFreshHeartbeat(h);
  seedCard(h, "u1_v1", { balance: 0 });
  await run(h);
  assert.equal(alertsOf(h, "balance_mismatch").length, 0);
});

test("пульс: expireVenuePoints не отработала сутки → alert job_stale", async () => {
  const h = harness();
  h.seed("ops/heartbeats", { expireVenuePoints: { toMillis: () => Date.now() - 30 * 60 * 60 * 1000 } });
  await run(h);
  const alerts = alertsOf(h, "job_stale");
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].detail.job, "expireVenuePoints");
});

test("пульс: задача не запускалась никогда → alert job_stale", async () => {
  const h = harness();
  await run(h);
  assert.equal(alertsOf(h, "job_stale").length, 1);
});

test("эмиссия: всплеск больше 3× недельного среднего → alert issuance_spike", async () => {
  const h = harness();
  seedFreshHeartbeat(h);
  seedCard(h, "u1_v1", { balance: 1470 });
  // 7 дней по 10 баллов = среднее 10/день; сегодня 1400 → фактор 140.
  const prior = Array.from({ length: 7 }, (_, i) => ({
    type: "earn", points: 10, atMs: Date.now() - (i + 2) * DAY,
  }));
  seedLedger(h, "u1_v1", [...prior, { type: "earn", points: 1400, atMs: Date.now() }]);
  await run(h);
  const alerts = alertsOf(h, "issuance_spike");
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].detail.venueID, "v1");
  assert.equal(alerts[0].detail.issuedToday, 1400);
});

test("эмиссия: ровный день в пределах нормы → алерта нет", async () => {
  const h = harness();
  seedFreshHeartbeat(h);
  seedCard(h, "u1_v1", { balance: 80 });
  const prior = Array.from({ length: 7 }, (_, i) => ({
    type: "earn", points: 10, atMs: Date.now() - (i + 2) * DAY,
  }));
  seedLedger(h, "u1_v1", [...prior, { type: "earn", points: 10, atMs: Date.now() }]);
  await run(h);
  assert.equal(alertsOf(h, "issuance_spike").length, 0);
});

test("эмиссия: у заведения без истории порог не применяется", async () => {
  const h = harness();
  seedFreshHeartbeat(h);
  seedCard(h, "u1_v1", { balance: 5000 });
  seedLedger(h, "u1_v1", [{ type: "earn", points: 5000, atMs: Date.now() }]);
  await run(h);
  assert.equal(alertsOf(h, "issuance_spike").length, 0);
});

test("прогон записывает свой пульс", async () => {
  const h = harness();
  seedFreshHeartbeat(h);
  await run(h);
  assert.ok(h.read("ops/heartbeats").reconcileVenuePoints);
});
