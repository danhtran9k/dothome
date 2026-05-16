# Plan: Refactor Step Validation to API-Driven Architecture (v0.4)

## Context

The current step validation system is **frontend-only**, using a mock `validateSteps` function in `mock-scenario-validate.ts` that checks if a step has more than 5 blocks. This is a temporary placeholder awaiting backend integration.

**Version 0.4 Requirements** introduce API-driven validation with the following changes:

**Validation Purpose:**
- Provide real-time reference information during scenario editing
- Help users identify and fix issues that would prevent the scenario from operating normally

**API Call Trigger Points:**
1. **Page entry** - When entering scenario edit page (except first-time "new" scenario creation)
2. **Step operations** - When deleting or reordering steps
3. **Block operations** - When adding or deleting blocks from steps

**Expected Behavior:**
- **Case 1 (Issues Found)**: Expose "확인 필요" (Confirmation Required) badge with detailed error information
- **Case 2 (No Issues)**: Hide the badge completely

**Current Implementation Issues:**
1. Frontend validation logic is a mock placeholder
2. No API integration for real-time validation
3. Validation only checks block count (> 5), not actual scenario health
4. No automatic validation triggers on step/block operations
5. No mechanism to display server-returned validation errors

## Investigation Findings

### Current Validation Flow

**Files:**
- `use-steps-validate.ts` - Hook that calls frontend validation
- `mock-scenario-validate.ts` - Mock validation function (checks blocks.length > 5)
- `step-validate-tag.tsx` - UI component displaying validation badge

**Current Logic:**
```typescript
// Frontend mock validation
const validateSteps = (steps: ScenarioStep[]) => {
  let hasBlockError = false;
  const errors = Array.from({ length: steps.length }, () => '');

  steps.forEach((step, index) => {
    if (step.blocks.length > 5) {
      errors[index] = PLACEHOLDER_ERR_MSG;
      hasBlockError = true;
    }
  });

  return { hasBlockError, errors };
};
```

**Current Trigger:**
- Only triggers on `values.steps` changes via `useMemo` dependency
- No explicit calls on step/block operations
- No API integration

### Operation Trigger Points (from exploration)

**Block Operations:**
- **Add**: `useBlockSelect()` → `setFieldValue('steps.${indexSelected}.blocks', blockIds)`
- **Delete**: FieldArray `remove(index)` in `step-composition.tsx`

**Step Operations:**
- **Add**: FieldArray `push(step)` via `useStepAdd()`
- **Delete**: FieldArray `remove(index)` via `useStepDelete()`
- **Reorder**: FieldArray `swap(from, to)` via `useStepSwap()`

**Page Entry:**
- **Edit Page**: `useScenarioLatest()` fetches scenario data on mount
- **Create Page**: Uses `INITIAL_SCENARIO` (no validation needed)

### Existing API Patterns

**Validation APIs:**
- `postValidateCreate()` - Dry-run validation before scenario creation
- `postValidatePublish()` - Dry-run validation before publish
- Both use `allow_save_draft=false` / `allow_expose=false` pattern
- Both expect HTTP 400 and normalize to success code

**Mutation Pattern:**
```typescript
const mutation = useMutation(scenarioOptions.someOperation());
mutation.mutateAsync(data);
await queryClient.invalidateQueries({ queryKey: scenarioKeys.all });
```

## Proposed Solution

### API Endpoint Design (Improvised)

Since API specs are not available, we'll design a validation endpoint following existing patterns:

**Endpoint:** `POST /console/admin/scenarios/{id}/validate`

**Request Body:**
```typescript
{
  steps: ScenarioStep[]  // Current form state
}
```

**Response (Success - No Issues):**
```typescript
{
  code: "0",
  data: {
    valid: true,
    errors: []
  },
  message: "Validation passed"
}
```

