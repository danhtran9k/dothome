# Scenario API Migration: Query-Param Based Validation

## Context

The backend is consolidating scenario APIs. The old separate `postValidateScenario` endpoint is being removed. Validation is now built into the create and publish endpoints via query parameters that act as a "commit flag". The real API endpoints are not ready yet (DTO/Swagger specs are finalizing), so we restructure the mock layer to match the new behavior first, then swap with real `apiFetch` calls when ready.

### New API Endpoints

| Endpoint | Query Param | `false` (default) | `true` |
|---|---|---|---|
| `POST /console/admin/scenarios` | `allow_save_draft` | Dry-run validate only | Actually create scenario |
| `POST /console/admin/scenarios/{id}/publish` | `allow_expose` | Dry-run validate only | Actually publish |
| `POST /console/admin/scenarios/{id}/draft` | *(none)* | N/A | Save draft directly |
| `DELETE` draft endpoint | — | — | **Unchanged** |

### Dry-run Behavior (query=false) — Always HTTP 400

Dry-run **always** returns HTTP 400 (never 200), because the server refuses to save. The body `code` distinguishes outcomes:

| Outcome | HTTP | Body Code | Meaning |
|---|---|---|---|
| Validation passed | 400 | `9801-50006` (SCENARIO_NOT_ALLOW_SAVE) | Valid data, but save not allowed |
| Invalid payload | 400 | `9801-90101` (INVALID_PARAMETER) | Bad request format |
| Duplicate scenario name | 400 | `9801-50003` (SCENARIO_NAME_ALREADY_EXISTS) | Name conflict |
| Duplicate step name | 400 | `9801-50101` (STEP_NAME_DUPLICATE) | Step name conflict |
| Block not available | 400 | `9801-40006` (BLOCK_UNAVAILABLE) | Block dependency missing |

### Real Call Behavior (query=true)

| Outcome | HTTP | Body Code |
|---|---|---|
| Success | 200 | `"0"` (SUCCESS) with `data: { id }` |
| Validation fails (BE second guard) | 400 | Specific error code (same as above, minus SCENARIO_NOT_ALLOW_SAVE) |

### Key Frontend Implication

Since `apiFetch` throws on non-2xx, **all dry-run responses will throw**. The validate wrapper functions must catch HTTP 400 and check body code:
- `SCENARIO_NOT_ALLOW_SAVE` → treat as success (return normalized success response)
- Any other code → re-throw for hooks to handle

---

## Architecture Decision: Wrapper Functions vs Single Endpoint

### Option A — Separate validate wrappers (Recommended)

```
postScenario(data)                    → POST /scenarios?allow_save_draft=true
postValidateCreate(data)              → POST /scenarios?allow_save_draft=false
postScenarioPublish({data, id})       → POST /scenarios/{id}/publish?allow_expose=true
postValidatePublish({data, id})       → POST /scenarios/{id}/publish?allow_expose=false
postScenarioDraft({data, id})         → POST /scenarios/{id}/draft
```

| Pro | Con |
|---|---|
| Hooks don't manage query params | 4 functions for 2 endpoints |
| Intent clear from function name | Must keep paired functions in sync |
| Dry-run 400-as-success encapsulated in wrapper | — |
| Minimal hook-layer changes | — |
| Old `postValidateScenario` splits naturally (create has no `id`, publish needs `id`) | — |

### Option B — Single function per endpoint with boolean param

```
postScenario(data, allowSaveDraft = true)
postScenarioPublish({data, id, allowExpose = true})
```

| Pro | Con |
|---|---|
| 1:1 mapping to actual endpoints | Hooks must manage boolean — harder to read |
| Fewer functions | 400-as-success handling bleeds into hooks |
| — | More changes to existing hook code |

### Recommendation: **Option A**

The old `postValidateScenario({ data, id })` naturally splits into two functions because create validation needs no `id` while publish validation does. Wrappers encapsulate the 400-as-success pattern for dry-run. Naming makes intent explicit.

---

## Changes Overview

### Layer 0: Error Codes (`06-shared/config/error-codes.ts`)

Add missing error code:

```ts
export const ScenarioErrorCode = {
  // ... existing codes ...
  SCENARIO_NOT_ALLOW_SAVE: '9801-50006',  // NEW — dry-run validation passed, save not allowed
};
```

---

### Layer 1: Mock Layer (`05-entities/scenario/api/mock/`)

