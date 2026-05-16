# Plan: Parallelize Chunk Reducer Assembly Phase

## Context

The current `chunk_reducer` skill has a bottleneck in Phase 2 (Assembly): a single agent reads ALL chunk files and ALL boundary files simultaneously. For videos with many chunks (e.g., 20+), this creates:
- High memory/context usage
- Sequential processing bottleneck
- Scalability issues

## Proposed Architecture

**Current flow:**
```
Phase 1: Boundary agents (parallel) → boundary_i.txt files
Phase 2: 1 Assembly agent reads ALL chunks + boundaries → final.md
```

**New flow:**
```
Phase 1: Boundary agents (parallel) → boundary_i.txt files
Phase 2a: Trim agents (parallel) → trimmed_chunk_i.txt
Phase 2b: Bash cat + small agent → final.md
```

## Implementation

### Files to modify
- `.claude/commands/chunk_reducer.md` - Main reducer skill
- `.claude/commands/yt-sum.md` - May need minor updates to reference new flow

### Phase 2a: Parallel Trim Agents

After all boundary agents complete, launch **N trim agents in parallel** (one per chunk).

Each trim agent i handles one chunk:

**Dependencies:**
- Chunk 1: reads `boundary_1.txt` only (right boundary)
- Chunk i (2 ≤ i ≤ N-1): reads `boundary_{i-1}.txt` and `boundary_i.txt`
- Chunk N: reads `boundary_{N-1}.txt` only (left boundary)

**Trim logic:**

For **chunk 1**:
- If `boundary_1.txt` says `OVERLAP`: include content up to (but not including) `LEFT_REPLACE_FROM`, then append `MERGED` block
- Else: include all content

For **chunk i** (2 ≤ i ≤ N-1):
- **Start:** If `boundary_{i-1}.txt` says `OVERLAP`, skip up to and including `RIGHT_REPLACE_UNTIL`
- **End:** If `boundary_i.txt` says `OVERLAP`, include up to (but not including) `LEFT_REPLACE_FROM`, then append `MERGED` block
- Else for either: include fully from determined start to end

For **chunk N**:
- If `boundary_{N-1}.txt` says `OVERLAP`: skip up to and including `RIGHT_REPLACE_UNTIL`, include rest
- Else: include all content

**Output per trim agent:**
- Write `<OUTPUT_DIR>/temps/trimmed_chunk_i.txt` using Write tool
- Extract and write `<OUTPUT_DIR>/temps/kt_i.txt` containing only the `### Key Takeaway` sections from this chunk (for parallel KT synthesis)

**Return:** `"chunk i trimmed, overlap: left/right/none/both"`

### Phase 2b: Lightweight Final Assembly

After all trim agents complete:

1. **Use Bash tool** to concatenate trimmed chunks:
   ```bash
   cat <OUTPUT_DIR>/temps/trimmed_chunk_*.txt > <OUTPUT_DIR>/temps/body.md
   ```

2. **Launch one small agent** with minimal context:
   - Read `<OUTPUT_DIR>/temps/meta.txt` for URL and TITLE
   - Read `<OUTPUT_DIR>/temps/body.md` for main content
   - Read all `<OUTPUT_DIR>/temps/kt_*.txt` files for Key Takeaways synthesis

3. **Write final file** `<OUTPUT_DIR>/<TITLE>.md`:
   ```markdown
   # <TITLE>
   <URL>
   ---
   <2-3 sentence overall summary (in SUMMARY_LANG)>

   <body.md content>

   ## Key Takeaways
   <consolidated KT from all kt_i.txt files (in SUMMARY_LANG)>
   ```

## Benefits

1. **Parallelization**: N trim agents work independently instead of 1 agent doing everything sequentially
2. **Reduced context per agent**: Each trim agent reads 1 chunk + 2 boundaries (small), not all chunks
3. **Scalability**: Linear scaling with number of chunks
4. **Memory efficiency**: No single agent loads all content at once

## Verification

Test with a video that produces 10+ chunks:
1. Run `/yt-sum` with the URL
2. Verify all `trimmed_chunk_i.txt` files are created
3. Verify `kt_i.txt` files contain extracted Key Takeaways
4. Verify final `<TITLE>.md` has proper structure with no duplicate content
5. Compare with original flow output to ensure correctness

## Edge Cases

- **N == 1**: Skip Phase 1 entirely, trim agent just copies chunk to trimmed_chunk_1.txt
- **All NO_OVERLAP**: Trim agents copy chunks as-is, no merging needed
- **All OVERLAP**: Each trim agent applies both left and right merge rules
