#!/bin/bash
# Claude Code Status Line

input=$(cat)

ONE_HOUR_SEC=3600
OFFSET_HOUR=$((1 * ONE_HOUR_SEC))      # X hours in seconds (X * 3600)
OFFSET_DAY=$((24 * ONE_HOUR_SEC)) 
# Took advantage of the endTime always being rounded to the hour

SESSION_HOURS=$((5 * ONE_HOUR_SEC)) # 5 or 6 hour
DEBUG_FILE=~/.claude/myScript/debug.txt
SESSION_FILE=~/.claude/session.log.txt

# For debugging save input to tmp file
echo "$input" > "$DEBUG_FILE"
# env >> "$DEBUG_FILE"

is_fake=false
[[ "$ANTHROPIC_BASE_URL" == *"pro-x"* ]] && is_fake=true

is_trial=false
[[ "$ANTHROPIC_AUTH_TOKEN" == *"af399"* ]] && is_trial=true

# Parse JSON using grep
json_str() { echo "$input" | grep -o "\"$1\":\"[^\"]*\"" | grep -o '"[^"]*"$' | tr -d '"'; }
json_num() {
  local v
  v=$(echo "$input" | grep -o "\"$1\":[^,}]*" | grep -o '[^:]*$')
  [ "$v" != "null" ] && echo "$v"
}

# Parse session file key-value pairs
session_get() { grep -o "^$1=[0-9]*" "$SESSION_FILE" 2>/dev/null | cut -d'=' -f2; }

# Get git branch display
gitBranch() {
  local cwd="$1"
  local branch
  branch=$(cd "$cwd" 2>/dev/null && git branch --show-current 2>/dev/null || echo "")
  if [ -n "$branch" ]; then
    echo "\033[35m🏷️ $branch\033[0m"
  else
    echo "-"
  fi
}
# Initialize session file if needed and read CLAUDE_REFRESH value
initAndRead() {
    if [ ! -f "$SESSION_FILE" ]; then
        CURRENT_HOUR=$((CURRENT_EPOCH - CURRENT_EPOCH % ONE_HOUR_SEC))
        INITIAL_END=$((CURRENT_HOUR + OFFSET_HOUR))
        echo "CLAUDE_REFRESH=$INITIAL_END" >> "$SESSION_FILE"
        echo "$INITIAL_END"
    else
        session_get "CLAUDE_REFRESH"
    fi
}

claudeTimeSelfUpdate() {
  # Claude mode: existing CLAUDE_REFRESH logic
  local CURRENT_EPOCH=$(date +%s)
  local END=$(initAndRead)
  local REMAINING=$((END - CURRENT_EPOCH))

  # Update saved end time when remaining is negative
  if [ "$REMAINING" -lt 0 ]; then
    local intervals=$(( (-REMAINING + SESSION_HOURS - 1) / SESSION_HOURS ))
    END=$((END + intervals * SESSION_HOURS))
    REMAINING=$((END - CURRENT_EPOCH))

    # Update CLAUDE_REFRESH value in file
    if grep -q "CLAUDE_REFRESH=" "$SESSION_FILE" 2>/dev/null; then
      sed -i "s/CLAUDE_REFRESH=.*/CLAUDE_REFRESH=$END/" "$SESSION_FILE"
    else
      echo "CLAUDE_REFRESH=$END" >> "$SESSION_FILE"
    fi
  fi

  echo "$END|$REMAINING"
}

# Format percentage display with context icon
formatPercentDisplay() {
  local percent="$1"
  local icon

  if [ "$percent" -ge 60 ]; then
    icon="🟡"
  else
    icon="🟢"
  fi

  echo "$icon ${percent}%"
}

# Format remaining time display
formatRemainingTime() {
  local remaining="$1"
  local hours=$((remaining / ONE_HOUR_SEC))
  local mins=$(((remaining % ONE_HOUR_SEC) / 60))

  if [ "$hours" -eq 0 ]; then
    echo "🕐 ${mins}m"
  else
    echo "🕐 ${hours}h${mins}m"
  fi
}

# Get formatted end time as hh:mm am/pm (e.g., "3:15pm")
getTimeEnd() {
  local saved_end="$1"
  local time_end

  time_end=$(date -d "@$saved_end" '+%-l:%M%p' 2>/dev/null || date -r "$saved_end" '+%-l:%M%p' 2>/dev/null)
  echo "$time_end" | tr 'A-Z' 'a-z'
}

# Format GLM time display from GLM_REFRESH (timestamp in milliseconds)
glmTime() {
  local glm_refresh="$1"
  local current_epoch refresh_epoch remaining time_end

  current_epoch=$(date +%s)
  # GLM_REFRESH is in milliseconds, convert to seconds
  refresh_epoch=$((glm_refresh / 1000))
  remaining=$((refresh_epoch - current_epoch))

  local time_display
  time_display=$(formatRemainingTime "$remaining")

  # Format end time as hh:mm am/pm (e.g., "3:15pm")
  time_end=$(date -d "@$refresh_epoch" '+%-l:%M%p' 2>/dev/null || date -r "$refresh_epoch" '+%-l:%M%p' 2>/dev/null | tr 'A-Z' 'a-z')

  echo "$time_display ($time_end)"
}