**Strategy:** Keep mocks but restructure to match real API behavior. Mocks now throw errors in the same format as `apiFetch` (error object with `.status` and `.body`). When real API is ready, just replace mock calls with `apiFetch` calls.

#### Update `mock-scenario-validate.ts`

Current mock returns `ApiBaseResponse` directly or throws it. New mock should throw errors that mimic `apiFetch` error format:

```ts
// Helper: create an error matching apiFetch's throw format
function createMockApiError(status: number, body: ApiBaseResponse<unknown>) {
  const error = new Error(`[HTTP ${status}]`) as Error & {
    status: number; body: unknown;
  };
  error.status = status;
  error.body = body;
  return error;
}

// Dry-run validation mock — always throws (HTTP 400)
const mockDryRunValidate = (data: Partial<ScenarioPayload>): never | ApiBaseResponse<unknown> => {
  // Check for validation errors (using existing keyword-based mock triggers)
  if (data.name?.includes('error')) {
    throw createMockApiError(400, {
      code: ScenarioErrorCode.SCENARIO_NAME_ALREADY_EXISTS,
      message: 'SCENARIO_NAME_EXSITED',
      data: { name: data.name },
      // ... other ApiBaseResponse fields
    });
  }
  // ... other error checks (step, block) ...

  // Validation passed → still throw 400 with SCENARIO_NOT_ALLOW_SAVE
  throw createMockApiError(400, {
    code: ScenarioErrorCode.SCENARIO_NOT_ALLOW_SAVE,
    message: 'SCENARIO_NOT_ALLOW_SAVE',
    data: {},
    // ...
  });
};
```

**Error response structure:** Offending values go in the `data` field (specs finalizing, design for `data.name` with fallback).

**Single vs array:** Current mock returns single error code. `extractValidationErrors` normalizer checks for `cause.validations` array first (future-proof), then falls back to single code mapping.

---

### Layer 2: API Functions (`05-entities/scenario/api/`)

#### 2a. `post-scenario.ts` — Update mock to real-API-shaped call

```ts
// Currently: mock with delay + mockScenarioValidate
// New: mock that simulates POST /scenarios?allow_save_draft=true
// Later: swap with apiFetch('/console/admin/scenarios?allow_save_draft=true', ...)
async function postScenario(data: Partial<ScenarioPayload>): Promise<MutateScenarioResponse> {
  await delay();
  // Mock: validate then return success
  mockScenarioValidate(data);  // throws on error (simulates BE second guard)
  return createMockResponse({ id: Math.floor(Math.random() * 10000) });
}
```

#### 2b. NEW `post-validate-create.ts` — Dry-run create validation wrapper

```ts
// POST /console/admin/scenarios?allow_save_draft=false
// Catches HTTP 400 and normalizes: SCENARIO_NOT_ALLOW_SAVE → success, others → re-throw
async function postValidateCreate(data: Partial<ScenarioPayload>): Promise<MutateScenarioResponse> {
  try {
    await delay();
    mockDryRunValidate(data);  // always throws (mock simulates 400)
    // When real API: return apiFetch('/console/admin/scenarios?allow_save_draft=false', ...)
    throw new Error('unreachable');  // mock always throws
  } catch (error: any) {
    if (error.status === 400) {
      const body = error.body as ApiBaseResponse<unknown>;
      if (body.code === ScenarioErrorCode.SCENARIO_NOT_ALLOW_SAVE) {
        // Validation passed — return as success
        return { ...body, code: SUCCESS_CODE } as MutateScenarioResponse;
      }
    }
    throw error;  // Re-throw validation errors
  }
}
```

#### 2c. `post-scenario-distribution.ts` → **Rename to `post-scenario-publish.ts`**

```ts
// POST /console/admin/scenarios/{id}/publish?allow_expose=true
async function postScenarioPublish({ data, id }: { data: Partial<ScenarioPayload>, id: number }): Promise<MutateScenarioResponse> {
  await delay();
  return mockDistribution(data, id);  // keep existing mock, rename later
}
```

#### 2d. NEW `post-validate-publish.ts` — Dry-run publish validation wrapper

Same 400-catch pattern as 2b, but with `id` param:

```ts
async function postValidatePublish({ data, id }: { data: Partial<ScenarioPayload>, id: number }): Promise<MutateScenarioResponse> {
  try {
    await delay();
    mockDryRunValidate(data);  // always throws
    throw new Error('unreachable');
  } catch (error: any) {
    if (error.status === 400) {
      const body = error.body as ApiBaseResponse<unknown>;
      if (body.code === ScenarioErrorCode.SCENARIO_NOT_ALLOW_SAVE) {
        return { ...body, code: SUCCESS_CODE } as MutateScenarioResponse;
      }
    }
    throw error;
  }
}
```

