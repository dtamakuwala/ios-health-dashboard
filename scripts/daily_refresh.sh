#!/bin/bash
# Runs the daily dashboard refresh headlessly via the claude CLI.
# Invoked by com.dtamakuwala.ios-health-dashboard-refresh.plist (launchd).
set -euo pipefail

REPO_DIR="/Users/drew.tamakuwala/Code/ios-health-dashboard"
CLAUDE_BIN="/Users/drew.tamakuwala/.local/bin/claude"

cd "$REPO_DIR"
mkdir -p logs

PROMPT="$(cat scripts/daily_refresh_prompt.txt)"

echo "=== $(date) ===" >> logs/refresh.log
"$CLAUDE_BIN" -p "$PROMPT" --permission-mode bypassPermissions >> logs/refresh.log 2>&1
echo "=== done: $(date) ===" >> logs/refresh.log
