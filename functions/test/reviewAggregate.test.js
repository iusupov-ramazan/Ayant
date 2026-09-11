"use strict";

/**
 * Денормализация рейтинга на документ заведения (`aggregateReviewRating`).
 *
 * Это то, что позволило клиентам перестать выгружать всю коллекцию `reviews`
 * на каждом старте (см. docs/design/system-design.md §4.2). Поэтому проверяем
 * не только «среднее посчиталось», но и три свойства, на которые опирается
 * клиент: идемпотентность, сохранение seed-значений и отсутствие лишней работы
 * на ответах владельца.
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeHarness, writtenEvent } = require("./helpers/harness");

const VENUE = "v1";

function review(venueID, rating, extra = {}) {
  return { venueID, rating, authorID: "a", text: "", ...extra };
}

/** Кладёт отзывы в фейк и прогоняет триггер так, будто записан последний из них. */
async function seedAndRun(h, reviews, { before = null, params = { id: "r1" } } = {}) {
  reviews.forEach((r, i) => h.seed(`reviews/r${i + 1}`, r));
  const after = reviews[reviews.length - 1] ?? null;
  await h.mod.aggregateReviewRating.run(writtenEvent(h, "reviews/r1", before, after, params));
}

test("считает среднее и количество из реальных отзывов", async () => {
  const h = makeHarness();
  await seedAndRun(h, [review(VENUE, 5), review(VENUE, 3), review(VENUE, 4)]);

  const v = h.read(`venues/${VENUE}`);
  assert.equal(v.reviewCount, 3);
  assert.equal(v.rating, 4);                       // (5+3+4)/3
  assert.deepEqual(v.ratingHistogram, { 1: 0, 2: 0, 3: 1, 4: 1, 5: 1 });
});

test("идемпотентность: повторная доставка события не меняет агрегат", async () => {
  const h = makeHarness();
  const reviews = [review(VENUE, 5), review(VENUE, 2)];
  await seedAndRun(h, reviews);
  const first = h.read(`venues/${VENUE}`);

  // Триггеры Firestore доставляются «хотя бы один раз» — повтор обязан быть безвредным.
  await seedAndRun(h, reviews);
  const second = h.read(`venues/${VENUE}`);

  assert.equal(second.rating, first.rating);
  assert.equal(second.reviewCount, first.reviewCount);
  assert.deepEqual(second.ratingHistogram, first.ratingHistogram);
});

test("без единого валидного отзыва seed-значения заведения не затираются", async () => {
  const h = makeHarness();
  h.seed(`venues/${VENUE}`, { name: "Кафе", rating: 4.2, reviewCount: 37 });

  // Отзыв удалён: after = null, реальных отзывов в коллекции нет.
  await h.mod.aggregateReviewRating.run(
    writtenEvent(h, "reviews/r1", review(VENUE, 5), null, { id: "r1" }));

  const v = h.read(`venues/${VENUE}`);
  assert.equal(v.rating, 4.2, "seed-рейтинг должен остаться");
  assert.equal(v.reviewCount, 37, "seed-счётчик должен остаться");
});

test("мусорная оценка не попадает в агрегат", async () => {
  const h = makeHarness();
  await seedAndRun(h, [review(VENUE, 5), review(VENUE, 99), review(VENUE, 0), review(VENUE, 3)]);

  const v = h.read(`venues/${VENUE}`);
  assert.equal(v.reviewCount, 2, "учтены только оценки 1…5");
  assert.equal(v.rating, 4);                        // (5+3)/2
});

test("ответ владельца (hostReply) не запускает пересчёт", async () => {
  const h = makeHarness();
  h.seed(`venues/${VENUE}`, { rating: 4.2, reviewCount: 37 });
  h.seed("reviews/r1", review(VENUE, 5));

  const before = review(VENUE, 5);
  const after = review(VENUE, 5, { hostReply: { text: "Спасибо!" } });
  await h.mod.aggregateReviewRating.run(writtenEvent(h, "reviews/r1", before, after, { id: "r1" }));

  // Оценка и заведение те же → выходим до запроса, документ не тронут.
  const v = h.read(`venues/${VENUE}`);
  assert.equal(v.rating, 4.2);
  assert.equal(v.reviewCount, 37);
});

test("перенос отзыва на другое заведение пересчитывает оба", async () => {
  const h = makeHarness();
  h.seed("reviews/r1", review("v2", 4));            // отзыв уже переехал в v2

  await h.mod.aggregateReviewRating.run(
    writtenEvent(h, "reviews/r1", review("v1", 4), review("v2", 4), { id: "r1" }));

  // v1 остался без отзывов → seed не трогаем (документа нет вовсе).
  assert.equal(h.read("venues/v1"), undefined);
  // v2 получил агрегат.
  assert.equal(h.read("venues/v2").reviewCount, 1);
  assert.equal(h.read("venues/v2").rating, 4);
});

test("рейтинг не смешивается между заведениями", async () => {
  const h = makeHarness();
  h.seed("reviews/r1", review("v1", 5));
  h.seed("reviews/r2", review("v2", 1));

  await h.mod.aggregateReviewRating.run(
    writtenEvent(h, "reviews/r1", null, review("v1", 5), { id: "r1" }));

  assert.equal(h.read("venues/v1").rating, 5);
  assert.equal(h.read("venues/v2"), undefined, "чужое заведение не тронуто");
});
