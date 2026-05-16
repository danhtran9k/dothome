# Plan: Create `plan-policy.md` - Scenario Action Policies

## Context
Document the enable/disable conditions for every action button across the Scenario Create and Edit pages. This serves as a reference for the team to understand the current validation rules and action policies at a glance.

## Task
Create `apps/scenario-console/src/fsd/04-features/scenario/plan-policy.md` summarizing:

### Content Structure

**1. Shared Concepts**
- `isValid` — Formik schema validation (name required/unique, steps >= 1, step names unique, layout type valid)
- `isNoEmptySteps` — `values.steps.every(({ blocks }) => blocks.length > 0)`
- `dirty` — Formik deep-equality check of `values` vs `initialValues`
- `isDraft` — `!values.version || values.state === 'DRAFT'`

**2. Create Page Actions**
| Action | Condition |
|---|---|
| Preview | `isValid` |
| Add (create draft) | `isValid && isNoEmptySteps` |

**3. Edit Page Actions**
| Action | Condition |
|---|---|
| Preview | `isValid` |
| Save Draft | `dirty && isValid` |
| Delete Draft | `version >= 1 && state === DRAFT` (hidden otherwise) |
| Distribute | `isValid && isNoEmptySteps && (isDraft \|\| dirty)` |

**4. Notes**
- Preview and Save Draft do NOT require `isNoEmptySteps`; Add and Distribute do.
- Delete Draft is conditionally rendered (hidden entirely when not applicable), not just disabled.
- All actions except Delete Draft and Preview rely on Formik's `isValid`.
- Post-click, Add and Distribute also run a backend validation API that can surface additional errors (duplicate names, block variable issues).

## Key Source Files
- `apps/scenario-console/src/fsd/04-features/scenario/lib/validation/scenario-validation.ts`
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-distribution/use-distribution-trigger.ts`
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-draft-manage/use-draft-save.ts`
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-draft-manage/use-draft-delete.ts`
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/scenario-add/use-scenario-submit-trigger.ts`
- `apps/scenario-console/src/fsd/04-features/scenario/ui/scenario-preview/scenario-preview-btn.tsx`

## Verification
- Review the created file for accuracy against the source hooks listed above.
