"use strict";

/**
 * Аудит запуска (2026-10-01): пуши о новых акциях и отзывах, токен списания
 * баллов, удаление аккаунта владельца, рассылка кампаний, подтверждение почты
 * для денег, подписанные загрузки Cloudinary, телеметрия, потолок инстансов.
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeHarness, makeReq, makeRes, createdEvent, writtenEvent } = require("./helpers/harness");

const HOST = "host-uid", GUEST = "guest-uid", OTHER_HOST = "host2-uid";
const T = { host: "t-host", guest: "t-guest", host2: "t-host2", anon: "t-anon", fresh: "t-fresh", google: "t-google" };
const bearer = (t) => ({ Authorization: `Bearer ${t}` });
const NOW_HTTP = () => new Date().toUTCString();

function harness(opts = {}) {
  return makeHarness({
    tokens: { [T.host]: HOST, [T.guest]: GUEST, [T.host2]: OTHER_HOST, [T.anon]: "anon-uid",
      [T.fresh]: "fresh-uid", [T.google]: "google-uid" },
    anonymousTokens: [T.anon],
    ...opts,
  });
}

async function call(h, fn, token, body, method = "POST") {
  const res = makeRes();
  await h.mod[fn](makeReq({ method, headers: token ? bearer(token) : {}, body }), res);
  return res;
}

/* ═══════════════════════ notifyOnNewDeal ═══════════════════════ */

function dealEvent(h, id, deal) {
  h.seed(`deals/${id}`, deal);
  return createdEvent(h, `deals/${id}`, deal, { id });
}

test("newDeal: пуш только по акции владельца заведения", async () => {
  const h = harness();
  h.seed("venues/v1", { ownerID: HOST, name: "Кафе" });
  await h.mod.notifyOnNewDeal.run(dealEvent(h, "d1", { venueID: "v1", ownerID: "evil", title: "спам" }));
  assert.equal(h.messagingCalls.length, 0, "акция не от владельца — без пуша");
  await h.mod.notifyOnNewDeal.run(dealEvent(h, "d2", { venueID: "v1", ownerID: HOST, title: "−20%" }));
  assert.equal(h.messagingCalls.length, 1);
  assert.equal(h.messagingCalls[0].topic, "venue_v1");
});

test("newDeal: заведение на модерации или на паузе — без пуша; нет статуса = одобрено", async () => {
  const h = harness();
  h.seed("venues/vp", { ownerID: HOST, name: "P", status: "pending" });
  h.seed("venues/vz", { ownerID: HOST, name: "Z", isPaused: true });
  h.seed("venues/vl", { ownerID: HOST, name: "L" });
  await h.mod.notifyOnNewDeal.run(dealEvent(h, "d1", { venueID: "vp", ownerID: HOST, title: "x" }));
  await h.mod.notifyOnNewDeal.run(dealEvent(h, "d2", { venueID: "vz", ownerID: HOST, title: "x" }));
  assert.equal(h.messagingCalls.length, 0);
  await h.mod.notifyOnNewDeal.run(dealEvent(h, "d3", { venueID: "vl", ownerID: HOST, title: "x" }));
  assert.equal(h.messagingCalls.length, 1);
});

test("newDeal: неактивная акция и несуществующее заведение — без пуша", async () => {
  const h = harness();
  h.seed("venues/v1", { ownerID: HOST, name: "Кафе" });
  await h.mod.notifyOnNewDeal.run(dealEvent(h, "d1", { venueID: "v1", ownerID: HOST, status: "draft" }));
  await h.mod.notifyOnNewDeal.run(dealEvent(h, "d2", { venueID: "nope", ownerID: HOST }));
  assert.equal(h.messagingCalls.length, 0);
});

test("newDeal: не больше одного пуша на заведение в сутки", async () => {
  const h = harness();
  h.seed("venues/v1", { ownerID: HOST, name: "Кафе" });
  for (let i = 0; i < 4; i++) {
    await h.mod.notifyOnNewDeal.run(dealEvent(h, `d${i}`, { venueID: "v1", ownerID: HOST, title: `#${i}` }));
  }
  assert.equal(h.messagingCalls.length, 1);
  assert.equal(h.read("pushThrottle/deal_v1").count, 1);
  // Окно прошло — снова можно.
  h.seed("pushThrottle/deal_v1", { windowStart: new Date(Date.now() - 25 * 3600 * 1000), count: 1 });
  await h.mod.notifyOnNewDeal.run(dealEvent(h, "d9", { venueID: "v1", ownerID: HOST, title: "x" }));
  assert.equal(h.messagingCalls.length, 2);
});

