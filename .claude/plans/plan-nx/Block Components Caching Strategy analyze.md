# Stale Cache Analysis: Block Components Caching Strategy

## Context

The scenario-console app uses React Query to cache block component data (`BlockComponentItem`) fetched via a batch API (`fetchBlockComponents({ block_ids })`). The current implementation uses an **imperative caching pattern** — `setQueryData`/`getQueryData` — rather than declarative `useQuery` hooks. This document analyzes how staleness and garbage collection interact with this pattern, identifies potential issues, and proposes solutions.

---

## Current Implementation Summary

### Global QueryClient Config
**File:** `apps/scenario-console/src/fsd/01-application/providers/react-query/query-client.ts`

| Setting | Value | Notes |
|---------|-------|-------|
| `staleTime` | 60,000ms (60s) | Data considered "fresh" for 1 minute |
| `gcTime` | Not set (default: 5 min) | Garbage collected 5 min after last observer unmounts |
| `refetchOnWindowFocus` | false | No refetch on tab focus |
| `retry` | false | No automatic retries |

### Cache Flow

```
blocksCacheQuery(blockIds)
  ├─ For each id: getQueryData(componentItemCache(id))
  │   ├─ Found in cache → use cached value (skip fetch)
  │   └─ Not in cache → add to missingIds
  ├─ fetchBlockComponents({ block_ids: missingIds })
  └─ For each response: setQueryData(componentItemCache(id), blockData)
```

### Key Files

| File | Role |
|------|------|
| `05-entities/block/model/block-cache.ts` | `blocksCacheQuery`, `getCachedBlock`, `getCachedBlocks` |
| `05-entities/block/model/block-queries.ts` | `blockKeys.componentItemCache(id)` key factory |
| `04-features/scenario/model/hooks/use-scenario-latest.ts` | Calls `blocksCacheQuery` inside scenario's `queryFn` |
| `04-features/scenario/model/hooks/step-configuration/use-block-select.ts` | Calls `blocksCacheQuery` on block selection |
| `04-features/scenario/ui/step-configuration/step-block-list.tsx` | Reads cache via `getCachedBlocks(blockIds)` |

### Critical Observation: No Observers

**Zero `useQuery` hooks subscribe to `blockKeys.componentItemCache(id)` keys.**

All reads are via `queryClient.getQueryData()` (imperative, non-reactive).
All writes are via `queryClient.setQueryData()`.

---

## Problem Analysis

### How `setQueryData` Interacts with `staleTime` and `gcTime`

When `setQueryData(key, data)` is called:

1. React Query stores the data with `dataUpdatedAt = Date.now()`
2. The entry is marked with the **global default `staleTime`** (60s) — but this only matters for `useQuery` observers
3. Since **no `useQuery` observers** watch `componentItemCache` keys:
   - `staleTime` has **no practical effect** — there is no observer to trigger a background refetch
   - `gcTime` countdown starts **immediately** (no observer to keep it alive)

### Timeline of a Cache Entry

```
Time 0:     setQueryData(key, data)  →  entry created, dataUpdatedAt = now
Time 0-60s: "Fresh" period           →  staleTime window (IRRELEVANT - no observers)
Time 60s:   Entry becomes "stale"    →  No effect - no observer to trigger refetch
Time 5min:  gcTime expires            →  Entry GARBAGE COLLECTED, getQueryData returns undefined
```

### Identified Issues

#### Issue 1: `getQueryData` Never Checks Staleness

`getQueryData()` returns data if it exists in cache — **it does not check `staleTime`**. This means:

- A block cached 4 minutes ago (stale for 3 minutes) is still returned by `getCachedBlock()`
- `blocksCacheQuery()` sees it as "cached" and skips re-fetching
- If the block was updated on the server 2 minutes ago, the user sees **stale data** with no way to know

**Impact:** Users may see outdated block component data for up to 5 minutes (until gcTime evicts it).

#### Issue 2: Cache Entries Silently Disappear After gcTime

Since there are no observers, entries are garbage collected after 5 minutes:

- User loads scenario → blocks [1,2,3] cached
- User works on the form for 6 minutes without triggering a scenario refetch
- `getCachedBlocks([1,2,3])` now returns `[]` — blocks vanish from UI
- The only recovery is navigating away and back (triggering `useScenarioLatest` refetch)

**Impact:** Block data can disappear from the UI during long editing sessions.

#### Issue 3: No Reactivity — UI Doesn't Auto-Update

Since `getCachedBlocks()` is called imperatively (not via `useQuery`), the `StepBlockList` component:

- Reads cache on render
- Does NOT re-render when cache updates
- Relies on parent re-renders (e.g., Formik state changes) to refresh

**Impact:** If blocks are re-fetched or invalidated, the UI won't reflect changes until something else triggers a re-render.

#### Issue 4: `blocksCacheQuery` Inside `queryFn` Creates Tight Coupling

