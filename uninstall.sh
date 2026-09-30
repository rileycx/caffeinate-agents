#!/bin/bash
set -euo pipefail

LABEL="com.caffeinate-agents"
APP_DIR="$HOME/.caffeinate-agents"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
if [ "$(uname -s)" != Darwin ] || [ "$(id -u)" = 0 ]; then
  echo "Run this uninstaller on macOS as your login user, without sudo." >&2
  exit 1
fi
case "${1:-}" in
  ""|--purge) ;;
  *) echo "Usage: ./uninstall.sh [--purge]" >&2; exit 1 ;;
esac

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
# Clear launchd's persistent disabled override for a future fresh install.
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -n "$PLUGIN_DIR" ]; then rm -f "$PLUGIN_DIR/caffeinate-agents.10s.sh"; fi
if [ -f "$APP_DIR/swiftbar-directory" ]; then
  IFS= read -r PLUGIN_DIR < "$APP_DIR/swiftbar-directory" || true
  if [ -n "$PLUGIN_DIR" ]; then rm -f "$PLUGIN_DIR/caffeinate-agents.10s.sh"; fi
fi
rm -f "$HOME/.swiftbar/caffeinate-agents.10s.sh"
# Never kill other apps' caffeinate processes. launchd stops our watcher;
# any hold left by a crash expires on its own within HOLD seconds.
rm -f "$APP_DIR/caffeinate-agents.sh" "$APP_DIR/detect-agents.awk" "$APP_DIR/swiftbar-directory"
if [ "${1:-}" = --purge ]; then
  rm -rf "$APP_DIR"
else
  echo "Configuration and logs preserved in $APP_DIR (use --purge to remove)."
fi
echo "Removed the login watcher and menu bar plugin. SwiftBar itself is unchanged."
echo "Any separately started --run or --hold monitor ends with its command or timer."
