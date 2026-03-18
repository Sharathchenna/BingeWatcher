# CineMatch — Movie Recommendation App Build Plan

> **Stack:** Swift · SwiftUI · CoreData · TMDB API · MovieLens 25M · SQLite · Accelerate.framework  
> **Algorithm:** Weighted merger (collaborative + content-based + LinUCB bandit)  
> **Total estimated time:** ~7 weeks

---

## Architecture Overview

The recommendation engine is a three-signal weighted merger:

```
final_score = 0.40 × collab_score
            + 0.35 × content_score
            + 0.25 × linucb_score
            − diversity_penalty
```

- **Collaborative score** — looks up MovieLens-derived similar movies against your rated films
- **Content score** — cosine similarity between candidate and your preference centroid vector
- **LinUCB score** — on-device contextual bandit that updates live on every swipe

---

## Feature Vector (~100 dims, float32)

| Dims | Signal | Source |
|------|--------|--------|
| 0–17 | Genre multi-hot (18 TMDB genres) | TMDB |
| 18–23 | Decade one-hot (1960s–2020s, 6 buckets) | TMDB |
| 24–29 | Director + top-5 cast affinity (RL-updated) | Learned |
| 30–49 | Mood / keyword embedding (20-dim TF-IDF) | TMDB keywords |
| 50 | Log-normalised popularity score | TMDB |
| 51 | Log-normalised vote count | TMDB |
| 52 | Runtime bucket (short / medium / long) | TMDB |
| 53–99 | Collaborative latent factor (SVD rank-64) | MovieLens |

---

## Phase 1 — Foundation (~2 weeks)

**Goal:** Working TMDB integration, CoreData schema, onboarding flow. No ML yet.

### Tasks

- Xcode project setup: SwiftUI + MVVM architecture
- CoreData schema (see below)
- TMDB API client using async/await
- Movie search + browse screen
- Poster image caching via NSCache
- Onboarding flow: search → tag watched films → loved / liked / meh
- Progress gate: minimum 10 movies required to unlock swipe deck

### CoreData Schema

```
Movie
  tmdbId:       Int       (unique)
  title:        String
  genres:       [String]
  director:     String
  cast:         [String]
  year:         Int
  moodTags:     [String]
  popularity:   Float
  featureVec:   Data      (float32[100])

UserRating
  movie →       Movie
  rating:       loved | liked | meh
  timestamp:    Date

SwipeLog
  movie →       Movie
  action:       like | dislike | skip
  timeOnCard:   Float
  timestamp:    Date

BanditState
  aMatrix:      Data      (float32[100×100])
  bVector:      Data      (float32[100])
  updatedAt:    Date
```

### Deliverables

| File | Description |
|------|-------------|
| `TMDBClient.swift` | Search, discover, movie detail, keyword fetch |
| `CoreDataStack.swift` | Persistent store + migration strategy |
| `OnboardingView.swift` | Search + tag + progress indicator |
| `MovieRepository.swift` | Single source of truth for all movie data |

---

## Phase 2 — Feature Vectors & Offline Dataset (~1.5 weeks)

**Goal:** Pre-build the MovieLens collaborative brain and wire up feature vector construction.

### Python Preprocessing Script (runs once, offline)

1. Download MovieLens 25M + TMDB ID links from GroupLens
2. Run SVD at rank-64 on the ratings matrix (scipy sparse SVD)
3. For each movie, compute top-50 nearest neighbors by cosine distance on latent factors
4. Export to `neighbors.sqlite` (~40MB) — bundled in the app bundle as read-only
5. Map MovieLens IDs → TMDB IDs for lookup at runtime

### FeatureVectorBuilder.swift

- 18-dim genre multi-hot from TMDB genre list
- 6-dim decade one-hot
- Director affinity and top-5 cast affinity (initialised to 0, updated by RL)
- Mood/keyword embedding via TF-IDF on TMDB keyword strings
- Log-normalised popularity + vote count
- Runtime bucket encoding
- Collaborative latent factor from SQLite lookup by TMDB ID
- Encode and persist as `float32` Data blob in CoreData

### Deliverables

| File | Description |
|------|-------------|
| `preprocess.py` | MovieLens → SVD → SQLite neighbors table |
| `neighbors.sqlite` | Bundled read-only resource in app bundle |
| `FeatureVectorBuilder.swift` | TMDB metadata → float32[100] |
| `CollabLookup.swift` | SQLite FMDB wrapper for neighbor queries |

---

## Phase 3 — Recommendation Engine (~2 weeks)