test("newDeal: заголовок и текст пуша обрезаются", async () => {
  const h = harness();
  h.seed("venues/v1", { ownerID: HOST, name: "К".repeat(200) });
  await h.mod.notifyOnNewDeal.run(dealEvent(h, "d1", { venueID: "v1", ownerID: HOST, title: "Т".repeat(500) }));
  const n = h.messagingCalls[0].notification;
  assert.ok(Array.from(n.title).length <= 60, `title ${n.title.length}`);
  assert.ok(Array.from(n.body).length <= 140, `body ${n.body.length}`);
  assert.ok(n.body.endsWith("…"));
});

/* ═══════════════════════ notifyHostOnReview: потолок ═══════════════════════ */

test("review push: не больше 10 в сутки на заведение", async () => {
  const h = harness();
  h.seed("venues/v1", { ownerID: HOST, name: "Кафе" });
  h.seed("userTokens/fcm1", { uid: HOST });
  for (let i = 0; i < 13; i++) {
    const r = { venueID: "v1", authorID: `a${i}`, rating: 5, text: "ok" };
    await h.mod.notifyHostOnReview.run(createdEvent(h, `reviews/r${i}`, r, { id: `r${i}` }));
  }
  assert.equal(h.messagingCalls.length, h.mod.REVIEW_PUSH_DAILY_CAP);
});

/* ═══════════════════════ Токен списания ═══════════════════════ */

const REWARDS = [
  { id: "coffee", type: "item", title: "Кофе", cost: 50, active: true },
  { id: "money", type: "money", title: "Скидка", cost: 100, ratio: 1, active: true },
];

function pointsHarness(balance = 200) {
  const h = harness();
  h.seed("venues/v1", { ownerID: HOST, name: "Кафе", pointsEnabled: true, pointsRewards: REWARDS });
  h.seed("venues/v2", { ownerID: OTHER_HOST, name: "Другое", pointsEnabled: true, pointsRewards: REWARDS });
  h.seed(`venuePoints/${GUEST}_v1`, { userID: GUEST, venueID: "v1", balance });
  return h;
}

async function issue(h, body, token = T.guest) {
  return call(h, "issueRedeemToken", token, body);
}

test("issueRedeemToken: выдаёт одноразовый токен без uid", async () => {
  const h = pointsHarness();
  const res = await issue(h, { venueID: "v1", rewardId: "coffee" });
  assert.equal(res.statusCode, 200);
  assert.match(res.body.token, /^[A-Za-z0-9_-]{20,}$/);
  assert.ok(!res.body.token.includes(GUEST));
  assert.ok(res.body.expiresAt > Date.now() + 170 * 1000 && res.body.expiresAt <= Date.now() + 180 * 1000);
  const doc = h.read(`redeemTokens/${res.body.token}`);
  assert.equal(doc.uid, GUEST);
  assert.equal(doc.venueID, "v1");
  assert.equal(doc.rewardId, "coffee");
  assert.equal(doc.used, false);
});

test("issueRedeemToken: не хватает баллов / нет награды / ниже минимума / аноним", async () => {
  const h = pointsHarness(10);
  assert.equal((await issue(h, { venueID: "v1", rewardId: "coffee" })).body.error, "insufficient");
  assert.equal((await issue(h, { venueID: "v1", rewardId: "nope" })).statusCode, 404);
  assert.equal((await issue(h, { venueID: "v1", rewardId: "money", pointsToSpend: 5 })).body.error, "below_min");
  const anon = await issue(h, { venueID: "v1", rewardId: "coffee" }, T.anon);
  assert.equal(anon.statusCode, 403);
  assert.equal(anon.body.error, "anonymous_not_allowed");
  assert.equal((await issue(h, { venueID: "v1", rewardId: "coffee" }, null)).statusCode, 401);
});

