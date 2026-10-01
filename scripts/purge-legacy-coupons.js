/**
 * PURGE LEGACY COUPONS — Ayant / удалить старые купоны гостей
 *
 * До серверного кошелька (2026-10-01) купоны создавал клиент: награды
 * глобального кошелька, купоны акций, подарки — в том числе те, что нельзя
 * погасить. Скрипт удаляет купоны, созданные ДО отсечки, из `coupons`
 * (и, по флагу, незабранные подарки из `giftCoupons`).
 *
 * Запуск (из корня проекта, нужен serviceAccountKey.json):
 *   node scripts/purge-legacy-coupons.js                 # СУХОЙ прогон: только считает
 *   node scripts/purge-legacy-coupons.js --apply         # бэкап + удаление
 *
 * Флаги:
 *   --before=2026-10-01T00:00:00+06:00   отсечка (по умолчанию — запуск кошелька)
 *   --keep-loyalty    не трогать купоны-награды карт штампов (kind "loyalty") —
 *                     их гость заработал визитами, и сервер создал их сам
 *   --keep-used       не трогать уже погашенные (для истории/аналитики)
 *   --gifts           также удалить незабранные подарки из giftCoupons
 *
 * Перед удалением пишет backup-coupons-<время>.json — восстановить можно
 * вручную из него. Удаление необратимо; сначала запустите без --apply и
 * посмотрите, что попадёт под удаление.
 *
 * Купоны на телефонах чистит само приложение (одноразовая очистка кэша в
 * `CouponStore`): после этого скрипта синк больше не вернёт их с сервера.
 */
const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const fs = require("fs");
const path = require("path");
const serviceAccount = require("../serviceAccountKey.json");

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

function arg(name, fallback) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
}
const has = (name) => process.argv.includes(`--${name}`);

const APPLY = has("apply");
const CUTOFF = new Date(arg("before", "2026-10-01T00:00:00+06:00"));
const KEEP_LOYALTY = has("keep-loyalty");
const KEEP_USED = has("keep-used");
const GIFTS = has("gifts");

function millis(v) {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  const t = new Date(v).getTime();
  return Number.isFinite(t) ? t : 0;
}

// Документ без даты считается старым: даты не ставил только старый клиент.
function isOld(data) {
  const created = millis(data.createdAt);
  return created === 0 || created < CUTOFF.getTime();
}

async function collect(collection, keep) {
  const snap = await db.collection(collection).get();
  return snap.docs.filter((d) => {
    const data = d.data() || {};
    return isOld(data) && !keep(data);
  });
}

async function deleteDocs(docs) {
  // Пачками по 400 — лимит batch в Firestore 500.
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const d of docs.slice(i, i + 400)) batch.delete(d.ref);
    await batch.commit();
    console.log(`  удалено ${Math.min(i + 400, docs.length)} / ${docs.length}`);
  }
}

async function main() {
  if (Number.isNaN(CUTOFF.getTime())) {
    console.error("Неверная дата в --before");
    process.exit(1);
  }
  console.log(`Отсечка: ${CUTOFF.toISOString()}${APPLY ? "" : "  (СУХОЙ ПРОГОН — ничего не удаляется)"}`);

  const coupons = await collect("coupons", (c) =>
    (KEEP_LOYALTY && c.kind === "loyalty") || (KEEP_USED && c.used === true));
  const gifts = GIFTS ? await collect("giftCoupons", (g) => g.claimed === true) : [];

  const byKind = {};
  for (const d of coupons) {
    const k = String((d.data() || {}).kind || "bonus");
    byKind[k] = (byKind[k] || 0) + 1;
  }
  console.log(`coupons к удалению: ${coupons.length}`, byKind);
  if (GIFTS) console.log(`giftCoupons (незабранные) к удалению: ${gifts.length}`);

  if (!APPLY) {
    console.log("\nЧтобы удалить — запустите снова с --apply.");
    return;
  }
  if (coupons.length === 0 && gifts.length === 0) {
    console.log("Удалять нечего.");
    return;
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const file = path.join(process.cwd(), `backup-coupons-${stamp}.json`);
  fs.writeFileSync(file, JSON.stringify({
    cutoff: CUTOFF.toISOString(),
    coupons: coupons.map((d) => ({ id: d.id, data: d.data() })),
    giftCoupons: gifts.map((d) => ({ id: d.id, data: d.data() })),
  }, null, 2));
  console.log(`Бэкап: ${file}`);

  await deleteDocs(coupons);
  if (gifts.length) await deleteDocs(gifts);
  console.log("Готово.");
}

main().catch((e) => { console.error(e); process.exit(1); });
