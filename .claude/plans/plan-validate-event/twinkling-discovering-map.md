# Step Validation Refactor: Detailed Analysis & Implementation Plan

## Table of Contents
1. [Problem Statement](#problem-statement)
2. [Codebase Exploration Results](#codebase-exploration-results)
3. [Architecture Decision: Event-Driven vs Parent Orchestration](#architecture-decision)
4. [Technical Deep Dive: Debounce + AbortController](#technical-deep-dive)
5. [UX Decision: No Button Disabling](#ux-decision)
6. [Implementation Plan](#implementation-plan)

---

## 1. Problem Statement

Current step validation is a **frontend-only mock** (`validateSteps` checks `blocks.length > 5`). We need API-driven validation that:
- Triggers on page entry (except new scenarios), step operations, and block operations
- Shows "확인 필요" badge with error details when issues found
- Hides badge when no issues
- Is purely **advisory** — never blocks user interaction

---

## 2. Codebase Exploration Results

### 2.1 Current Validation Files

**`use-steps-validate.ts`** — `apps/scenario-console/src/fsd/03-widgets/scenario-form/model/step-configuration/use-steps-validate.ts`
```typescript
function useStepsValidate() {
  const { values } = useFormikContext<ScenarioForm>();
  const { indexSelected } = useScenarioStore();
  // TODO: Update validation logic after clarification
  const { hasBlockError, errors } = useMemo(() => validateSteps(values.steps ?? []), [values.steps]);
  const currentErrMsg = errors[indexSelected];
  return { hasBlockError, currentErrMsg };
}
```
- Synchronous, useMemo-based
- Calls mock `validateSteps` from `@/entities/scenario`
- Returns `hasBlockError` (unused externally — only in mock + this hook) and `currentErrMsg` (consumed by `StepValidateTag`)

**`mock-scenario-validate.ts`** — `apps/scenario-console/src/fsd/05-entities/scenario/api/mock/mock-scenario-validate.ts`
- `validateSteps(steps: ScenarioStep[])` — checks `step.blocks.length > 5`, returns `{ hasBlockError, errors: string[] }`
- Also contains: `mockScenarioValidate`, `mockDryRunValidate`, `createMockApiError` — used for create/publish mock validation (separate concern)
- Exported via `api/mock/index.ts` → `api/index.ts` → `@/entities/scenario`

**`step-validate-tag.tsx`** — `apps/scenario-console/src/fsd/03-widgets/scenario-form/ui/step-configuration/step-validate-tag.tsx`
```typescript
function StepValidateTag() {
  const [isOpen, setIsOpen] = useState(false);
  const { currentErrMsg } = useStepsValidate();
  if (!currentErrMsg) return null;
  return (
    <Popover open={isOpen} onOpenChange={setIsOpen}>
      <Popover.Trigger>
        <Badge semanticColor="error" size="l" className="py-2 px-6">확인 필요</Badge>
      </Popover.Trigger>
      <div>... error display ...</div>
    </Popover>
  );
}
```
- Rendered in `StepComposition`'s `<Panel.Header title="스텝 구성" actions={<StepValidateTag />} />`
- Always mounted (even when returning null, hooks still run)

### 2.2 Operation Hooks That Should Trigger Validation

**`use-block-select.ts`** — `03-widgets/scenario-form/model/step-configuration/`
```typescript
const onSubmit = async (blockIds: number[]) => {
  setIsLoadingComponents(true);
  try {
    await blocksCacheQuery(blockIds);
    setFieldValue(`steps.${indexSelected}.blocks`, blockIds);
    blockSelectDialog.onClose();
  } finally {
    setIsLoadingComponents(false);
  }
};
```
- Has popup dialog (natural delay) — user selects blocks in dialog before submitting

**`use-block-delete.ts`** — `03-widgets/scenario-form/model/step-configuration/`
```typescript
const onConfirmDelete = (remove: (index: number) => void) => {
  if (ixDelete === null) { dialog.onClose(); return; }
  remove(ixDelete);
  dialog.onClose('ok');
};
```
- Has confirm dialog (natural delay)

**`use-step-delete.ts`** — `03-widgets/scenario-form/model/scenario-configuration/`
```typescript
const onConfirmDelete = (remove: (index: number) => void) => {
  // ... index adjustment logic for useScenarioStore ...
  remove(ixDelete);
  dialog.onClose('ok');
};
```
- Has confirm dialog (natural delay)
- Complex indexSelected adjustment across 4 cases

**`use-step-swap.ts`** — `03-widgets/scenario-form/model/scenario-configuration/`
```typescript
const onSwap = (ixDiff: -1 | 1) => {
  if (!values.steps || indexSelected === NULL_SELECTED_STEP) return;
  const newIndex = indexSelected + ixDiff;
  if (newIndex < 0 || newIndex >= values.steps.length) return;
  handleSwap(indexSelected, newIndex);
  setIndexSelected(newIndex);
};
```
- NO popup — can be spammed via arrow buttons

**`use-step-add.ts`** — `04-features/scenario/model/hooks/`
```typescript
const handleAddStep = () => {
  const clientId = Date.now();
  const name = getInitialStepName(values.steps);
  handleAdd({ ...INITIAL_STEP, name, clientId });
  if (indexSelected === NULL_SELECTED_STEP) setIndexSelected(DEFAULT_STEP_INDEX);
};
```
- NO popup — can be spammed via button click
- Note: in `04-features` layer (important for FSD import direction)

### 2.3 Composition Components

**`step-composition.tsx`** — `03-widgets/scenario-form/ui/step-configuration/`
- Uses `useBlockSelect`, `useBlockDelete`
- Renders `StepValidateTag` in panel header
- Contains `FieldArray` for `steps.${indexSelected}.blocks`

**`scenario-composition.tsx`** — `03-widgets/scenario-form/ui/scenario-configuration/`
- Uses `useStepDelete`
- Contains `FieldArray` for `steps`
- Renders `StepAddBtn` (uses `useStepAdd` internally) and `StepSwapBtn` (uses `useStepSwap` internally)

**`scenario-form.tsx`** — `03-widgets/scenario-form/ui/`
- Top-level form component
- Contains `ScenarioComposition` and `StepComposition`
- Submit buttons: `PublishTriggerBtn`, `DraftSaveBtn`, `ScenarioCreateTriggerBtn`

### 2.4 API Patterns

**`apiFetch`** — `06-shared/lib/utils/api-fetch.ts`
```typescript
interface ApiFetchOptions extends Omit<RequestInit, 'body'> {
  params?: Record<string, ParamsValue | ParamsValue[]>
  data?: object
}
async function apiFetch<T>(url: string, { params, data, headers, ...rest }: ApiFetchOptions = {}): Promise<ApiBaseResponse<T>> {
  const response = await fetch(fullUrl, { ...rest, body: data != null ? JSON.stringify(data) : undefined, headers: {...} });
  // ...
}
```
- **KEY: `signal` IS supported** — `ApiFetchOptions extends Omit<RequestInit, 'body'>`, and `signal` is part of `RequestInit`. The `...rest` spread passes it to `fetch()`.

**Endpoints** — `05-entities/scenario/config/endpoints.ts`
```typescript
const SCENARIO_ENDPOINTS = {
  BASE, ACTIVATION, HISTORIES, LATEST, PUBLISH, DRAFT
}
```
- No `/validate` endpoint yet — needs to be added

**Mutation pattern** — `05-entities/scenario/model/scenario-queries.ts`
```typescript
scenarioOptions.post() → { mutationKey, mutationFn: ({data, params}) => postScenario({data, params}) }
```

### 2.5 Zustand Store

**`scenario-form-store.ts`** — `04-features/scenario/model/stores/`
```typescript
interface ScenarioFormStore {
  indexSelected: StepId
  existedScenarioName: string
  setExistedScenarioName: (names: string) => void
  setIndexSelected: (step: StepId) => void
  resetStore: () => void
}
```
- No `isValidating` — and we decided NOT to add it (no button disabling)

### 2.6 Export Chain

```
step-validate-tag.tsx imports from '../../model'
  → 03-widgets/scenario-form/model/index.ts
    → exports from './step-configuration'
      → 03-widgets/scenario-form/model/step-configuration/index.ts
        → exports from './use-steps-validate'
```

### 2.7 Existing Event Usage

- Only `window.addEventListener('hashchange', ...)` in `main.tsx` — no CustomEvent usage anywhere

### 2.8 FSD Layer Dependencies

```
02-pages → 03-widgets → 04-features → 05-entities → 06-shared
```
- `04-features` CANNOT import from `03-widgets`
- `03-widgets` CAN import from `04-features`
- Event emitter utility must live in `04-features` or lower so both layers can use it
- `useStepAdd` is in `04-features` — important constraint

---

## 3. Architecture: Event-Driven with Custom Events

### How It Works

Operation hooks emit a `'scenario-validate'` custom event after mutations. The validation hook (`useScenarioValidate`, used inside `StepValidateTag`) listens for this event and handles the API call internally.

```typescript
// Each operation hook adds 1 line after its mutation:
emitScenarioValidate();

// The validation hook listens internally:
window.addEventListener('scenario-validate', validate);
```

### Why This Approach

- **Minimal edits:** 1 line added per operation hook (~15-20 lines changed total)
- **No parent component changes:** `step-composition.tsx`, `scenario-composition.tsx`, `scenario-form.tsx` are untouched
- **No prop drilling:** Validation state is local to the hook, no `isValidating` threaded through components
- **Self-contained:** All validation logic (debounce, abort, API call, state) lives in one hook
- **Decoupled:** Operation hooks don't know about validation — they just emit an event

### Trade-off

- CustomEvent is a new pattern in this codebase (no existing usage) — implicit coupling makes event flow harder to trace vs explicit callbacks. Mitigated by using a single, well-named event constant (`SCENARIO_VALIDATE_EVENT`).

---

## 4. Technical Deep Dive: Debounce + AbortController

### 4.1 Why Debounce Is Needed

**Problem: Stale Formik values after `setFieldValue`**

When an operation hook calls `setFieldValue`, React schedules a state update but hasn't re-rendered yet. If the event handler reads `values.steps` immediately, it gets stale data:

```
T=0ms   setFieldValue('steps.0.blocks', newBlocks)  ← schedules React update
T=0ms   emitScenarioValidate()                       ← fires event SYNCHRONOUSLY
T=0ms   Event handler reads stepsRef.current          ← STALE (React hasn't re-rendered)
T=~16ms React re-renders                              ← stepsRef.current updated
```

**Solution:** `setTimeout` (even `setTimeout(0)`) pushes the read to a macrotask, which fires AFTER React processes the state update:
```
T=0ms   setFieldValue() + emitScenarioValidate()
T=0ms   Handler sets setTimeout(300)
T=~16ms React re-renders → stepsRef.current updated
T=300ms setTimeout fires → reads FRESH stepsRef.current ✓
```

**Why 300ms instead of 0ms:** The BE validation is heavy (DB lookups + JOINs). Without button disabling, users can spam operations freely. The 300ms debounce batches rapid operations into fewer API calls, reducing BE load:

| Scenario | setTimeout(0) | debounce(300ms) |
|----------|--------------|-----------------|
| 5 clicks at 200ms intervals | 5 API calls (but 4 aborted on FE) | 1 API call |
| 5 clicks at 400ms intervals | 5 API calls (but 4 aborted on FE) | 5 API calls |
| Backend load | Higher (5 heavy queries processed) | Lower (1 heavy query) |

### 4.2 Why AbortController Is Needed

**Problem:** Even with debounce, if the user spaces actions > 300ms apart, multiple API calls fire. If response #1 arrives after response #2, the UI shows stale validation results.

**Solution:** Each new validation call aborts the previous in-flight request:
```
T=0ms      Validate #1 starts (API call in-flight)
T=400ms    Validate #2 starts → abort #1 → new API call
T=800ms    Validate #2 response arrives → UI updated with correct state
T=1200ms   Validate #1 response would arrive → but it was aborted, ignored
```

### 4.3 AbortController: What Actually Happens

**Frontend behavior:**
- `controller.abort()` rejects the `fetch()` promise with `AbortError`
- Browser may close TCP connection (sends RST/FIN)
- The handler catches `AbortError` and silently ignores it

**Backend behavior:**
- **Backend has NO way to know the request was aborted**
- Even if FE aborts, BE processes the request fully (all DB lookups, JOINs complete)
- The backend may detect "broken pipe" when writing the response, but the work is already done
- HTTP/2 RST_STREAM frame could theoretically signal cancellation, but most backend frameworks ignore it

**Implication:** AbortController is purely a **frontend correctness** mechanism — it prevents stale responses from being processed. It does NOT reduce backend load. Only debounce reduces backend load.

### 4.4 Combined Flow

```
User clicks "Add Step"
│
├─ handleAddStep() runs
│  ├─ handleAdd({...INITIAL_STEP})     ← Formik push (state update scheduled)
│  ├─ setIndexSelected(newIndex)        ← Zustand update
│  └─ emitScenarioValidate()           ← fires CustomEvent
│
├─ Event handler fires (SYNC)
│  ├─ clearTimeout(debounceRef)         ← cancel any pending debounce
│  └─ debounceRef = setTimeout(300ms)   ← schedule validation
│
├─ React re-renders (~16ms)
│  └─ stepsRef.current = values.steps   ← ref updated with new step
│
└─ setTimeout fires (300ms)
   ├─ abortRef.current?.abort()         ← cancel previous in-flight request
   ├─ new AbortController()
   ├─ setIsValidating(true)             ← local state for badge "확인 중..."
   ├─ postValidateSteps(id, payload, signal)
   │  └─ API call with abort signal
   ├─ if (!signal.aborted):
   │  ├─ setValidationResult(data)      ← update validation errors
   │  └─ setIsValidating(false)
   └─ if AbortError: silently ignore
```

---

## 5. UX Decision: No Button Disabling

**Decision:** Validation never disables buttons or blocks user interaction. It is purely advisory.

**Rationale (from user):** Disabling buttons during validation is bad UX — users should be free to interact at all times.

**Implications:**
- No `isValidating` in Zustand store (no shared state needed)
- No changes to button components (`StepAddBtn`, `StepSwapBtn`, `DraftSaveBtn`, `PublishTriggerBtn`)
- No changes to parent composition components
- `isValidating` is local state in the validation hook, only used for badge text ("확인 중...")
- Submit (draft save, publish) is NOT blocked by validation state

---

## 6. Implementation Plan

### Phase 1: API Layer

**1.1 Add endpoint** — `apps/scenario-console/src/fsd/05-entities/scenario/config/endpoints.ts`
- Add `VALIDATE: (id: number) => \`${SCENARIO_BASE}/${id}/validate\`` to `SCENARIO_ENDPOINTS`

**1.2 Create API function** — `apps/scenario-console/src/fsd/05-entities/scenario/api/post-validate-steps.ts` (NEW)
- Define `ValidationError` type: `{ step_index: number, message: string, severity: 'error' | 'warning' }`
- Define `ScenarioValidateData`: `{ valid: boolean, errors: ValidationError[] }`
- Export `postValidateSteps(id: number, data: number[][], signal?: AbortSignal): Promise<ApiBaseResponse<ScenarioValidateData>>`
- Currently calls mock; will switch to `apiFetch(SCENARIO_ENDPOINTS.VALIDATE(id), { method: 'POST', data, signal })` when BE is ready

**1.3 Add mock function** — `apps/scenario-console/src/fsd/05-entities/scenario/api/mock/mock-scenario-validate.ts` (MODIFY)
- Add `mockPostValidateSteps(data: number[][], signal?: AbortSignal)`:
  - Simulate delay: `await new Promise(resolve => setTimeout(resolve, 500))` with signal check
  - Map existing logic: `if (blocks.length > 5)` → `ValidationError { step_index, message: '블록이 5개를 초과합니다', severity: 'error' }`
  - Return `ApiBaseResponse<ScenarioValidateData>` format

**1.4 Update exports** — `apps/scenario-console/src/fsd/05-entities/scenario/api/index.ts` (MODIFY)
- Add `export * from './post-validate-steps'`

### Phase 2: Event Emitter

**Create:** `apps/scenario-console/src/fsd/04-features/scenario/lib/emit-scenario-validate.ts` (NEW)
- Export `SCENARIO_VALIDATE_EVENT` constant and `emitScenarioValidate()` function
- Must be in `04-features` layer so both `03-widgets` hooks and `04-features` hooks (`useStepAdd`) can import it
- Export from `04-features/scenario/index.ts`

### Phase 3: Validation Hook

**Create:** `apps/scenario-console/src/fsd/03-widgets/scenario-form/model/step-configuration/use-scenario-validate.ts` (NEW)
- Replaces `use-steps-validate.ts`
- Uses: `useParamsId`, `useFormikContext<ScenarioForm>`, `useScenarioStore`
- Internal state: `validationResult` (ScenarioValidateData | null), `isValidating` (boolean)
- Refs: `abortRef` (AbortController), `debounceRef` (setTimeout), `stepsRef` (always-fresh steps)
- `validate` callback: clear debounce → setTimeout(300ms) → abort previous → call API → update state
- `useEffect` #1: addEventListener for `SCENARIO_VALIDATE_EVENT`
- `useEffect` #2: validate on mount if `id` is valid (page entry trigger)
- `useEffect` #3: cleanup on unmount (abort + clearTimeout)
- Returns: `{ currentStepErrors, hasBlockError, isValidating }`

### Phase 4: Update Badge Component

**Modify:** `apps/scenario-console/src/fsd/03-widgets/scenario-form/ui/step-configuration/step-validate-tag.tsx`
- Import `useScenarioValidate` instead of `useStepsValidate`
- Destructure `{ currentStepErrors, isValidating }` from hook
- Condition: if `currentStepErrors.length === 0 && !isValidating` return null
- Badge text: `isValidating ? '확인 중...' : '확인 필요'`
- Error display: map `currentStepErrors` showing `err.message`

### Phase 5: Add Emitters to Operation Hooks

Add `emitScenarioValidate()` (1 line each):

| File | Where to add | Import from |
|------|-------------|-------------|
| `03-widgets/.../step-configuration/use-block-select.ts` | After `blockSelectDialog.onClose()` in `onSubmit` | `@/features/scenario` |
| `03-widgets/.../step-configuration/use-block-delete.ts` | After `dialog.onClose('ok')` in `onConfirmDelete` | `@/features/scenario` |
| `03-widgets/.../scenario-configuration/use-step-delete.ts` | After `dialog.onClose('ok')` in `onConfirmDelete` | `@/features/scenario` |
| `03-widgets/.../scenario-configuration/use-step-swap.ts` | After `setIndexSelected(newIndex)` in `onSwap` | `@/features/scenario` |
| `04-features/.../hooks/use-step-add.ts` | After `handleAdd()` in `handleAddStep` | `../lib/emit-scenario-validate` (or local import) |

### Phase 6: Cleanup

- **Delete:** `03-widgets/scenario-form/model/step-configuration/use-steps-validate.ts`
- **Modify:** `03-widgets/scenario-form/model/step-configuration/index.ts`
  - Remove `export * from './use-steps-validate'`
  - Add `export * from './use-scenario-validate'`
- **Note:** `validateSteps` in mock file may still be needed by other code — verify before removing

### Files Summary

| Action | File |
|--------|------|
| NEW | `05-entities/scenario/api/post-validate-steps.ts` |
| NEW | `04-features/scenario/lib/emit-scenario-validate.ts` |
| NEW | `03-widgets/scenario-form/model/step-configuration/use-scenario-validate.ts` |
| MODIFY | `05-entities/scenario/config/endpoints.ts` |
| MODIFY | `05-entities/scenario/api/mock/mock-scenario-validate.ts` |
| MODIFY | `05-entities/scenario/api/index.ts` |
| MODIFY | `04-features/scenario/index.ts` |
| MODIFY | `03-widgets/.../step-validate-tag.tsx` |
| MODIFY | `03-widgets/.../use-block-select.ts` (+1 line) |
| MODIFY | `03-widgets/.../use-block-delete.ts` (+1 line) |
| MODIFY | `03-widgets/.../use-step-delete.ts` (+1 line) |
| MODIFY | `03-widgets/.../use-step-swap.ts` (+1 line) |
| MODIFY | `04-features/.../use-step-add.ts` (+1 line) |
| MODIFY | `03-widgets/.../step-configuration/index.ts` |
| DELETE | `03-widgets/.../use-steps-validate.ts` |

### Verification

1. TypeScript: `cd apps/scenario-console && npm run tsc:alpha`
2. Build: `cd apps/scenario-console && npm run build:alpha`
