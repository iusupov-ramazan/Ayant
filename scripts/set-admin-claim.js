/**
 * SET ADMIN CLAIM — Ayant / выдать (или снять) роль администратора.
 *
 * Панель админки (docs/admin) и firestore.rules теперь пускают к записи каталога
 * только пользователей с кастомным claim `admin: true`. Этот скрипт выставляет
 * или снимает его по email.
 *
 * Запуск:
 *   node scripts/set-admin-claim.js <email>            # выдать роль
 *   node scripts/set-admin-claim.js <email> --revoke   # снять роль
 *
 * Нужен serviceAccountKey.json в корне проекта (тот же, что и у seed-скриптов).
 * После смены claim пользователь должен перелогиниться (или токен обновится сам
 * в течение часа) — панель делает getIdTokenResult(true), т.е. форсит refresh.
 */
const { initializeApp, cert } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const serviceAccount = require("../serviceAccountKey.json");

initializeApp({ credential: cert(serviceAccount) });

async function main() {
  const email = process.argv[2];
  const revoke = process.argv.includes("--revoke");
  if (!email) {
    console.error("Usage: node scripts/set-admin-claim.js <email> [--revoke]");
    process.exit(1);
  }

  const auth = getAuth();
  const user = await auth.getUserByEmail(email);
  await auth.setCustomUserClaims(user.uid, revoke ? { admin: false } : { admin: true });
  // Инвалидируем текущие токены, чтобы claim применился при следующем запросе.
  await auth.revokeRefreshTokens(user.uid);

  console.log(
    `${revoke ? "🚫 revoked" : "✅ granted"} admin for ${email} (uid=${user.uid}). ` +
    "Пользователю нужно перелогиниться."
  );
}

main().catch((e) => {
  console.error("❌", e.message);
  process.exit(1);
});
