"use strict";

/**
 * Авторизация HTTP-функций Apple Wallet (generateLoyaltyPass / generateCouponPass).
 * Раньше эндпоинты были открыты (onRequest без токена) — любой мог заставить сервер
 * подписывать .pkpass и рендерить canvas (анонимный DoS) и генерировать чужие карты.
 * Теперь требуется валидный Firebase ID-токен; карта лояльности — только на свой userID.
 *
 * Сертификаты в юнит-тестах не настроены (WALLET_CONFIGURED != "1"), поэтому успешная
 * авторизация упирается в мягкий 503 — этого достаточно, чтобы проверить порядок
 * проверок: 401/403 срабатывают ДО генерации.
 */

// Модуль читает WALLET_CONFIGURED при загрузке — гарантируем «не настроено».
delete process.env.WALLET_CONFIGURED;

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeHarness, makeReq, makeRes } = require("./helpers/harness");

const TOKEN = "user-token";
const UID = "user-1";

function harness() { return makeHarness({ tokens: { [TOKEN]: UID } }); }

async function call(fn, req) {
  const res = makeRes();
  await fn(req, res);
  return res;
}

function req({ query = {}, token } = {}) {
  const headers = token ? { Authorization: `Bearer ${token}` } : {};
  return makeReq({ method: "GET", headers, query });
}

/* ── generateLoyaltyPass ─────────────────────────────────────────────────── */

test("loyaltyPass: без токена → 401 no_token", async () => {
  const res = await call(harness().mod.generateLoyaltyPass, req({ query: { venue: "v1", user: UID } }));
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "no_token");
});

test("loyaltyPass: невалидный токен → 401", async () => {
  const res = await call(harness().mod.generateLoyaltyPass, req({ query: { venue: "v1", user: UID }, token: "nope" }));
  assert.equal(res.statusCode, 401);
});

test("loyaltyPass: чужой userID → 403 not_owner", async () => {
  const res = await call(harness().mod.generateLoyaltyPass, req({ query: { venue: "v1", user: "other" }, token: TOKEN }));
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "not_owner");
});

test("loyaltyPass: свой userID проходит авторизацию (503 без сертификатов)", async () => {
  const res = await call(harness().mod.generateLoyaltyPass, req({ query: { venue: "v1", user: UID }, token: TOKEN }));
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.error, "wallet_not_configured");
});

test("loyaltyPass: без venue/user → 400 (ещё до авторизации)", async () => {
  const res = await call(harness().mod.generateLoyaltyPass, req({ query: {} }));
  assert.equal(res.statusCode, 400);
});

/* ── generateCouponPass ──────────────────────────────────────────────────── */

test("couponPass: без токена → 401 no_token", async () => {
  const res = await call(harness().mod.generateCouponPass, req({ query: { code: "AYANT-ABC" } }));
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "no_token");
});

test("couponPass: с токеном проходит авторизацию (503 без сертификатов)", async () => {
  const res = await call(harness().mod.generateCouponPass, req({ query: { code: "AYANT-ABC" }, token: TOKEN }));
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.error, "wallet_not_configured");
});
