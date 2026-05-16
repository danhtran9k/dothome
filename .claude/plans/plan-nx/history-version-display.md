# Plan: Add Documentation for Scenario Version Display Logic

## Context
The scenario list table displays version information for each scenario. Currently, the code shows either `v{version}` or `임시` (temporary), but there's no documentation explaining when each case appears. The logic needs clarification:

- **임시 (temporary)**: Shown when `version` is falsy - indicates the scenario has **never been published** (brand new draft)
- **v{number}**: Shown when `version` exists - indicates the scenario has been published at least once

The scenario lifecycle follows this flow:
1. **Initial creation**: Draft with no version (shows `임시`)
2. **First publish**: Becomes v1
3. **Subsequent publishes**: v2, v3, etc.
4. **Draft from published version**: Retains version number (e.g., v1, v2), NOT `임시`

The key insight: Once a scenario has been published, it will **always** have a version number, even when saved as a draft again. The `임시` label specifically indicates a scenario that has never been published.

## Changes Required

### File: `apps/scenario-console/src/fsd/03-widgets/scenario-list/ui/scenario-list-table.tsx`

**Location**: Line 34-35 (version case in render function)

**Change**: Add a JSDoc comment above the `case 'version':` block explaining the version display logic

**Comment to add**:
```typescript
// Version display logic in this table:
// This table shows the latest PUBLISHED version of each scenario, regardless of its current state (draft or published).
//
// - "임시" (temporary): Appears ONLY when the scenario has NEVER been published.
//   This includes:
//   - Brand new drafts created via POST /admin/scenarios
//   - Edits to those unpublished drafts (version remains falsy)
//
// - "v{number}": Appears when the scenario has been published at least once.
//   Once published, the version number is retained even if a new draft is created from it.
//   For example: v1 (published) → create draft → still shows v1 in this table
//
// Scenario lifecycle:
// - Initial creation: draft with no version → shows "임시"
// - Save draft again: still no version → still shows "임시"
// - First publish: v1
// - Subsequent publishes: v2, v3, etc.
// - Create draft from v2: table still shows v2 (not 임시)
//
// Note: To see the actual draft version number, check the draft tab in the history dialog.
//       This table only displays the latest published version.
```

## Implementation Steps

1. Open `apps/scenario-console/src/fsd/03-widgets/scenario-list/ui/scenario-list-table.tsx`
2. Locate the `case 'version':` block (line 34)
3. Add the explanatory comment above it
4. Ensure the comment clearly distinguishes between:
   - Brand new drafts (never published) → 임시
   - Published/drafts of published scenarios → v{number}

## Verification

1. Review the comment for clarity and accuracy
2. Ensure the explanation matches the API documentation behavior
3. Confirm the comment helps developers understand when 임시 vs v{number} appears
