#!/bin/bash
# Offset Session Time Script
# Usage: ./offset_session.sh [hours]
# Default: 1 hour if no argument provided

ONE_HOUR_SEC=3600
SESSION_FILE=~/.claude/session.log.txt

# Get offset argument (default 1)
OFFSET_HOURS=${1:-1}

# Validate argument is a number (allow negative numbers)
if ! [[ "$OFFSET_HOURS" =~ ^-?[0-9]+$ ]]; then
    echo "Error: Argument must be a number" >&2
    exit 1
fi

# Check if session file exists
if [ ! -f "$SESSION_FILE" ]; then
    echo "Error: Session file not found: $SESSION_FILE" >&2
    exit 1
fi

# Read current value (handle CLAUDE_REFRESH=value format)
CURRENT_VALUE=$(cat "$SESSION_FILE" | grep -o 'CLAUDE_REFRESH=[0-9]*' | cut -d'=' -f2)

# Validate current value is a number
if ! [[ "$CURRENT_VALUE" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid value in session file: $CURRENT_VALUE" >&2
    exit 1
fi

# Calculate new value
OFFSET_SEC=$((OFFSET_HOURS * ONE_HOUR_SEC))
NEW_VALUE=$((CURRENT_VALUE + OFFSET_SEC))

# Update CLAUDE_REFRESH value in file (replace existing or append)
if grep -q "CLAUDE_REFRESH=" "$SESSION_FILE" 2>/dev/null; then
    perl -i -pe "s/CLAUDE_REFRESH=.*/CLAUDE_REFRESH=$NEW_VALUE/" "$SESSION_FILE"
else
    echo "CLAUDE_REFRESH=$NEW_VALUE" >> "$SESSION_FILE"
fi

# Display confirmation
echo "Session end time offset by $OFFSET_HOURS hour(s)"
echo "New value: $NEW_VALUE"
echo "New end time: $(date -d "@$NEW_VALUE" '+%Y-%m-%d %l:%M%p' 2>/dev/null || date -r "$NEW_VALUE" '+%Y-%m-%d %l:%M%p' 2>/dev/null)"