longcatTime() {
  local current_epoch=$(date +%s)

  # Calculate next GMT midnight
  local gmt_midnight=$(( (current_epoch / $OFFSET_DAY) * $OFFSET_DAY + $OFFSET_DAY ))
  local remaining=$((gmt_midnight - current_epoch))

  local time_display
  time_display=$(formatRemainingTime "$remaining")

  # Format end time as hh:mm am/pm (e.g., "3:15pm")
  local time_end
  time_end=$(date -d "@$gmt_midnight" '+%-l:%M%p' 2>/dev/null || date -r "$gmt_midnight" '+%-l:%M%p' 2>/dev/null | tr 'A-Z' 'a-z')

  echo "$time_display ($time_end)"
}

# Get and format model from JSON with abbreviations and color
getModel() {
  local MODEL=$(json_str display_name)
  MODEL="${MODEL:-Unknown}"

  # Convert to lowercase for case-insensitive matching (works with older bash)
  local lower_model=$(echo "$MODEL" | tr '[:upper:]' '[:lower:]')
  local formatted="$MODEL"

  # Apply abbreviations
  if [[ "$lower_model" == *"flash"* ]]; then
    formatted="${formatted//[Ff]lash/Fl}"
  fi
  if [[ "$lower_model" == *"thinking"* ]]; then
    formatted="${formatted//[Tt]hinking/Tk}"
  fi
  if [[ "$lower_model" == *"context"* ]]; then
    formatted="${formatted//[Cc]ontext/}"
  fi

  # Apply color based on provider
  if [ "$is_trial" = true ]; then
    echo "\033[91m$formatted\033[0m"
  elif [ "$is_fake" = true ]; then
    echo "\033[92m$formatted\033[0m"
  else
    echo "\033[94m$formatted\033[0m"
  fi
}

trialTime() {
  local current_epoch=$(date +%s)
  local trial_target
  local remaining
  local time_display

  trial_target=$(date -j -f "%H:%M:%S" "18:38:00" "+%s")
  if [ "$current_epoch" -ge "$trial_target" ]; then
    trial_target=$((trial_target + OFFSET_DAY))
  fi

  remaining=$((trial_target - current_epoch))
  time_display=$(formatRemainingTime "$remaining")

  echo "$trial_target|$time_display|18:38:00"
}

MODEL=$(getModel)
# Path and git
# Unescape JSON backslashes (Windows paths: \\ -> \)
CWD=$(json_str cwd)
CWD="${CWD//\\\\/\\}"
CWD="${CWD:-.}"
FOLDER_NAME="$(basename "$CWD")"
GIT_DISPLAY=$(gitBranch "$CWD")

# GLM mode
if [[ "$ANTHROPIC_BASE_URL" == *"z.ai"* ]]; then
    GLM_USED=$(session_get "GLM_USED")
    GLM_USED="${GLM_USED:-0}"

    if [ -z "$GLM_REFRESH" ] || [ "$GLM_REFRESH" = "0" ]; then
        node ~/.claude/myScript/getGlm.js --force >/dev/null 2>&1
    else
        node ~/.claude/myScript/getGlm.js >/dev/null 2>&1
    fi

    GLM_REFRESH=$(session_get "GLM_REFRESH")
    TIME_DISPLAY=$(glmTime "$GLM_REFRESH")

    SESSION_INFO="$TIME_DISPLAY $(formatPercentDisplay "$GLM_USED")"
# LongCat mode
elif [[ "$ANTHROPIC_BASE_URL" == *"longcat.chat"* ]]; then
    SESSION_INFO="$(longcatTime)"
# Claude / Default mode (Empty or other URLs)
else
    PERCENT=$(json_num used_percentage)
    PERCENT="${PERCENT:-0}"

    if [ "$is_trial" = true ]; then
        RESULT=$(trialTime)
        SAVED_END=$(echo "$RESULT" | cut -d'|' -f1)
        TIME_LEFT=$(echo "$RESULT" | cut -d'|' -f2)
        TIME_END=$(echo "$RESULT" | cut -d'|' -f3)
    else
        RESULT=$(claudeTimeSelfUpdate)
        SAVED_END=$(echo "$RESULT" | cut -d'|' -f1)
        REMAINING=$(echo "$RESULT" | cut -d'|' -f2)
        TIME_LEFT=$(formatRemainingTime "$REMAINING")
        TIME_END=$(getTimeEnd "$SAVED_END")
    fi

    TIME_DISPLAY="$TIME_LEFT ($TIME_END)"

    echo "DEBUG: TIME_END=$TIME_END" >> "$DEBUG_FILE"
    echo "DEBUG: TIME_LEFT=$TIME_LEFT" >> "$DEBUG_FILE"

    # Only display cost if is Claude model
    TOTAL_COST=$(json_num total_cost_usd)
    TOTAL_COST="${TOTAL_COST:-0}"
    COST_DISPLAY=$(printf "\$%.2f" "$TOTAL_COST")

    SESSION_INFO="$TIME_DISPLAY $(formatPercentDisplay "$PERCENT") | 💳 $COST_DISPLAY"
fi

echo -e "$FOLDER_NAME $GIT_DISPLAY | $MODEL $SESSION_INFO"
