# Apple Wallet — карта лояльности (настройка)

Карта лояльности работает **полностью в приложении уже сейчас** (штампы, награды,
экран «Карты лояльности»). Кнопка **«Добавить в Apple Wallet»** начнёт выдавать
реальные `.pkpass` только после того, как вы настроите сертификат Apple и включите
Cloud Function `generateLoyaltyPass`. До этого приложение показывает мягкое
сообщение «Apple Wallet скоро» — ничего не ломается.

## Что уже готово в коде

- Клиент: `SAN/Bonus/LoyaltyStore.swift` — `WalletService` дёргает
  `https://us-central1-san-25d32.cloudfunctions.net/generateLoyaltyPass`.
- Сервер: `functions/index.js` → `exports.generateLoyaltyPass` (HTTP-функция).
  Пока `WALLET_CONFIGURED != "1"` она отвечает `503`, и приложение это корректно обрабатывает.
- Зависимость `passkit-generator` добавлена в `functions/package.json`.

## Шаги настройки (делаете вы — сертификат нельзя сгенерировать из кода)

### 1. Создайте Pass Type ID
Apple Developer → Certificates, IDs & Profiles → **Identifiers** → «+» →
**Pass Type IDs** → например `pass.com.yourcompany.san.loyalty`.

### 2. Создайте сертификат для этого Pass Type ID
Там же → Create Certificate → загрузите CSR (из «Связка ключей» на Mac:
Ассистент сертификации → запросить сертификат у CA → сохранить на диск).
Скачайте `.cer`, дважды кликните → он попадёт в Keychain.

### 3. Экспортируйте в PEM
В Keychain найдите сертификат, экспортируйте пару **сертификат + приватный ключ**
как `Certificates.p12`, затем:

```bash
# сертификат подписи
openssl pkcs12 -in Certificates.p12 -clcerts -nokeys -out signerCert.pem -legacy
# приватный ключ
openssl pkcs12 -in Certificates.p12 -nocerts -out signerKey.pem -legacy
# WWDR (Apple Worldwide Developer Relations) — скачайте AppleWWDRCAG4.cer с developer.apple.com
openssl x509 -inform der -in AppleWWDRCAG4.cer -out wwdr.pem
```

Положите три файла в `functions/certs/`:
```
functions/certs/signerCert.pem
functions/certs/signerKey.pem
functions/certs/wwdr.pem
functions/certs/images/icon.png      (29x29)
functions/certs/images/icon@2x.png   (58x58)
functions/certs/images/logo.png      (≤160x50)
functions/certs/images/logo@2x.png
```
⚠️ **Добавьте `functions/certs/` в `.gitignore`** — это секреты, в git их не коммитим.

### 4. Задайте переменные окружения функции
```bash
firebase functions:secrets:set PASS_KEY_PASSPHRASE   # пароль от .p12 (если ставили)
```
и обычные env (в `functions/.env` или через `--set-env-vars`):
```
WALLET_CONFIGURED=1
PASS_TYPE_ID=pass.com.yourcompany.san.loyalty
PASS_TEAM_ID=R6W6JK63KU
PASS_ORG_NAME=Ayant
```

### 5. Установите зависимость и задеплойте
```bash
cd functions
npm install
firebase deploy --only functions:generateLoyaltyPass
```

### 6. Проверьте
Открыть в браузере:
```
https://us-central1-san-25d32.cloudfunctions.net/generateLoyaltyPass?venue=test&name=Test&stamps=2&goal=6
```
Должен скачаться `.pkpass`. На iPhone он откроется в Wallet. В приложении кнопка
«Добавить в Apple Wallet» покажет системный лист добавления.

## Заметки
- Обновление карт (при новом штампе) — отдельная возможность (APNs push на pass +
  `webServiceURL`). Сейчас карта статична на момент добавления; можно добавить позже.
- `serialNumber` = `loyal-<venueID>` — при повторном добавлении Wallet обновит тот же pass.

---

# Бэкенд-купоны + сканер заведения (server-synced)

Купоны теперь трекаются в Firestore, а заведение сканирует их камерой (сторона
бизнеса) → погашение + 1 штамп лояльности гостю. Всё атомарно на сервере.

## Как это работает (3 стороны)
- **Гость:** на акции жмёт «Получить купон» → создаётся документ `coupons/{id}`
  (`used:false`, `venueID`). Купон виден в «Мои купоны» + можно «Добавить в Apple
  Wallet» (QR = `code`). Штампы/награды приходят синком из `loyaltyCards`.
- **Бизнес:** вкладка «Заведения» → 🔳 (сканер) или на странице заведения
  «Сканировать купоны гостей». Камера читает QR → Cloud Function `scanCoupon`.
- **Backend:** `scanCoupon` проверяет владельца заведения (по ID-токену хоста),
  что купон этого заведения и не погашен → помечает `used`, +1 штамп в
  `loyaltyCards/{userID}_{venueID}`, на goal-м штампе создаёт купон-награду,
  инкрементит аналитику `redemptions`.

## Что задеплоить
```bash
cd functions && npm install            # (passkit-generator уже в lock)
firebase deploy --only functions:scanCoupon,functions:generateCouponPass,functions:generateLoyaltyPass
firebase deploy --only firestore:rules # новые правила coupons + loyaltyCards
```
Приложение: пересобрать в Xcode (добавлены файлы `HostScannerView.swift` и
`NSCameraUsageDescription` в Info.plist для камеры сканера).

## Новые Cloud Functions
- `scanCoupon` (POST, `Authorization: Bearer <idToken>`, body `{code, venueID}`) —
  погашение + штамп. Ошибки: `already_used` / `wrong_venue` / `not_owner` / …
- `generateCouponPass` (GET `?code=&title=&venue=`) — купон в Apple Wallet
  (те же сертификаты, что и карта лояльности; 503 пока `WALLET_CONFIGURED != 1`).

## Проверка сканера
Реальный QR берётся из купона (`code`, вида `AYANT-XXXXXX`). Сканер работает
только на устройстве с камерой; на симуляторе — ручной ввод кода. Заведение,
которое сканирует, должно принадлежать вошедшему хосту (`venues/{id}.ownerID == uid`).
