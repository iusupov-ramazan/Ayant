"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeHarness, createdEvent } = require("./helpers/harness");

const VENUE = "v1";

function analyticsDay(h, venue) {
  for (const [path, data] of h.db.store.entries()) {
    if (path.startsWith(`analytics/${venue}/days/`)) return data;
  }
  return undefined;
}

/* ── countRedemption: серверный авторитетный счётчик погашений ───────────── */

test("countRedemption инкрементит аналитику и помечает документ", async () => {
  const h = makeHarness();
  h.seed("deals/d1", { venueID: VENUE, title: "−20%" });
  const event = createdEvent(h, "redemptions/r1", { venueID: VENUE, dealID: "d1" }, { id: "r1" });
  await h.mod.countRedemption.run(event);

  assert.equal(analyticsDay(h, VENUE).redemptions, 1);
  assert.equal(h.read("redemptions/r1").status, "counted");
});

test("countRedemption: чужая или несуществующая акция не накручивает счётчик", async () => {
  const h = makeHarness();
  h.seed("deals/d1", { venueID: "other-venue" });
  await h.mod.countRedemption.run(createdEvent(h, "redemptions/r3", { venueID: VENUE, dealID: "d1" }, { id: "r3" }));
  await h.mod.countRedemption.run(createdEvent(h, "redemptions/r4", { venueID: VENUE, dealID: "nope" }, { id: "r4" }));
  assert.equal(analyticsDay(h, VENUE), undefined);
  assert.equal(h.read("redemptions/r3").status, "rejected");
});

test("countRedemption без venueID — ничего не пишет", async () => {
  const h = makeHarness();
  const event = createdEvent(h, "redemptions/r2", { dealID: "d1" }, { id: "r2" });
  await h.mod.countRedemption.run(event);
  assert.equal(analyticsDay(h, VENUE), undefined);
});

/* ── countAnalyticsEvent: белый список метрик (анти-чит) ─────────────────── */

test("countAnalyticsEvent считает метрику из белого списка и чистит событие", async () => {
  const h = makeHarness();
  h.seed("analyticsEvents/e1", { venueID: VENUE, metric: "views" });
  const event = createdEvent(h, "analyticsEvents/e1", { venueID: VENUE, metric: "views" }, { id: "e1" });
  await h.mod.countAnalyticsEvent.run(event);

  assert.equal(analyticsDay(h, VENUE).views, 1);
  assert.equal(h.read("analyticsEvents/e1"), undefined); // событие удалено
});

test("countAnalyticsEvent НЕ даёт подделать redemptions (не в белом списке)", async () => {
  const h = makeHarness();
  h.seed("analyticsEvents/e2", { venueID: VENUE, metric: "redemptions" });
  const event = createdEvent(h, "analyticsEvents/e2", { venueID: VENUE, metric: "redemptions" }, { id: "e2" });
  await h.mod.countAnalyticsEvent.run(event);

  // Счётчик не тронут — клиент не может накрутить погашения телеметрией.
  assert.equal(analyticsDay(h, VENUE), undefined);
  // Но событие-триггер всё равно удалено.
  assert.equal(h.read("analyticsEvents/e2"), undefined);
});

/* ── rewardReferral: бонус пригласившему + идемпотентность ───────────────── */

// Приглашённый — новый аккаунт: по умолчанию харнесс считает аккаунты давними.
const NOW_HTTP = () => new Date().toUTCString();
function referralHarness(invitees, opts = {}) {
  const createdAt = {};
  for (const uid of invitees) createdAt[uid] = NOW_HTTP();
  return makeHarness({ createdAt, ...opts });
}
// Триггер срабатывает на уже записанный документ: засеиваем его, как сделал бы клиент.
function referralEvent(h, path, data, params) {
  h.seed(path, data);
  return createdEvent(h, path, data, params);
}
const grantsOf = (h) => [...h.db.store.entries()].filter(([p]) => p.startsWith("bonusGrants/")).map(([, g]) => g);

