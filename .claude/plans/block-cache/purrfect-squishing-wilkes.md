# Implementation Plan: Optimized Block Components Fetching

## Summary

Implement per-block caching for React Query to avoid re-fetching blocks that are already cached. When a scenario needs blocks `[1, 2, 3, 4]` and blocks `[1, 2]` are already cached, only fetch `[3, 4]`.

## Problem

Current caching creates one cache entry per unique block ID combination:
- Request `[1,2]` → Cache key: `['block', 'components', '1,2']`
- Request `[1,2,3,4]` → Cache key: `['block', 'components', '1,2,3,4']` (separate entry, re-fetches 1,2)

## Solution

Per-block caching with smart batch fetching:
- Cache key: `['block', 'components', 'cache', <id>]` for each block
- Check cache before API call, fetch only missing IDs
- Split API response and populate individual caches

---

## Files to Modify

### Phase 1: Type Definitions

**1. `apps/scenario-console/src/fsd/05-entities/scenario/model/scenario-types.ts`**
- Fix `ScenarioStep.blocks` from `{ id: number, order: number }` (bug: missing `[]`) to `number[]`
- Add `ScenarioStepResponse` type for API response with `blocks: Array<{ id, order }>`

```typescript
// API Response type (from server)
interface ScenarioStepResponse {
  id?: StepId
  name: string
  required: boolean
  layout_type: LayoutType
  order: number
  blocks: Array<{ id: number; order: number }>
}

// Form type (Formik state)
interface ScenarioStep {
  clientId?: StepId
  id?: StepId
  name: string
  required: boolean
  layout_type: LayoutType
  blocks: number[]  // IDs only, order dropped
}
```

### Phase 2: Block Caching Infrastructure

**2. `apps/scenario-console/src/fsd/05-entities/block/model/block-queries.ts`**
- Add `componentsCache(id)` key for per-block caching
- Keep existing `components()` for batch API calls

```typescript
const blockKeys = {
  // ... existing keys
  componentsCache: (id: number) => [...blockKeys.all, 'components', 'cache', id] as const,
};
```

**3. NEW: `apps/scenario-console/src/fsd/05-entities/block/model/use-block-components.ts`**
- Create hook for smart batch fetching with cache awareness
- Exports: `fetchBlockComponents(ids)`, `getCachedBlock(id)`, `getCachedBlocks(ids)`

**4. `apps/scenario-console/src/fsd/05-entities/block/model/index.ts`**
- Export new `useBlockComponents` hook

### Phase 3: Scenario Detail Integration

**5. `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/use-scenario-detail.ts`**
- Transform API response: drop `order` fields, extract block IDs
- Pre-cache all block components on scenario load

**6. `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/use-step-selected.ts`**
- Return `blockIds: number[]` instead of `blocksSteps: BlockItem[]`

**7. `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/step-configuration/use-block-select.ts`**
- Use `useBlockComponents().fetchBlockComponents()` for smart caching
- Store only IDs in form state

### Phase 4: UI Components

**8. `apps/scenario-console/src/fsd/04-features/scenario/ui/step-configuration/step-block-list.tsx`**
- Use `useBlockComponents().getCachedBlocks(blockIds)` for display
- Handle loading state when cache is empty

**9. `apps/scenario-console/src/fsd/04-features/scenario/ui/step-configuration/block-select-dialog.tsx`**
- Change `selectedBlock: BlockItem[]` to `selectedBlockIds: number[]`
- Use `Set<number>` internally for O(1) selection checks

**10. `apps/scenario-console/src/fsd/04-features/scenario/ui/step-configuration/block-select-table.tsx`**
- Update props to use `selectedIds: Set<number>`

**11. `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/step-configuration/use-block-select-table.tsx`**
- Use `Set.has()` for O(1) lookup instead of `array.some()`

**12. `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/step-configuration/use-block-select-pagination.ts`**
- Update to accept `Set<number>` for selectedIds

### Phase 5: Mock Updates

**13. `apps/scenario-console/src/fsd/05-entities/scenario/api/mock/mock-scenario-setting-policy.ts`**
- Update `genBlocks()` to return `{ id, order }[]`
- Update `hydrateSteps()` to match API response structure

---

## Data Flow After Implementation

```
API Response (blocks: [{id, order}])
         ↓
Transform: Extract IDs → blocks: number[]
         ↓
Formik Form State (lightweight, IDs only)
         ↓
Extract unique IDs → [1, 2, 3]
         ↓
Check cache → Missing: [3] → Fetch [3] only
         ↓
Populate individual caches: ['block', 'components', 'cache', 3]
         ↓
UI reads from cache via useBlockComponents().getCachedBlocks()
```

---

## Testing

1. **Initial load**: Scenario with blocks [1, 2] → Verify 1, 2 fetched and cached
2. **Add blocks**: Add [3, 4] → Verify only 3, 4 fetched (1, 2 cached)
3. **Cross-scenario**: Load scenario with [2, 4, 5] → Verify only 5 fetched
4. **React Query DevTools**: Verify individual cache entries per block

---

## Implementation Order

1. Types (scenario-types.ts) - Foundation
2. Block queries (block-queries.ts) - Cache infrastructure
3. useBlockComponents hook (NEW) - Core logic
4. use-scenario-detail.ts - Transform + pre-cache
5. use-step-selected.ts - Return IDs
6. use-block-select.ts - Smart fetch on selection
7. UI components (step-block-list, dialogs) - Display
8. Mock updates - Testing support
