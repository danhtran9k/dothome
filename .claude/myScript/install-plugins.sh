#!/bin/bash
# Bootstrap script: installs all plugins listed in enabledPlugins from settings.json
# Run this once on a new machine after syncing your dotfiles

SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo "settings.json not found at $SETTINGS"
  exit 1
fi

plugins=$(jq -r '.enabledPlugins | to_entries[] | select(.value == true) | .key' "$SETTINGS" 2>/dev/null)

if [ -z "$plugins" ]; then
  echo "No enabled plugins found in settings.json"
  exit 0
fi

echo "Installing plugins..."
while IFS= read -r plugin; do
  echo "  -> $plugin"
  claude plugin install "$plugin"
done <<< "$plugins"

echo "Done."
