"use strict";

/**
 * Тестовый харнесс для functions/index.js.
 *
 * Загружает реальный index.js, подменяя ТОЛЬКО admin SDK (Firestore/Auth/
 * Messaging) на in-memory фейки через proxyquire. Триггеры firebase-functions
 * остаются настоящими — их вызываем через `.run(event)`, HTTP-функции (onRequest)
 * вызываются напрямую как `fn(req, res)`.
 */

const { EventEmitter } = require("node:events");
const proxyquire = require("proxyquire").noCallThru();
const { FakeFirestore, FieldValue, toStored } = require("./fakeFirestore");

/**
 * @param {object} opts
 * @param {Record<string,string>} opts.tokens  Map<idToken, uid> для verifyIdToken.
 * @returns харнесс с загруженным модулем и доступом к хранилищу.
 */
function makeHarness({ tokens = {} } = {}) {
  const db = new FakeFirestore();
  const messagingCalls = [];
  const messaging = {
    send: async (m) => {
      messagingCalls.push(m);
      return "msg-id";
    },
    sendEachForMulticast: async (m) => {
      messagingCalls.push(m);
      return {
        successCount: (m.tokens || []).length,
        responses: (m.tokens || []).map(() => ({ success: true })),
      };
    },
  };
  const auth = {
    verifyIdToken: async (token) => {
      if (Object.prototype.hasOwnProperty.call(tokens, token)) {
        return { uid: tokens[token] };
      }
      throw new Error("invalid token");
    },
  };

  // Тесты гоняются по СКОМПИЛИРОВАННОМУ выводу (lib/index.js) — источник на TS
  // (src/index.ts). `npm test` сначала собирает (pretest → build). proxyquire
  // подменяет только admin SDK; tsc сохраняет строковые require("firebase-admin/*"),
  // поэтому перехват работает как и раньше.
  const mod = proxyquire("../../lib/index.js", {
    "firebase-admin/app": { initializeApp: () => ({}) },
    "firebase-admin/firestore": { getFirestore: () => db, FieldValue },
    "firebase-admin/messaging": { getMessaging: () => messaging },
    "firebase-admin/auth": { getAuth: () => auth },
  });

  return {
    mod,
    db,
    messagingCalls,
    /**
     * Записать документ по полному пути ("venues/v1").
     * Значения проходят ту же нормализацию, что и при записи через SDK
     * (`Date` → Timestamp), чтобы засеянный документ читался как настоящий.
     */
    seed: (path, obj) => db.store.set(path, toStored(obj)),
    /** Прочитать документ по полному пути (или undefined). */
    read: (path) => db.store.get(path),
  };
}

/** Фейковый Express req для onRequest-функций. */
function makeReq({ method = "POST", headers = {}, query = {}, body = {} } = {}) {
  const lower = {};
  for (const [k, v] of Object.entries(headers)) lower[k.toLowerCase()] = v;
  return {
    method,
    query,
    body,
    headers: lower, // cors-middleware читает req.headers.origin
    get: (h) => lower[String(h).toLowerCase()],
  };
}

/**
 * Фейковый Express res — копит statusCode/body/headers и эмитит "finish"
 * при отправке ответа (v2 onRequest ждёт это событие, чтобы зарезолвить промис).
 */
function makeRes() {
  const res = new EventEmitter();
  res.statusCode = 200;
  res.body = undefined;
  res.headers = {};
  res.ended = false;
  const finish = () => {
    if (res.ended) return;
    res.ended = true;
    res.emit("finish");
  };
  res.status = (c) => {
    res.statusCode = c;
    return res;
  };
  res.json = (o) => {
    res.body = o;
    finish();
    return res;
  };
  res.send = (b) => {
    res.body = b;
    finish();
    return res;
  };
  res.set = (k, v) => {
    res.headers[String(k).toLowerCase()] = v;
    return res;
  };
  // Методы, которые дёргает cors-middleware (при { cors: true }).
  res.setHeader = (k, v) => {
    res.headers[String(k).toLowerCase()] = v;
    return res;
  };
  res.getHeader = (k) => res.headers[String(k).toLowerCase()];
  res.end = () => {
    finish();
    return res;
  };
  return res;
}

/**
 * Событие onDocumentCreated: `event.data` — снапшот созданного документа,
 * `event.data.ref` — реальный DocRef в фейке (чтобы .set/.delete работали).
 */
function createdEvent(harness, path, data, params = {}) {
  const ref = harness.db.doc(path);
  return {
    params,
    data: {
      exists: true,
      id: ref.id,
      ref,
      data: () => data,
    },
  };
}

/**
 * Событие onDocumentWritten: `event.data.before` / `.after` — снапшоты до и
 * после записи. `null` в любой из позиций означает «документа не было»
 * (создание) или «документ удалён».
 *
 * Соответствует форме, которую v2-триггер получает от Firestore: у обоих
 * снапшотов есть `exists`, `data()` и рабочий `ref` в фейке.
 */
function writtenEvent(harness, path, before, after, params = {}) {
  const ref = harness.db.doc(path);
  const snap = (data) => ({
    exists: data != null,
    id: ref.id,
    ref,
    data: () => data ?? undefined,
  });
  return { params, data: { before: snap(before), after: snap(after) } };
}

module.exports = { makeHarness, makeReq, makeRes, createdEvent, writtenEvent };
