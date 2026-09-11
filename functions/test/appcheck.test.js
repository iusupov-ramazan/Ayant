"use strict";

/**
 * App Check для onRequest-функций (checkAppCheck) в трёх режимах env APPCHECK_MODE:
 *   off (по умолчанию) — пропускает без проверки;
 *   monitor            — логирует провал, но ПРОПУСКАЕТ дальше по пайплайну;
 *   enforce            — блокирует (401 app_check_failed) до привилегированной работы.
 *
 * Режим читается на КАЖДЫЙ вызов (не при загрузке модуля), поэтому ставим/снимаем
 * env вокруг каждого теста. Проверяем путь «нет заголовка X-Firebase-AppCheck» —
 * он не дёргает реальный App Check SDK (getAppCheck вызывается только при наличии
 * токена), так что тесты остаются офлайновыми.
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeHarness, makeReq, makeRes } = require("./helpers/harness");

const HOST = "host-uid";
const TOKEN = "host-token";
const VENUE = "v1";

function harness() { return makeHarness({ tokens: { [TOKEN]: HOST } }); }

async function call(fn, req) {
  const res = makeRes();
  await fn(req, res);
  return res;
}

// POST-запрос скана БЕЗ App Check-заголовка (но с валидным Bearer хоста).
function scanReq() {
  return makeReq({
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}` },
    body: { code: "AYANT-XXXX", venueID: VENUE },
  });
}

test("enforce: скан без X-Firebase-AppCheck → 401 app_check_failed (до всего остального)", async () => {
  process.env.APPCHECK_MODE = "enforce";
  try {
    const h = harness();
    h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе" });
    const res = await call(h.mod.scanCoupon, scanReq());
    assert.equal(res.statusCode, 401);
    assert.equal(res.body.error, "app_check_failed");
  } finally { delete process.env.APPCHECK_MODE; }
});

test("monitor: скан без заголовка НЕ блокируется (доходит до логики скана)", async () => {
  process.env.APPCHECK_MODE = "monitor";
  try {
    const h = harness();
    h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе" });
    const res = await call(h.mod.scanCoupon, scanReq());
    // Не app_check_failed: прошли App Check (monitor), купон просто не найден.
    assert.notEqual(res.body.error, "app_check_failed");
    assert.equal(res.statusCode, 404); // coupon_not_found — значит логика скана отработала
  } finally { delete process.env.APPCHECK_MODE; }
});

test("off (по умолчанию): App Check не вмешивается", async () => {
  delete process.env.APPCHECK_MODE;
  const h = harness();
  h.seed(`venues/${VENUE}`, { ownerID: HOST, name: "Кафе" });
  const res = await call(h.mod.scanCoupon, scanReq());
  assert.notEqual(res.body.error, "app_check_failed");
  assert.equal(res.statusCode, 404);
});

test("enforce: wallet-эндпоинт без заголовка → 401 app_check_failed", async () => {
  process.env.APPCHECK_MODE = "enforce";
  try {
    const req = makeReq({ method: "GET", headers: { Authorization: `Bearer ${TOKEN}` },
      query: { venue: VENUE, user: HOST } });
    const res = await call(harness().mod.generateLoyaltyPass, req);
    assert.equal(res.statusCode, 401);
    assert.equal(res.body.error, "app_check_failed");
  } finally { delete process.env.APPCHECK_MODE; }
});