test("rewardReferral начисляет бонус пригласившему и помечает rewarded", async () => {
  const h = referralHarness(["invitee-1"]);
  const event = referralEvent(
    h,
    "referrals/invitee-1",
    { referrerID: "referrer-1" },
    { inviteeID: "invitee-1" }
  );
  await h.mod.rewardReferral.run(event);

  const grants = grantsOf(h);
  assert.equal(grants.length, 2);
  const grant = grants.find((g) => g.reason === "referral");
  assert.equal(grant.userID, "referrer-1");
  assert.equal(grant.amount, 100);
  assert.equal(grant.claimed, false);
  // Приветственный бонус приглашённому — грантом (его забирает bonusWalletSync).
  const welcome = h.read("bonusGrants/welcome_invitee-1");
  assert.equal(welcome.userID, "invitee-1");
  assert.equal(welcome.amount, 100);
  assert.equal(welcome.reason, "welcome");
  assert.equal(welcome.claimed, false);
  assert.equal(h.read("referrals/invitee-1").rewarded, true);
  assert.equal(h.read("referralCounts/referrer-1").rewarded, 1);
});

test("rewardReferral игнорирует самоприглашение", async () => {
  const h = referralHarness(["u1"]);
  const event = referralEvent(
    h,
    "referrals/u1",
    { referrerID: "u1" },
    { inviteeID: "u1" }
  );
  await h.mod.rewardReferral.run(event);
  assert.equal(grantsOf(h).length, 0);
});

test("rewardReferral идемпотентен (rewarded уже true)", async () => {
  const h = referralHarness(["invitee-2"]);
  const event = referralEvent(
    h,
    "referrals/invitee-2",
    { referrerID: "referrer-2", rewarded: true },
    { inviteeID: "invitee-2" }
  );
  await h.mod.rewardReferral.run(event);
  assert.equal(grantsOf(h).length, 0); // повторный триггер не начисляет второй бонус
});

test("rewardReferral: повторный запуск триггера по тому же событию не удваивает награду", async () => {
  const h = referralHarness(["invitee-3"]);
  const event = referralEvent(h, "referrals/invitee-3", { referrerID: "referrer-3" }, { inviteeID: "invitee-3" });
  await h.mod.rewardReferral.run(event);
  await h.mod.rewardReferral.run(event);
  assert.equal(grantsOf(h).length, 2);
  assert.equal(h.read("referralCounts/referrer-3").rewarded, 1);
});

/* ── rewardReferral: анти-фарм ─────────────────────────────────────────── */

test("rewardReferral: сверх потолка новый грант не выдаётся (capped)", async () => {
  const h = referralHarness(["inv-capped"]);
  // Дефолтный лимит = 20; засеваем ровно 20 уже выданных реферальных грантов.
  for (let i = 1; i <= 20; i++) {
    h.seed(`bonusGrants/g${i}`, { userID: "farmer", reason: "referral", amount: 100, claimed: false });
  }
  const event = referralEvent(h, "referrals/inv-capped", { referrerID: "farmer" }, { inviteeID: "inv-capped" });
  await h.mod.rewardReferral.run(event);

  assert.equal(grantsOf(h).length, 20, "новый грант сверх лимита не создаётся");
  assert.equal(h.read("referrals/inv-capped").rewarded, true);
  assert.equal(h.read("referrals/inv-capped").capped, true);
});

// Параллельность фейк не моделирует (его транзакции не конфликтуют) — здесь
// закреплено, что потолок считает счётчик, который живёт в транзакции; от
// одновременных триггеров его защищает сериализация транзакций Firestore.
test("rewardReferral: потолок держит счётчик referralCounts", async () => {
  const invitees = Array.from({ length: 30 }, (_, i) => `burst-${i}`);
  const h = referralHarness(invitees);
  for (const id of invitees) {
    await h.mod.rewardReferral.run(referralEvent(h, `referrals/${id}`, { referrerID: "burst-farmer" }, { inviteeID: id }));
  }
  const referralGrants = grantsOf(h).filter((g) => g.reason === "referral" && g.userID === "burst-farmer");
  assert.equal(referralGrants.length, 20);
  assert.equal(h.read("referralCounts/burst-farmer").rewarded, 20);
});

