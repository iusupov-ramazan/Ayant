/**
 * EXPORT — Ayant / Firestore `rankingEvents` → training rows (JSONL)
 *
 * Reads the append-only ranking-log (see RankingEvent.swift/.kt), joins each
 * impression item with its outcome (tap / redeem), and emits one training row
 * per shown deal. This is step 1 of the learning-to-rank pipeline; step 2 is
 * `train_ranking_weights.py`.
 *
 * Run:
 *   node ml/export_ranking_events.js [--out ml/rows.jsonl] [--since-days 90]
 *
 * Needs serviceAccountKey.json at repo root (same as backup-firestore.js).
 *
 * Label join
 * ──────────
 *  - impression events carry the shown slate: items[] with rank-time features,
 *    a renderID, and the userID.
 *  - CLIENT tap/redeem events carry the same renderID → exact join on
 *    (renderID, dealID).
 *  - SERVER redeem events (host-verified scan) have renderID="server", so they
 *    are attributed by last-touch: the most recent impression of (userID, dealID)
 *    at or before the redeem's clientTs. This is the authoritative, cross-platform
 *    positive label.
 *
 * Each row = { <rank-time features…>, tapped: 0|1, redeemed: 0|1, + context }.
 * `redeemed` is the primary training label; `tapped` is an intermediate signal.
 */
const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const fs = require("fs");

// ── args ────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const arg = (name, def) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : def;
};
const OUT = arg("--out", "ml/rows.jsonl");
const SINCE_DAYS = Number(arg("--since-days", "90"));

const serviceAccount = require("../serviceAccountKey.json");
initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

// Feature fields copied verbatim from each impression item onto the training row.
const FEATURE_KEYS = [
  "score", "bayesRating", "reviewCount", "savedByCount", "isVerified",
  "hasTodaySpecial", "activeDealCount", "isFresh", "daysSinceStart",
  "discountPercent", "hoursUntilExpiry", "distanceKm", "timeRelevance",
];

async function main() {
  const cutoffMs = Date.now() - SINCE_DAYS * 86400000;

  // Firestore stores createdAt as a Timestamp; clientTs is epoch ms on every doc.
  const snap = await db.collection("rankingEvents")
    .where("clientTs", ">=", cutoffMs)
    .get();

  const impressions = [];
  const tapKeys = new Set();          // `${renderID}|${dealID}`  (client taps)
  const redeemKeys = new Set();       // `${renderID}|${dealID}`  (client redeems)
  const serverRedeems = [];           // { userID, dealID, clientTs }  (host scans)

  for (const doc of snap.docs) {
    const e = doc.data();
    switch (e.type) {
      case "impression":
        impressions.push(e);
        break;
      case "tap":
        if (e.renderID && e.renderID !== "server") tapKeys.add(`${e.renderID}|${e.dealID}`);
        break;
      case "redeem":
        if (e.renderID && e.renderID !== "server") redeemKeys.add(`${e.renderID}|${e.dealID}`);
        else if (e.userID && e.dealID) serverRedeems.push({ userID: e.userID, dealID: e.dealID, clientTs: e.clientTs });
        break;
      default:
        break;
    }
  }

  // Index impressions by (userID, dealID) → sorted [{clientTs, ref}] for last-touch
  // attribution of server redeems. `ref` uniquely marks one item within one slate.
  const impIndex = new Map();
  for (const imp of impressions) {
    for (const it of imp.items || []) {
      const k = `${imp.userID}|${it.dealID}`;
      if (!impIndex.has(k)) impIndex.set(k, []);
      impIndex.get(k).push({ clientTs: imp.clientTs, ref: `${imp.renderID}|${it.dealID}` });
    }
  }
  for (const list of impIndex.values()) list.sort((a, b) => a.clientTs - b.clientTs);

  // Last-touch: attribute each server redeem to the latest impression at/ before it.
  const serverRedeemRefs = new Set();
  for (const r of serverRedeems) {
    const list = impIndex.get(`${r.userID}|${r.dealID}`);
    if (!list) continue;
    let chosen = null;
    for (const cand of list) {
      if (cand.clientTs <= r.clientTs) chosen = cand; else break;
    }
    if (chosen) serverRedeemRefs.add(chosen.ref);
  }

  // Emit one row per impression item.
  const stream = fs.createWriteStream(OUT);
  let rows = 0, positives = 0;
  for (const imp of impressions) {
    for (const it of imp.items || []) {
      const key = `${imp.renderID}|${it.dealID}`;
      const redeemed = redeemKeys.has(key) || serverRedeemRefs.has(key) ? 1 : 0;
      const row = {
        renderID: imp.renderID, userID: imp.userID, dealID: it.dealID, venueID: it.venueID,
        position: it.position, category: imp.category ?? null,
        hour: imp.hour, weekday: imp.weekday, platform: imp.platform, clientTs: imp.clientTs,
        tapped: tapKeys.has(key) ? 1 : 0,
        redeemed,
      };
      for (const f of FEATURE_KEYS) row[f] = it[f] ?? null;
      stream.write(JSON.stringify(row) + "\n");
      rows++; positives += redeemed;
    }
  }
  await new Promise((res) => stream.end(res));

  console.log(`✅ ${rows} rows → ${OUT}`);
  console.log(`   impressions=${impressions.length}  taps=${tapKeys.size}  ` +
    `redeems(client)=${redeemKeys.size}  redeems(server)=${serverRedeems.length}`);
  console.log(`   positives(redeemed)=${positives}  (${(100 * positives / Math.max(rows, 1)).toFixed(2)}%)`);
  if (positives < 200) {
    console.warn("⚠️  Few positive labels — weights will be noisy. Keep the heuristic " +
      "until redemptions accumulate (rule of thumb: ≥200, ideally ≥1000).");
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
