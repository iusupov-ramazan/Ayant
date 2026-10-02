"use strict";

/**
 * Минимальный in-memory Firestore для офлайн-тестов Cloud Functions.
 *
 * Реализует ровно ту поверхность admin SDK, которую используют денежные/
 * анти-чит функции (`index.js`): collection/doc/get/set/update/delete,
 * подколлекции (analytics/{v}/days/{day}), where(...).limit(...).get(),
 * add(), batch(), runTransaction(...) и FieldValue.increment.
 *
 * Документы хранятся плоско по полному пути ("venues/v1",
 * "analytics/v1/days/2026-07-30"). Это НЕ полноценный Firestore — только
 * то, что реально вызывается кодом; так тест проверяет логику функции,
 * а не эмулятор.
 *
 * ВАЖНО про время: настоящий SDK конвертирует записанный `Date` в `Timestamp`
 * и возвращает при чтении именно `Timestamp` (у него есть `toMillis()`).
 * Фейк обязан делать так же — иначе `toMillis(doc.lastEarnAt)` в функциях
 * молча вернёт 0, кулдауны в тестах никогда не сработают, и тест «повтор
 * заблокирован» пройдёт, ничего не проверив. См. [toStored].
 */

/**
 * То, что реальный SDK возвращает при чтении поля, куда записали `Date`.
 * Достаточно `toMillis`/`toDate` (их используют функции) и `valueOf` —
 * чтобы диапазонные where(...) по времени сравнивались как числа.
 */
class FakeTimestamp {
  constructor(ms) { this.__ms = ms; }
  toMillis() { return this.__ms; }
  toDate() { return new Date(this.__ms); }
  get seconds() { return Math.floor(this.__ms / 1000); }
  get nanoseconds() { return (this.__ms % 1000) * 1e6; }
  valueOf() { return this.__ms; }
}

/**
 * Приводит записываемое значение к тому виду, в котором его вернёт Firestore:
 * `Date` → [FakeTimestamp], рекурсивно по массивам и вложенным картам.
 *
 * Не трогает сентинелы `FieldValue` и значения, которые УЖЕ выглядят как
 * Timestamp (тесты часто сеют `{ toMillis: () => … }` вручную).
 */
function toStored(value) {
  if (value instanceof Date) return new FakeTimestamp(value.getTime());
  if (value instanceof FakeTimestamp) return value;
  if (Array.isArray(value)) return value.map(toStored);
  if (value && typeof value === "object") {
    if (isIncrement(value)) return value;
    if (typeof value.toMillis === "function") return value;   // уже Timestamp-подобное
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = toStored(v);
    return out;
  }
  return value;
}

// Сентинел FieldValue.increment(n) — распознаётся при слиянии данных.
const FieldValue = {
  increment: (n) => ({ __inc: n }),
};

// Агрегаты (`query.aggregate({ s: AggregateField.sum("points") })`, `count()`)
// — как в admin SDK: описание поля, которое считает CollectionRef.aggregate.
const AggregateField = {
  sum: (field) => ({ __agg: "sum", field }),
  count: () => ({ __agg: "count" }),
  average: (field) => ({ __agg: "avg", field }),
};

// `FieldPath.documentId()` — сортировка/пагинация по id документа.
const DOC_ID = "__name__";
const FieldPath = { documentId: () => DOC_ID };

function isIncrement(v) {
  return v && typeof v === "object" && typeof v.__inc === "number";
}

// Сравнение для where(field, op, value). Поддерживает операторы, которыми
// реально пользуются функции (== и диапазонные для сгорания баллов).
function cmpValue(v) {
  if (v instanceof Date) return v.getTime();
  if (v && typeof v === "object" && typeof v.toMillis === "function") return v.toMillis();
  return v;
}

function matchesOp(actualRaw, op, expectedRaw) {
  const actual = cmpValue(actualRaw), expected = cmpValue(expectedRaw);
  switch (op) {
    case "==": return actual === expected;
    case "!=": return actual !== expected;
    case ">": return actual > expected;
    case ">=": return actual >= expected;
    case "<": return actual < expected;
    case "<=": return actual <= expected;
    default: return true;
  }
}

// Слияние incoming в existing с раскрытием сентинелов increment.
function mergeData(existing, incoming, merge) {
  const base = merge && existing ? { ...existing } : {};
  for (const [k, v] of Object.entries(incoming)) {
    base[k] = isIncrement(v) ? (Number(base[k]) || 0) + v.__inc : toStored(v);
  }
  return base;
}

class FakeFirestore {
  constructor() {
    this.store = new Map(); // fullPath -> plain object
    this._autoId = 0;
  }

  _nextId() {
    this._autoId += 1;
    return `auto-${this._autoId}`;
  }

  collection(name) {
    return new CollectionRef(this, name);
  }

  // Удобный доступ к произвольному документу по полному пути (как db.doc в SDK).
  doc(path) {
    return new DocRef(this, path);
  }

  /**
   * Пакетная запись (`deleteInChunks`, удаление аккаунта и подключений
   * инстаграма). Тесты однопоточные, поэтому операции копятся и применяются
   * на commit() — атомарность имитировать незачем, а порядок важен.
   */
  batch() {
    const ops = [];
    return {
      set: (ref, data, opts) => { ops.push(() => ref.set(data, opts)); },
      update: (ref, data) => { ops.push(() => ref.update(data)); },
      delete: (ref) => { ops.push(() => ref.delete()); },
      commit: async () => { for (const op of ops) await op(); },
    };
  }