#### 2e. `put-scenario-draft.ts` → **Rename to `post-scenario-draft.ts`**

```ts
// POST /console/admin/scenarios/{id}/draft  (was PUT, now POST)
async function postScenarioDraft({ data, id }: ...): Promise<MutateScenarioResponse> {
  await delay();
  return mockDraftSave(data, id);
}
```

#### 2f. `post-validate-scenario.ts` → **DELETE** (replaced by 2b + 2d)

---

### Layer 3: Query Options (`scenario-queries.ts`)

Update `scenarioKeys` and `scenarioOptions`:

**Renames:** `postDistribution` → `postPublish`, `putDraft` → `postDraft`, `validate` → split into `validateCreate` + `validatePublish`

```ts
const scenarioKeys = {
  all: ['scenario'] as const,
  list: (...) => ...,
  latest: (...) => ...,
  patch: () => [...scenarioKeys.all, 'patch'] as const,
  post: () => [...scenarioKeys.all, 'post'] as const,
  postDraft: () => [...scenarioKeys.all, 'post-draft'] as const,       // was putDraft
  deleteDraft: () => [...scenarioKeys.all, 'delete-draft'] as const,
  postPublish: () => [...scenarioKeys.all, 'post-publish'] as const,   // was postDistribution
  validateCreate: () => [...scenarioKeys.all, 'validate-create'] as const,  // NEW
  validatePublish: () => [...scenarioKeys.all, 'validate-publish'] as const, // NEW
  history: (...) => ...,
};

const scenarioOptions = {
  // ... list, latest, patch unchanged ...
  post: () => ({
    mutationKey: scenarioKeys.post(),
    mutationFn: (data: Partial<ScenarioPayload>) => postScenario(data),
  }),
  postDraft: () => ({                                                   // was putDraft
    mutationKey: scenarioKeys.postDraft(),
    mutationFn: ({ data, id }: ...) => postScenarioDraft({ data, id }),
  }),
  deleteDraft: () => ({ ... }),  // unchanged
  postPublish: () => ({                                                 // was postDistribution
    mutationKey: scenarioKeys.postPublish(),
    mutationFn: ({ data, id }: ...) => postScenarioPublish({ id, data }),
  }),
  validateCreate: () => ({                                              // NEW
    mutationKey: scenarioKeys.validateCreate(),
    mutationFn: (data: Partial<ScenarioPayload>) => postValidateCreate(data),
  }),
  validatePublish: () => ({                                             // NEW
    mutationKey: scenarioKeys.validatePublish(),
    mutationFn: ({ data, id }: ...) => postValidatePublish({ data, id }),
  }),
};
```

**Note:** `validateCreate` takes `data` only (no `id`). `validatePublish` takes `{ data, id }`.

---

### Layer 4: Error Handling (`use-catch-validation-error.ts`)

Add `extractValidationErrors` helper that normalizes API errors (single code or array) into the existing `MockErrorCause[]` format:

```ts
import { ScenarioErrorCode, BlockErrorCode, CommonErrorCode } from '@/shared/config/error-codes';

interface ValidationErrorCause {
  type: string;
  name: string;
}

function extractValidationErrors(error: any): ValidationErrorCause[] {
  const body = error?.body as ApiBaseResponse<unknown> | undefined;
  if (!body) return [];

  // Future-proof: if cause.validations array exists, use directly
  if (Array.isArray((body.cause as any)?.validations)) {
    return (body.cause as any).validations;
  }

  // Single error code → normalize to array
  const errorData = body.data as Record<string, any> | undefined;
  switch (body.code) {
    case ScenarioErrorCode.SCENARIO_NAME_ALREADY_EXISTS:
      return [{ type: 'ScenarioName', name: errorData?.name ?? '' }];
    case ScenarioErrorCode.STEP_NAME_DUPLICATE:
      return [{ type: 'StepName', name: errorData?.name ?? '' }];
    case BlockErrorCode.BLOCK_UNAVAILABLE:
      return [{ type: 'BlockVariable', name: errorData?.name ?? '' }];
    case CommonErrorCode.INVALID_PARAMETER:
      return [];  // General format error — no specific field to highlight
    default:
      return [];
  }
}
```

