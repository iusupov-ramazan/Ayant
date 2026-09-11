# Firebase App Check — план внедрения (Ayant / САН)

> Статус: план (не внедрено). Владелец: —. Целевой проект: `san-25d32`.

## Зачем

App Check добавляет к каждому запросу **аттестацию устройства/приложения**: сервер
получает доказательство, что запрос пришёл из подлинной сборки нашего приложения на
настоящем устройстве, а не из скрипта, эмулятора или curl с валидным ID-токеном.

Это закрывает класс атак, который **не** закрывается правилами Firestore и проверкой
ID-токена, потому что там злоумышленник использует легитимные учётные данные:

| Вектор (из аудита) | Как App Check помогает |
|---|---|
| Реферальный фарм (N аккаунтов → бонусы) | Массовое создание аккаунтов/вызовов со скриптов/эмуляторов отсекается аттестацией |
| Анонимный DoS wallet-эндпоинтов | Запрос без валидного App Check-токена отклоняется до подписи/рендера |
| Накрутка `analyticsEvents` конкурентам | Запись телеметрии — только из настоящего приложения |
| Спам `pushCampaigns` (pending) | То же |

App Check — это **защита в глубину поверх** уже сделанного (серверный лимит рефералов,
авторизация wallet-эндпоинтов). Он не заменяет правила и токены, а дополняет их.

## Провайдеры аттестации

| Платформа | Провайдер (прод) | Fallback | Дев |
|---|---|---|---|
| iOS | **App Attest** (DeviceCheck на устройствах без App Attest) | DeviceCheck | Debug provider |
| Android | **Play Integrity** | — | Debug provider |
| Web (админка/маркетинг) | reCAPTCHA Enterprise / v3 | — | Debug token |

## Фазы внедрения (безопасный порядок — сначала наблюдаем, потом принуждаем)

### Фаза 0. Регистрация (Console, без релиза)
- Firebase Console → App Check → зарегистрировать каждое приложение (iOS bundle id,
  Android package + SHA, web).
- iOS: включить App Attest у App ID в Apple Developer. Android: подключить Play Integrity.
- Ничего ещё **не** принуждаем (enforcement выключен) — приложения в проде не ломаются.

### Фаза 1. SDK в клиентах (релиз, режим «monitor»)
- **iOS** (`SANApp.swift`, до `FirebaseApp.configure()` фактически сразу после):
  ```swift
  import FirebaseAppCheck
  // Провайдер: App Attest в проде, Debug в DEBUG-сборке.
  #if DEBUG
  AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
  #else
  AppCheck.setAppCheckProviderFactory(AyantAppCheckFactory()) // App Attest + DeviceCheck fallback
  #endif
  FirebaseApp.configure()
  ```
- **Android** (`AyantApp.kt`, после `FirebaseApp.initializeApp`):
  ```kotlin
  FirebaseAppCheck.getInstance().installAppCheckProviderFactory(
      if (BuildConfig.DEBUG) DebugAppCheckProviderFactory.getInstance()
      else PlayIntegrityAppCheckProviderFactory.getInstance()
  )
  ```
- Раскатать релиз. В Console → App Check смотрим метрики: доля **verified** vs
  **unverified** запросов по Firestore/Functions. Держим, пока подавляющее большинство
  живого трафика (обновлённые клиенты) не станет verified (обычно 1–2 недели на
  естественное обновление приложения).

### Фаза 2. Принуждение (Console, по одному сервису)
Включаем enforcement постепенно, наблюдая за ошибками:
1. **Cloud Functions** (см. ниже про `onRequest` — нужен ручной разбор токена).
2. **Firestore** — включить enforcement (после того как unverified-трафик по Firestore
   упал до шума). Внимание: гостевой режим приложения тоже должен слать App Check-токен
   (App Check не требует аутентификации — токен привязан к устройству, не к пользователю),
   так что публичное чтение ленты продолжит работать из настоящего приложения.
3. **Storage** (если используется напрямую) и **Web** (reCAPTCHA) — в последнюю очередь.

### Фаза 3. Обслуживание
- Мониторить дашборд App Check на всплески unverified (сломанный релиз/атака).
- Ротация: App Attest ключи управляются ОС; секретов хранить не нужно.
- Держать актуальным список отладочных токенов (только для дев-устройств/CI).

