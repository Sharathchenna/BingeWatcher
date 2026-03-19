# Recommendation deck behavior

## Save to watchlist (bookmark)

- The current card is **removed from the deck** immediately.
- **No swipe is logged** and the **LinUCB bandit is not updated** — saving is neutral for the recommendation algorithm.
- Movies that are on your watchlist are **excluded from future candidate pools**, so the same title should not reappear in the deck while it stays saved.
- Removing a movie from the watchlist in Library makes it eligible for the deck again on future refreshes.

## Swipes (like / pass / skip)

- Logged to `SwipeLogEntity` and used to update bandit state.
- Swiped titles are excluded from future candidate pools.

## When the deck refills

- The deck loads up to **20** cards at a time. It **only auto-refills when that batch is exhausted** (last card removed by swipe or by saving to watchlist).
- There is **no** periodic mid-deck refresh (e.g. not every N swipes).
- You can still **manually** refresh: toolbar refresh, **Get fresh picks** on the empty state, or **Apply / Clear** on Taste filters (those intentionally rebuild the deck).
