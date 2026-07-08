/**
 * BACKUP — Ayant / Firestore → локальный JSON
 *
 * Сохраняет коллекции venues, deals, reviews, hosts в файл backup-<дата>.json.
 * Запуск:
 *   node backup-firestore.js
 *
 * Нужен serviceAccountKey.json рядом с файлом.
 * Восстановление — node restore-firestore.js backup-<дата>.json
 */
const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const fs = require("fs");
const serviceAccount = require("./serviceAccountKey.json");

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

const COLLECTIONS = ["venues", "deals", "reviews", "hosts"];

async function backupAll(prefix = "backup") {
  const out = {};
  for (const c of COLLECTIONS) {
    const snap = await db.collection(c).get();
    out[c] = snap.docs.map((d) => ({ id: d.id, data: d.data() }));
    console.log(`  📦 ${c}: ${snap.size}`);
  }
  const ts = new Date().toISOString().replace(/[:.]/g, "-");
  const file = `${prefix}-${ts}.json`;
  fs.writeFileSync(file, JSON.stringify(out, null, 2));
  console.log(`✅ Сохранено: ${file}`);
  return file;
}

module.exports = { backupAll, COLLECTIONS };

// Запуск напрямую (не через require).
if (require.main === module) {
  backupAll().then(() => process.exit(0)).catch((e) => { console.error("❌", e); process.exit(1); });
}
