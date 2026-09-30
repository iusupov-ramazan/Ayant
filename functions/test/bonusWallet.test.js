"use strict";

/**
 * Серверный кошелёк бонусов: bonusWalletSync / earnBonus / buyCoupon.
 *
 * Это денежный путь: купон, купленный здесь, заведение отдаёт по-настоящему.
 * Поэтому проверяем не только «работает», но и каждое «нельзя»: перенос с
 * потолком, потолки начисления, остаток и модерацию купона, идемпотентность.
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeHarness, makeReq, makeRes } = require("./helpers/harness");

const UID = "guest-uid";
const TOKEN = "guest-token";
const ANON = "anon-uid";
const ANON_TOKEN = "anon-token";
const FRIEND = "friend-uid";
const FRIEND_TOKEN = "friend-token";

function harness(opts = {}) {
  return makeHarness({
    tokens: { [TOKEN]: UID, [ANON_TOKEN]: ANON, [FRIEND_TOKEN]: FRIEND },
    anonymousTokens: [ANON_TOKEN],
    ...opts,
  });
}

async function call(h, name, body, token = TOKEN) {
  const res = makeRes();
  const headers = token ? { Authorization: `Bearer ${token}` } : {};
  await h.mod[name](makeReq({ method: "POST", headers, body }), res);
  return res;
}

const wallet = (h) => h.read(`bonusWallets/${UID}`) || {};
function docsUnder(h, prefix) {
  const out = [];
  for (const [path, data] of h.db.store.entries()) if (path.startsWith(prefix)) out.push({ path, data });
  return out;
}
const ledger = (h) => docsUnder(h, `bonusWallets/${UID}/ledger/`).map((d) => d.data);
const coupons = (h) => docsUnder(h, "coupons/").map((d) => d.data);

function bishkekDay(ms = Date.now()) {
  return new Date(ms + 6 * 3600000).toISOString().slice(0, 10);
}

function seedWallet(h, extra = {}) {
  h.seed(`bonusWallets/${UID}`, { balance: 0, lifetimeEarned: 0, lifetimeSpent: 0, ...extra });
}

function seedOffer(h, extra = {}) {
  // Заведение купона — владельца купона: иначе buyCoupon не продаёт.
  h.seed("venues/v1", { ownerID: "host", name: "Кафе" });
  h.seed("couponOffers/co1", {
    venueID: "v1", venueName: "Кафе", title: "Капучино", cost: 120,
    stock: 5, soldCount: 0, status: "approved", isPaused: false, ownerID: "host", ...extra,
  });
}

/* ═══════════════════════ Авторизация ═══════════════════════════════════════ */

test("кошелёк: без токена → 401 на всех трёх функциях", async () => {
  const h = harness();
  for (const fn of ["bonusWalletSync", "earnBonus", "buyCoupon"]) {
    const res = await call(h, fn, {}, null);
    assert.equal(res.statusCode, 401, fn);
  }
});

/* ═══════════════════════ bonusWalletSync ═══════════════════════════════════ */

test("sync: первый вход переносит баланс устройства", async () => {
  const h = harness();
  const res = await call(h, "bonusWalletSync", { localBalance: 340 });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.balance, 340);
  assert.equal(res.body.migrated, 340);
  assert.equal(wallet(h).balance, 340);
  assert.equal(ledger(h)[0].type, "migrate");
});

test("sync: перенос с потолком — поправленное на телефоне число не становится деньгами", async () => {
  const h = harness();
  const res = await call(h, "bonusWalletSync", { localBalance: 99999 });
  assert.equal(res.body.migrated, 1000);
  assert.equal(wallet(h).balance, 1000);
});

test("sync: перенос только один раз", async () => {
  const h = harness();
  await call(h, "bonusWalletSync", { localBalance: 50 });
  const res = await call(h, "bonusWalletSync", { localBalance: 500 });
  assert.equal(res.body.migrated, 0);
  assert.equal(res.body.balance, 50);
});

