/**
 * RESTORE — Ayant / JSON-бэкап → Firestore
 *
 * Запуск:
 *   node restore-firestore.js backup-2026-06-30T05-10-00-000Z.json
 *
 * Пишет документы обратно (merge). Timestamp-поля восстанавливаются корректно.
 * Нужен serviceAccountKey.json рядом с файлом.
 */
const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const fs = require("fs");
const serviceAccount = require("./serviceAccountKey.json");

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

const file = process.argv[2];
if (!file) { console.error("Укажи файл: node restore-firestore.js <backup.json>"); process.exit(1); }

// Восстанавливаем Timestamp из {_seconds,_nanoseconds}.
function revive(v) {
  if (v && typeof v === "object") {
    if (typeof v._seconds === "number" && typeof v._nanoseconds === "number") {
      return new Timestamp(v._seconds, v._nanoseconds);
    }
    if (Array.isArray(v)) return v.map(revive);
    const o = {};
    for (const k of Object.keys(v)) o[k] = revive(v[k]);
    return o;
  }
  return v;
}

async function run() {
  const dump = JSON.parse(fs.readFileSync(file, "utf8"));
  for (const c of Object.keys(dump)) {
    const docs = dump[c] || [];
    for (let i = 0; i < docs.length; i += 400) {
      const batch = db.batch();
      docs.slice(i, i + 400).forEach((d) =>
        batch.set(db.collection(c).doc(d.id), revive(d.data), { merge: true }));
      await batch.commit();
    }
    console.log(`  ♻️  ${c}: ${docs.length}`);
  }
  console.log("✅ Восстановление завершено.");
  process.exit(0);
}
run().catch((e) => { console.error("❌", e); process.exit(1); });