test("rewardReferral: к лимиту считаются только гранты reason=referral", async () => {
  const h = referralHarness(["inv-mixed"]);
  // 20 НЕ-реферальных грантов (welcome) не должны блокировать реферальную награду.
  for (let i = 1; i <= 20; i++) {
    h.seed(`bonusGrants/w${i}`, { userID: "mixed", reason: "welcome", amount: 50, claimed: false });
  }
  const event = referralEvent(h, "referrals/inv-mixed", { referrerID: "mixed" }, { inviteeID: "inv-mixed" });
  await h.mod.rewardReferral.run(event);

  const referralGrants = grantsOf(h).filter((g) => g.reason === "referral");
  assert.equal(referralGrants.length, 1, "welcome-гранты не считаются к реферальному лимиту");
});

test("rewardReferral: анонимный приглашённый ничего не приносит", async () => {
  const h = referralHarness(["anon-inv"], { anonymousUsers: ["anon-inv"] });
  await h.mod.rewardReferral.run(referralEvent(h, "referrals/anon-inv", { referrerID: "r1" }, { inviteeID: "anon-inv" }));
  assert.equal(grantsOf(h).length, 0);
  assert.equal(h.read("referrals/anon-inv").rejected, "invitee_anonymous");
});

test("rewardReferral: несуществующий или анонимный пригласивший — без награды", async () => {
  const h = referralHarness(["i1", "i2"], { missingUsers: ["ghost"], anonymousUsers: ["anon-ref"] });
  await h.mod.rewardReferral.run(referralEvent(h, "referrals/i1", { referrerID: "ghost" }, { inviteeID: "i1" }));
  await h.mod.rewardReferral.run(referralEvent(h, "referrals/i2", { referrerID: "anon-ref" }, { inviteeID: "i2" }));
  assert.equal(grantsOf(h).length, 0);
  assert.equal(h.read("referrals/i1").rejected, "referrer_invalid");
  assert.equal(h.read("referrals/i2").rejected, "referrer_invalid");
});

test("rewardReferral: старый аккаунт «пригласить» задним числом нельзя", async () => {
  const h = makeHarness();   // аккаунт создан в 2024-м
  await h.mod.rewardReferral.run(referralEvent(h, "referrals/old-acc", { referrerID: "r1" }, { inviteeID: "old-acc" }));
  assert.equal(grantsOf(h).length, 0);
  assert.equal(h.read("referrals/old-acc").rejected, "invitee_not_new");
});

/* ── notifyHostOnReview: push владельцу заведения о новом отзыве ─────────── */

test("notifyHostOnReview шлёт push на все токены владельца", async () => {
  const h = makeHarness();
  h.seed("venues/v9", { name: "Нават", ownerID: "owner1" });
  h.seed("userTokens/tokA", { uid: "owner1", city: "bishkek" });
  h.seed("userTokens/tokB", { uid: "owner1", city: "bishkek" });
  h.seed("userTokens/tokC", { uid: "someone-else", city: "bishkek" });
  const event = createdEvent(h, "reviews/r9",
    { venueID: "v9", authorID: "guest1", authorName: "Айжан", rating: 5, text: "Очень вкусно" }, { id: "r9" });
  await h.mod.notifyHostOnReview.run(event);

  assert.equal(h.messagingCalls.length, 1);
  const m = h.messagingCalls[0];
  assert.deepEqual([...m.tokens].sort(), ["tokA", "tokB"]);
  assert.equal(m.notification.title, "Новый отзыв · Нават");
  assert.match(m.notification.body, /★★★★★ Айжан: Очень вкусно/);
  assert.equal(m.data.type, "review");
  assert.equal(m.data.venueID, "v9");
});

