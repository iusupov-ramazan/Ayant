"use strict";

/**
 * Минимальный in-memory Firestore для офлайн-тестов Cloud Functions.
 *
 * Реализует ровно ту поверхность admin SDK, которую используют денежные/
 * анти-чит функции (`index.js`): collection/doc/get/set/update/delete,
 * подколлекции (analytics/{v}/days/{day}), where(...).limit(...).get(),
 * add(), runTransaction(...) и FieldValue.increment.
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

function isIncrement(v) {
  return v && typeof v === "object" && typeof v.__inc === "number";
}

// Сравнение для where(field, op, value). Поддерживает операторы, которыми
// реально пользуются функции (== и диапазонные для сгорания баллов).
function matchesOp(actual, op, expected) {
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

  async runTransaction(fn) {
    // Однопоточные тесты: операции применяются сразу, изоляция не нужна.
    const tx = {
      get: (ref) => ref.get(),
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
  }

  doc(id) {
    return new DocRef(this.fs, `${this.path}/${id || this.fs._nextId()}`);
  }

  where(field, op, value) {
    const q = new CollectionRef(this.fs, this.path);
    q._filters = this._filters.concat([{ field, op, value }]);
    q._limit = this._limit;
    return q;
  }

  limit(n) {
    const q = new CollectionRef(this.fs, this.path);
    q._filters = this._filters;
    q._limit = n;
    return q;
  }

  async add(obj) {
    const ref = this.doc();
    await ref.set(obj);
    return ref;
  }

  async get() {
    const prefix = `${this.path}/`;
    const docs = [];
    for (const [fullPath, data] of this.fs.store.entries()) {
      if (!fullPath.startsWith(prefix)) continue;
      const rest = fullPath.slice(prefix.length);
      if (rest.includes("/")) continue; // прямые дети, не подколлекции
      const ok = this._filters.every((f) => matchesOp(data[f.field], f.op, f.value));
      if (!ok) continue;
      docs.push(new DocRef(this.fs, fullPath)._snapshot());
      if (docs.length >= this._limit) break;
    }
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

module.exports = { FakeFirestore, FieldValue, FakeTimestamp, mergeData, toStored };
