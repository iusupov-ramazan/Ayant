/**
 * PUBLISH — Ayant / learned weights → Firestore `config/rankingWeights`
 *
 * Step 3 of the pipeline (after train_ranking_weights.py). Writes the learned
 * coefficients to the config doc both clients read at startup into RankingWeights.
 * No app release needed — the next launch (or next `load()`) picks them up; a
 * missing/partial doc is safe (each client falls back to RankingWeights.DEFAULT
 * field-by-field).
 *
 * Run:
 *   node ml/publish_ranking_weights.js [--in ml/ranking_weights.json] [--dry-run]
 *
 * Needs serviceAccountKey.json at repo root (admin SDK bypasses the config rule,
 * which otherwise only lets an admin write). Roll out behind an A/B split and watch
 * redemptions-per-user — do not ship on offline accuracy alone (see ml/README.md).
 */
const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const fs = require("fs");

const argv = process.argv.slice(2);
const arg = (name, def) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : def;
};
const IN = arg("--in", "ml/ranking_weights.json");
const DRY = argv.includes("--dry-run");

// Keys the clients understand (RankingWeights.from). Anything else is ignored by
// the clients, so we drop it here too and warn — catches typos before they ship.
const KNOWN = new Set([
  "W_RATING", "W_REVIEWS", "W_SAVES", "W_VERIFIED", "W_TODAY_SPECIAL", "W_OPEN_NOW",
  "W_ACTIVE_DEALS", "W_FRESH", "W_RECENCY", "W_VALUE", "W_URGENCY", "W_TIME",
  "FW_DISTANCE", "FW_QUALITY", "FW_POPULARITY", "FW_FRESH_DEAL", "FW_TODAY_SPECIAL",
  "FW_DEALS", "FW_TIME",
]);

function main() {
  const parsed = JSON.parse(fs.readFileSync(IN, "utf8"));
  const weights = parsed.weights || parsed;   // accept the trainer's {weights:{…}} or a bare map

  const clean = {};
  for (const [k, v] of Object.entries(weights)) {
    if (!KNOWN.has(k)) { console.warn(`⚠️  ignoring unknown key: ${k}`); continue; }
    if (typeof v !== "number" || !Number.isFinite(v)) { console.warn(`⚠️  skipping non-numeric ${k}=${v}`); continue; }
    clean[k] = v;
  }
  if (Object.keys(clean).length === 0) throw new Error("no valid weights to publish");

  console.log("weights to publish:", JSON.stringify(clean, null, 2));
  if (DRY) { console.log("— dry run, nothing written —"); return; }

  const serviceAccount = require("../serviceAccountKey.json");
  initializeApp({ credential: cert(serviceAccount) });
  const db = getFirestore();

  // updatedAt is metadata; the clients only read the W_*/FW_* number fields.
  db.collection("config").doc("rankingWeights")
    .set({ ...clean, updatedAt: new Date() }, { merge: true })
    .then(() => console.log("✅ published → config/rankingWeights"))
    .catch((e) => { console.error(e); process.exit(1); });
}

main();
