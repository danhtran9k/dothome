# Plan: Improve `by-summary` Skill

## Context

The `by-summary` skill splits an aggregated commit into ordered child commits guided by a summary markdown. It's meant to be a **general-purpose tool** reusable across different repos/branches. The current definition has several hardcoded values and ambiguities that limit reusability and robustness.

Two files define the skill:
- `.claude/skills/by-summary.md` — compact version (invocation entry point)
- `.claude/skills/by-summary/SKILL.md` — detailed version with Context section

---

## Improvements

### 0. Add Prerequisites Check phase (new Step 0)

**Current:** Step 1 "Resolve inputs" jumps straight into execution. If something is missing, it fails mid-way.
**Problem:** No upfront validation — failures surface late after partial work is done.
**Fix:** Add a **Step 0: Prerequisites Check** that runs before anything else.

**Behavior: User provides → use it. Not provided → auto-scan. Not found → error.**

```markdown
## Step 0: Prerequisites Check

Validate all required inputs and auto-discover defaults. Abort with a clear
error table before any git operations if anything is missing.

### Resolution order (per input)

1. User-provided value → validate it exists → use it
2. Not provided → auto-scan using defaults below → use if found
3. Not found → add to error list

### Inputs to check

| Input | Auto-scan strategy | Error if missing |
|-------|-------------------|-----------------|
| `SUMMARY_MD` | Scan `docs/**/*summary*.md`, `*.summary.md`, `.claude/**/*summary*.md` | "No summary markdown found. Provide SUMMARY_MD=<path>" |
| `BASE_COMMIT` / `BASE_SUBJECT` | `git log --format='%H %s' HEAD \| grep -m1 'BASE_SUBJECT'` | "No commit with subject 'X' found in history" |
| `SOURCE_BRANCH` | `git rev-parse --abbrev-ref HEAD` | "Cannot determine current branch" |
| `WORKTREE_PATH` | Check `../goal-rebase` exists | (optional — skip if not found) |
| Package manager | Check lockfiles: `pnpm-lock.yaml` > `package-lock.json` > `bun.lockb` | "No lockfile found" |
| Check commands | Scan `package.json` scripts + `turbo.json` tasks for `lint`/`eslint`, `check-types`/`tsc`, `build` | "Cannot find lint/typecheck/build scripts" |
| `OUTPUT_BRANCH` | Derive from `SOURCE_BRANCH` + `-split` suffix | (always derivable) |

### Output

Print a resolved configuration table:

```
┌─────────────────┬──────────────────────────┬────────┐
│ Input           │ Resolved Value           │ Source │
├─────────────────┼──────────────────────────┼────────┤
│ SUMMARY_MD      │ docs/sum-cc-short.md     │ user   │
│ BASE_COMMIT (A) │ 97f51db                  │ auto   │
│ TARGET (Z)      │ 468bd98                  │ auto   │
│ SOURCE_BRANCH   │ g-split                  │ auto   │
│ OUTPUT_BRANCH   │ g-split-out              │ user   │
│ Package manager │ pnpm                     │ auto   │
│ Lint command    │ pnpm lint                │ auto   │
│ Type check      │ pnpm check-types         │ auto   │
│ Build command   │ pnpm build               │ auto   │
│ DIFF_EXCLUDE    │ *.md                     │ user   │
│ COMMIT_SCOPE    │ bo                       │ default│
│ SKIP_HOOKS      │ false                    │ default│
└─────────────────┴──────────────────────────┴────────┘
```

If ANY required input cannot be resolved, print all errors at once
(not one-by-one) and abort.
```

This replaces the current Step 1 "Resolve inputs" which is too brief and mixes resolution with execution.

### 1. Replace hardcoded check commands with auto-detection

**Current:** `eslint -> tsc -> build` (hardcoded)
**Problem:** This repo uses `lint`, `check-types`, `build` — not `eslint`/`tsc`
**Fix:** Add a `CHECK_COMMANDS` parameter with auto-detection fallback:

```
- `CHECK_COMMANDS`: optional; default auto-detected from package.json/turbo.json
  Priority: look for scripts `lint` > `eslint`, then `check-types` > `tsc`, then `build`
```

Update all references (success conditions, steps 3/5/7/9) to use the resolved command names.

### 2. Make base commit subject configurable

**Current:** `A` is hardcoded to `chore: prep home`
**Problem:** Not reusable for other projects/workflows
**Fix:** Add a `BASE_SUBJECT` parameter:

```
- `BASE_SUBJECT`: optional; default `chore: prep home`
```

Or allow `BASE_COMMIT` as an explicit hash override:

```
- `BASE_COMMIT`: optional; if provided, use this hash directly instead of searching by subject
```

### 3. Make commit scope configurable

**Current:** `type(bo): subject` hardcodes scope to `bo`
**Problem:** Different projects use different scopes
**Fix:** Add a `COMMIT_SCOPE` parameter:

```
- `COMMIT_SCOPE`: optional; default `bo`. Used in commit messages as `type(SCOPE): subject`
```