**Goal:** All three scorers implemented, weighted merger producing a ranked deck.

### Three Scorers

**ContentScorer.swift**
- Maintains a preference centroid: average feature vector of all liked/loved movies (weighted: loved = 1.0, liked = 0.6, meh = −0.2)
- Scores each candidate as cosine similarity to centroid
- Updates centroid on every new rating

**CollabScorer.swift**
- Queries `neighbors.sqlite` for the top-50 MovieLens neighbors of a candidate
- Looks up which neighbors the user has rated
- Returns weighted average of those ratings (loved = 1.0, liked = 0.7, meh = 0.2, unrated = ignored)

**LinUCBBandit.swift**
- Maintains `A` (100×100 matrix) and `b` (100-dim vector) in CoreData
- Uses `Accelerate.framework` (BLAS/LAPACK) for matrix ops — fast enough to update synchronously on-device
- Reward signal: 👍 = +1.0, 👎 = −0.5, skip = 0.0

```swift
// LinUCB update (called after every swipe)
A += x * xᵀ           // feature outer product
b += reward * x        // reward-weighted feature update

// Scoring
θ = A⁻¹ · b
score = θᵀx + α * √(xᵀA⁻¹x)   // α = 0.3 (exploration parameter)
```

### Weighted Merger (RecommendationEngine.swift)

```swift
finalScore =
    0.40 * collabScore
  + 0.35 * contentScore
  + 0.25 * linucbScore
  - diversityPenalty     // −0.15 if same genre or director as any of last 3 cards
```

- Pulls a candidate pool of 200 movies from TMDB Discover (filtered by language, exclude already-seen)
- Scores all 200, returns top 20 as the swipe deck
- Deck refreshes automatically after every 5 swipes

### Deliverables

| File | Description |
|------|-------------|
| `ContentScorer.swift` | Cosine similarity + preference centroid update |
| `CollabScorer.swift` | Neighbor lookup + weighted average |
| `LinUCBBandit.swift` | A matrix, b vector, θ update, UCB calculation |
| `RecommendationEngine.swift` | Orchestrates all three, returns ranked deck of 20 |

---

## Phase 4 — Swipe UI, Watchlist & Polish (~1.5 weeks)

**Goal:** Full working app, shippable on TestFlight.

### Swipe Deck UI (SwipeDeckView.swift)

- Card stack with spring physics — top 3 cards visible at once
- Drag gesture with 👍 / 👎 threshold at 120pt offset
- Green / red colour tint overlay during drag
- Tap card → detail sheet (poster, cast, synopsis, "why recommended" breakdown)
- Deck auto-refills after 5 swipes
- Haptic feedback on confirmed swipe decision

### Supporting Screens

- **Watchlist tab** — saved-to-watch films
- **History tab** — watched + rated films
- **Taste profile screen** — visual breakdown of top genres, directors, decades (from preference centroid)
- **Filter overrides** — mood, decade, runtime sliders
- **Settings** — reset model weights, re-seed from history, data export

### Deliverables

| File | Description |
|------|-------------|
| `SwipeDeckView.swift` | Card stack, drag gesture, tint overlay |
| `MovieDetailSheet.swift` | Poster, cast, synopsis, why recommended |
| `TasteProfileView.swift` | Visual breakdown of learned preferences |
| `WatchlistView.swift` | Saved + history tabs |

---

## Tech Stack Summary

| Layer | Technology |
|-------|-----------|
| Language | Swift 5.9 |
| UI | SwiftUI |
| Local persistence | CoreData |
| Networking | async/await URLSession |
| Movie data | TMDB API v3 |
| Collaborative data | MovieLens 25M (offline, bundled) |
| SQLite access | FMDB |
| Matrix math | Accelerate.framework (BLAS/LAPACK) |
| Offline preprocessing | Python + scipy + pandas |
| Cross-device sync (optional) | CloudKit |

---

## Future Upgrade Path

Once you've accumulated ~500 personal swipes, you can drop in a Phase 2 upgrade without touching the data pipeline:

1. **Pre-train a small MLP re-ranker** on MovieLens data (Python + PyTorch)
2. **Fine-tune on your SwipeLog** data from CoreData
3. **Export to CoreML** and replace the weighted merger with the neural re-ranker
4. Keep the LinUCB bandit running in parallel for cold-start on brand new film releases

The `SwipeLog` table is specifically designed to capture exactly the training signal this future model will need — every swipe is logged with full context (time of day, what you watched before, time spent on card).

---

*Plan version 1.0 — weighted merger architecture*
