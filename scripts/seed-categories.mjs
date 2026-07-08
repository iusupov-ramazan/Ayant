// Seed the six built-in categories into Firestore `categories`.
//
// SAFE: uses set({ merge:true }) with doc id = slug, so it only creates/updates
// those six category documents. It never reads, changes, or deletes `venues`
// or `deals` (or anything else).
//
// Usage:
//   npm i firebase-admin
//   node scripts/seed-categories.mjs /path/to/serviceAccountKey.json
// or set GOOGLE_APPLICATION_CREDENTIALS and run without an argument.

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { readFileSync, readdirSync, existsSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

// Find the service-account key: explicit arg/env first, else auto-search
// common locations for a "san-25d32...adminsdk...json" file.
function findKey() {
  const explicit = process.argv[2] || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (explicit) return explicit;
  const home = homedir();
  const dirs = [process.cwd(), join(process.cwd(), 'scripts'),
                join(home, 'Downloads'), join(home, 'Desktop'), home];
  for (const dir of dirs) {
    try {
      const hit = readdirSync(dir).find(f =>
        /adminsdk.*\.json$/i.test(f) && f.includes('san-25d32'));
      if (hit) return join(dir, hit);
    } catch {}
  }
  return null;
}

const keyPath = findKey();
if (!keyPath || !existsSync(keyPath)) {
  console.error('❌ Не найден ключ сервис-аккаунта (san-25d32-...-adminsdk-...json).');
  console.error('   Передайте путь явно:  node scripts/seed-categories.mjs /полный/путь/к/ключу.json');
  process.exit(1);
}
console.log('Ключ:', keyPath);

const svc = JSON.parse(readFileSync(keyPath, 'utf8'));
initializeApp({ credential: cert(svc), projectId: svc.project_id });

const db = getFirestore();

const CATEGORIES = [
  { slug: 'cafe',       name: 'Кафе',     icon: 'fork.knife',                        emoji: '🍽', order: 0 },
  { slug: 'coffee',     name: 'Кофейня',  icon: 'cup.and.saucer.fill',               emoji: '☕️', order: 1 },
  { slug: 'fastfood',   name: 'Фастфуд',  icon: 'takeoutbag.and.cup.and.straw.fill', emoji: '🍔', order: 2 },
  { slug: 'restaurant', name: 'Ресторан', icon: 'wineglass.fill',                    emoji: '🍷', order: 3 },
  { slug: 'teahouse',   name: 'Чайхана',  icon: 'mug.fill',                          emoji: '🫖', order: 4 },
  { slug: 'bakery',     name: 'Пекарня',  icon: 'birthday.cake.fill',                emoji: '🧁', order: 5 },
];

for (const c of CATEGORIES) {
  await db.collection('categories').doc(c.slug).set({ ...c, enabled: true }, { merge: true });
  console.log('  ✓', c.slug, '→', c.name);
}

const snap = await db.collection('categories').get();
console.log(`\nDone. \`categories\` now has ${snap.size} documents.`);
console.log('venues and deals were not touched.');
process.exit(0);