This approach:
- Works with current single-code responses from BE
- Auto-switches to array if BE adds `cause.validations` later (minimal change)
- Keeps existing `displayValidationError()` unchanged
- Maps from real API error codes (`9801-xxxxx`) to existing mock type strings (`ScenarioName`, `StepName`, `BlockVariable`)

---

### Layer 5: Hook Updates (`04-features/scenario/model/hooks/`)

All "distribution" references renamed to "publish".

#### 5a. `use-scenario-submit-trigger.ts` (Create Page — validate before add)

```diff
- const { mutateAsync } = useMutation(scenarioOptions.validate());
+ const { mutateAsync } = useMutation(scenarioOptions.validateCreate());

  const onAddTrigger = async () => {
-   const res = await mutateAsync({ data: scenarioFormToPayload(values), id: values.id! });
-   if (res && res.code === SUCCESS_CODE) {
+   try {
+     const res = await mutateAsync(scenarioFormToPayload(values));
+     if (res.code === SUCCESS_CODE) {
        addDraftDialog.onOpen();
-     return;
-   }
-   if (res && res.code === VALIDATE_CODE_ERR) {
-     const cause = res.cause?.validations as MockErrorCause[];
-     displayValidationError(cause);
+     }
+   } catch (error: any) {
+     if (error.status === 400) {
+       displayValidationError(extractValidationErrors(error));
+     }
    }
  };
```

**Key:** No more `id` param for create validation. Wrapper handles the 400→success normalization for `SCENARIO_NOT_ALLOW_SAVE`.

#### 5b. `use-distribution-trigger.ts` → **Rename to `use-publish-trigger.ts`**

```diff
- const { mutateAsync } = useMutation(scenarioOptions.validate());
+ const { mutateAsync } = useMutation(scenarioOptions.validatePublish());
  // Same try/catch pattern as 5a, keeps { data, id } params
```

#### 5c. `use-scenario-submit.ts` (Create Page — actual create)

Add try/catch for BE second guard (validation fail on real create call):

```diff
  const handleSubmit = async (values: ScenarioForm) => {
    const payload = scenarioFormToPayload(values, true);
-   const res = await mutateAsync(payload);
-   if (res.code === SUCCESS_CODE) {
+   try {
+     const res = await mutateAsync(payload);
+     if (res.code === SUCCESS_CODE) {
        queryClient.invalidateQueries({ queryKey: scenarioKeys.all });
        navigate(ROUTES.SCENARIO_MANAGE);
+     }
+   } catch (error: any) {
+     if (error.status === 400) {
+       displayValidationError(extractValidationErrors(error));
+     }
    }
  };
```

#### 5d. `use-distribution-scenario.ts` → **Rename to `use-publish-scenario.ts`**

Same try/catch pattern as 5c.

#### 5e. `use-draft-save.ts` (Edit Page — save draft)

```diff
- const { mutateAsync: saveDraft } = useMutation(scenarioOptions.putDraft());
+ const { mutateAsync: saveDraft } = useMutation(scenarioOptions.postDraft());
  // Existing try/catch stays — update error extraction:
  catch (error: any) {
-   if (error.code === VALIDATE_CODE_ERR) {
-     const cause = error.cause?.validations as MockErrorCause[];
-     displayValidationError(cause);
+   if (error.status === 400) {
+     displayValidationError(extractValidationErrors(error));
    }
  }
```

---

### Layer 6: Exports & Barrel Files

#### `05-entities/scenario/api/index.ts`
- Remove: `postValidateScenario`, `putScenarioDraft`, `postScenarioDistribution`
- Add: `postValidateCreate`, `postValidatePublish`, `postScenarioDraft`, `postScenarioPublish`

#### `05-entities/scenario/model/index.ts`
- Update re-exports: remove `VALIDATE_CODE_ERR`, keep `SUCCESS_CODE`
- Export new query keys/options names

#### UI component renames (distribution → publish)
- `04-features/scenario/ui/scenario-distribution/` → `scenario-publish/`
- `distribution-trigger-btn.tsx` → `publish-trigger-btn.tsx`
- `distribution-dialog.tsx` → `publish-dialog.tsx`
- Update imports in `scenario-form.tsx`

---

### Layer 7: Update `plan-policy.md`

Update the "Current API Implementation" section:

**Create Page:**

| Action | API | Function | Params |
|--------|-----|----------|--------|
| Validate (dry-run) | `POST /scenarios?allow_save_draft=false` | `postValidateCreate` | `Partial<ScenarioPayload>` |
| Add (create draft) | `POST /scenarios?allow_save_draft=true` | `postScenario` | `Partial<ScenarioPayload>` |

