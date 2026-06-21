#!/bin/bash
# Installer for caffeinate-agents.
# Installs a LaunchAgent that keeps your Mac awake while AI agents run,
# and (if SwiftBar is present) a menu bar toggle.
set -euo pipefail

LABEL="com.caffeinate-agents"
APP_DIR="$HOME/.caffeinate-agents"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(uname)" != "Darwin" ]; then
  echo "This tool is macOS-only (it uses caffeinate, pmset, and launchd)." >&2
  exit 1
fi

echo "Installing caffeinate-agents..."

# 1) Watcher script
mkdir -p "$APP_DIR"
cp "$SRC_DIR/caffeinate-agents.sh" "$APP_DIR/caffeinate-agents.sh"
chmod +x "$APP_DIR/caffeinate-agents.sh"

# 2) LaunchAgent (auto-starts on login, kept alive)
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$APP_DIR/caffeinate-agents.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/caffeinate-agents.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/caffeinate-agents.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "✓ Watcher installed and running (auto-starts on login)."

# 3) Optional SwiftBar menu bar plugin
if [ -d "/Applications/SwiftBar.app" ]; then
  PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
  [ -z "$PLUGIN_DIR" ] && PLUGIN_DIR="$HOME/.swiftbar" && defaults write com.ameba.SwiftBar PluginDirectory "$PLUGIN_DIR"
  mkdir -p "$PLUGIN_DIR"
  cp "$SRC_DIR/swiftbar/caffeinate-agents.10s.sh" "$PLUGIN_DIR/caffeinate-agents.10s.sh"
  chmod +x "$PLUGIN_DIR/caffeinate-agents.10s.sh"
  open -a SwiftBar 2>/dev/null || true
  echo "✓ SwiftBar plugin installed to $PLUGIN_DIR — look for ☕️ in the menu bar."
else
  echo "• SwiftBar not found — skipping the menu bar toggle (the watcher still works)."
  echo "  To add the toggle: brew install --cask swiftbar  &&  ./install.sh"
fi

echo
echo "Done. Your Mac will stay awake while any of these run: \"\${AGENT_PROCESSES:-claude}\""
echo "Logs: /tmp/caffeinate-agents.log   |   Uninstall: ./uninstall.sh"
