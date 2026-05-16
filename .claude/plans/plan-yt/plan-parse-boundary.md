# Cleanup: remove dead section-header mode from assemble_chunks.py

## Current state (after temps fix)

All boundary files across all z_0utub directories now use the correct strict format:

**NO_OVERLAP case:** exactly `NO_OVERLAP` on line 1.

**OVERLAP case:**
```
OVERLAP
LEFT_CUT_AT: <integer>
RIGHT_CUT_UNTIL: <integer>
MERGED:
<markdown content>
```

No files use the old `LEFT_REPLACE_FROM / RIGHT_REPLACE_UNTIL` section-header format.

## Script logic vs current files — is it correct?

`parse_boundary` flow for OVERLAP files:
- `text.strip() == "NO_OVERLAP"` → False ✓
- `re.search(r'MERGED:\n(.*)', text, re.DOTALL)` → matches content ✓
- `re.search(r'LEFT_CUT_AT:\s*(\d+)', text)` → matches integer ✓
- `re.search(r'RIGHT_CUT_UNTIL:\s*(\d+)', text)` → matches integer ✓
- Returns `{"overlap": True, "mode": "line", ...}` ✓

The line-number path works correctly. **No logic bugs for current files.**

## What is dead code

The section-header branch (`mode: "section"`, `LEFT_REPLACE_FROM`, `RIGHT_REPLACE_UNTIL`, `find_section_line`) is never reached. Zero files match it.

## Change required

**Only `assemble_chunks.py`** — remove dead section-header mode. No changes needed to `chunk_reducer.md`.

Simplified script:

```python
def parse_boundary(path):
    if not path.exists():
        return {"overlap": False}
    text = path.read_text()
    if text.strip() == "NO_OVERLAP":
        return {"overlap": False}
    left_match = re.search(r'LEFT_CUT_AT:\s*(\d+)', text)
    right_match = re.search(r'RIGHT_CUT_UNTIL:\s*(\d+)', text)
    merged = re.search(r'MERGED:\n(.*)', text, re.DOTALL)
    if left_match and right_match and merged:
        return {
            "overlap": True,
            "left_cut_at": int(left_match.group(1)),
            "right_cut_until": int(right_match.group(1)),
            "merged": merged.group(1).strip()
        }
    print(f"WARNING: {path} unrecognized format, treating as no overlap", file=sys.stderr)
    return {"overlap": False}
```

Main loop (no `mode` checks needed):
```python
# Step A: cut tail, append merged
if i < N and boundaries[i]["overlap"]:
    cut = boundaries[i]["left_cut_at"] - 1
    lines = lines[:cut] + [boundaries[i]["merged"] + "\n"]

# Step B: trim head
if i > 1 and boundaries[i - 1]["overlap"]:
    lines = lines[boundaries[i - 1]["right_cut_until"]:]
```

Also remove `find_section_line` helper entirely.

## File to modify

| File | Change |
|------|--------|
| `.claude/scripts/yt-sum/assemble_chunks.py` | Remove section-header mode, `find_section_line`, `"mode"` key |

## Verification

Run: `python3 .claude/scripts/yt-sum/assemble_chunks.py z_0utub/Ta_Chỉ_Làm_Mô_Hình_Máy_Bay_Thế_Giới_Đã_Bắt_Đầu_Hoảng_Loạn_Tập_1_60_Ma_Tổ_Vietsub`
- Should print `assembled N chunks -> body.md, X takeaways` with no WARNINGs
- `body.md` should have no duplicate sections at boundaries that had OVERLAP
