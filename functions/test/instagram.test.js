"use strict";

/**
 * Instagram: подключение аккаунта заведения, синхронизация постов, импорт.
 *
 * Проверяется то, что ломается молча и дорого:
 *   — токен доступа не утекает клиенту НИ В ОДНОМ ответе;
 *   — чужое заведение подключить нельзя (владение + одноразовый `state`);
 *   — протухший токен превращается в `reauth_required` и флаг `needsReauth`,
 *     а не в пустой список постов («постов нет» хост читает как поломку);
 *   — при импорте ссылки на CDN инстаграма заменяются нашими: ссылки Meta
 *     протухают за часы, и фото у импортированных акций отвалились бы молча.
 *
 * Graph API и Cloudinary подменяются заглушкой `globalThis.fetch`.
 */

process.env.INSTAGRAM_APP_ID = "ig-app";
process.env.INSTAGRAM_APP_SECRET = "ig-secret";
process.env.INSTAGRAM_REDIRECT_URI = "https://example.test/cb";
process.env.INSTAGRAM_RETURN_URL = "https://ayant.kg/ig/connected";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { makeHarness, makeReq, makeRes } = require("./helpers/harness");

const TOKEN = "host-token";
const UID = "host-1";
const VENUE = "v1";

function harness() {
  const h = makeHarness({ tokens: { [TOKEN]: UID } });
  h.seed(`venues/${VENUE}`, { ownerID: UID, name: "Кафе" });
  h.seed("venues/other", { ownerID: "someone-else", name: "Чужое" });
  return h;
}

function connect(h, extra = {}) {
  h.seed(`igAccounts/${UID}_${VENUE}`, {
    ownerID: UID, venueID: VENUE, igUserID: "ig-9", username: "cafe",
    accessToken: "long-token", needsReauth: false, ...extra,
  });
  h.seed(`igConnections/${UID}_${VENUE}`, {
    ownerID: UID, venueID: VENUE, username: "cafe", needsReauth: false,
  });
}

function req({ body = {}, query = {}, token = TOKEN, method = "POST" } = {}) {
  return makeReq({
    method,
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body, query,
  });
}

async function call(fn, r) {
  const res = makeRes();
  await fn(r, res);
  return res;
}

/** Подменяет fetch на маршрутизатор по подстроке URL. Возвращает список вызовов. */
function stubFetch(routes) {
  const calls = [];
  const real = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    const u = String(url);
    calls.push({ url: u, init });
    for (const [needle, reply] of Object.entries(routes)) {
      if (u.includes(needle)) {
        const body = typeof reply === "function" ? reply(u, init) : reply;
        return { ok: body.__status ? body.__status < 400 : true, json: async () => body };
      }
    }
    throw new Error(`неожиданный fetch: ${u}`);
  };
  calls.restore = () => { globalThis.fetch = real; };
  return calls;
}

const MEDIA_OK = {
  data: [{
    id: "post-1",
    caption: "Новое меню\nПриходите",
    media_type: "IMAGE",
    media_url: "https://scontent.cdninstagram.com/a.jpg",
    permalink: "https://instagram.com/p/1",
    timestamp: "2026-09-01T10:00:00+0000",
  }],
};

/* ── Шаг 1: ссылка входа ─────────────────────────────────────────────────── */

test("authStart: без токена → 401", async () => {
  const res = await call(harness().mod.instagramAuthStart, req({ token: null, body: { venueID: VENUE } }));
  assert.equal(res.statusCode, 401);
});

test("authStart: чужое заведение → 403 not_owner", async () => {
  const res = await call(harness().mod.instagramAuthStart, req({ body: { venueID: "other" } }));
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "not_owner");
});

test("authStart: владельцу выдаётся ссылка с одноразовым state", async () => {
  const h = harness();
  const res = await call(h.mod.instagramAuthStart, req({ body: { venueID: VENUE } }));
  assert.equal(res.statusCode, 200);
  const url = new URL(res.body.authURL);
  assert.equal(url.host, "www.instagram.com");
  assert.equal(url.searchParams.get("client_id"), "ig-app");
  assert.equal(url.searchParams.get("scope"), "instagram_business_basic");
  const state = url.searchParams.get("state");
  assert.ok(state && state.length >= 32, "state должен быть длинным случайным");
  const saved = h.read(`igAuthStates/${state}`);
  assert.equal(saved.ownerID, UID);
  assert.equal(saved.venueID, VENUE);
  assert.ok(!res.body.authURL.includes("ig-secret"), "секрет приложения не уходит клиенту");
});

/* ── Шаг 2: возврат из Instagram ─────────────────────────────────────────── */

test("callback: неизвестный state отклоняется", async () => {
  const res = await call(harness().mod.instagramAuthCallback,
    req({ method: "GET", token: null, query: { code: "c", state: "подделка" } }));
  assert.match(res.redirectedTo, /status=bad_state/);
});

