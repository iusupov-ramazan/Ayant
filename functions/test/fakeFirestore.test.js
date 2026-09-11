"use strict";

/**
 * Контракт фейкового Firestore: записанный `Date` читается как Timestamp.
 *
 * Это не мелочь про типы. `toMillis()` в functions/src/index.ts возвращает 0
 * для всего, у чего нет метода `toMillis` — значит при «наивном» фейке ЛЮБОЙ
 * кулдаун (штампы, баллы) в тестах молчаливо отключён, и тест «повтор
 * заблокирован» проходит, ничего не проверив. Этот файл закрывает регрессию.
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { FakeFirestore, FieldValue } = require("./helpers/fakeFirestore");

test("Date, записанный через set(), читается как Timestamp", async () => {
  const db = new FakeFirestore();
  const when = new Date("2026-08-01T10:00:00Z");
  await db.collection("c").doc("d").set({ at: when });

  const read = (await db.collection("c").doc("d").get()).data().at;
  assert.equal(typeof read.toMillis, "function", "нет toMillis — кулдауны молча отключатся");
  assert.equal(read.toMillis(), when.getTime());
  assert.equal(read.toDate().toISOString(), when.toISOString());
});

test("вложенные и массивные Date конвертируются тоже", async () => {
  const db = new FakeFirestore();
  const when = new Date("2026-08-01T10:00:00Z");
  await db.collection("c").doc("d").set({
    reply: { createdAt: when },
    log: [{ at: when }],
  });

  const d = (await db.collection("c").doc("d").get()).data();
  assert.equal(d.reply.createdAt.toMillis(), when.getTime());
  assert.equal(d.log[0].at.toMillis(), when.getTime());
});

test("уже Timestamp-подобные значения не оборачиваются повторно", async () => {
  const db = new FakeFirestore();
  const stamp = { toMillis: () => 123 };
  await db.collection("c").doc("d").set({ at: stamp });
  assert.equal((await db.collection("c").doc("d").get()).data().at, stamp);
});

test("сентинел increment переживает нормализацию", async () => {
  const db = new FakeFirestore();
  await db.collection("c").doc("d").set({ n: 5 });
  await db.collection("c").doc("d").set({ n: FieldValue.increment(3) }, { merge: true });
  assert.equal((await db.collection("c").doc("d").get()).data().n, 8);
});

test("Timestamp сравним в диапазонном where() (как в expireVenuePoints)", async () => {
  const db = new FakeFirestore();
  await db.collection("c").doc("old").set({ at: new Date(1000) });
  await db.collection("c").doc("new").set({ at: new Date(9000) });
  const snap = await db.collection("c").where("at", ">", 5000).get();
  assert.equal(snap.size, 1);
  assert.equal(snap.docs[0].id, "new");
});
