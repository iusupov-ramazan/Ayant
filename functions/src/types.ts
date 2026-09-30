/**
 * Единый источник правды по формам документов Firestore, которые читают/пишут
 * Cloud Functions. Поля здесь названы РОВНО так же, как их читают iOS
 * (`Models.swift`) и Android (`data/model/Models.kt`). Меняешь имя поля здесь —
 * ищи и меняй на обоих клиентах, иначе клиенты разъедутся с бэкендом
 * (см. предупреждение в CLAUDE.md).
 *
 * Типы намеренно «мягкие» (`number | string`, опциональные поля): Firestore
 * не гарантирует тип, а функции читают защитно (`parseInt(...) || default`).
 * Задача этих интерфейсов — задокументировать СХЕМУ и имена полей, а не
 * заставить компилятор ругаться на защитный разбор.
 */

/** Числовое поле, которое в базе может лежать строкой (разбираем через parseInt). */
export type Numeric = number | string | undefined | null;

/** Ряд «баллов по кнопке» (points bands). */
export interface PointsBand {
  points: Numeric;
  label?: string;
}

/** Награда каталога баллов (System 1). type: item — фикс. cost; money — списание ≥ cost. */
export interface PointsReward {
  id: string;
  type?: "item" | "money";
  cost?: Numeric;
  ratio?: Numeric;
  title?: string;
  active?: boolean;
}

/** Элемент `venues/{id}.stampCards` — зеркало `StampCard` (Swift). */
export interface StampCardDef {
  id?: string;
  title?: string;
  goal?: Numeric;
  reward?: string;
  active?: boolean;
}

/** venues/{id} — заведение (каталог + конфиг лояльности/баллов). */
export interface VenueDoc {
  ownerID?: string;
  name?: string;
  citySlug?: string;

  // Лояльность (штампы).
  loyaltyEnabled?: boolean;
  loyaltyGoal?: Numeric;
  loyaltyReward?: string;
  /** Имя первой карты штампов (её цель/награда — поля выше). */
  loyaltyTitle?: string;
  /** Дополнительные карты штампов; первая карта сюда НЕ входит. */
  stampCards?: StampCardDef[];

  // Баллы САН (System 1).
  pointsEnabled?: boolean;
  pointsMode?: "flat" | "bands" | "cashback";
  pointsFlat?: Numeric;
  pointsBands?: PointsBand[];
  cashbackPercent?: Numeric;
  earnCooldownMinutes?: Numeric;
  redeemMode?: "staffScan" | "customerInitiated";
  pointsRewards?: PointsReward[];
  pointsExpiryMonths?: Numeric;
}

/**
 * config/appSettings — глобальные настройки из админ-панели («Настройки»).
 * Зеркало `AppSettings.swift` / `AppSettings.kt`: имена полей — контракт.
 */
export interface AppSettingsDoc {
  /** Пауза между штампами лояльности, мин. Явный 0 = без паузы. Пусто → 15. */
  stampCooldownMinutes?: Numeric;
  /** Текст рекламного плейсхолдера (читают только клиенты). */
  adPlaceholderText?: string;
}

/** coupons/{id} — купон акции (погашается один раз). */
export interface CouponDoc {
  code?: string;
  venueID?: string;
  userID?: string;
  dealID?: string;
  used?: boolean;
  usedAt?: Date;
  usedByVenue?: string;
  title?: string;
}

/** loyaltyCards/{userID_venueID} — карта штампов. */
export interface LoyaltyCardDoc {
  userID?: string;
  venueID?: string;
  venueName?: string;
  goal?: Numeric;
  reward?: string;
  stamps?: Numeric;
  completedRounds?: Numeric;
  updatedAt?: Date;
}

/** venuePoints/{userID_venueID} — кошелёк баллов заведения. */
export interface VenuePointsDoc {
  userID?: string;
  venueID?: string;
  venueName?: string;
  balance?: Numeric;
  lifetimeEarned?: Numeric;
  lifetimeRedeemed?: Numeric;
  lastEarnAt?: FirestoreTimestampLike;
  lastActivityAt?: FirestoreTimestampLike;
  updatedAt?: Date;
}

/** venuePoints/{card}/ledger/{txn} — строка истории баллов. */
export interface LedgerEntry {
  type: "earn" | "redeem" | "expire";
  points: number;
  billAmount?: number | null;
  rewardId?: string;
  byVenue?: boolean;
  at: Date;
}

/** pushCampaigns/{id} — рекламная кампания (шлётся после одобрения админом). */
export interface PushCampaignDoc {
  status?: "pending" | "approved" | "rejected" | "sent" | "error";
  delivered?: boolean;
  city?: string;
  headline?: string;
  body?: string;
  venueID?: string;
  dealID?: string;
}

/** Значение времени Firestore: Timestamp (.toMillis()) либо ещё не сериализованное. */
export interface FirestoreTimestampLike {
  toMillis?: () => number;
}

/**
 * igAccounts/{ownerID}_{venueID} — подключённый инстаграм заведения.
 *
 * ЗАКРЫТАЯ коллекция: `allow read, write: if false` в правилах. Здесь лежит
 * токен доступа, и клиенту он не нужен ни при каких обстоятельствах — за
 * постами он ходит через наши функции. Публичная часть (имя аккаунта, статус)
 * продублирована в `igConnections`, её хост читает напрямую.
 */
export interface IgAccountDoc {
  ownerID?: string;
  venueID?: string;
  igUserID?: string;
  username?: string;
  accessToken?: string;
  /** Момент протухания длинного токена (60 дней с выдачи/обновления). */
  tokenExpiresAt?: FirestoreTimestampLike | Date;
  lastRefreshAt?: FirestoreTimestampLike | Date;
  connectedAt?: FirestoreTimestampLike | Date;
  /** Обновление токена не удалось — нужен повторный вход хоста. */
  needsReauth?: boolean;
}

/** igAuthStates/{nonce} — одноразовый state OAuth (защита от CSRF). */
export interface IgAuthStateDoc {
  ownerID?: string;
  venueID?: string;
  createdAt?: FirestoreTimestampLike | Date;
}