test("redeem по токену: списывает, помечает использованным, повтор — replay", async () => {
  const h = pointsHarness(200);
  const tok = (await issue(h, { venueID: "v1", rewardId: "money", pointsToSpend: 120 })).body.token;
  const r1 = await call(h, "redeemVenuePoints", T.host, { venueID: "v1", token: tok });
  assert.equal(r1.statusCode, 200);
  assert.equal(r1.body.redeemed, 120);
  assert.equal(r1.body.balance, 80);
  assert.equal(r1.body.replayed, false);
  assert.equal(h.read(`redeemTokens/${tok}`).used, true);
  // Второй сотрудник сканирует тот же QR — исходный ответ, баллы не списаны.
  const r2 = await call(h, "redeemVenuePoints", T.host, { venueID: "v1", token: tok });
  assert.equal(r2.statusCode, 200);
  assert.equal(r2.body.replayed, true);
  assert.equal(r2.body.redeemed, 120);
  assert.equal(r2.body.receiptCode, r1.body.receiptCode);
  assert.equal(h.read(`venuePoints/${GUEST}_v1`).balance, 80);
  assert.ok(h.read(`venuePoints/${GUEST}_v1/redeemKeys/rdm_${tok}`));
});

test("redeem по токену: награда и сумма — из токена, не из запроса", async () => {
  const h = pointsHarness(200);
  const tok = (await issue(h, { venueID: "v1", rewardId: "coffee" })).body.token;
  const r = await call(h, "redeemVenuePoints", T.host,
    { venueID: "v1", token: tok, rewardId: "money", pointsToSpend: 200, userID: "someone-else" });
  assert.equal(r.statusCode, 200);
  assert.equal(r.body.redeemed, 50);
  assert.equal(r.body.rewardTitle, "Кофе");
  assert.equal(h.read(`venuePoints/${GUEST}_v1`).balance, 150);
});

test("redeem по токену: протухший → token_expired, баллы целы", async () => {
  const h = pointsHarness(200);
  const tok = (await issue(h, { venueID: "v1", rewardId: "coffee" })).body.token;
  h.seed(`redeemTokens/${tok}`, { ...h.read(`redeemTokens/${tok}`), expiresAt: new Date(Date.now() - 1000) });
  const r = await call(h, "redeemVenuePoints", T.host, { venueID: "v1", token: tok });
  assert.equal(r.statusCode, 409);
  assert.equal(r.body.error, "token_expired");
  assert.equal(h.read(`venuePoints/${GUEST}_v1`).balance, 200);
});

test("redeem по токену: повтор после истечения срока — всё равно replay", async () => {
  const h = pointsHarness(200);
  const tok = (await issue(h, { venueID: "v1", rewardId: "coffee" })).body.token;
  await call(h, "redeemVenuePoints", T.host, { venueID: "v1", token: tok });
  h.seed(`redeemTokens/${tok}`, { ...h.read(`redeemTokens/${tok}`), expiresAt: new Date(Date.now() - 1000) });
  const r = await call(h, "redeemVenuePoints", T.host, { venueID: "v1", token: tok });
  assert.equal(r.statusCode, 200);
  assert.equal(r.body.replayed, true);
});

