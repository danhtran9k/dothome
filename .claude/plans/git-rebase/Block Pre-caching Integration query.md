# Implementation Plan: Block Pre-caching Integration

## Overview

Implement the "Combined queryFn" approach to pre-cache block components when scenario loads. Fix existing bugs in block caching usage.

---

## Tasks

### Task 1: Fix `use-block-select.ts` - Wrong Function Call

**File:** `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/step-configuration/use-block-select.ts`

**Bug:** Line 19 calls `blocksCacheQuery.fetchBlockComponents(blockIds)` but `blocksCacheQuery` is a function, not an object.

**Current (broken):**
```typescript
await blocksCacheQuery.fetchBlockComponents(blockIds);
```

**Fix:**
```typescript
await blocksCacheQuery(blockIds);
```

---

### Task 2: Export `useBlockComponents` from Block Entity

**File:** `apps/scenario-console/src/fsd/05-entities/block/model/index.ts`

**Change:** Add missing export

```typescript
export * from './use-block-components';
```

---

### Task 3: Refactor `useScenarioLatest` with Combined queryFn

**File:** `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/use-scenario-latest.ts`

**Approach:** Combined queryFn - single `isLoading` covers both scenario + blocks

**Implementation:**
```typescript
import { useQuery } from '@tanstack/react-query';
import { useCacheBlocks } from '@/entities/block';
import { fetchScenarioLatest, scenarioKeys } from '@/entities/scenario';
import { useParamsId } from '@/shared/lib/hooks';
import { useToast } from '@/shared/lib/utils';

function useScenarioLatest() {
  const id = useParamsId();
  const { blocksCacheQuery } = useCacheBlocks();
  const toast = useToast();

  const { data, isError, isLoading, isFetching } = useQuery({
    queryKey: scenarioKeys.latest(id),
    enabled: !Number.isNaN(id),
    staleTime: 5 * 60 * 1000,
    queryFn: async () => {
      const res = await fetchScenarioLatest(id);
      const rawData = res.data;

      // Transform: drop order, extract block IDs
      const transformedSteps = rawData.steps?.map((step) => {
        const blockIds = step.blocks.map(block =>
          typeof block === 'object' && 'id' in block
            ? (block as { id: number }).id
            : block,
        );
        const { order: _order, ...stepWithoutOrder } = step as typeof step & { order?: number };
        return { ...stepWithoutOrder, blocks: blockIds };
      });

      // Pre-cache blocks
      const allBlockIds = transformedSteps?.flatMap(step => step.blocks) ?? [];
      const uniqueBlockIds = [...new Set(allBlockIds)] as number[];

      if (uniqueBlockIds.length > 0) {
        try {
          await blocksCacheQuery(uniqueBlockIds);
        } catch (error) {
          toast.error('블록 데이터를 불러오는데 실패했습니다.');
          console.error('Block pre-cache error:', error);
        }
      }

      return { ...rawData, steps: transformedSteps };
    },
  });

  return { id, data, isError, isLoading, isFetching };
}

export { useScenarioLatest };
```

---

## Files to Modify

| File | Change |
|------|--------|
| `.../step-configuration/use-block-select.ts` | Fix: `blocksCacheQuery(blockIds)` |
| `.../block/model/index.ts` | Add `use-block-components` export |
| `.../hooks/use-scenario-latest.ts` | Implement combined queryFn |

---

## Verification

1. **Build check:** `pnpm lint` passes
2. **Initial load:** Page waits for both scenario + blocks before rendering
3. **Block select:** Dialog submit caches blocks correctly
4. **Error handling:** Toast shows on block fetch failure
