# Fix: Duplicate Summary Overlap in YouTube Summarizer

## Context

When the YouTube summarizer processes long videos (split into multiple 500-line chunks), overlapping sections appear at chunk boundaries in the final summary. This happens because map agents read 10 context lines before their chunk start but incorrectly summarize content that originates in that context overlap.

**Example of the problem:**
- Chunk 4 (lines 1501-2000) includes section at [00:46:10] "Ancient Alien Civilizations"
- Chunk 5 (lines 2001-2500) also includes section at [00:46:00] "Ancient Civilizations" (same topic, slightly different timestamp)
- The reduce agent's smart-merge doesn't catch this because timestamps differ slightly

**Root cause:** Map agents aren't explicitly instructed to skip sections where the timestamp line falls in the context overlap area.

## Subtitle Format Structure

Each section in `subs_cleaned.txt` is exactly 2 lines:
```
Line 1: [HH:MM:SS]  ← timestamp line
Line 2: text content
```

No blank lines separate sections.

## Solution: Explicit Boundary Instructions for Map Agents

Update the **map agent prompt (step 7)** in `.claude/commands/yt-sum.md` to include explicit section boundary logic.

### File to Modify
- `.claude/commands/yt-sum.md`

### Changes Required

**1. Update step 7, line 80** - Replace the vague instruction:
```
- **For chunks 2+:** also read 10 lines before the chunk start (e.g., chunk 2 reads offset=491, limit=510) to recover context from any timestamp-text pair split at the boundary. Summarize only content that starts within the chunk's own range — the overlap lines are only for context.
```

**With explicit boundary logic:**
```
- **For chunks 2+:** also read 10 lines before the chunk start (e.g., chunk 2 reads offset=491, limit=510) to recover context from any timestamp-text pair split at the boundary. **CRITICAL: Each section is exactly 2 lines (timestamp line + text line). Only summarize sections where the TIMESTAMP LINE falls within your assigned line range. If a section's timestamp line is in the context overlap (lines 1-10 of what you read), SKIP that section entirely—it belongs to the previous chunk.**
```

**2. Update step 7, lines 84-90** - Add explicit boundary checking to the agent instructions:

Add between current points 1 and 2:
```
1. Read its assigned chunk using the Read tool (with offset and limit parameters)
   **IMPORTANT: For chunks 2+, identify section boundaries:**
   - Each section = 2 lines (even line = timestamp, odd line = text)
   - Calculate which line numbers within your read correspond to actual chunk lines
   - For example: chunk 5 reads offset=1991 (10 context) + 500 = 511 lines total
     * Lines 1-10 are context overlap (lines 1991-2000 of original file)
     * Lines 11-511 are the actual chunk (lines 2001-2500)
     * Skip any section whose timestamp line falls in lines 1-10
2. **Process only valid sections:**
   - For each section, check: is this section's timestamp line within my actual chunk range?
   - If YES: summarize it
   - If NO (timestamp line is in context overlap): skip it entirely
   - Group text under each timestamp into a coherent section before summarizing
3. Produce section summaries with `## [HH:MM:SS] Topic` headings...
```

**3. Keep the existing smart-merge logic** in step 8 as a safety net (already present in lines 110-117).

## Verification

After implementing the fix:

1. **Re-run the summarizer** on a long video (1000+ lines)
2. **Check chunk files** for overlap:
   ```bash
   # Compare sections at boundaries
   tail -20 chunk_4.txt
   head -20 chunk_5.txt
   ```
3. **Verify no duplicate topics** appear across chunk boundaries
4. **Confirm the final summary** flows naturally without repeated content

## Expected Outcome

- Chunk 4 ends cleanly at its last valid section (timestamp within lines 1501-2000)
- Chunk 5 starts with its first valid section (timestamp within lines 2001-2500)
- No overlap in topics between consecutive chunks
- Smart-merge in reduce phase serves as backup for edge cases