In `use-scenario-latest.ts`, `blocksCacheQuery` runs inside the scenario query's `queryFn`. This means:
- Block fetching is coupled to scenario fetching
- If blocks fail, it's caught and swallowed (toast only) — but the scenario query still succeeds with potentially incomplete block cache
- Scenario query's `staleTime`/refetch controls also control when blocks get refreshed

---

## Approaches to Fix the Staleness Problem

### Approach A: Add Staleness Check to `getCachedBlock` (Minimal Change)

**Idea:** Before returning cached data, check if it's stale based on `dataUpdatedAt`.

```typescript
function getCachedBlock(blockId: number, maxAge?: number) {
  const queryClient = getQueryClient();
  const state = queryClient.getQueryState(blockKeys.componentItemCache(blockId));

  if (!state?.data) return undefined;

  const age = Date.now() - state.dataUpdatedAt;
  const effectiveMaxAge = maxAge ?? 60_000; // default: 60s, matching global staleTime

  if (age > effectiveMaxAge) return undefined; // treat as missing

  return state.data as BlockComponentItem;
}
```

**Pros:**
- Minimal code change — only modifies `block-cache.ts`
- `blocksCacheQuery` will automatically re-fetch stale blocks (they appear as "missing")
- Preserves the batch fetching pattern (backend batch API is still used efficiently)
- No architectural changes needed

**Cons:**
- Still imperative — no reactivity for UI updates
- Still subject to gcTime eviction (blocks can disappear during long sessions)
- Custom staleness logic that duplicates what React Query already provides
- Need to manually keep `maxAge` in sync with global `staleTime`

---

### Approach B: Use `fetchQuery` Instead of `getQueryData`/`setQueryData` (Recommended)

**Idea:** Replace the manual cache-check-then-fetch pattern with `queryClient.fetchQuery()`, which natively respects `staleTime`.

```typescript
async function blocksCacheQuery(blockIds: number[]) {
  const queryClient = getQueryClient();

  // fetchQuery returns cached data if fresh, fetches if stale/missing
  // But we need batch fetching, so we still check manually for missing IDs
  // and use setQueryData — but with fetchQuery for reads

  const missingIds: number[] = [];

  for (const id of blockIds) {
    const state = queryClient.getQueryState(blockKeys.componentItemCache(id));
    const isStale = !state || (Date.now() - state.dataUpdatedAt > (queryClient.getDefaultOptions().queries?.staleTime ?? 0));
    if (isStale) {
      missingIds.push(id);
    }
  }

  if (missingIds.length > 0) {
    const response = await fetchBlockComponents({ block_ids: missingIds });
    for (const [idStr, blockData] of Object.entries(response.data)) {
      const id = Number(idStr);
      queryClient.setQueryData(blockKeys.componentItemCache(id), blockData);
    }
  }
}
```

**Alternative (cleaner):** Define a proper `queryOptions` for individual blocks and use `ensureQueryData`:

```typescript
const blockComponentOption = (id: number) => queryOptions({
  queryKey: blockKeys.componentItemCache(id),
  queryFn: () => fetchBlockComponents({ block_ids: [id] }).then(res => res.data[id]),
  staleTime: 60_000,
});

// For batch: check which are stale, batch-fetch, then setQueryData
```

**Pros:**
- Uses React Query's native staleness mechanism via `queryOptions`
- Each cache entry has its own `staleTime` tied to its `queryOptions`
- `ensureQueryData` automatically returns cached data if fresh, fetches if stale
- Clear, idiomatic React Query usage