**Response (Has Issues):**
```typescript
{
  code: "0",
  data: {
    valid: false,
    errors: [
      {
        step_index: number,
        message: string,
        severity: "error" | "warning"
      }
    ]
  },
  message: "Validation found issues"
}
```

### Implementation Architecture

**New Files to Create:**

1. **`fetch-scenario-validate.ts`** (Entity Layer - API)
   - API call function
   - Type definitions for request/response

2. **`use-scenario-validate.ts`** (Feature Layer - Hook)
   - React Query mutation hook
   - Replaces current `use-steps-validate.ts`
   - Manages validation state
   - Auto-triggers validation at appropriate times

**Files to Modify:**

3. **`scenario-queries.ts`** (Entity Layer)
   - Add `validate` query key and option
   - Export new validation query option

4. **`step-validate-tag.tsx`** (UI Layer)
   - Update to use new validation hook
   - Display server-returned error messages
   - Support multiple errors per step

5. **`scenario-form.tsx`** (Feature Layer)
   - Trigger validation on mount (page entry)
   - Pass validation trigger to child components

6. **Remove `mock-scenario-validate.ts`** (Cleanup)
   - Delete mock implementation
   - Remove mock imports

### Validation Trigger Strategy

**1. Page Entry (useEffect on mount):**
```typescript
// In scenario-form.tsx
useEffect(() => {
  if (id && !isNaN(id)) {
    // Skip validation for new scenario creation
    validateScenario({ id, steps: values.steps });
  }
}, []); // Only on mount
```

**2. Block Operations (after mutation):**
```typescript
// In useBlockSelect
const onSubmit = async (blockIds: number[]) => {
  await blocksCacheQuery(blockIds);
  setFieldValue(`steps.${indexSelected}.blocks`, blockIds);
  // Trigger validation after update
  await validateScenario({ id, steps: values.steps });
};
```

**3. Step Operations (after mutation):**
```typescript
// In useStepDelete, useStepSwap, useStepAdd
const handleOperation = () => {
  // Perform operation (remove/swap/push)
  arrayHelpers.remove(index);
  // Trigger validation after update
  validateScenario({ id, steps: values.steps });
};
```

### Query vs Mutation Decision

**Use React Query Mutation (not Query):**
- Validation is an **action** (POST request with body)
- Should not cache validation results (stale quickly)
- Manual trigger control needed
- No automatic refetching required

```typescript
const { mutateAsync: validateScenario, data: validationResult } = useMutation(
  scenarioOptions.validate()
);
```

### Error Display Strategy

**Current:** Single error message per step
**New:** Support multiple errors per step with priority

```typescript
interface ValidationError {
  step_index: number;
  message: string;
  severity: 'error' | 'warning';
}

// Display logic in step-validate-tag.tsx
const currentStepErrors = validationResult?.errors.filter(
  err => err.step_index === indexSelected
);

if (currentStepErrors?.length > 0) {
  // Show badge with error count
  // Display all errors in popover
}
```

## Implementation Plan

### Phase 1: Create API Layer

**File:** `apps/scenario-console/src/fsd/05-entities/scenario/api/fetch-scenario-validate.ts`

```typescript
import type { ApiBaseResponse } from '@/shared/api';

interface ScenarioValidateRequest {
  steps: ScenarioStep[];
}

interface ValidationError {
  step_index: number;
  message: string;
  severity: 'error' | 'warning';
}

interface ScenarioValidateResponse extends ApiBaseResponse<{
  valid: boolean;
  errors: ValidationError[];
}> {}

async function fetchScenarioValidate(
  id: number,
  data: ScenarioValidateRequest
): Promise<ScenarioValidateResponse> {
  // Mock implementation until API is ready
  await delay();
  return mockScenarioValidate(data);
}

export { fetchScenarioValidate };
export type { ScenarioValidateRequest, ScenarioValidateResponse, ValidationError };
```

**File:** `apps/scenario-console/src/fsd/05-entities/scenario/api/mock/mock-scenario-validate.ts`