test("redeem по токену: чужое заведение → wrong_venue; угаданный токен → token_not_found", async () => {
  const h = pointsHarness(200);
  const tok = (await issue(h, { venueID: "v1", rewardId: "coffee" })).body.token;
  const wrong = await call(h, "redeemVenuePoints", T.host2, { venueID: "v2", token: tok });
  assert.equal(wrong.statusCode, 409);
  assert.equal(wrong.body.error, "wrong_venue");
  const guess = await call(h, "redeemVenuePoints", T.host, { venueID: "v1", token: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" });
  assert.equal(guess.statusCode, 404);
  assert.equal(guess.body.error, "token_not_found");
  assert.equal(h.read(`venuePoints/${GUEST}_v1`).balance, 200);
  assert.equal(h.read(`redeemTokens/${tok}`).used, false);
});

test("redeem по токену: гасит только владелец заведения", async () => {
  const h = pointsHarness(200);
  const tok = (await issue(h, { venueID: "v1", rewardId: "coffee" })).body.token;
  const r = await call(h, "redeemVenuePoints", T.guest, { venueID: "v1", token: tok });
  assert.equal(r.statusCode, 403);
  assert.equal(h.read(`venuePoints/${GUEST}_v1`).balance, 200);
});

test("redeem по токену: использованный без ключа (гонка) → token_used", async () => {
  const h = pointsHarness(200);
  const tok = (await issue(h, { venueID: "v1", rewardId: "coffee" })).body.token;
  h.seed(`redeemTokens/${tok}`, { ...h.read(`redeemTokens/${tok}`), used: true });
  const r = await call(h, "redeemVenuePoints", T.host, { venueID: "v1", token: tok });
  assert.equal(r.statusCode, 409);
  assert.equal(r.body.error, "token_used");
});

test("старый QR с uid: работает по умолчанию, REDEEM_REQUIRE_TOKEN=true → token_required", async () => {
  const h = pointsHarness(200);
  const legacy = await call(h, "redeemVenuePoints", T.host, { venueID: "v1", rewardId: "coffee", userID: GUEST });
  assert.equal(legacy.statusCode, 200);
  process.env.REDEEM_REQUIRE_TOKEN = "true";
  try {
    const r = await call(h, "redeemVenuePoints", T.host, { venueID: "v1", rewardId: "coffee", userID: GUEST });
    assert.equal(r.statusCode, 400);
    assert.equal(r.body.error, "token_required");
    // Гость сам (customerInitiated) — не затронут флагом.
    h.seed("venues/v1", { ...h.read("venues/v1"), redeemMode: "customerInitiated" });
    const self = await call(h, "redeemVenuePoints", T.guest, { venueID: "v1", rewardId: "coffee" });
    assert.equal(self.statusCode, 200);
  } finally {
    delete process.env.REDEEM_REQUIRE_TOKEN;
  }
});

/* ═══════════════════════ deleteAccount ═══════════════════════ */

test("deleteAccount: владелец — заведения сняты с публикации, акции/купоны удалены, аккаунт удалён", async () => {
  const h = harness();
  h.seed("venues/v1", { ownerID: HOST, name: "Кафе", status: "approved" });
  h.seed("deals/d1", { ownerID: HOST, venueID: "v1" });
  h.seed("deals/d2", { venueID: "v1" });                       // запись админа без ownerID
  h.seed("deals/dx", { ownerID: "other", venueID: "vx" });
  h.seed("couponOffers/o1", { ownerID: HOST, venueID: "v1" });
  h.seed("pushCampaigns/p1", { ownerID: HOST, venueID: "v1" });
  h.seed(`igAccounts/${HOST}_v1`, { ownerID: HOST, accessToken: "secret" });
  h.seed(`igConnections/${HOST}_v1`, { ownerID: HOST });
  h.seed("reviewReports/r_host", { reporterID: HOST, reviewID: "r" });
  h.seed("giftCoupons/GIFT-A", { fromUserID: HOST, claimed: false });
  h.seed("giftCoupons/GIFT-B", { fromUserID: HOST, claimed: true, claimedBy: "friend" });
  h.seed("redeemTokens/tokX", { uid: HOST, venueID: "v9" });
  h.seed(`userLibraries/${HOST}`, { savedVenueIDs: ["v1"], blockedAuthorIDs: ["x"] });
  h.seed("reviews/g_v1_venue", { authorID: "g", venueID: "v1", rating: 5 });
  const res = await call(h, "deleteAccount", T.host, {});
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.venuesUnpublished, 1);
  assert.deepEqual(h.deletedUsers, [HOST]);
  const v = h.read("venues/v1");
  assert.equal(v.status, "pending");
  assert.equal(v.isPaused, true);
  assert.equal(v.ownerDeleted, true);
  assert.equal(v.name, "Кафе", "данные заведения сохранены");
  assert.equal(h.read("deals/d1"), undefined);
  assert.equal(h.read("deals/d2"), undefined);
  assert.ok(h.read("deals/dx"), "чужая акция не тронута");
  assert.equal(h.read("couponOffers/o1"), undefined);
  assert.equal(h.read("pushCampaigns/p1"), undefined);
  assert.equal(h.read(`igAccounts/${HOST}_v1`), undefined);
  assert.equal(h.read(`igConnections/${HOST}_v1`), undefined);
  assert.equal(h.read("reviewReports/r_host"), undefined);
  assert.equal(h.read("giftCoupons/GIFT-A"), undefined);
  assert.ok(h.read("giftCoupons/GIFT-B"), "забранный подарок — уже чужой купон");
  assert.equal(h.read("redeemTokens/tokX"), undefined);
  assert.equal(h.read(`userLibraries/${HOST}`), undefined, "библиотека гостя удалена");
  assert.ok(h.read("reviews/g_v1_venue"), "отзывы гостей остаются");
});

test("deleteAccount: без токена → 401", async () => {
  const h = harness();
  const res = await call(h, "deleteAccount", null, {});
  assert.equal(res.statusCode, 401);
});

/* ═══════════════════════ sendPushCampaign ═══════════════════════ */

function campaignEvent(h, id, data) {
  h.seed(`pushCampaigns/${id}`, data);
  return writtenEvent(h, `pushCampaigns/${id}`, null, data, { id });
}

test("sendPushCampaign: approved → sending → sent; повторная доставка не шлёт второй раз", async () => {
  const h = harness({ staleTokens: ["dead"] });
  h.seed("userTokens/a", { uid: "u1", city: "bishkek" });
  h.seed("userTokens/b", { uid: "u2", city: "bishkek" });
  h.seed("userTokens/dead", { uid: "u3", city: "bishkek" });
  const data = { status: "approved", delivered: false, city: "bishkek", headline: "Скидка", body: "−20%" };
  const ev = campaignEvent(h, "c1", data);
  await h.mod.sendPushCampaign.run(ev);
  assert.equal(h.messagingCalls.length, 1);
  assert.equal(h.read("pushCampaigns/c1").status, "sent");
  assert.equal(h.read("pushCampaigns/c1").recipients, 2);
  assert.equal(h.read("userTokens/dead"), undefined, "протухший токен удалён (дождались)");
  assert.ok(h.db.getAllCalls >= 1, "история читается пачкой getAll");
  // То же событие пришло ещё раз (at-least-once) — рассылки нет.
  await h.mod.sendPushCampaign.run(ev);
  assert.equal(h.messagingCalls.length, 1);
});

test("sendPushCampaign: кампания уже в sending (ретрай после падения) — не шлёт", async () => {
  const h = harness();
  h.seed("userTokens/a", { uid: "u1" });
  const data = { status: "approved", delivered: false, headline: "x", body: "y" };
  const ev = campaignEvent(h, "c2", data);
  h.seed("pushCampaigns/c2", { ...data, status: "sending" });
  await h.mod.sendPushCampaign.run(ev);
  assert.equal(h.messagingCalls.length, 0);
});

test("sendPushCampaign: частотный лимит по pushLog соблюдается", async () => {
  const h = harness();
  h.seed("userTokens/a", { uid: "u1" });
  h.seed("userTokens/b", { uid: "u2" });
  h.seed("pushLog/a", { sends: [Date.now() - 3600 * 1000] });   // уже получил сегодня
  await h.mod.sendPushCampaign.run(campaignEvent(h, "c3", { status: "approved", headline: "x", body: "y" }));
  assert.deepEqual(h.messagingCalls[0].tokens, ["b"]);
});

/* ═══════════════════════ Подтверждение почты для денег ═══════════════════════ */

test("кошелёк: новый аккаунт с неподтверждённой почтой → 403 email_not_verified", async () => {
  const h = harness({ createdAt: { "fresh-uid": NOW_HTTP() }, unverifiedUsers: ["fresh-uid"] });
  // После cutoff: двигаем cutoff в прошлое через дату создания — cutoff по умолчанию
  // 2026-10-02, поэтому для детерминизма ставим дату создания после него.
  h.seed("bonusWallets/fresh-uid", { balance: 500 });
  const later = makeHarness({
    tokens: { [T.fresh]: "fresh-uid" },
    createdAt: { "fresh-uid": "Fri, 01 Jan 2027 00:00:00 GMT" },
    unverifiedUsers: ["fresh-uid"],
  });
  later.seed("bonusWallets/fresh-uid", { balance: 500 });
  for (const fn of ["earnBonus", "buyCoupon", "claimGift", "bonusWalletSync"]) {
    const res = await call(later, fn, T.fresh, { amount: 1, source: "game:snake", idempotencyKey: "k1", offerID: "o1", code: "GIFT-X" });
    assert.equal(res.statusCode, 403, fn);
    assert.equal(res.body.error, "email_not_verified", fn);
  }
  void h;
});

test("кошелёк: подтверждённая почта, Google и старые аккаунты проходят", async () => {
  const h = makeHarness({
    tokens: { a: "verified", b: "google", c: "old" },
    createdAt: { verified: "Fri, 01 Jan 2027 00:00:00 GMT", google: "Fri, 01 Jan 2027 00:00:00 GMT" },
    providers: { google: "google.com" },
    unverifiedUsers: ["google", "old"],
  });
  for (const t of ["a", "b", "c"]) {
    const res = await call(h, "bonusWalletSync", t, {});
    assert.equal(res.statusCode, 200, t);
  }
});

test("реферал: неподтверждённый приглашённый — отложен, доводится после подтверждения", async () => {
  const created = "Fri, 01 Jan 2027 00:00:00 GMT";
  const realNow = Date.now;
  Date.now = () => Date.parse("2027-01-02T00:00:00Z");
  try {
    const h = makeHarness({
      tokens: { inv: "invitee" },
      createdAt: { invitee: created },
      unverifiedUsers: ["invitee"],
    });
    h.seed("referrals/invitee", { referrerID: "referrer" });
    await h.mod.rewardReferral.run(createdEvent(h, "referrals/invitee", { referrerID: "referrer" }, { inviteeID: "invitee" }));
    assert.equal(h.read("referrals/invitee").pendingVerification, true);
    assert.notEqual(h.read("referrals/invitee").rewarded, true);
    assert.equal(h.read("bonusGrants/referral_invitee"), undefined);

    // Почта подтверждена — тот же пользователь заходит в кошелёк.
    const h2 = makeHarness({ tokens: { inv: "invitee" }, createdAt: { invitee: created } });
    for (const [k, v] of h.db.store.entries()) h2.db.store.set(k, v);
    const res = await call(h2, "bonusWalletSync", "inv", {});
    assert.equal(res.statusCode, 200);
    assert.equal(h2.read("referrals/invitee").rewarded, true);
    assert.equal(h2.read("bonusGrants/referral_invitee").userID, "referrer");
    assert.equal(res.body.granted, 100, "приветственный бонус зачислен сразу");
  } finally {
    Date.now = realNow;
  }
});

/* ═══════════════════════ signCloudinaryUpload ═══════════════════════ */

test("signCloudinaryUpload: не настроено → 503 not_configured", async () => {
  const h = harness();
  delete process.env.CLOUDINARY_API_KEY;
  delete process.env.CLOUDINARY_API_SECRET;
  const res = await call(h, "signCloudinaryUpload", T.guest, { folder: "ayant/images", resourceType: "image" });
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.error, "not_configured");
});

