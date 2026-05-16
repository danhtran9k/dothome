# Plan-Policy vs Implementation Audit

## Context
Verifying the scenario form button enable/disable conditions, validation schema, and rendering logic against `plan-policy.md`.

---

## Audit Results: Policy vs Implementation

### All conditions that MATCH correctly

| Action | Policy Condition | Implementation | File | Verdict |
|---|---|---|---|---|
| Preview | `isValid` | `disabled={!isValid}` | `scenario-preview-btn.tsx:12` | MATCH |
| Add (create) | `isValid && isNoEmptySteps` | `canSubmit = isValid && isNoEmptySteps` | `use-scenario-submit-trigger.ts:15` | MATCH |
| Save Draft | `dirty && isValid` | `canSaveDraft = dirty && isValid` | `use-draft-save.ts:18` | MATCH |
| Delete Draft | `version >= 1 && state === DRAFT` (hidden, not disabled) | `canDeleteDraft && (...)` conditional render | `draft-delete-btn.tsx:8`, `use-draft-delete.ts:17` | MATCH |
| Distribute | `isValid && isNoEmptySteps && (isDraft \|\| dirty)` | `canDistribute = isScenarioFormValid && (isDraft \|\| dirty)` | `use-distribution-trigger.ts:17` | MATCH |
| isDraft | `!values.version \|\| values.state === 'DRAFT'` | `!values.version \|\| values.state === SCENARIO_STATE.DRAFT` | `use-distribution-trigger.ts:15` | MATCH |
| isNoEmptySteps | `values.steps.every(({ blocks }) => blocks.length > 0)` | `values.steps && values.steps.every(...)` (extra null guard) | 2 hooks | MATCH |
| Schema | name req/unique/50, steps>=1, step names req/unique/50, layout oneOf | All validated in Yup schema | `scenario-validation.ts` | MATCH |
| Backend validation | Add & Distribute trigger validate API | Both call `mutateAsync` (validate endpoint) | 2 trigger hooks | MATCH |
| Create page buttons | Preview + Add | `isSetting=false` branch | `scenario-form.tsx:33-37` | MATCH |
| Edit page buttons | Distribute + DeleteDraft + Preview + SaveDraft | `isSetting=true` branch | `scenario-form.tsx:23-31` | MATCH |

---

## Issues Found

### Bug 1: Debug `console.log` left in production code
- **File**: `use-distribution-trigger.ts:20`
- **Code**: `console.log({ isValid, isNoEmptySteps, isDraft, dirty });`
- **Impact**: Logs form state to browser console on every render. Should be removed.

### Bug 2 (Minor/UX): No client-side step name dedup within form
- **File**: `scenario-validation.ts:13-16`
- **Current**: Step name uniqueness only validates against `existedStepNames` from the Zustand store (populated by backend validation errors). It does NOT check for duplicate names among sibling steps within the same form.
- **Effect**: A user can name two steps "Step A" and "Step A" — the form stays `isValid=true` until they click Add/Distribute and the backend returns an error. The feedback is delayed rather than immediate.
- **Note**: This might be intentional by design (backend-driven uniqueness). Flag for discussion.

---

## Proposed Fix

### Fix 1: Remove console.log
**File**: `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-distribution/use-distribution-trigger.ts`
- Delete line 20: `console.log({ isValid, isNoEmptySteps, isDraft, dirty });`

### Fix 2 (Optional): Add client-side step name sibling uniqueness
**File**: `apps/scenario-console/src/fsd/04-features/scenario/lib/validation/scenario-validation.ts`
- Add a Yup `.test()` on the `steps` array that checks no two steps share the same name.
- This would give immediate feedback instead of waiting for backend validation.

---

## Verification
- Check the Distribute button no longer logs to console
- If Fix 2 is applied: create two steps with the same name and verify the form shows invalid immediately