test("callback: протухший state отклоняется", async () => {
  const h = harness();
  h.seed("igAuthStates/old", {
    ownerID: UID, venueID: VENUE, createdAt: new Date(Date.now() - 60 * 60 * 1000),
  });
  const res = await call(h.mod.instagramAuthCallback,
    req({ method: "GET", token: null, query: { code: "c", state: "old" } }));
  assert.match(res.redirectedTo, /status=expired_state/);
});

test("callback: успешный вход сохраняет длинный токен, но не в публичный документ", async () => {
  const h = harness();
  h.seed("igAuthStates/s1", { ownerID: UID, venueID: VENUE, createdAt: new Date() });
  const calls = stubFetch({
    "api.instagram.com/oauth/access_token": { access_token: "short", user_id: 9 },
    "graph.instagram.com/access_token": { access_token: "long", expires_in: 5184000 },
    "graph.instagram.com/me?": { id: "ig-9", username: "cafe" },
  });
  try {
    const res = await call(h.mod.instagramAuthCallback,
      req({ method: "GET", token: null, query: { code: "code-1", state: "s1" } }));
    assert.equal(res.statusCode, 302);
    assert.match(res.redirectedTo, /status=ok/);
    const acc = h.read(`igAccounts/${UID}_${VENUE}`);
    assert.equal(acc.accessToken, "long");
    assert.equal(acc.username, "cafe");
    assert.equal(acc.needsReauth, false);
    const pub = h.read(`igConnections/${UID}_${VENUE}`);
    assert.equal(pub.username, "cafe");
    assert.equal(pub.accessToken, undefined, "токена в читаемом клиентом документе быть не должно");
    assert.equal(h.read("igAuthStates/s1"), undefined, "state одноразовый");
    // Секрет уходит только в Meta, и только в теле/строке запроса токена.
    assert.ok(calls.some((c) => c.url.includes("graph.instagram.com/access_token")
      && c.url.includes("ig-secret")));
  } finally { calls.restore(); }
});

/**
 * Instagram Login отдаёт токен завёрнутым в массив `data`, старый Basic Display
 * отдавал плоско. Работать должны оба вида: ошибка здесь не ломает ничего
 * заметного в тестах, но на живом аккаунте означает «подключение не работает».
 */
test("callback: токен в обёртке data тоже принимается", async () => {
  const h = harness();
  h.seed("igAuthStates/s2", { ownerID: UID, venueID: VENUE, createdAt: new Date() });
  const calls = stubFetch({
    "api.instagram.com/oauth/access_token": {
      data: [{ access_token: "short-wrapped", user_id: 777, permissions: "instagram_business_basic" }],
    },
    "graph.instagram.com/access_token": { access_token: "long-wrapped", expires_in: 5184000 },
    "graph.instagram.com/me?": { id: "ig-app-scoped", username: "cafe" },
  });
  try {
    const res = await call(h.mod.instagramAuthCallback,
      req({ method: "GET", token: null, query: { code: "code-2", state: "s2" } }));
    assert.match(res.redirectedTo, /status=ok/);
    const acc = h.read(`igAccounts/${UID}_${VENUE}`);
    assert.equal(acc.accessToken, "long-wrapped");
    // Деавторизация от Meta приходит с `user_id` из обмена кода — по нему и ищем.
    assert.equal(acc.igUserID, "777");
  } finally { calls.restore(); }
});

/* ── Синхронизация ───────────────────────────────────────────────────────── */

test("media: без подключения → 409 not_connected", async () => {
  const res = await call(harness().mod.instagramMedia, req({ body: { venueID: VENUE } }));
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "not_connected");
});

test("media: посты приходят без токена внутри", async () => {
  const h = harness();
  connect(h);
  const calls = stubFetch({ "graph.instagram.com/me/media": MEDIA_OK });
  try {
    const res = await call(h.mod.instagramMedia, req({ body: { venueID: VENUE } }));
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.posts.length, 1);
    const post = res.body.posts[0];
    assert.equal(post.id, "post-1");
    assert.equal(post.previewURL, "https://scontent.cdninstagram.com/a.jpg");
    assert.ok(!JSON.stringify(res.body).includes("long-token"), "токен не должен попасть в ответ");
    assert.ok(h.read(`igConnections/${UID}_${VENUE}`).lastSyncAt, "отметка о синхронизации");
  } finally { calls.restore(); }
});

test("media: протухший токен → reauth_required и флаг в обоих документах", async () => {
  const h = harness();
  connect(h);
  const calls = stubFetch({
    "graph.instagram.com/me/media": { __status: 401, error: { code: 190, type: "OAuthException" } },
  });
  try {
    const res = await call(h.mod.instagramMedia, req({ body: { venueID: VENUE } }));
    assert.equal(res.statusCode, 409);
    assert.equal(res.body.error, "reauth_required");
    assert.equal(h.read(`igAccounts/${UID}_${VENUE}`).needsReauth, true);
    assert.equal(h.read(`igConnections/${UID}_${VENUE}`).needsReauth, true);
  } finally { calls.restore(); }
});

