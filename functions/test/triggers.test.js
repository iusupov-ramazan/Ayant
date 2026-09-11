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
  const event = createdEvent(h, "redemptions/r1", { venueID: VENUE, dealID: "d1" }, { id: "r1" });
  await h.mod.countRedemption.run(event);

  assert.equal(analyticsDay(h, VENUE).redemptions, 1);
  assert.equal(h.read("redemptions/r1").status, "counted");
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

test("rewardReferral начисляет бонус пригласившему и помечает rewarded", async () => {
  const h = makeHarness();
  const event = createdEvent(
    h,
    "referrals/invitee-1",
    { referrerID: "referrer-1" },
    { inviteeID: "invitee-1" }
  );
  await h.mod.rewardReferral.run(event);

  const grants = [...h.db.store.entries()].filter(([p]) => p.startsWith("bonusGrants/"));
  assert.equal(grants.length, 1);
  const [, grant] = grants[0];
  assert.equal(grant.userID, "referrer-1");
  assert.equal(grant.amount, 100);
  assert.equal(grant.reason, "referral");
  assert.equal(grant.claimed, false);
  assert.equal(h.read("referrals/invitee-1").rewarded, true);
});

test("rewardReferral игнорирует самоприглашение", async () => {
  const h = makeHarness();
  const event = createdEvent(
    h,
    "referrals/u1",
    { referrerID: "u1" },
    { inviteeID: "u1" }
  );
  await h.mod.rewardReferral.run(event);

  const grants = [...h.db.store.entries()].filter(([p]) => p.startsWith("bonusGrants/"));
  assert.equal(grants.length, 0);
});

test("rewardReferral идемпотентен (rewarded уже true)", async () => {
  const h = makeHarness();
  const event = createdEvent(
    h,
    "referrals/invitee-2",
    { referrerID: "referrer-2", rewarded: true },
    { inviteeID: "invitee-2" }
  );
  await h.mod.rewardReferral.run(event);

  const grants = [...h.db.store.entries()].filter(([p]) => p.startsWith("bonusGrants/"));
  assert.equal(grants.length, 0); // повторный триггер не начисляет второй бонус
});

/* ── rewardReferral: анти-фарм (потолок наград на пригласившего) ─────────── */

test("rewardReferral: сверх потолка новый грант не выдаётся (capped)", async () => {
  const h = makeHarness();
  // Дефолтный лимит = 20; засеваем ровно 20 уже выданных реферальных грантов.
  for (let i = 1; i <= 20; i++) {
    h.seed(`bonusGrants/g${i}`, { userID: "farmer", reason: "referral", amount: 100, claimed: false });
  }
  const event = createdEvent(h, "referrals/inv-capped", { referrerID: "farmer" }, { inviteeID: "inv-capped" });
  await h.mod.rewardReferral.run(event);

  const grants = [...h.db.store.entries()].filter(([p]) => p.startsWith("bonusGrants/"));
  assert.equal(grants.length, 20, "новый грант сверх лимита не создаётся");
  assert.equal(h.read("referrals/inv-capped").rewarded, true);
  assert.equal(h.read("referrals/inv-capped").capped, true);
});

test("rewardReferral: к лимиту считаются только гранты reason=referral", async () => {
  const h = makeHarness();
  // 20 НЕ-реферальных грантов (welcome) не должны блокировать реферальную награду.
  for (let i = 1; i <= 20; i++) {
    h.seed(`bonusGrants/w${i}`, { userID: "mixed", reason: "welcome", amount: 50, claimed: false });
  }
  const event = createdEvent(h, "referrals/inv-mixed", { referrerID: "mixed" }, { inviteeID: "inv-mixed" });
  await h.mod.rewardReferral.run(event);

  const referralGrants = [...h.db.store.entries()]
    .filter(([p, d]) => p.startsWith("bonusGrants/") && d.reason === "referral");
  assert.equal(referralGrants.length, 1, "welcome-гранты не считаются к реферальному лимиту");
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