test("sync: зачисляет незабранные награды и помечает их забранными", async () => {
  const h = harness();
  h.seed("bonusGrants/g1", { userID: UID, amount: 100, reason: "referral", claimed: false });
  h.seed("bonusGrants/g2", { userID: UID, amount: 100, reason: "referral", claimed: true });
  h.seed("bonusGrants/g3", { userID: "someone-else", amount: 100, claimed: false });
  const res = await call(h, "bonusWalletSync", { localBalance: 0 });
  assert.equal(res.body.granted, 100);
  assert.equal(wallet(h).balance, 100);
  assert.equal(h.read("bonusGrants/g1").claimed, true);
  assert.equal(h.read("bonusGrants/g3").claimed, false);
  // Второй sync ту же награду не зачисляет.
  const again = await call(h, "bonusWalletSync", { localBalance: 0 });
  assert.equal(again.body.granted, 0);
  assert.equal(wallet(h).balance, 100);
});

/* ═══════════════════════ earnBonus ═════════════════════════════════════════ */

test("earn: без кошелька → 409 no_wallet (не затираем перенос нулём)", async () => {
  const h = harness();
  const res = await call(h, "earnBonus", { amount: 5, source: "game:snake", idempotencyKey: "k1" });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "no_wallet");
});

test("earn: начисляет и пишет ledger", async () => {
  const h = harness();
  seedWallet(h, { balance: 10 });
  const res = await call(h, "earnBonus", { amount: 7, source: "game:tetris", idempotencyKey: "k1" });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.granted, 7);
  assert.equal(res.body.balance, 17);
  assert.equal(wallet(h).earnedToday, 7);
  assert.deepEqual(ledger(h).map((l) => l.type), ["earn"]);
});

test("earn: повтор с тем же ключом не начисляет второй раз", async () => {
  const h = harness();
  seedWallet(h);
  await call(h, "earnBonus", { amount: 7, source: "time", idempotencyKey: "k1" });
  const res = await call(h, "earnBonus", { amount: 7, source: "time", idempotencyKey: "k1" });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.replayed, true);
  assert.equal(res.body.granted, 7);
  assert.equal(wallet(h).balance, 7);
});

test("earn: тот же ключ на другую сумму — коллизия, 409 key_reused", async () => {
  const h = harness();
  seedWallet(h);
  await call(h, "earnBonus", { amount: 7, source: "time", idempotencyKey: "k1" });
  const res = await call(h, "earnBonus", { amount: 70, source: "time", idempotencyKey: "k1" });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "key_reused");
  assert.equal(wallet(h).balance, 7);
});

test("earn: потолок за вызов — 100", async () => {
  const h = harness();
  seedWallet(h);
  const res = await call(h, "earnBonus", { amount: 5000, source: "game:2048", idempotencyKey: "k1" });
  assert.equal(res.body.granted, 100);
});

test("earn: дневной потолок — отдаём остаток, дальше ноль", async () => {
  const h = harness();
  seedWallet(h, { earnDay: bishkekDay(), earnedToday: 990 });
  const res = await call(h, "earnBonus", { amount: 50, source: "game:snake", idempotencyKey: "k1" });
  assert.equal(res.body.granted, 10);
  const next = await call(h, "earnBonus", { amount: 50, source: "game:snake", idempotencyKey: "k2" });
  assert.equal(next.statusCode, 200);
  assert.equal(next.body.granted, 0);
});

test("earn: вчерашний счётчик не мешает сегодня", async () => {
  const h = harness();
  seedWallet(h, { earnDay: "2000-01-01", earnedToday: 1000 });
  const res = await call(h, "earnBonus", { amount: 5, source: "time", idempotencyKey: "k1" });
  assert.equal(res.body.granted, 5);
});

test("earn: неизвестный источник, ноль и отрицательное — 400", async () => {
  const h = harness();
  seedWallet(h);
  for (const body of [
    { amount: 5, source: "admin", idempotencyKey: "a" },
    { amount: 0, source: "time", idempotencyKey: "b" },
    { amount: -5, source: "time", idempotencyKey: "c" },
    { amount: 5, source: "time" },
  ]) {
    const res = await call(h, "earnBonus", body);
    assert.equal(res.statusCode, 400, JSON.stringify(body));
  }
  assert.equal(wallet(h).balance, 0);
});

/* ═══════════════════════ buyCoupon: купон заведения ════════════════════════ */

