# Ayta — Telegram-бот поддержки (ИИ, бесплатно)

ИИ-помощник, который отвечает пользователям 24/7 на русском, опираясь на справку Ayta и FAQ. Работает в режиме long-polling — не нужен сервер с публичным адресом, бот можно запустить где угодно (свой ПК, бесплатный тариф Render/Railway/Fly.io).

Стоимость: **0**. Telegram Bot API бесплатный, ИИ — бесплатный тариф [Groq](https://console.groq.com). Без ИИ-ключа бот всё равно отвечает по FAQ.

## 1. Создать бота

1. Открой [@BotFather](https://t.me/BotFather) в Telegram → `/newbot`.
2. Задай имя и username (напр. `AytaSupportBot`).
3. Скопируй **токен** — это `TELEGRAM_BOT_TOKEN`.
4. Впиши тот же username в приложении: `SAN/Help/HelpViews.swift` → `SupportView` → ссылка `https://t.me/<username>`.

## 2. (Опционально) Бесплатный ИИ-ключ

1. Зайди на [console.groq.com/keys](https://console.groq.com/keys) (бесплатно).
2. Создай API key → это `GROQ_API_KEY`.

## 3. Запуск локально

```bash
cd telegram-bot
cp .env.example .env      # впиши TELEGRAM_BOT_TOKEN и (по желанию) GROQ_API_KEY
npm install
npm start
```

В чате с ботом: `/start`, `/faq`, или просто напиши вопрос.

## 4. Бесплатный хостинг (24/7)

Бот использует long-polling, поэтому подойдёт любой «worker / background»:

- **Render** → New → Background Worker → подключи репозиторий, Start command `npm start`, добавь переменные окружения из `.env`.
- **Railway / Fly.io** → аналогично, задай переменные окружения.

> ⚠️ `.env` не коммить в git (уже в `.gitignore` проекта). На хостинге задавай переменные через панель.

## Как это работает

- Любое текстовое сообщение → ИИ-ответ (Groq), приправленный справкой Ayta и FAQ из `faq.js`.
- Нет ключа ИИ или ошибка сети → фолбэк: подбор ответа из FAQ по ключевым словам.
- Не знает ответ → предлагает написать живой поддержке (`SUPPORT_CONTACT`).

Чтобы поменять тексты — редактируй `faq.js` (он же контекст для ИИ).