Update to return server-like response format instead of simple validation.

### Phase 2: Update Query Configuration

**File:** `apps/scenario-console/src/fsd/05-entities/scenario/model/scenario-queries.ts`

```typescript
const scenarioKeys = {
  // ... existing keys
  validate: (id: number) => [...scenarioKeys.all, 'validate', id],
};

const scenarioOptions = {
  // ... existing options
  validate: (id: number) => ({
    mutationKey: scenarioKeys.validate(id),
    mutationFn: (data: ScenarioValidateRequest) => fetchScenarioValidate(id, data),
  }),
};
```

**File:** `apps/scenario-console/src/fsd/05-entities/scenario/api/index.ts`

```typescript
export * from './fetch-scenario-validate';
```

### Phase 3: Create Validation Hook

**File:** `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/use-scenario-validate.ts`

```typescript
import { useMutation } from '@tanstack/react-query';
import { useFormikContext } from 'formik';
import { scenarioOptions } from '@/entities/scenario';
import { useScenarioStore } from '../store';
import { useParamsId } from '@/shared/lib/hooks';

function useScenarioValidate() {
  const id = useParamsId();
  const { values } = useFormikContext<ScenarioForm>();
  const { indexSelected } = useScenarioStore();

  const { mutateAsync, data, isPending } = useMutation(
    scenarioOptions.validate(id)
  );

  const validateScenario = async () => {
    if (isNaN(id)) return; // Skip for new scenario
    await mutateAsync({ steps: values.steps ?? [] });
  };

  // Get current step's errors
  const currentStepErrors = data?.data.errors.filter(
    err => err.step_index === indexSelected
  ) ?? [];

  const hasBlockError = data?.data.valid === false;

  return {
    validateScenario,
    currentStepErrors,
    hasBlockError,
    isValidating: isPending,
  };
}

export { useScenarioValidate };
```

### Phase 4: Update UI Component

**File:** `apps/scenario-console/src/fsd/04-features/scenario/ui/step-configuration/step-validate-tag.tsx`

```typescript
import { Badge, Popover } from '@nxui/core';
import { useState } from 'react';
import { useScenarioValidate } from '../../model';

function StepValidateTag() {
  const [isOpen, setIsOpen] = useState(false);
  const { currentStepErrors, isValidating } = useScenarioValidate();

  if (currentStepErrors.length === 0) return null;

  return (
    <Popover open={isOpen} onOpenChange={setIsOpen}>
      <Popover.Trigger>
        <Badge semanticColor="error" size="l" className="py-2 px-6">
          {isValidating ? '확인 중...' : '확인 필요'}
        </Badge>
      </Popover.Trigger>

      <div className="p-2 flex flex-col max-w-[250px]">
        <p>확인 필요 블록 존재</p>
        <div className="flex flex-col gap-0">
          <span>일부 블록이 정상적으로 동작하지 않습니다.</span>
          <span>설정된 블록을 다시 확인해 주세요.</span>
          {currentStepErrors.map((err, idx) => (
            <span key={idx}>
              대상 : {err.message}
            </span>
          ))}
        </div>
      </div>
    </Popover>
  );
}

export { StepValidateTag };
```

### Phase 5: Integrate Validation Triggers

**File:** `apps/scenario-console/src/fsd/04-features/scenario/ui/scenario-form.tsx`

Add validation trigger on mount:

```typescript
function ScenarioForm({ id, isSetting }) {
  const { validateScenario } = useScenarioValidate();

  useEffect(() => {
    // Trigger validation on page entry (except new scenario)
    if (id && !isNaN(id)) {
      validateScenario();
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ... rest of component
}
```

**Files:** Update operation hooks to trigger validation:
- `use-block-select.ts` - After block selection
- `use-step-delete.ts` - After step deletion
- `use-step-swap.ts` - After step reorder
- `use-step-add.ts` - After step addition

