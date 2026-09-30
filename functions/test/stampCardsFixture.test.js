"use strict";

/*
 * Прогон общего фикстура `specs/fixtures/stamp-cards-fixtures.json` через
 * серверные правила карт штампов (`activeStampCards`, `stampCardDocID`,
 * `stampCardCollection`). Тот же файл гоняет `StampCardsFixtureTests` на iOS —
 * расхождение правил ловится здесь, а не в продакшене.
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { makeHarness } = require("./helpers/harness");

const FIXTURE_PATH = path.join(__dirname, "..", "..", "specs", "fixtures", "stamp-cards-fixtures.json");
const fixture = JSON.parse(fs.readFileSync(FIXTURE_PATH, "utf8"));
const { activeStampCards, stampCardDocID, stampCardCollection } = makeHarness({ tokens: {} }).mod;

for (const c of fixture.docID) {
  test(`stamp docID: ${c.cardID || "(пусто)"} → ${c.expect}`, () => {
    assert.equal(stampCardDocID(c.userID, c.venueID, c.cardID), c.expect);
    assert.equal(stampCardCollection(c.cardID), c.collection);
  });
}

for (const c of fixture.active) {
  test(`stamp cards: ${c.name}`, () => {
    const got = activeStampCards(c.venue).map((x) => [x.id, x.title, x.goal, x.reward]);
    assert.deepEqual(got, c.expect);
  });
}