test("buy: списывает бонусы, увеличивает soldCount и выдаёт купон заведения", async () => {
  const h = harness();
  seedWallet(h, { balance: 200 });
  seedOffer(h);
  const res = await call(h, "buyCoupon", { offerID: "co1", idempotencyKey: "b1" });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.balance, 80);
  assert.equal(res.body.cost, 120);
  assert.match(res.body.code, /^AYANT-/);
  assert.equal(wallet(h).balance, 80);
  assert.equal(wallet(h).lifetimeSpent, 120);
  assert.equal(h.read("couponOffers/co1").soldCount, 1);
  const [c] = coupons(h);
  // Купон привязан к заведению — только такой сотрудник может погасить.
  assert.equal(c.userID, UID);
  assert.equal(c.venueID, "v1");
  assert.equal(c.kind, "offer");
  assert.equal(c.used, false);
  assert.equal(c.code, res.body.code);
});

test("buy: цена берётся с сервера, а не из запроса", async () => {
  const h = harness();
  seedWallet(h, { balance: 200 });
  seedOffer(h);
  const res = await call(h, "buyCoupon", { offerID: "co1", cost: 1, idempotencyKey: "b1" });
  assert.equal(res.body.cost, 120);
  assert.equal(wallet(h).balance, 80);
});

test("buy: не хватает бонусов → 409 insufficient, ничего не меняется", async () => {
  const h = harness();
  seedWallet(h, { balance: 100 });
  seedOffer(h);
  const res = await call(h, "buyCoupon", { offerID: "co1", idempotencyKey: "b1" });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "insufficient");
  assert.equal(wallet(h).balance, 100);
  assert.equal(h.read("couponOffers/co1").soldCount, 0);
  assert.equal(coupons(h).length, 0);
});

test("buy: разобранный купон → 409 sold_out", async () => {
  const h = harness();
  seedWallet(h, { balance: 500 });
  seedOffer(h, { stock: 2, soldCount: 2 });
  const res = await call(h, "buyCoupon", { offerID: "co1", idempotencyKey: "b1" });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "sold_out");
});

test("buy: без остатка (stock null) — продаётся без ограничения", async () => {
  const h = harness();
  seedWallet(h, { balance: 500 });
  seedOffer(h, { stock: null, soldCount: 999 });
  const res = await call(h, "buyCoupon", { offerID: "co1", idempotencyKey: "b1" });
  assert.equal(res.statusCode, 200);
});

test("buy: на модерации, на паузе, просрочен → 409 unavailable", async () => {
  for (const extra of [
    { status: "pending" },
    { status: "rejected" },
    { isPaused: true },
    { expiresAt: new Date(Date.now() - 86400000) },
  ]) {
    const h = harness();
    seedWallet(h, { balance: 500 });
    seedOffer(h, extra);
    const res = await call(h, "buyCoupon", { offerID: "co1", idempotencyKey: "b1" });
    assert.equal(res.statusCode, 409, JSON.stringify(extra));
    assert.equal(res.body.error, "unavailable");
    assert.equal(wallet(h).balance, 500);
  }
});

test("buy: нет такого купона → 404", async () => {
  const h = harness();
  seedWallet(h, { balance: 500 });
  const res = await call(h, "buyCoupon", { offerID: "nope", idempotencyKey: "b1" });
  assert.equal(res.statusCode, 404);
});

test("buy: повтор с тем же ключом возвращает тот же купон и не списывает снова", async () => {
  const h = harness();
  seedWallet(h, { balance: 500 });
  seedOffer(h);
  const first = await call(h, "buyCoupon", { offerID: "co1", idempotencyKey: "b1" });
  const again = await call(h, "buyCoupon", { offerID: "co1", idempotencyKey: "b1" });
  assert.equal(again.statusCode, 200);
  assert.equal(again.body.replayed, true);
  assert.equal(again.body.code, first.body.code);
  assert.equal(wallet(h).balance, 380);
  assert.equal(h.read("couponOffers/co1").soldCount, 1);
  assert.equal(coupons(h).length, 1);
});

test("buy: тот же ключ на другую покупку → 409 key_reused", async () => {
  const h = harness();
  seedWallet(h, { balance: 500 });
  seedOffer(h);
  h.seed("couponOffers/co2", { venueID: "v1", title: "Десерт", cost: 50, status: "approved", ownerID: "host" });
  await call(h, "buyCoupon", { offerID: "co1", idempotencyKey: "b1" });
  const res = await call(h, "buyCoupon", { offerID: "co2", idempotencyKey: "b1" });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "key_reused");
});

test("buy: без кошелька → 409 no_wallet; без ключа → 400", async () => {
  const h = harness();
  seedOffer(h);
  const noWallet = await call(h, "buyCoupon", { offerID: "co1", idempotencyKey: "b1" });
  assert.equal(noWallet.body.error, "no_wallet");
  seedWallet(h, { balance: 500 });
  const noKey = await call(h, "buyCoupon", { offerID: "co1" });
  assert.equal(noKey.statusCode, 400);
});

