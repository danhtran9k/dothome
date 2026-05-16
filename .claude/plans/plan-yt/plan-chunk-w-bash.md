# Plan: Reduce context load in chunk_reducer assembly phase

## Context

The current `chunk_reducer.md` Phase 2 uses a single assembly agent that reads ALL chunk files and ALL boundary files simultaneously. For long videos with many chunks, this creates a massive context spike. The fix is to split Phase 2 into three sub-phases that distribute the work.

## Critical file

- `.claude/commands/chunk_reducer.md` — full replacement of Phase 2

## Changes

### Phase 1 — unchanged
Only text edit: last sentence of N==1 skip note changes from "Go directly to Phase 2." → "Go directly to Phase 2a."

### Phase 2 — replace entirely with 2a + 2b + 2c

---

**Phase 2a: Pre-trim (parallel, N agents)**

Before launching, Glob `<OUTPUT_DIR>/temps/trimmed_chunk_*.txt` and skip already-done chunks (resumability).

Launch all missing trim agents in one message (parallel). Each agent i:

1. Read `chunk_i.txt` (always) + `boundary_{i-1}.txt` (if i > 1) + `boundary_i.txt` (if i < N)
2. **Left trim**: if `boundary_{i-1}` = OVERLAP → find section headed by `RIGHT_REPLACE_UNTIL`, discard it and everything before it; begin at the next `## ` heading
3. **Right trim**: if `boundary_i` = OVERLAP → find section headed by `LEFT_REPLACE_FROM`, discard it and everything after it; append the full `MERGED` block from `boundary_i.txt`
4. **Extract KT**: collect all `-` bullet lines under every `### Key Takeaway` block in the trimmed content (incl. inside MERGED) → write as flat bullet list to `temps/kt_i.txt` (no headings, just bullets)
5. Write trimmed body (all headings, bullets, `### Key Takeaway` blocks preserved) to `temps/trimmed_chunk_i.txt`
6. Return: `"trim chunk i done"`

N=1 edge case: no boundary files → left/right trim steps are no-ops; agent just writes trimmed = full chunk_1.txt and extracts kt_1.txt.

---

**Phase 2b: Synthesis (1 small agent)**

Reads ONLY: `meta.txt` + `kt_1.txt` … `kt_N.txt` (no chunk files).

1. Write `temps/header_summary.txt`:
   ```
   # <TITLE>
   <URL>
   ---
   <2-3 sentence overall summary from KT bullets, in SUMMARY_LANG>

   ```
   *(trailing blank line required for clean cat join)*

2. Write `temps/consolidated_kt.txt`:
   ```
   ## Key Takeaways
   - <bullet>
   ...
   ```
   Consolidate + deduplicate from all kt files, in SUMMARY_LANG.

Return: `"synthesis done"`

---

**Phase 2c: Bash assembly**

Use the Bash tool to run:
```bash
cat "<OUTPUT_DIR>/temps/header_summary.txt" \
    "<OUTPUT_DIR>/temps/trimmed_chunk_1.txt" \
    ... \
    "<OUTPUT_DIR>/temps/trimmed_chunk_N.txt" \
    "<OUTPUT_DIR>/temps/consolidated_kt.txt" \
    > "<OUTPUT_DIR>/<TITLE>.md"
```

List chunks 1 to N in order, all paths quoted. Then confirm: `"Final output written: <OUTPUT_DIR>/<TITLE>.md"`.

---

## New temp files introduced

| File | Written by | Content |
|------|-----------|---------|
| `temps/trimmed_chunk_i.txt` | Phase 2a agent i | Trimmed section content |
| `temps/kt_i.txt` | Phase 2a agent i | Flat KT bullet list (no headings) |
| `temps/header_summary.txt` | Phase 2b agent | Title, URL, separator, overall summary |
| `temps/consolidated_kt.txt` | Phase 2b agent | `## Key Takeaways` + bullets |

## Context savings

| Step | Old | New |
|------|-----|-----|
| Assembly context | All N chunks + N-1 boundaries | 0 chunk files |
| Per-trim context | — | 1 chunk + ≤2 boundary files |
| Synthesis context | — | meta.txt + N kt files (small) |

## Verification

Run `/yt-sum` on a multi-chunk video and confirm:
- All `trimmed_chunk_*.txt` and `kt_*.txt` files appear in `temps/`
- `header_summary.txt` and `consolidated_kt.txt` appear in `temps/`
- Final `<TITLE>.md` is complete with header, body, and Key Takeaways
- Re-running reducer skips already-trimmed chunks (resumability)
