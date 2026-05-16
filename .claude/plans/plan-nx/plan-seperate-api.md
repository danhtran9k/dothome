# Consolidate Scenario Validation and Mutation Operations

## Context

The scenario feature currently has separate mutations for validation and actual operations:
- `validateCreate` (validation-only) vs `post` (actual creation)
- `validatePublish` (validation-only) vs `postPublish` (actual publishing)

This separation creates duplication and inconsistency. The backend API uses the same endpoint with query parameters (`allow_save_draft` and `allow_expose`) to control whether operations are dry-run validation or actual execution. Additionally, `validatePublish` incorrectly calls `postPublish()` instead of a dedicated validation function.

This refactoring will:
1. Consolidate create/validate into a single `post` mutation with `allow_save_draft` parameter
2. Consolidate publish/validate into a single `postPublish` mutation with `allow_expose` parameter
3. Ensure 400 error handling is consistent across both modes
4. Remove duplicate validation functions

## Implementation Approach

### 1. Update API Functions

**File: `apps/scenario-console/src/fsd/05-entities/scenario/api/post-scenario.ts`**

Modify `postScenario()` to accept `allow_save_draft` parameter and handle both modes:
- When `allow_save_draft=true` (or default): use `mockScenarioValidate()` for real creation
- When `allow_save_draft=false`: use `mockDryRunValidate()` and convert SCENARIO_NOT_ALLOW_SAVE to success

Current signature:
```typescript
postScenario({data, params}: { data: Partial<ScenarioPayload>, params?: PostScenarioParams })
```

Implementation logic:
```typescript
const allowSaveDraft = params?.allow_save_draft ?? true;

if (allowSaveDraft) {
  // Real creation mode
  mockScenarioValidate(data, mockId);
  return createMockResponse({ id: mockId });
} else {
  // Dry-run validation mode
  try {
    mockDryRunValidate(data);
    throw new Error('unreachable');
  } catch (error: any) {
    if (error.status === HttpStatus.BAD_REQUEST) {
      const body = error.body as { code: string };
      if (body.code === ScenarioErrorCode.SCENARIO_NOT_ALLOW_SAVE) {
        return { ...error.body, code: SUCCESS_CODE } as MutateScenarioResponse;
      }
    }
    throw error;
  }
}
```

**File: `apps/scenario-console/src/fsd/05-entities/scenario/api/post-publish.ts`**

Modify `postPublish()` to accept `allow_expose` parameter via params:
- Update signature to accept `params?: PostPublishParams`
- When `allow_expose=true` (or default): use `mockDistribution()` for real publishing
- When `allow_expose=false`: use `mockDryRunValidate()` and convert SCENARIO_NOT_ALLOW_SAVE to success

Implementation logic similar to `postScenario()` above.

### 2. Update Type Definitions

**File: `apps/scenario-console/src/fsd/05-entities/scenario/model/scenario-types.ts`**

Ensure `PostPublishParams` includes `allow_expose`:
```typescript
interface PostPublishParams {
  id: number
  allow_expose?: boolean
}
```

Update the mutation signature type:
```typescript
// For postPublish mutation
{ data: Partial<ScenarioPayload>, id: number, params?: PostPublishParams }
```

### 3. Update Mutation Options

**File: `apps/scenario-console/src/fsd/05-entities/scenario/model/scenario-queries.ts`**

Remove `validateCreate` and `validatePublish` options and keys:
- Delete lines 13-14 (validateCreate and validatePublish keys)
- Delete lines 39-44 (validateCreate option)
- Delete lines 72-77 (validatePublish option)

Update `postPublish` mutation signature (line 68):
```typescript
mutationFn: ({ data, id, params }: { data: Partial<ScenarioPayload>, id: number, params?: PostPublishParams }) =>
  postPublish({ id, data, params }).then(res => res),
```

### 4. Update Usage Sites

**File: `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-add/use-scenario-submit-trigger.ts`**

Line 18: Change from `validateCreate()` to `post()`:
```typescript
const { mutateAsync, isPending } = useMutation(scenarioOptions.post());
```

Line 22: Update mutation call to pass `allow_save_draft=false`:
```typescript
const res = await mutateAsync({
  data: scenarioFormToPayload(values),
  params: { allow_save_draft: false }
});
```

**File: `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-publish/use-publish-trigger.ts`**