/* ═══════════════════════ buyCoupon: каталог и подарки ══════════════════════ */

function seedCatalog(h) {
  h.seed("config/globalRewards", { items: [
    { id: "r1", title: "Кофе у партнёра", cost: 90, venueID: "v9", venueName: "Партнёр" },
    { id: "r2", title: "Без партнёра", cost: 10, venueID: "" },
  ] });
}

test("buy: награда каталога → купон заведения-партнёра", async () => {
  const h = harness();
  seedWallet(h, { balance: 100 });
  seedCatalog(h);
  const res = await call(h, "buyCoupon", { rewardID: "r1", idempotencyKey: "b1" });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.balance, 10);
  const [c] = coupons(h);
  assert.equal(c.venueID, "v9");
  assert.equal(c.kind, "reward");
});

test("buy: награду без партнёра не продаём (её не погасить у стойки)", async () => {
  const h = harness();
  seedWallet(h, { balance: 100 });
  seedCatalog(h);
  const res = await call(h, "buyCoupon", { rewardID: "r2", idempotencyKey: "b1" });
  assert.equal(res.statusCode, 404);
  assert.equal(wallet(h).balance, 100);
});

test("buy: подарок — списывает и создаёт giftCoupons, купона себе нет", async () => {
  const h = harness();
  seedWallet(h, { balance: 100 });
  seedCatalog(h);
  const res = await call(h, "buyCoupon", { rewardID: "r1", asGift: true, fromName: "Айгерим", idempotencyKey: "g1" });
  assert.equal(res.statusCode, 200);
  assert.match(res.body.giftCode, /^GIFT-/);
  const gift = h.read(`giftCoupons/${res.body.giftCode}`);
  assert.equal(gift.claimed, false);
  assert.equal(gift.fromName, "Айгерим");
  assert.equal(coupons(h).length, 0);
  assert.equal(wallet(h).balance, 10);
});

test("buy: купон заведения подарком — нельзя (400)", async () => {
  const h = harness();
  seedWallet(h, { balance: 500 });
  seedOffer(h);
  const res = await call(h, "buyCoupon", { offerID: "co1", asGift: true, idempotencyKey: "g1" });
  assert.equal(res.statusCode, 400);
  assert.equal(wallet(h).balance, 500);
});

test("buy: offerID и rewardID одновременно или ни одного → 400", async () => {
  const h = harness();
  seedWallet(h, { balance: 500 });
  assert.equal((await call(h, "buyCoupon", { idempotencyKey: "x" })).statusCode, 400);
  assert.equal((await call(h, "buyCoupon", { offerID: "a", rewardID: "b", idempotencyKey: "y" })).statusCode, 400);
});

/* ═══════════════════════ Защита от фарма (аудит 2026-09-30) ═══════════════ */

test("кошелёк: анонимный аккаунт → 403 на sync, earn и buy", async () => {
  const h = harness();
  for (const fn of ["bonusWalletSync", "earnBonus", "buyCoupon", "claimGift"]) {
    const res = await call(h, fn, { localBalance: 1000, amount: 5, source: "time", idempotencyKey: "k" }, ANON_TOKEN);
    assert.equal(res.statusCode, 403, fn);
    assert.equal(res.body.error, "anonymous_not_allowed");
  }
  assert.equal(h.read(`bonusWallets/${ANON}`), undefined);
});

test("sync: новый аккаунт (после запуска кошелька) баланс устройства не переносит", async () => {
  const h = harness({ createdAt: { [UID]: new Date().toUTCString() } });
  const res = await call(h, "bonusWalletSync", { localBalance: 1000 });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.migrated, 0);
  assert.equal(wallet(h).balance, 0);
});

test("earn: у Diamond свой дневной потолок — 30", async () => {
  const h = harness();
  seedWallet(h, { earnDay: bishkekDay(), earnedToday: 0, earnedBySource: { "game:diamond": 25 } });
  const res = await call(h, "earnBonus", { amount: 20, source: "game:diamond", idempotencyKey: "k1" });
  assert.equal(res.body.granted, 5);
  // Другие игры потолком Diamond не ограничены.
  const other = await call(h, "earnBonus", { amount: 20, source: "game:snake", idempotencyKey: "k2" });
  assert.equal(other.body.granted, 20);
});

