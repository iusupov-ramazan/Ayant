# Universal Links — что доделать

Диплинки уже работают через кастомную схему `san://`. Чтобы ссылки вида
`https://san.kg/venue/<id>` открывали приложение (а не только при установленном
приложении на устройстве с зарегистрированной схемой), нужно настроить Universal Links.

## Шаги

1. **Домен.** Замени `san.kg` на свой домен в трёх местах:
   - `SAN/SAN.entitlements` → `applinks:<домен>`
   - `SAN/Deeplink/Deeplink.swift` → `DeepLinkRouter.domain`
   - этот файл AASA (необязательно — он про appID, не про домен)

2. **Team ID.** В `web/.well-known/apple-app-site-association` замени `TEAMID` на
   свой Apple Developer Team ID (Membership → Team ID). Итог: `TEAMID.kg.san.app`.

3. **Хостинг AASA.** Размести файл по адресу:
   `https://<домен>/.well-known/apple-app-site-association`
   - HTTPS обязательно, без редиректов.
   - Content-Type: `application/json`.
   - Без расширения `.json` в имени файла.

4. **Веб-фолбэк (желательно).** Сделай простые страницы `/venue/<id>` и `/deal/<id>`
   на сайте — чтобы при отсутствии приложения ссылка показывала превью заведения/акции.

5. **Xcode.** Associated Domains capability уже прописана в entitlements. Проверь, что
   в таргете включён Associated Domains и подпись (Team) настроена.

После этого `ShareLink` уже шлёт `https://<домен>/...`, а приложение ловит их через
`.onContinueUserActivity` (уже реализовано).
