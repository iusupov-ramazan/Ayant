import { Bot, InlineKeyboard } from "grammy";
import http from "node:http";
import "dotenv/config";
import { KNOWLEDGE, USER_FAQ, BUSINESS_FAQ, matchFAQ } from "./faq.js";

const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const GROQ_KEY = process.env.GROQ_API_KEY;                 // бесплатный ключ: console.groq.com
const GROQ_MODEL = process.env.GROQ_MODEL || "llama-3.3-70b-versatile";
const HANDOFF = process.env.SUPPORT_CONTACT || "WhatsApp +996707266556 или email ostepp1@gmail.com";

if (!TOKEN) {
  console.error("❌ Укажи TELEGRAM_BOT_TOKEN в .env (получи у @BotFather).");
  process.exit(1);
}

const bot = new Bot(TOKEN);

const SYSTEM_PROMPT = `Ты — ИИ-помощник поддержки приложения «Ayant» (Bonus.kg).
Отвечай ТОЛЬКО на русском, кратко (1–4 предложения), дружелюбно и по делу.
Помогай и обычным пользователям, и заведениям (бизнесу), опираясь на справку ниже.
Если вопрос не про Ayant или ты не уверен — честно скажи и предложи написать живой поддержке: ${HANDOFF}.
Не выдумывай функции, которых нет в справке.

=== БАЗА ЗНАНИЙ ===
${KNOWLEDGE}`;

// /start
bot.command("start", (ctx) =>
  ctx.reply(
    "👋 Привет! Я — помощник поддержки Ayant (Bonus.kg).\n\n" +
      "Задай любой вопрос о приложении, бонусах, купонах или размещении заведения — отвечу сразу.\n" +
      "Или открой частые вопросы: /faq",
    { reply_markup: categoryKeyboard() }
  )
);

// Меню категорий FAQ
function categoryKeyboard() {
  return new InlineKeyboard()
    .text("🙋 Для пользователей", "cat_u").row()
    .text("🏪 Для бизнеса", "cat_b");
}
// Список вопросов одной категории: data = "u3" / "b7"
function listKeyboard(prefix, list) {
  const kb = new InlineKeyboard();
  list.forEach((f, i) => kb.text(f.q, `${prefix}${i}`).row());
  kb.text("⬅️ Назад", "faq_menu");
  return kb;
}

bot.command("faq", (ctx) =>
  ctx.reply("О чём вопрос?", { reply_markup: categoryKeyboard() })
);
bot.callbackQuery("faq_menu", async (ctx) => {
  await ctx.answerCallbackQuery();
  await ctx.reply("О чём вопрос?", { reply_markup: categoryKeyboard() });
});
bot.callbackQuery("cat_u", async (ctx) => {
  await ctx.answerCallbackQuery();
  await ctx.reply("Вопросы пользователей:", { reply_markup: listKeyboard("u", USER_FAQ) });
});
bot.callbackQuery("cat_b", async (ctx) => {
  await ctx.answerCallbackQuery();
  await ctx.reply("Вопросы бизнеса:", { reply_markup: listKeyboard("b", BUSINESS_FAQ) });
});
bot.callbackQuery(/^([ub])(\d+)$/, async (ctx) => {
  const list = ctx.match[1] === "u" ? USER_FAQ : BUSINESS_FAQ;
  const item = list[Number(ctx.match[2])];
  await ctx.answerCallbackQuery();
  if (item) await ctx.reply(`❓ ${item.q}\n\n${item.a}`);
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
    res.end("Ayant support bot is alive");
  })
  .listen(PORT, () => console.log(`🌐 health-check на порту ${PORT}`));

bot.start({ onStart: (i) => console.log(`✅ @${i.username} запущен (long-polling).`) });
