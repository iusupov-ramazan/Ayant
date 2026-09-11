#!/usr/bin/env python3
"""
TRAIN — Ayant / learn deal-feed ranking weights from rankingEvents rows.

Step 2 of the learning-to-rank pipeline (step 1 = export_ranking_events.js).
Fits a logistic regression that predicts P(redeem) from the rank-time features,
and prints the learned coefficients mapped onto the named Ranking weights
(W_RATING, W_VALUE, …) so they drop straight back into Ranking.kt / Ranking.swift.

    python3 ml/train_ranking_weights.py --rows ml/rows.jsonl [--label redeemed]

The trick that makes the coefficients usable: we feed the model the SAME normalized
terms Ranking computes (bayes/5, saturating(reviews), value ramp, …), not the raw
signals. So each coefficient is exactly the weight on that term. Score *scale* is
irrelevant — ranking only sorts — so the raw coefficients are usable as-is.

Needs: numpy, scikit-learn  (pip install numpy scikit-learn)
"""
import argparse
import json
import math
import sys

# ── Normalization constants — MUST match Ranking.kt / Ranking.swift ──────────
REVIEWS_REF = 150.0
SAVES_REF = 150.0
DEALS_REF = 5.0
RECENCY_DAYS = 14.0
VALUE_REF_PCT = 50.0
URGENCY_HOURS = 48.0
DISTANCE_MAX_KM = 5.0

# Current hand-tuned weights (deal feed = venueScore terms + deal terms), for a
# side-by-side sanity check against what the model learns.
CURRENT = {
    "W_RATING": 4.0, "W_REVIEWS": 2.0, "W_SAVES": 1.0, "W_VERIFIED": 1.5,
    "W_TODAY_SPECIAL": 1.0, "W_ACTIVE_DEALS": 1.5, "W_FRESH": 3.0, "W_RECENCY": 2.0,
    "W_VALUE": 3.0, "W_URGENCY": 1.5, "W_TIME": 2.0, "W_DISTANCE": 6.0,
}


def sat(n, ref):
    return min(1.0, math.log(n + 1.0) / math.log(ref + 1.0))


def featurize(row):
    """Raw logged features → the normalized terms Ranking weights. Order defines
    the coefficient→weight mapping below. `position` is a debias term (see NOTE)."""
    days = row.get("daysSinceStart")
    disc = row.get("discountPercent")
    hrs = row.get("hoursUntilExpiry")
    km = row.get("distanceKm")
    return [
        (row.get("bayesRating") or 0.0) / 5.0,                                  # W_RATING
        sat(row.get("reviewCount") or 0, REVIEWS_REF),                          # W_REVIEWS
        sat(row.get("savedByCount") or 0, SAVES_REF),                          # W_SAVES
        1.0 if row.get("isVerified") else 0.0,                                 # W_VERIFIED
        1.0 if row.get("hasTodaySpecial") else 0.0,                            # W_TODAY_SPECIAL
        sat(row.get("activeDealCount") or 0, DEALS_REF),                      # W_ACTIVE_DEALS
        1.0 if row.get("isFresh") else 0.0,                                    # W_FRESH
        max(0.0, (RECENCY_DAYS - days) / RECENCY_DAYS) if days is not None else 0.0,   # W_RECENCY
        min(1.0, disc / VALUE_REF_PCT) if disc else 0.0,                       # W_VALUE
        ((URGENCY_HOURS - hrs) / URGENCY_HOURS) if hrs is not None and 0 <= hrs <= URGENCY_HOURS else 0.0,  # W_URGENCY
        row.get("timeRelevance") or 0.0,                                       # W_TIME
        max(0.0, (DISTANCE_MAX_KM - km) / DISTANCE_MAX_KM) if km is not None else 0.0, # W_DISTANCE
        # NOTE: position is a debias feature — higher slots get clicked more
        # regardless of relevance. Train WITH it, then DROP it at serving.
        float(row.get("position") or 0),                                       # (debias, not shipped)
    ]


WEIGHT_NAMES = list(CURRENT.keys())  # 12 terms; position is the 13th, unnamed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", default="ml/rows.jsonl")
    ap.add_argument("--label", default="redeemed", choices=["redeemed", "tapped"])
    ap.add_argument("--out", default="ml/ranking_weights.json")
    args = ap.parse_args()

    try:
        import numpy as np
        from sklearn.linear_model import LogisticRegression
    except ImportError:
        sys.exit("Missing deps. Run: pip install numpy scikit-learn")

    X, y = [], []
    with open(args.rows) as f:
        for line in f:
            if not line.strip():
                continue
            row = json.loads(line)
            X.append(featurize(row))
            y.append(int(row.get(args.label, 0)))

    X, y = np.array(X), np.array(y)
    pos = int(y.sum())
    print(f"rows={len(y)}  positives({args.label})={pos}  ({100*pos/max(len(y),1):.2f}%)")
    if pos < 200 or (len(y) - pos) < 200:
        print("⚠️  Too few labels in one class — keep the hand-tuned weights for now.")

    # class_weight balances the rare-positive problem; no intercept scaling needed
    # because ranking only cares about relative order.
    model = LogisticRegression(class_weight="balanced", max_iter=1000, C=1.0)
    model.fit(X, y)
    coefs = model.coef_[0]

    # Map coefficients → named weights (drop the trailing position/debias term).
    learned = {name: round(float(c), 4) for name, c in zip(WEIGHT_NAMES, coefs)}

    print("\n  weight            current   learned   Δ")
    print("  " + "-" * 44)
    for name in WEIGHT_NAMES:
        cur, new = CURRENT[name], learned[name]
        flag = "  ⚠︎ sign flip" if (cur > 0) != (new > 0) else ""
        print(f"  {name:<16} {cur:>7.3f}  {new:>7.3f}   {new-cur:>+6.3f}{flag}")
    print(f"\n  (position debias coef = {coefs[-1]:+.4f} — NOT shipped)")

    with open(args.out, "w") as f:
        json.dump({"label": args.label, "weights": learned,
                   "positionDebias": round(float(coefs[-1]), 4)}, f, indent=2)
    print(f"\n✅ weights → {args.out}")
    print("   Publish: write these to config/rankingWeights (or Remote Config);")
    print("   both clients read them into Ranking at startup. See ml/README.md.")


if __name__ == "__main__":
    main()