test("notifyHostOnReview молчит, если владелец пишет отзыв сам себе или токенов нет", async () => {
  const h = makeHarness();
  h.seed("venues/v9", { name: "Нават", ownerID: "owner1" });
  h.seed("userTokens/tokA", { uid: "owner1" });
  await h.mod.notifyHostOnReview.run(
    createdEvent(h, "reviews/r10", { venueID: "v9", authorID: "owner1", rating: 4 }, { id: "r10" }));
  assert.equal(h.messagingCalls.length, 0);

  h.seed("venues/v10", { name: "Без токенов", ownerID: "owner2" });
  await h.mod.notifyHostOnReview.run(
    createdEvent(h, "reviews/r11", { venueID: "v10", authorID: "guest1", rating: 4 }, { id: "r11" }));
  assert.equal(h.messagingCalls.length, 0);
});

/* ── notifyGuestOnHostReply: ответ владельца → push автору ───────────────── */

test("notifyGuestOnHostReply шлёт push автору, когда появился ответ", async () => {
  const { writtenEvent } = require("./helpers/harness");
  const h = makeHarness();
  h.seed("venues/v9", { name: "Нават", ownerID: "owner1" });
  h.seed("userTokens/tokG", { uid: "guest1" });
  const before = { venueID: "v9", authorID: "guest1", rating: 5, text: "Вкусно" };
  const after = { ...before, hostReply: { text: "Спасибо, ждём снова!" } };
  await h.mod.notifyGuestOnHostReply.run(writtenEvent(h, "reviews/r9", before, after, { id: "r9" }));

  assert.equal(h.messagingCalls.length, 1);
  assert.deepEqual(h.messagingCalls[0].tokens, ["tokG"]);
  assert.equal(h.messagingCalls[0].notification.title, "Нават ответили на ваш отзыв");
  assert.equal(h.messagingCalls[0].data.type, "hostReply");

  // Правка отзыва без изменения ответа — второго push нет.
  await h.mod.notifyGuestOnHostReply.run(writtenEvent(h, "reviews/r9", after, { ...after, text: "Очень вкусно" }, { id: "r9" }));
  assert.equal(h.messagingCalls.length, 1);
});

/* ── warnExpiringPoints: предупреждение за 7 дней до сгорания ────────────── */

test("warnExpiringPoints предупреждает один раз в окне и молчит вне его", async () => {
  const h = makeHarness();
  const DAY = 86400000;
  h.seed("venues/v9", { name: "Нават", pointsExpiryMonths: 6 });
  h.seed("userTokens/tokG", { uid: "guest1" });
  // Порог = 180 дней с последней активности; активность 176 дней назад → 4 дня до сгорания.
  h.seed("venuePoints/guest1_v9", { userID: "guest1", venueID: "v9", balance: 120,
                                    lastActivityAt: new Date(Date.now() - 176 * DAY) });
  // Далеко до порога — не трогаем.
  h.seed("venuePoints/guest2_v9", { userID: "guest2", venueID: "v9", balance: 50,
                                    lastActivityAt: new Date(Date.now() - 30 * DAY) });
  h.seed("userTokens/tokH", { uid: "guest2" });

  await h.mod.warnExpiringPoints.run({});
  assert.equal(h.messagingCalls.length, 1);
  assert.deepEqual(h.messagingCalls[0].tokens, ["tokG"]);
  assert.match(h.messagingCalls[0].notification.body, /120 баллов/);
  assert.ok(h.read("venuePoints/guest1_v9").expiryWarnedAt, "отметка о предупреждении");

  await h.mod.warnExpiringPoints.run({});
  assert.equal(h.messagingCalls.length, 1, "повторно в том же окне не шлём");
});
