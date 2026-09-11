# Ranking weight learning (offline)

Turns the `rankingEvents` log into learned `Ranking` weights. This is the offline
tail of the pipeline; the online half (feature snapshots + event emission) lives in
the apps and `functions/`. See the `ranking-ml-pipeline` project memory for the map.

```
rankingEvents (Firestore)
   │  ① export_ranking_events.js   join impressions ↔ tap/redeem outcomes
   ▼
rows.jsonl  (one row per shown deal + label)
   │  ② train_ranking_weights.py   logistic regression over the normalized terms
   ▼
ranking_weights.json  (W_RATING, W_VALUE, … coefficients)
   │  ③ publish → config/rankingWeights (or Remote Config)
   ▼
both clients read weights into Ranking at startup   ← no code change, no drift
```

## Run

```bash
# ① export (needs serviceAccountKey.json at repo root, like backup-firestore.js)
node ml/export_ranking_events.js --out ml/rows.jsonl --since-days 90

# ② train (needs: pip install numpy scikit-learn)
python3 ml/train_ranking_weights.py --rows ml/rows.jsonl --label redeemed
```

## Why the coefficients map straight onto `W_*`

`Ranking.dealScore` is a **linear model over normalized terms** (`bayesRating/5`,
`saturating(reviewCount)`, the value/urgency/recency ramps, `timeRelevance`, …).
`train_ranking_weights.py` recomputes *those same terms* from the raw logged
features before fitting, so each logistic-regression coefficient is exactly the
weight on that term. Copy them into the `W_*` / `w*` constants in
[`Ranking.kt`](../android/app/src/main/java/kg/ayant/app/data/Ranking.kt) and
[`Ranking.swift`](../SAN/Domain/Ranking.swift) — the normalization refs
(`REVIEWS_REF=150`, `VALUE_REF_PCT=50`, …) are shared constants and must stay in
sync across all three places. Absolute scale is irrelevant: ranking only sorts.

## Label join (in the export)

- **Client** `tap`/`redeem` events share the impression's `renderID` → exact join
  on `(renderID, dealID)`.
- **Server** `redeem` (host-verified scan, `renderID="server"`) → last-touch
  attribution to the most recent impression of `(userID, dealID)` before the scan.
  This is the authoritative, cross-platform positive label.

`redeemed` is the primary label; `tapped` is a weaker intermediate (`--label tapped`).

## Caveats before you ship learned weights

- **Volume gate.** Redemptions are rare. Below ~200 positives the fit is noise —
  both scripts warn and you should keep the hand-tuned weights. Aim for ≥1000.
- **Position bias.** Top slots get clicked regardless of relevance. The trainer
  includes `position` as a debias feature and **drops it at serving** (it is not a
  `Ranking` term). Longer term, prefer inverse-propensity weighting.
- **Class imbalance** is handled with `class_weight="balanced"`.
- **Feedback loop.** The model is trained on what the current ranker chose to show,
  so it can only re-weight seen items. The exploration slots (a still-open TODO) are
  what keep the candidate pool from collapsing onto the model's current beliefs.
- **`isOpenNow` isn't logged** as a separate feature, so its `venueScore` weight
  isn't learned here — add it to `RankingItemFeatures` first if you want it tuned.

## ③ Publishing (the consume side — not yet wired)

Make the weights data, not code, so learning closes the loop without an app release:

1. Write `ranking_weights.json` to a `config/rankingWeights` Firestore doc (or
   Firebase Remote Config).
2. Small refactor: turn the `W_*` constants in `Ranking` into a `RankingWeights`
   struct with the current values as defaults; have each client fetch the doc at
   startup and pass it into `Ranking`. Missing/failed fetch → defaults (safe).
3. Roll out behind an A/B split and compare **redemptions per user** (the north-star
   metric), not offline accuracy.

Files here are **git-tracked scaffolding**; the generated `rows.jsonl` /
`ranking_weights.json` are gitignored (add them to `.gitignore` when you first run).
