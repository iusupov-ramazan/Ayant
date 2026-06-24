import { Bot, InlineKeyboard } from "grammy";
import http from "node:http";
import "dotenv/config";
import { ABOUT, FAQ, matchFAQ } from "./faq.js";

const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const GROQ_KEY = process.env.GROQ_API_KEY;                 // бесплатный ключ: console.groq.com
const GROQ_MODEL = process.env.GROQ_MODEL || "llama-3.3-70b-versatile";
const HANDOFF = process.env.SUPPORT_CONTACT || "ostepp1@gmail.com";

if (!TOKEN) {
  console.error("❌ Укажи TELEGRAM_BOT_TOKEN в .env (получи у @BotFather).");
  process.exit(1);
}

const bot = new Bot(TOKEN);

const SYSTEM_PROMPT = `Ты — ИИ-помощник поддержки приложения «Ayta».
Отвечай ТОЛЬКО на русском, кратко (1–4 предложения), дружелюбно и по делу.
Отвечай на вопросы пользователей о приложении, опираясь на справку ниже.
Если вопрос не про Ayta или ты не уверен — честно скажи и предложи написать живой поддержке: ${HANDOFF}.
Не выдумывай функции, которых нет в справке.

=== СПРАВКА О ПРИЛОЖЕНИИ ===
${ABOUT}

=== ЧАСТЫЕ ВОПРОСЫ ===
${FAQ.map((f, i) => `${i + 1}. ${f.q}\n${f.a}`).join("\n\n")}`;

// /start
bot.command("start", (ctx) =>
  ctx.reply(
    "👋 Привет! Я — помощник поддержки Ayta.\n\n" +
      "Задай любой вопрос о приложении, бонусах или купонах — отвечу сразу.\n" +
      "Или загляни в частые вопросы: /faq",
    { reply_markup: new InlineKeyboard().text("❓ Частые вопросы", "faq_menu") }
  )
);

// /faq — список вопросов кнопками
function faqKeyboard() {
  const kb = new InlineKeyboard();
  FAQ.forEach((f, i) => kb.text(f.q, `faq_${i}`).row());
  return kb;
}
bot.command("faq", (ctx) => ctx.reply("Выбери вопрос:", { reply_markup: faqKeyboard() }));
bot.callbackQuery("faq_menu", async (ctx) => {
  await ctx.answerCallbackQuery();
  await ctx.reply("Выбери вопрос:", { reply_markup: faqKeyboard() });
});
bot.callbackQuery(/^faq_(\d+)$/, async (ctx) => {
  const i = Number(ctx.match[1]);
  await ctx.answerCallbackQuery();
  if (FAQ[i]) await ctx.reply(`❓ ${FAQ[i].q}\n\n${FAQ[i].a}`);
});

// Любой текст → ИИ-ответ (с фолбэком на FAQ)
bot.on("message:text", async (ctx) => {
  const question = ctx.message.text.trim();
  if (question.startsWith("/")) return;
  await ctx.replyWithChatAction("typing");
  const answer = await askAI(question);
  await ctx.reply(answer);
});

async function askAI(question) {
  // Нет ключа ИИ — работаем на FAQ.
  if (!GROQ_KEY) {
    return matchFAQ(question) ||
      `Я пока не нашёл точного ответа. Напиши, пожалуйста, живой поддержке: ${HANDOFF}, или посмотри /faq.`;
  }
  try {
    const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${GROQ_KEY}` },
      body: JSON.stringify({
        model: GROQ_MODEL,
        temperature: 0.3,
        max_tokens: 400,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: question },
        ],
      }),
    });
    if (!res.ok) throw new Error(`Groq ${res.status}`);
    const data = await res.json();
    const text = data?.choices?.[0]?.message?.content?.trim();
    return text || matchFAQ(question) || `Напиши, пожалуйста, поддержке: ${HANDOFF}.`;
  } catch (e) {
    console.error("AI error:", e.message);
    return matchFAQ(question) ||
      `Сейчас не получилось ответить. Попробуй ещё раз или напиши поддержке: ${HANDOFF}.`;
  }
}

bot.catch((err) => console.error("Bot error:", err));

// Мини HTTP-сервер: нужен бесплатному хостингу (Render), чтобы не «засыпать».
// Пингер (UptimeRobot) стучится сюда раз в 5 минут и держит бота онлайн 24/7.
const PORT = process.env.PORT || 3000;
http
  .createServer((_, res) => {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("Ayta support bot is alive");
  })
  .listen(PORT, () => console.log(`🌐 health-check на порту ${PORT}`));

bot.start({ onStart: (i) => console.log(`✅ @${i.username} запущен (long-polling).`) });
