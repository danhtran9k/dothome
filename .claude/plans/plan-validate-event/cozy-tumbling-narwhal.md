# Post-Publish Query Invalidation — Approach Analysis

## Context

After a successful publish in `handlePublish` (`use-publish-scenario.ts:51-74`), the current code immediately calls:

```ts
await queryClient.invalidateQueries({ queryKey: scenarioKeys.all });
```

This triggers `useScenarioLatest` to refetch. Because the edit page (`edit.tsx`) has `enableReinitialize={true}` on Formik, the form **resets** with the new server data (version bumped, state changed, `note` cleared, etc.) while the success dialog is still open. The form state no longer matches what the user just published.

### Critical Files
- `apps/scenario-console/src/fsd/03-widgets/scenario-form/model/use-publish-scenario.ts` — mutation + invalidation logic
- `apps/scenario-console/src/fsd/03-widgets/scenario-form/ui/publish-trigger-btn.tsx` — dialog UI
- `apps/scenario-console/src/fsd/02-pages/scenario/ui/edit.tsx` — Formik with `enableReinitialize={true}`
- `apps/scenario-console/src/fsd/04-features/scenario/model/hooks/use-scenario-latest.ts` — query hook
- `apps/scenario-console/src/fsd/05-entities/scenario/model/scenario-queries.ts` — query keys + options

---

## Approach A: `refetchType: 'inactive'`

**Change:** One line in `use-publish-scenario.ts`

```ts
// Before
await queryClient.invalidateQueries({ queryKey: scenarioKeys.all });

// After
await queryClient.invalidateQueries({ queryKey: scenarioKeys.all, refetchType: 'inactive' });
```

**How it works:**
- Marks ALL scenario queries as **stale** in the cache
- Only triggers refetch for queries that are **not currently mounted/observed**
- The active `useScenarioLatest` on the edit page does NOT refetch immediately
- When the user navigates away and comes back (or another component mounts), React Query sees the stale flag and refetches automatically

**Pros:**
- Minimal code change (1 line)
- Form stays completely stable after publish
- Other pages (list, etc.) will get fresh data when they mount
- Follows React Query's built-in staleness model

**Cons:**
- If user stays on the same page, form shows old data (pre-publish version/state) until they navigate away
- If another component on the SAME page uses a different scenario query, it also won't refetch (since it's mounted)

**Risk level:** Low

---

## Approach B: Navigate away after publish success

**Change:** In `publish-trigger-btn.tsx`, after user confirms the success dialog, navigate to the scenario list page.

```ts
// In PublishTriggerBtn or handlePublish
const navigate = useNavigate();

// After success dialog confirm:
onConfirm={isConfirmDialog ? handlePublish : () => {
  dialog.onClose();
  navigate('/scenarios'); // or wherever the list page is
}}
```

Keep the existing `invalidateQueries` as-is (immediate).

**How it works:**
- Publish succeeds → invalidateQueries runs → success dialog shows
- User clicks "확인" on success dialog → navigates to list page
- Form unmounts before refetch completes, so no form-reset issue
- List page mounts with fresh data from the invalidated/refetched query

**Pros:**
- Natural UX flow — user published, done editing, goes back to list
- No stale data anywhere — invalidation is immediate and complete
- Simple mental model

**Cons:**
- Forces navigation — user can't stay on the edit page after publishing
- Requires knowing the correct navigation target
- Changes UX behavior (may or may not be desired)

**Risk level:** Low, but UX change

---

## Approach C: Defer invalidation to unmount

**Change:** Remove `invalidateQueries` from `handlePublish`. Add a ref-based cleanup.

```ts
const publishedRef = useRef(false);

const handlePublish = async () => {
  // ... existing logic ...
  if (data.code === SUCCESS_CODE) {
    publishedRef.current = true;
    dialog.onClose('ok');
  }
};

useEffect(() => {
  return () => {
    if (publishedRef.current) {
      queryClient.invalidateQueries({ queryKey: scenarioKeys.all });
    }
  };
}, [queryClient]);
```

**How it works:**
- On successful publish, sets a ref flag (no re-render)
- When the component/page unmounts (user navigates away), the cleanup runs invalidation
- Form stays completely stable during the entire session

**Pros:**
- Form stays stable — no reset at all while on the page
- Simple to understand — "invalidate when leaving"

**Cons:**
- If user stays on the page indefinitely, ALL scenario data across the app is stale
- If another tab/window shows scenario data, it won't update until this page unmounts
- Cleanup effects can be unreliable in edge cases (fast navigation, React strict mode double-unmount)
- If user makes further edits after publish (without leaving), the form still shows pre-publish initialValues — `dirty` flag will be wrong

**Risk level:** Medium

---

## Approach D: Combine A + B (`refetchType: 'inactive'` + navigate)

**Change:** Both the `refetchType: 'inactive'` change AND navigation on dialog confirm.

```ts
// use-publish-scenario.ts
await queryClient.invalidateQueries({ queryKey: scenarioKeys.all, refetchType: 'inactive' });
dialog.onClose('ok');

// publish-trigger-btn.tsx — navigate on success dialog confirm
onConfirm={isConfirmDialog ? handlePublish : () => {
  dialog.onClose();
  navigate('/scenarios');
}}
```

**How it works:**
- Publish succeeds → queries marked stale but no immediate refetch on mounted queries
- Success dialog shows → user clicks confirm → navigates away
- When list page mounts, stale queries auto-refetch with fresh data

**Pros:**
- Belt and suspenders — even if navigation fails or is delayed, form won't reset
- Clean UX flow — publish → confirm → back to list
- All data is fresh on the next page

**Cons:**
- More changes than A alone
- Forces navigation (same as B)

**Risk level:** Low

---

## Recommendation

**Approach A** is the safest, smallest change that solves the immediate problem. If the product intent is for users to leave the page after publishing, **Approach D** adds a nice UX touch on top.

## Verification
- Publish a scenario → confirm form values don't reset while success dialog is open
- Close success dialog → verify form still shows consistent state
- Navigate to scenario list → verify list shows updated publish status
- Navigate back to the edit page → verify form shows the latest published data
- TypeScript check: `npm run tsc:alpha`
- Build check: `npm run build:alpha`