test("buy: купон, перенацеленный на чужое заведение, не продаётся", async () => {
  const h = harness();
  seedWallet(h, { balance: 500 });
  seedOffer(h);
  h.seed("venues/v2", { ownerID: "competitor", name: "Чужое" });
  h.seed("couponOffers/co1", {
    venueID: "v2", title: "Капучино", cost: 120, status: "approved", ownerID: "host",
  });
  const res = await call(h, "buyCoupon", { offerID: "co1", idempotencyKey: "b1" });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "unavailable");
  assert.equal(wallet(h).balance, 500);
});

/* ═══════════════════════ claimGift ═════════════════════════════════════════ */

async function buyGift(h) {
  seedWallet(h, { balance: 100 });
  h.seed("config/globalRewards", { items: [
    { id: "r1", title: "Кофе у партнёра", cost: 90, venueID: "v9", venueName: "Партнёр" },
  ] });
  const res = await call(h, "buyCoupon", { rewardID: "r1", asGift: true, fromName: "Айгерим", idempotencyKey: "g1" });
  return res.body.giftCode;
}

test("gift: получатель получает купон ЗАВЕДЕНИЯ — его можно погасить", async () => {
  const h = harness();
  const code = await buyGift(h);
  const res = await call(h, "claimGift", { code }, FRIEND_TOKEN);
  assert.equal(res.statusCode, 200);
  const c = coupons(h).find((x) => x.userID === FRIEND);
  assert.equal(c.venueID, "v9");
  assert.equal(c.kind, "gift");
  assert.equal(c.code, res.body.code);
  assert.equal(h.read(`giftCoupons/${code}`).claimed, true);
});

test("gift: второй раз не забрать, повтор тем же получателем — тот же купон", async () => {
  const h = harness();
  const code = await buyGift(h);
  const first = await call(h, "claimGift", { code }, FRIEND_TOKEN);
  const again = await call(h, "claimGift", { code }, FRIEND_TOKEN);
  assert.equal(again.statusCode, 200);
  assert.equal(again.body.replayed, true);
  assert.equal(again.body.code, first.body.code);
  const stranger = await call(h, "claimGift", { code }, TOKEN);
  assert.equal(stranger.statusCode, 409);
  assert.equal(coupons(h).length, 1);
});

test("gift: свой подарок себе не забрать", async () => {
  const h = harness();
  const code = await buyGift(h);
  const res = await call(h, "claimGift", { code }, TOKEN);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "own_gift");
});

test("gift: подарок старой сборки (создан клиентом) — купон без заведения", async () => {
  const h = harness();
  // Клиентская запись могла нести любой venueID — сервер ему не верит.
  h.seed("giftCoupons/GIFT-OLD", { title: "Кофе", code: "GIFT-OLD", claimed: false, venueID: "v9" });
  const res = await call(h, "claimGift", { code: "GIFT-OLD" }, FRIEND_TOKEN);
  assert.equal(res.statusCode, 200);
  assert.equal(coupons(h)[0].venueID, "");
});

test("gift: неизвестный код → 404", async () => {
  const h = harness();
  const res = await call(h, "claimGift", { code: "GIFT-NOPE" }, FRIEND_TOKEN);
  assert.equal(res.statusCode, 404);
});

/* ═══════════════════════ reconcileBonusWallets ═════════════════════════════ */

test("reconcile: баланс ≠ сумме ledger → алерт wallet_mismatch", async () => {
  const h = harness();
  await call(h, "bonusWalletSync", { localBalance: 100 });
  h.seed(`bonusWallets/${UID}`, { ...wallet(h), balance: 5000 });   // «напечатанные» бонусы
  await h.mod.reconcileBonusWallets.run({});
  const alerts = docsUnder(h, "ops/alerts/items/").map((d) => d.data);
  assert.ok(alerts.some((a) => a.kind === "wallet_mismatch" && a.detail.userID === UID));
});

test("reconcile: честный кошелёк — без алертов", async () => {
  const h = harness();
  await call(h, "bonusWalletSync", { localBalance: 100 });
  await call(h, "earnBonus", { amount: 7, source: "time", idempotencyKey: "k" });
  await h.mod.reconcileBonusWallets.run({});
  assert.equal(docsUnder(h, "ops/alerts/items/").length, 0);
});
