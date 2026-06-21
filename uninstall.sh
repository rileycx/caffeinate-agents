#!/bin/bash
# Uninstaller for caffeinate-agents.
set -uo pipefail

LABEL="com.caffeinate-agents"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "Uninstalling caffeinate-agents..."

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

# Drop any hold this tool was keeping (harmless if you have no others)
pkill -x caffeinate 2>/dev/null || true

rm -rf "$HOME/.caffeinate-agents"

PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "$HOME/.swiftbar")"
rm -f "$PLUGIN_DIR/caffeinate-agents.10s.sh"

echo "✓ Removed. (SwiftBar itself was left installed — remove it with: brew uninstall --cask swiftbar)"