## Особый случай: наши HTTPS-функции — это `onRequest`, а не `onCall`

Автоматическое принуждение App Check в Cloud Functions работает «из коробки» только для
**callable** (`onCall`) функций. Наши денежные эндпоинты — `onRequest`
(`scanCoupon`, `redeemVenuePoints`, `generateLoyaltyPass`, `generateCouponPass`).
Для них App Check-токен нужно разобрать **вручную** из заголовка `X-Firebase-AppCheck`:

**Реализовано** в [`functions/src/index.ts`](../../functions/src/index.ts) как `checkAppCheck`
и уже встроено в 4 `onRequest`-функции (`scanCoupon`, `redeemVenuePoints`,
`generateLoyaltyPass`, `generateCouponPass`). Режим — env **`APPCHECK_MODE`**:

```ts
async function checkAppCheck(req, label): Promise<boolean> {
  const mode = process.env.APPCHECK_MODE || "off";  // off | monitor | enforce
  if (mode === "off") return true;                  // нулевой оверхед, поведение как раньше
  const token = req.get("X-Firebase-AppCheck");
  let ok = false;
  if (token) {
    try { const { getAppCheck } = require("firebase-admin/app-check");
          await getAppCheck().verifyToken(token); ok = true; } catch { ok = false; }
  }
  if (!ok) { console.warn(`app-check ${token ? "invalid" : "missing"} on ${label} (mode=${mode})`);
             if (mode === "enforce") return false; } // monitor → пропускаем, enforce → блок
  return true;
}
```
При провале в enforce обработчик отвечает `401 { error: "app_check_failed" }` **до**
привилегированной работы. Раскатка одним env-флагом, без передеплоя кода:

| `APPCHECK_MODE` | Поведение | Когда |
|---|---|---|
| `off` (дефолт) | не проверяем | сейчас (клиенты ещё не шлют токен) |
| `monitor` | проверяем, логируем провалы, **пропускаем** | после Фазы 1, собираем сигнал по логам |
| `enforce` | блокируем при провале | когда логи чистые |

Задать в проде: `firebase functions:config` не нужен — это обычная env-переменная
(`APPCHECK_MODE=monitor`) в конфиге функций.

Клиенты должны прикладывать заголовок к этим ручным вызовам:
- iOS: `let t = try await AppCheck.appCheck().token(forcingRefresh: false).token`
  → `req.setValue(t, forHTTPHeaderField: "X-Firebase-AppCheck")` (в `scanURL`/`redeemURL`
  и в `WalletService.fetchPass`).
- Android: `FirebaseAppCheck.getInstance().getAppCheckToken(false).await().token`
  → заголовок `X-Firebase-AppCheck` в `CouponService`.

Firestore-триггеры (`rewardReferral`, `countAnalyticsEvent`, …) App Check не проверяют —
их «вход» это документ, а запись документа контролируется правилами + Firestore App Check
enforcement (Фаза 2).

## Чек-лист

- [ ] Фаза 0: приложения зарегистрированы; App Attest / Play Integrity подключены
- [ ] Фаза 1 iOS: `FirebaseAppCheck` + фабрика провайдера, DEBUG → debug provider
- [ ] Фаза 1 Android: `installAppCheckProviderFactory`, DEBUG → debug provider
- [ ] Клиенты шлют `X-Firebase-AppCheck` в ручные `onRequest`-вызовы (scan/redeem/wallet)
- [x] `checkAppCheck` добавлен в 4 `onRequest`-функции за флагом `APPCHECK_MODE` (дефолт `off`)
- [ ] `APPCHECK_MODE=monitor` в проде; метрики: доля valid → ~95% живого трафика
- [ ] Фаза 2: `APPCHECK_MODE=enforce` для функций; enforcement Firestore → Storage/Web в Console
- [ ] Ролбэк-план: `APPCHECK_MODE=off` (функции) / снять enforcement в Console — мгновенно

## Ссылки
- Firebase App Check: https://firebase.google.com/docs/app-check
- Ручная проверка токена в бэкенде: https://firebase.google.com/docs/app-check/custom-resource-backend