Line 21: Change from `validatePublish()` to `postPublish()`:
```typescript
const { mutateAsync, isPending: isValidating } = useMutation(scenarioOptions.postPublish());
```

Line 25: Update mutation call to pass `allow_expose=false`:
```typescript
const res = await mutateAsync({
  data: scenarioFormToPayload(values),
  id: values.id!,
  params: { allow_expose: false }
});
```

**File: `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-submit/use-scenario-submit.ts`**

Update mutation call to explicitly pass `allow_save_draft=true` (or rely on default):
```typescript
await mutateAsync({
  data: payload,
  params: { allow_save_draft: true }
});
```

**File: `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-publish/use-publish-scenario.ts`**

Update mutation call to explicitly pass `allow_expose=true` (or rely on default):
```typescript
await mutateAsync({
  data: scenarioFormToPayload(values),
  id: values.id!,
  params: { allow_expose: true }
});
```

### 5. Remove Deprecated Files

Delete these files:
- `apps/scenario-console/src/fsd/05-entities/scenario/api/post-scenario-validate.ts`
- `apps/scenario-console/src/fsd/05-entities/scenario/api/post-publish-validate.ts`

**File: `apps/scenario-console/src/fsd/05-entities/scenario/api/index.ts`**

Remove exports for deleted functions:
- Remove `postValidateScenario` export
- Remove `postPublishValidate` (or similar) export

### 6. Import Updates

Check and update imports in files that may have imported the removed validation functions. The exploration found these are only used in `scenario-queries.ts`, which will be updated in step 3.

## Critical Files

- `apps/scenario-console/src/fsd/05-entities/scenario/api/post-scenario.ts` - Consolidate create/validate
- `apps/scenario-console/src/fsd/05-entities/scenario/api/post-publish.ts` - Consolidate publish/validate
- `apps/scenario-console/src/fsd/05-entities/scenario/model/scenario-queries.ts` - Remove separate mutations
- `apps/scenario-console/src/fsd/05-entities/scenario/model/scenario-types.ts` - Update PostPublishParams
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-add/use-scenario-submit-trigger.ts` - Use post with allow_save_draft=false
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-publish/use-publish-trigger.ts` - Use postPublish with allow_expose=false
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-submit/use-scenario-submit.ts` - Explicit allow_save_draft=true
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-publish/use-publish-scenario.ts` - Explicit allow_expose=true

## Mock Logic

The existing mock validation logic doesn't require changes:
- `mockScenarioValidate()` - Throws 400 on validation error, returns void on success (for real calls)
- `mockDryRunValidate()` - Always throws 400 (validation error OR SCENARIO_NOT_ALLOW_SAVE for success)

The consolidated API functions will call the appropriate mock based on the parameter value.

## Error Handling Consistency

Both dry-run and non-dry-run modes handle 400 validation errors identically:
- Validation errors throw 400 with specific error codes (SCENARIO_NAME_ALREADY_EXISTS, STEP_NAME_DUPLICATE, etc.)
- Feature layer catches 400 errors and displays validation messages via `displayValidationError()`

The only difference is in the success case:
- Dry-run mode: 400 with SCENARIO_NOT_ALLOW_SAVE → converted to SUCCESS_CODE
- Non-dry-run mode: Returns success response directly

## Verification

After implementation:

1. **Test Create Flow:**
   - Open scenario add form
   - Click submit (should trigger validation with `allow_save_draft=false`)
   - Verify validation dialog opens on success
   - Confirm creation (should call `post` with `allow_save_draft=true`)
   - Verify scenario is created

2. **Test Publish Flow:**
   - Open scenario edit form with draft
   - Click publish (should trigger validation with `allow_expose=false`)
   - Verify publish dialog opens on success
   - Confirm publish (should call `postPublish` with `allow_expose=true`)
   - Verify scenario is published

3. **Test Validation Errors:**
   - Enter "error" in scenario name (triggers SCENARIO_NAME_ALREADY_EXISTS)
   - Click submit - verify error message displays
   - Enter "step" in step name (triggers STEP_NAME_DUPLICATE)
   - Click submit - verify error message displays
   - Verify error handling works in both validation and actual operation modes

4. **Check TypeScript:**
   - Run `npm run type-check` (or equivalent)
   - Verify no type errors from signature changes

5. **Verify Imports:**
   - Confirm no broken imports for removed validation functions
   - Grep for `validateCreate` and `validatePublish` to ensure no remaining references