test("signCloudinaryUpload: подпись по правилам Cloudinary", async () => {
  const h = harness();
  process.env.CLOUDINARY_API_KEY = "key123";
  process.env.CLOUDINARY_API_SECRET = "sekret";
  try {
    const crypto = require("node:crypto");
    for (const [folder, resourceType] of [["ayant/images", "image"], ["ayant/documents", "auto"]]) {
      const res = await call(h, "signCloudinaryUpload", T.guest, { folder, resourceType });
      assert.equal(res.statusCode, 200, folder);
      assert.equal(res.body.apiKey, "key123");
      assert.equal(res.body.cloudName, "dsb14gwxw");
      assert.equal(res.body.folder, folder);
      assert.equal(res.body.resourceType, resourceType);
      const base = `folder=${folder}&timestamp=${res.body.timestamp}`;
      assert.equal(res.body.signature, crypto.createHash("sha1").update(base + "sekret").digest("hex"));
      assert.ok(!JSON.stringify(res.body).includes("sekret"), "секрет не уходит клиенту");
    }
    // Папка вне списка, плохой тип, аноним.
    assert.equal((await call(h, "signCloudinaryUpload", T.guest, { folder: "ayant/../x", resourceType: "image" })).statusCode, 400);
    assert.equal((await call(h, "signCloudinaryUpload", T.guest, { folder: "reviews", resourceType: "image" })).statusCode, 400);
    assert.equal((await call(h, "signCloudinaryUpload", T.guest, { folder: "ayant/images", resourceType: "raw" })).statusCode, 400);
    assert.equal((await call(h, "signCloudinaryUpload", T.anon, { folder: "ayant/images", resourceType: "image" })).statusCode, 403);
  } finally {
    delete process.env.CLOUDINARY_API_KEY;
    delete process.env.CLOUDINARY_API_SECRET;
  }
});

