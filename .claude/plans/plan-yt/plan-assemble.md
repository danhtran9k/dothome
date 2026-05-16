# Simplify assemble_chunks.py by removing dead code

## Context

The `assemble_chunks.py` script grew complex because it handled two boundary formats:
1. **Line-number format** (`LEFT_CUT_AT: 62, RIGHT_CUT_UNTIL: 15`) - the original, intended format
2. **Section-header format** (`LEFT_REPLACE_FROM: ## [HH:MM] Topic`) - added to handle inconsistent AI agent outputs

The boundary agents were outputting timestamps (`LEFT_CUT_AT=22:52`) which didn't match either format. This has been **fixed** - boundary files now correctly use the line-number format.

The section-header format support is now **dead code** that adds unnecessary complexity.

## Plan

### 1. Simplify `assemble_chunks.py` (lines 22-60, 86-99)

Remove the section-header format support:
- Delete the `LEFT_REPLACE_FROM` / `RIGHT_REPLACE_UNTIL` regex patterns
- Remove the `find_section_line()` helper function
- Remove the `mode: "section"` branch logic
- Keep only the line-number format (original design)

### 2. Strengthen `chunk_reducer.md` boundary format specification

Add explicit format template and validation hints to prevent future drift:
- Show exact expected output format
- Emphasize line numbers (integers), not timestamps
- Add warning about common mistakes

## Files to Modify

1. `.claude/scripts/yt-sum/assemble_chunks.py` - Remove section-header format code (~40 lines)
2. `.claude/commands/chunk_reducer.md` - Strengthen boundary format specification

## Verification

After changes:
1. Run the full yt-sum pipeline on a test video
2. Verify `assemble_chunks.py` correctly processes boundary files
3. Confirm no warnings about "unrecognized format"
4. Check final summary has no duplicate content at chunk boundaries