Pattern for each:
```typescript
const { validateScenario } = useScenarioValidate();

const handleOperation = async () => {
  // Perform operation
  await doOperation();
  // Trigger validation
  await validateScenario();
};
```

### Phase 6: Cleanup

**Delete:**
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/use-steps-validate.ts`

**Update exports:**
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/index.ts`
  - Remove `export * from './use-steps-validate'`
  - Add `export * from './use-scenario-validate'`

## Critical Files

### Entity Layer (Create)
- `/apps/scenario-console/src/fsd/05-entities/scenario/api/fetch-scenario-validate.ts` (NEW)
- `/apps/scenario-console/src/fsd/05-entities/scenario/api/mock/mock-scenario-validate.ts` (MODIFY)
- `/apps/scenario-console/src/fsd/05-entities/scenario/api/index.ts` (MODIFY)
- `/apps/scenario-console/src/fsd/05-entities/scenario/model/scenario-queries.ts` (MODIFY)

### Feature Layer (Create/Modify)
- `/apps/scenario-console/src/fsd/04-features/scenario/model/hooks/use-scenario-validate.ts` (NEW)
- `/apps/scenario-console/src/fsd/04-features/scenario/model/hooks/use-steps-validate.ts` (DELETE)
- `/apps/scenario-console/src/fsd/04-features/scenario/model/hooks/index.ts` (MODIFY)
- `/apps/scenario-console/src/fsd/04-features/scenario/ui/scenario-form.tsx` (MODIFY)

### UI Layer (Modify)
- `/apps/scenario-console/src/fsd/04-features/scenario/ui/step-configuration/step-validate-tag.tsx` (MODIFY)

### Operation Hooks (Add validation triggers)
- `/apps/scenario-console/src/fsd/04-features/scenario/model/hooks/step-configuration/use-block-select.ts`
- `/apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-configuration/use-step-delete.ts`
- `/apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-configuration/use-step-swap.ts`
- `/apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-configuration/use-step-add.ts`

## Verification Steps

### 1. Type Safety
```bash
cd apps/scenario-console
npm run type-check
```

### 2. Build Verification
```bash
npm run build
```

### 3. Manual Testing - Page Entry
- Navigate to scenario edit page
- Verify "확인 필요" badge appears if validation fails
- Verify badge is hidden if no errors
- Check network tab for POST /scenarios/{id}/validate call

### 4. Manual Testing - Block Operations
- Add blocks to a step
- Verify validation triggers after block selection
- Delete a block
- Verify validation re-runs

### 5. Manual Testing - Step Operations
- Delete a step → validation should trigger
- Swap step order → validation should trigger
- Add new step → validation should trigger

### 6. Manual Testing - UI Behavior
- Click "확인 필요" badge
- Verify popover shows all error messages for current step
- Switch to different step
- Verify badge updates to show that step's errors
- Create new scenario
- Verify validation doesn't trigger (no ID yet)

### 7. Error Display
- Trigger validation with multiple errors
- Verify all errors display in popover
- Verify error messages are from server response
- Verify loading state shows "확인 중..." during validation

## Summary

**Architecture Changes:**
- Frontend validation → API-driven validation
- Synchronous useMemo → Asynchronous mutation
- Mock placeholder → Real API integration (with mock fallback)

**Key Improvements:**
1. Real-time validation feedback during editing
2. Server-authoritative validation rules
3. Support for multiple error types per step
4. Automatic validation triggers on all relevant operations
5. Loading states during validation
6. Follows existing API patterns (mutations, invalidation)

**Backward Compatibility:**
- Hook interface stays similar (`hasBlockError`, error messages)
- UI component structure unchanged
- Formik integration unchanged
- Store integration unchanged

**API Flexibility:**
- Mock implementation until backend ready
- Easy to swap mock with real endpoint
- Response format designed for extensibility
- Supports error severity levels (error/warning)