/* ═══════════════════════ Телеметрия ═══════════════════════ */

test("countAnalyticsEvent: событие удаляется даже при сбое счётчика", async () => {
  const h = harness();
  h.seed("analyticsEvents/e1", { venueID: "v1", metric: "views" });
  const realSet = h.db.doc("x").constructor.prototype.set;
  let calls = 0;
  h.db.doc("x").constructor.prototype.set = async function (data, opts) {
    if (this.path.startsWith("analytics/")) { calls++; throw new Error("contention"); }
    return realSet.call(this, data, opts);
  };
  try {
    await h.mod.countAnalyticsEvent.run(createdEvent(h, "analyticsEvents/e1", { venueID: "v1", metric: "views" }, { id: "e1" }));
  } finally {
    h.db.doc("x").constructor.prototype.set = realSet;
  }
  assert.ok(calls >= 2, "инкремент повторяется");
  assert.equal(h.read("analyticsEvents/e1"), undefined);
});

/* ═══════════════════════ Сверки: агрегаты и страницы ═══════════════════════ */

test("reconcileBonusWallets: проходит все страницы кошельков", async () => {
  const h = harness();
  h.seed("ops/heartbeats", { reconcileVenuePoints: { toMillis: () => Date.now() } });
  for (let i = 0; i < 305; i++) {
    const id = `u${String(i).padStart(4, "0")}`;
    h.seed(`bonusWallets/${id}`, { balance: i === 304 ? 999 : 5 });
    h.seed(`bonusWallets/${id}/ledger/e1`, { amount: 5 });
  }
  await h.mod.reconcileBonusWallets.run({});
  const alerts = [...h.db.store.entries()].filter(([p, d]) => p.startsWith("ops/alerts/items/") && d.kind === "wallet_mismatch");
  assert.equal(alerts.length, 1, "расхождение на второй странице найдено");
  assert.equal(alerts[0][1].detail.userID, "u0304");
});