**Cons:**
- Still imperative for batch fetching (can't use `ensureQueryData` for batches without N+1 calls)
- Need a hybrid: staleness check + batch fetch + `setQueryData` for individual entries
- Slightly more complex logic in `blocksCacheQuery`

---

### Approach C: Switch to `useQuery`/`useQueries` Observers (Full Reactive)

**Idea:** Replace imperative cache access with `useQuery` hooks so React Query manages staleness, refetching, and reactivity automatically.

```typescript
// In step-block-list.tsx — each block gets its own useQuery
function StepBlockItem({ blockId }: { blockId: number }) {
  const { data: block } = useQuery({
    queryKey: blockKeys.componentItemCache(blockId),
    queryFn: () => fetchBlockComponents({ block_ids: [blockId] }).then(res => res.data[blockId]),
    staleTime: 60_000,
  });
  // ...render block
}
```

Or with `useQueries` for batch:

```typescript
function StepBlockList() {
  const { blockIds } = useStepSelected();
  const results = useQueries({
    queries: blockIds.map(id => ({
      queryKey: blockKeys.componentItemCache(id),
      queryFn: () => fetchBlockComponents({ block_ids: [id] }).then(res => res.data[id]),
      staleTime: 60_000,
    })),
  });
  // ...
}
```

**Pros:**
- Full React Query lifecycle — auto-refetch on stale, auto-gc, reactivity
- UI auto-updates when data changes
- No manual staleness tracking
- `gcTime` works correctly (kept alive while component is mounted)
- Proper loading/error states per block

**Cons:**
- **Loses batch fetching** — each block triggers a separate API call (N+1 problem)
- Significant architectural change
- More complex component tree (each block needs its own query)
- Pre-caching via `setQueryData` in `useScenarioLatest` still needed to avoid waterfall

---

### Approach D: Hybrid — Pre-cache with Batch + `useQuery` Observers (Best of Both Worlds)

**Idea:** Keep the batch `blocksCacheQuery` for initial population (in `useScenarioLatest`), but add `useQuery` observers in UI components. The observers use pre-cached data instantly (no loading state) but gain reactivity and proper staleness handling.

```typescript
// block-cache.ts — keep existing blocksCacheQuery for batch pre-caching
// Add queryOptions for individual block observation

// block-queries.ts
const blockOptions = {
  componentItem: (id: number) => queryOptions({
    queryKey: blockKeys.componentItemCache(id),
    queryFn: () => fetchBlockComponents({ block_ids: [id] }).then(res => res.data[id]),
    staleTime: 60_000,
  }),
};

// step-block-list.tsx — observe individual blocks
function StepBlockItem({ blockId }: { blockId: number }) {
  // Data is already in cache from blocksCacheQuery → instant, no loading
  // But now we have an observer → staleTime works, gcTime is kept alive
  const { data: block } = useQuery(blockOptions.componentItem(blockId));
  // ...
}

// use-scenario-latest.ts — keep batch pre-cache
// blocksCacheQuery populates cache → useQuery observers pick it up instantly
```

**How staleness works with this approach:**

1. `blocksCacheQuery` batch-fetches and calls `setQueryData` for each block → `dataUpdatedAt = now`
2. `useQuery(blockOptions.componentItem(id))` subscribes → sees fresh data, returns immediately
3. After 60s, data becomes stale → if component re-mounts or refetch is triggered, React Query calls individual `queryFn`
4. While component is mounted, `gcTime` is paused → no silent data disappearance
5. On re-fetch of scenario (e.g., navigating back), `blocksCacheQuery` batch-fetches again → `setQueryData` updates all entries → observers see new data

**Handling the N+1 concern on stale refetch:**
- Stale refetch after initial load triggers individual fetches (N+1), but this only happens after `staleTime` expires
- For most use cases, blocks don't change frequently — `staleTime: 5 * 60 * 1000` (5 min) or even `Infinity` is reasonable
- If N+1 is a concern: add a custom `refetchFn` that batches stale IDs (advanced)

**Pros:**
- Batch fetching on initial load (efficient)
- Reactive UI via `useQuery` observers
- Proper staleness handling by React Query
- No silent gc eviction (observers keep entries alive)
- Pre-cached data = no loading waterfall
- Incremental migration — can convert components one at a time

**Cons:**
- Stale refetches are individual (N+1), though infrequent with reasonable `staleTime`
- Need to define both batch cache function AND individual queryOptions
- Slightly more code surface area

---

## Comparison Matrix

| Criteria | A: MaxAge Check | B: fetchQuery | C: Full useQuery | D: Hybrid (Recommended) |
|----------|----------------|---------------|-----------------|------------------------|
| Batch fetch preserved | Yes | Yes | No (N+1) | Yes (initial) |
| Staleness handled | Manual | Semi-manual | Automatic | Automatic |
| UI reactivity | No | No | Yes | Yes |
| gcTime eviction safe | No | No | Yes | Yes |
| Code change size | Small | Medium | Large | Medium |
| Idiomatic React Query | No | Partial | Yes | Yes |
| Loading states | No | No | Yes | Yes |

---

## Recommendation: Approach D (Hybrid)

Approach D gives the best balance:
1. **Keeps batch API usage** — no N+1 on initial load
2. **Adds proper staleness** — React Query handles it via observers
3. **Prevents gc eviction** — mounted observers keep cache alive
4. **Adds reactivity** — UI updates when cache changes
5. **Incremental** — can migrate components one at a time

### Implementation Steps

1. Add `componentItem` queryOptions to `block-queries.ts` (individual block with `queryFn` fallback)
2. Keep `blocksCacheQuery` in `block-cache.ts` as-is (batch pre-cache)
3. In `step-block-list.tsx`, replace `getCachedBlocks()` with `useQuery(blockOptions.componentItem(id))` per block
4. Optionally increase `staleTime` for block components (e.g., 5 min) since block data changes infrequently
5. Consider adding staleness awareness to `blocksCacheQuery` itself (check `dataUpdatedAt` before skipping) to ensure batch re-fetches also respect freshness

---

## Additional Note: `staleTime` for `setQueryData`

Per React Query docs, `setQueryData` does respect `updatedAt`:
- You can pass `{ updatedAt: timestamp }` as options to `setQueryData` to control when the data is considered "set"
- Default: `Date.now()`
- The `staleTime` window starts from `updatedAt`

But this only matters when an **observer** (`useQuery`) is present. Without observers, `staleTime` has zero effect on `getQueryData` behavior.
