# Plan: Optimized Block Components Fetching

## Summary
Implement per-block React Query caching to avoid duplicate fetches across scenarios. Transform API response to lightweight form state (`blocks: number[]`) and fetch `BlockComponentItem` data separately with smart batch caching.

---

## Key Decisions
- **Form state:** `blocks: number[]` (IDs only, order dropped)
- **API response:** `blocks: Array<{ id: number, order: number }>` (order dropped during transform)
- **Cache strategy:** Per-block queries `['block', 'components', 'cache', <id>]`
- **BlockSelectDialog:** Receives `number[]`, uses `Set<number>` internally for optimized selection checks
- **Naming convention:**
  - `blockOptions.components` - KEEP as-is (batch fetch API)
  - `blockOptions.componentsCache(id)` - NEW (individual cache read)

---

## Phase 1: Types & Mock Update

### File 1: `apps/scenario-console/src/fsd/05-entities/scenario/model/scenario-types.ts`
- Add `ScenarioStepResponse` type for API response (includes `order` fields)
- Update `ScenarioStep.blocks` from `{ id, order }` to `number[]`

### File 2: `apps/scenario-console/src/fsd/05-entities/scenario/api/mock/mock-scenario-setting-policy.ts`
- Update `genBlocks()` to return `Array<{ id: number, order: number }>`
- Add `order` field to mock steps
- Update `hydrateSteps()` to return `{ id, order }[]` for blocks (not `BlockItem[]`)

### File 3: `apps/scenario-console/src/fsd/05-entities/block/api/mock/mock-block-component.ts`
- Update `genBaseBlock` return type to `BlockComponentItem`

### File 4: `apps/scenario-console/src/fsd/04-features/scenario/lib/utils/form-utils.ts`
- Add TODO comment: "Delete if no longer used - blocks is now number[]"

---

## Phase 2: Block Query & Hook Updates

### File 1: `apps/scenario-console/src/fsd/05-entities/block/model/block-queries.ts`
- KEEP `blockKeys.components` and `blockOptions.components` (batch fetch API)
- ADD `blockKeys.componentsCache(id)` for individual cache key
- ADD `blockOptions.componentsCache(id)` query option (use React Query defaults)

### File 2: `apps/scenario-console/src/fsd/05-entities/block/model/use-block-components.ts` (NEW)
- Create hook that:
  - Filters out cached IDs using `blockKeys.componentsCache(id)`
  - Batch fetches missing IDs using `fetchBlockComponents`
  - Populates individual caches with `setQueryData(blockKeys.componentsCache(id), data)`
  - Returns combined loading state via `useQueries`

### File 3: `apps/scenario-console/src/fsd/05-entities/block/index.ts`
- Export `useBlockComponents` and `blockKeys`

---

## Phase 3: Scenario Detail & Form Integration

### File 1: `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/use-scenario-detail.ts`
- Transform API response: drop `order` fields, extract block IDs
- Call `useBlockComponents` to prefetch all blocks
- Return combined `isLoading` (scenario + blocks)

### File 2: `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/use-step-selected.ts`
- Update `blocksSteps` type from `BlockItem[]` to `number[]`

### File 3: `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/step-configuration/use-block-select.ts`
- Check cache for each block ID
- Batch fetch missing blocks
- Populate individual caches
- Store only IDs in form state

---

## Phase 4: UI Component Updates

### File 1: `apps/scenario-console/src/fsd/04-features/scenario/ui/step-configuration/step-block-list.tsx`
- Update to iterate over `number[]`
- Create `BlockDisplay` component that uses `useQuery(blockOptions.componentsCache(blockId))`

### File 2: `apps/scenario-console/src/fsd/04-features/scenario/ui/step-configuration/block-select-dialog.tsx`
- Change `selectedBlock` prop type from `BlockItem[]` to `number[]`
- Create `selectedIdsSet: Set<number>` with `useMemo` for optimized lookups
- Pass `selectedIdsSet` to child components instead of `BlockItem[]`

### File 3: `apps/scenario-console/src/fsd/04-features/scenario/ui/step-configuration/block-select-table.tsx`
- Change `selectedItems` prop type from `BlockItem[]` to `Set<number>`
- Change `onSelectItems` to `onToggleSelect: (id: number) => void`

### File 4: `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/step-configuration/use-block-select-table.tsx`
- Update `selectedItems` type from `BlockItem[]` to `Set<number>`
- Replace `selectedItems.some(item => item.id === typedRow.id)` with `selectedItems.has(typedRow.id)`
- Simplify onChange to call `onToggleSelect(typedRow.id)`

### File 5: `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/step-configuration/use-block-select-pagination.ts`
- Update to work with `Set<number>` instead of `T[]` for selectedItems
- Already uses Set internally, simplify to accept Set directly

### File 6: `apps/scenario-console/src/fsd/04-features/scenario/ui/step-configuration/step-composition.tsx`
- No changes needed (loading handled by `useScenarioDetail`)

---

## Loading State Behavior

| Scenario | Behavior |
|----------|----------|
| Initial scenario load | `step-composition` shows loading until scenario + all blocks fetched |
| Block select dialog submit | Dialog stays open with loading button until cache check/fetch completes |
| Delete draft | Re-fetches scenario detail → triggers full loading |
| Save draft / Publish | No UI loading change needed |

---

## Verification

1. **Initial Load:**
   - Load scenario edit page
   - Verify loading state shown
   - Check React Query DevTools: individual `['block', 'component', <id>]` entries

2. **Add Blocks:**
   - Open block select dialog
   - Select new blocks
   - Verify only uncached blocks fetched (check network tab)
   - Verify dialog loading state

3. **Cross-Scenario Cache:**
   - Edit scenario with blocks [1, 2]
   - Navigate to another scenario with blocks [2, 3]
   - Verify only block 3 fetched (block 2 from cache)

4. **Delete Draft:**
   - Click delete draft
   - Verify scenario re-fetches and loading state shows