### 4. Add diff exclusion patterns

**Current:** `git diff Z..Z'` with no exclusions
**Problem:** Docs (*.md) in the worktree may be updated independently
**Fix:** Add a `DIFF_EXCLUDE` parameter:

```
- `DIFF_EXCLUDE`: optional; glob patterns to exclude from final diff verification
  Example: `*.md` — the final check becomes `git diff Z..Z' -- ':!*.md'`
```

Update step 9 (final verification) and success condition 5.

### 5. Clarify "nearest" base commit resolution

**Current:** "nearest commit whose subject is exactly `chore: prep home`"
**Problem:** Multiple commits match. "Nearest" is ambiguous (nearest to HEAD? nearest ancestor?)
**Fix:** Change to:

```
Find `A` as the nearest ancestor of `Z` (on SOURCE_BRANCH) whose subject exactly matches `BASE_SUBJECT`.
Use: `git log --format='%H %s' SOURCE_BRANCH | grep -m1 'BASE_SUBJECT'`
```

### 6. Fix Context section in SKILL.md

**Current:** `!git diff --name-status HEAD~1..HEAD`
**Problem:** Only shows last commit's changes, not the full `A..Z` delta
**Fix:** Change to show the full range:

```
- Changed files A..Z: !`git log --oneline --all --grep='chore: prep home' -1 | cut -d' ' -f1 | xargs -I{} git diff --name-status {}..HEAD`
```

Or simpler — just remove the context line since the skill will compute `A..Z` itself in step 2.

### 7. Add retry limit for per-commit checks

**Current:** "apply minimal-impact edits within the same logical commit and retry" — no limit
**Problem:** Could loop indefinitely
**Fix:** Add explicit limit:

```
- If checks fail, apply minimal-impact edits and retry (max 3 attempts per commit).
- After 3 failed retries, abort and report the failure point with error details.
```

### 8. Clarify worktree usage

**Current:** "If `WORKTREE_PATH` is provided, operate from that worktree"
**Problem:** Unclear whether worktree is for reading `Z` state or for doing the replay
**Fix:** Clarify:

```
- `WORKTREE_PATH` provides the target tree state (`Z`). File content for replay is read from this path.
- The output branch is created and commits are replayed in the current repository (not the worktree).
```

### 9. Add dependency reordering guidance

**Current:** "Keep heading order as execution order"
**Problem:** Heading order may cause intermediate compile failures (e.g., types imported before they're changed)
**Fix:** Add a note:

```
- When heading order causes intermediate compile failures, the executor MAY reorder commits
  for compilability. Any reordering must be documented in the deviation report.
- Foundation changes (types, constants, shared config) SHOULD be applied before
  consuming changes (hooks, UI) when possible.
```

### 10. Deduplicate the two skill files

**Current:** `by-summary.md` and `SKILL.md` contain nearly identical content
**Problem:** Drift between the two files; unclear which is authoritative
**Fix:** Make `by-summary.md` the compact invocation spec (parameters + success conditions only). Make `SKILL.md` the full reference with detailed steps. Remove duplication by having `by-summary.md` reference `SKILL.md` for details.

### 11. Add `--no-verify` configurability

**Current:** Not mentioned
**Problem:** Git hooks (lint-staged, commitlint) fire on every replay commit — may be redundant with explicit check steps
**Fix:** Add parameter:

```
- `SKIP_HOOKS`: optional; default `false`. If `true`, passes `--no-verify` to git commit.
```

---

## Files to Modify

1. `.claude/skills/by-summary.md` — update parameters, success conditions, remove hardcoded values
2. `.claude/skills/by-summary/SKILL.md` — update Context, Steps, Defaults, Abort conditions

---

## Git Setup Readiness (for current run)

| Check | Status |
|-------|--------|
| Base `A` (`chore: prep home`) | OK — `97f51db` |
| Target `Z` (HEAD) | OK — `468bd98` |
| Working tree | Clean |
| Summary file | OK — `docs/sum-cc-short.md` (8 headings) |
| Package manager | OK — pnpm |
| Output branch | `g-split-out` |

**Ready to launch** after skill improvements are applied.

---

## Summary Issues (appendix — for your own review)

The cross-reference of `sum-cc-short.md` vs the actual delta found:
- 17 orphaned files (in delta but not listed in any heading)
- 4 double-counted files (in 2 headings)
- 3 wrong status claims
- 2 content inaccuracies (constant values, isDraft claim)
- File count says 83, delta has 84

These are config-level issues (in the summary, not the skill). The biggest gaps are 6 block-select files missing from §3, and 3 new shared config files not in any section.

---

## Verification

After applying skill improvements:
1. Invoke skill with `SUMMARY_MD=docs/sum-cc-short.md`
2. Verify it auto-detects `pnpm`, resolves `lint`/`check-types`/`build`
3. Verify it finds `A=97f51db`, `Z=468bd98`
4. Verify output branch `g-split-out` is created with commits matching headings
5. Verify `git diff 468bd98..g-split-out -- ':!*.md'` is empty