test("reconcileVenuePoints: проходит все страницы карт", async () => {
  const h = harness();
  h.seed("ops/heartbeats", { expireVenuePoints: { toMillis: () => Date.now() }, reconcileBonusWallets: { toMillis: () => Date.now() } });
  for (let i = 0; i < 302; i++) {
    const id = `c${String(i).padStart(4, "0")}`;
    h.seed(`venuePoints/${id}`, { userID: id, venueID: "v1", balance: i === 301 ? 1 : 10 });
    h.seed(`venuePoints/${id}/ledger/e1`, { type: "earn", points: 10, at: new Date(Date.now() - 3 * 86400000) });
  }
  await h.mod.reconcileVenuePoints.run({});
  const alerts = [...h.db.store.entries()].filter(([p, d]) => p.startsWith("ops/alerts/items/") && d.kind === "balance_mismatch");
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0][1].detail.card, "c0301");
});

/* ═══════════════════════ Потолок инстансов ═══════════════════════ */

test("у всех HTTPS-функций задан maxInstances", () => {
  const h = harness();
  const https = Object.entries(h.mod).filter(([, f]) => f && f.__endpoint && f.__endpoint.httpsTrigger);
  assert.ok(https.length >= 18, `HTTPS-функций: ${https.length}`);
  for (const [name, f] of https) {
    assert.ok(Number(f.__endpoint.maxInstances) > 0, `${name}: нет maxInstances`);
  }
});

test("deleteAccount: неиндексированный rankingEvents.userID не роняет удаление", async () => {
  const h = harness();
  h.seed(`venuePoints/${GUEST}_v1`, { userID: GUEST, venueID: "v1", balance: 5 });
  const realCollection = h.db.collection.bind(h.db);
  h.db.collection = (name) => {
    const c = realCollection(name);
    if (name === "rankingEvents") c.where = () => ({ get: async () => { throw new Error("FAILED_PRECONDITION"); } });
    return c;
  };
  const res = await call(h, "deleteAccount", T.guest, {});
  assert.equal(res.statusCode, 200);
  assert.equal(h.read(`venuePoints/${GUEST}_v1`), undefined);
  assert.deepEqual(h.deletedUsers, [GUEST]);
});