  /** `db.recursiveDelete(ref)` — документ и все его подколлекции. */
  async recursiveDelete(ref) {
    const prefix = `${ref.path}/`;
    for (const key of [...this.store.keys()]) {
      if (key === ref.path || key.startsWith(prefix)) this.store.delete(key);
    }
  }

  /** `db.getAll(...refs)` — снапшоты в том же порядке. */
  async getAll(...refs) {
    this.getAllCalls = (this.getAllCalls || 0) + 1;
    return Promise.all(refs.map((r) => r.get()));
  }

  async runTransaction(fn) {
    // Однопоточные тесты: операции применяются сразу, изоляция не нужна.
    const tx = {
      get: (ref) => ref.get(),
      getAll: (...refs) => Promise.all(refs.map((r) => r.get())),
      set: (ref, data, opts) => ref.set(data, opts),
      update: (ref, data) => ref.update(data),
      delete: (ref) => ref.delete(),
    };
    return fn(tx);
  }
}

class CollectionRef {
  constructor(fs, path) {
    this.fs = fs;
    this.path = path;
    this._filters = [];
    this._limit = Infinity;
    this._orderById = false;
    this._startAfter = null;
  }

  _clone() {
    const q = new CollectionRef(this.fs, this.path);
    q._filters = this._filters;
    q._limit = this._limit;
    q._orderById = this._orderById;
    q._startAfter = this._startAfter;
    return q;
  }

  /** Поддержана только сортировка по id документа (пагинация ночных проходов). */
  orderBy(field) {
    const q = this._clone();
    if (field === DOC_ID) q._orderById = true;
    return q;
  }

  /** startAfter(snapshot | id) — после документа с этим id (при orderBy по id). */
  startAfter(cursor) {
    const q = this._clone();
    q._startAfter = cursor && typeof cursor === "object" ? cursor.id : String(cursor);
    return q;
  }

  /** `count()` — как `aggregate({ count: AggregateField.count() })`. */
  count() {
    return this.aggregate({ count: AggregateField.count() });
  }

  /** Агрегатный запрос: `{ get() → { data() → { alias: число } } }`. */
  aggregate(spec) {
    return {
      get: async () => {
        const snap = await this._clone()._all();
        const out = {};
        for (const [alias, f] of Object.entries(spec)) {
          if (f.__agg === "count") { out[alias] = snap.length; continue; }
          const nums = snap.map((d) => d.data()[f.field]).filter((v) => typeof v === "number");
          const total = nums.reduce((a, b) => a + b, 0);
          out[alias] = f.__agg === "sum" ? total : (nums.length ? total / nums.length : null);
        }
        return { data: () => out };
      },
    };
  }

  doc(id) {
    return new DocRef(this.fs, `${this.path}/${id || this.fs._nextId()}`);
  }

  where(field, op, value) {
    const q = this._clone();
    q._filters = this._filters.concat([{ field, op, value }]);
    return q;
  }

  limit(n) {
    const q = this._clone();
    q._limit = n;
    return q;
  }

  async add(obj) {
    const ref = this.doc();
    await ref.set(obj);
    return ref;
  }

  /** Все подходящие документы без limit (для агрегатов). */
  async _all() {
    const q = this._clone();
    q._limit = Infinity;
    return (await q.get()).docs;
  }

  async get() {
    const prefix = `${this.path}/`;
    let paths = [];
    for (const [fullPath, data] of this.fs.store.entries()) {
      if (!fullPath.startsWith(prefix)) continue;
      const rest = fullPath.slice(prefix.length);
      if (rest.includes("/")) continue; // прямые дети, не подколлекции
      const ok = this._filters.every((f) => matchesOp(data[f.field], f.op, f.value));
      if (!ok) continue;
      paths.push(fullPath);
    }
    if (this._orderById || this._startAfter !== null) {
      paths.sort((a, b) => (a.split("/").pop() < b.split("/").pop() ? -1 : 1));
      if (this._startAfter !== null) paths = paths.filter((p) => p.split("/").pop() > this._startAfter);
    }
    const docs = paths.slice(0, this._limit).map((p) => new DocRef(this.fs, p)._snapshot());
    return {
      empty: docs.length === 0,
      size: docs.length,
      docs,
      forEach: (cb) => docs.forEach(cb),
    };
  }
}

class DocRef {
  constructor(fs, path) {
    this.fs = fs;
    this.path = path;
    this.id = path.split("/").pop();
  }

  collection(name) {
    return new CollectionRef(this.fs, `${this.path}/${name}`);
  }

  _snapshot() {
    const exists = this.fs.store.has(this.path);
    const stored = this.fs.store.get(this.path);
    return {
      exists,
      id: this.id,
      ref: this,
      data: () => (exists ? { ...stored } : undefined),
    };
  }

  async get() {
    return this._snapshot();
  }

  async set(data, opts) {
    const merged = mergeData(this.fs.store.get(this.path), data, opts && opts.merge);
    this.fs.store.set(this.path, merged);
  }

  async update(data) {
    // Firestore update — это merge над существующим документом.
    return this.set(data, { merge: true });
  }

  async delete() {
    this.fs.store.delete(this.path);
  }
}

module.exports = { FakeFirestore, FieldValue, AggregateField, FieldPath, FakeTimestamp, mergeData, toStored };