test("media: аккаунт с needsReauth не ходит в Graph вовсе", async () => {
  const h = harness();
  connect(h, { needsReauth: true });
  const calls = stubFetch({});
  try {
    const res = await call(h.mod.instagramMedia, req({ body: { venueID: VENUE } }));
    assert.equal(res.statusCode, 409);
    assert.equal(calls.length, 0);
  } finally { calls.restore(); }
});

/* ── Импорт ──────────────────────────────────────────────────────────────── */

test("import: фото переезжают на наш CDN, ссылки инстаграма не возвращаются", async () => {
  const h = harness();
  connect(h);
  const calls = stubFetch({
    "graph.instagram.com/post-1": {
      id: "post-1", caption: "Скидка", media_type: "CAROUSEL_ALBUM",
      permalink: "https://instagram.com/p/1",
      children: { data: [
        { media_type: "IMAGE", media_url: "https://scontent.cdninstagram.com/1.jpg" },
        { media_type: "VIDEO", thumbnail_url: "https://scontent.cdninstagram.com/2.jpg" },
      ] },
    },
    "api.cloudinary.com": (url, init) => ({
      secure_url: `https://res.cloudinary.com/${String(init.body).includes("1.jpg") ? "one" : "two"}.jpg`,
    }),
  });
  try {
    const res = await call(h.mod.instagramImportMedia, req({ body: { venueID: VENUE, postID: "post-1" } }));
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.postID, "post-1");
    assert.equal(res.body.imageURLs.length, 2);
    assert.ok(res.body.imageURLs.every((u) => u.startsWith("https://res.cloudinary.com/")),
      "в акцию должны уходить только постоянные ссылки");
    assert.ok(!JSON.stringify(res.body).includes("cdninstagram"));
  } finally { calls.restore(); }
});

test("import: пост без картинок → 409 no_image", async () => {
  const h = harness();
  connect(h);
  const calls = stubFetch({ "graph.instagram.com/post-1": { id: "post-1", media_type: "IMAGE" } });
  try {
    const res = await call(h.mod.instagramImportMedia, req({ body: { venueID: VENUE, postID: "post-1" } }));
    assert.equal(res.statusCode, 409);
    assert.equal(res.body.error, "no_image");
  } finally { calls.restore(); }
});

/* ── Отключение и требования Meta ────────────────────────────────────────── */

test("disconnect: удаляет оба документа", async () => {
  const h = harness();
  connect(h);
  const res = await call(h.mod.instagramDisconnect, req({ body: { venueID: VENUE } }));
  assert.equal(res.statusCode, 200);
  assert.equal(h.read(`igAccounts/${UID}_${VENUE}`), undefined);
  assert.equal(h.read(`igConnections/${UID}_${VENUE}`), undefined);
});

function signedRequest(payload, secret) {
  const b64 = (buf) => Buffer.from(buf).toString("base64")
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const body = b64(JSON.stringify(payload));
  const sig = b64(crypto.createHmac("sha256", secret).update(body).digest());
  return `${sig}.${body}`;
}

test("deauthorize: подделанная подпись отклоняется", async () => {
  const h = harness();
  connect(h);
  const res = await call(h.mod.instagramDeauthorize,
    req({ token: null, body: { signed_request: signedRequest({ user_id: "ig-9" }, "чужой-секрет") } }));
  assert.equal(res.statusCode, 400);
  assert.ok(h.read(`igAccounts/${UID}_${VENUE}`), "подключение не должно пострадать");
});

test("deauthorize: валидная подпись удаляет подключение", async () => {
  const h = harness();
  connect(h);
  const res = await call(h.mod.instagramDeauthorize,
    req({ token: null, body: { signed_request: signedRequest({ user_id: "ig-9" }, "ig-secret") } }));
  assert.equal(res.statusCode, 200);
  assert.equal(h.read(`igAccounts/${UID}_${VENUE}`), undefined);
  assert.equal(h.read(`igConnections/${UID}_${VENUE}`), undefined);
});

test("dataDeletion: отвечает кодом обращения по формату Meta", async () => {
  const h = harness();
  connect(h);
  const res = await call(h.mod.instagramDataDeletion,
    req({ token: null, body: { signed_request: signedRequest({ user_id: "ig-9" }, "ig-secret") } }));
  assert.equal(res.statusCode, 200);
  assert.ok(res.body.url && res.body.confirmation_code);
  assert.equal(h.read(`igAccounts/${UID}_${VENUE}`), undefined);
});