**Edit Page:**

| Action | API | Function | Params |
|--------|-----|----------|--------|
| Save Draft | `POST /scenarios/{id}/draft` | `postScenarioDraft` | `{ data, id }` |
| Delete Draft | `DELETE` (unchanged) | `deleteScenarioDraft` | `id: number` |
| Validate (dry-run) | `POST /scenarios/{id}/publish?allow_expose=false` | `postValidatePublish` | `{ data, id }` |
| Publish | `POST /scenarios/{id}/publish?allow_expose=true` | `postScenarioPublish` | `{ data, id }` |

---

## Files Summary

| File | Action |
|---|---|
| `06-shared/config/error-codes.ts` | Add `SCENARIO_NOT_ALLOW_SAVE: '9801-50006'` |
| `05-entities/scenario/api/mock/mock-scenario-validate.ts` | Restructure mock to throw apiFetch-style errors |
| `05-entities/scenario/api/post-scenario.ts` | Update mock shape (keep mock, match real API behavior) |
| `05-entities/scenario/api/post-scenario-distribution.ts` | **Rename** → `post-scenario-publish.ts` |
| `05-entities/scenario/api/put-scenario-draft.ts` | **Rename** → `post-scenario-draft.ts` |
| `05-entities/scenario/api/post-validate-scenario.ts` | **Delete** |
| `05-entities/scenario/api/post-validate-create.ts` | **New** — dry-run create wrapper |
| `05-entities/scenario/api/post-validate-publish.ts` | **New** — dry-run publish wrapper |
| `05-entities/scenario/api/index.ts` | Update exports |
| `05-entities/scenario/model/scenario-queries.ts` | Rename keys/options, split validate |
| `05-entities/scenario/model/index.ts` | Update re-exports |
| `04-features/scenario/model/hooks/use-catch-validation-error.ts` | Add `extractValidationErrors` |
| `04-features/scenario/model/hooks/scenario-add/use-scenario-submit-trigger.ts` | `validateCreate`, try/catch |
| `04-features/scenario/model/hooks/scenario-submit/use-scenario-submit.ts` | Add try/catch for BE guard |
| `04-features/scenario/model/hooks/scenario-distribution/use-distribution-trigger.ts` | **Rename** → `use-publish-trigger.ts`, `validatePublish` |
| `04-features/scenario/model/hooks/scenario-distribution/use-distribution-scenario.ts` | **Rename** → `use-publish-scenario.ts`, try/catch |
| `04-features/scenario/model/hooks/scenario-draft-manage/use-draft-save.ts` | `postDraft`, update error handling |
| `04-features/scenario/ui/scenario-distribution/` | **Rename dir** → `scenario-publish/` |
| `04-features/scenario/ui/scenario-distribution/distribution-trigger-btn.tsx` | **Rename** → `publish-trigger-btn.tsx` |
| `04-features/scenario/ui/scenario-distribution/distribution-dialog.tsx` | **Rename** → `publish-dialog.tsx` |
| `04-features/scenario/ui/scenario-form.tsx` | Update distribution → publish imports |
| `plan-policy.md` | Update API implementation tables |

---

## Open Items (Confirm During Implementation)

1. **Error `data` field structure**: When validation fails (400), the offending value goes in `data` — exact shape TBD (e.g. `{ name: string }` or `{ names: string[] }` for step duplicates). Design `extractValidationErrors` to handle both.
2. **Mock-to-real swap**: When API is ready, each API function just replaces the mock call with `apiFetch(url, options)`. The wrapper 400-catch logic in `postValidateCreate`/`postValidatePublish` stays the same.

---

## Verification

1. **Type check**: `pnpm tsc --noEmit` in scenario-console
2. **Create Page flow**: Fill form → click Add → dry-run validate (mock throws 400 with SCENARIO_NOT_ALLOW_SAVE → wrapper normalizes to success) → dialog opens → confirm → mock create succeeds → navigate
3. **Create Page validation error**: Set name containing 'error' → click Add → mock throws 400 with SCENARIO_NAME_ALREADY_EXISTS → hook catches → `displayValidationError` → field error shown
4. **Edit Page — Save Draft**: Edit → click Save Draft → `postScenarioDraft` → success toast
5. **Edit Page — Publish**: Click Publish → dry-run validate → dialog → confirm → mock publish → success dialog
6. **BE second guard**: Hooks catch unexpected 400 errors from real calls and display validation errors
