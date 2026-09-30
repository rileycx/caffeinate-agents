#!/bin/bash
set -euo pipefail
umask 077

LABEL="com.caffeinate-agents"
APP_DIR="$HOME/.caffeinate-agents"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE="gui/$(id -u)/$LABEL"

if [ "$(uname -s)" != Darwin ]; then
  echo "This tool requires macOS (caffeinate, pmset, and launchd)." >&2
  exit 1
fi
if [ "$(id -u)" = 0 ]; then
  echo "Run this installer as your login user, without sudo." >&2
  exit 1
fi

# Validate the source before stopping an existing installation.
/bin/bash -n "$SRC_DIR/caffeinate-agents.sh"
[ -f "$SRC_DIR/detect-agents.awk" ] && [ -f "$SRC_DIR/config.example" ]
/bin/bash "$SRC_DIR/caffeinate-agents.sh" --check >/dev/null
mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents"
chmod 700 "$APP_DIR"

# Preserve previous in-script customizations for manual migration.
if [ -f "$APP_DIR/caffeinate-agents.sh" ] && [ ! -f "$APP_DIR/config" ]; then
  cp "$APP_DIR/caffeinate-agents.sh" "$APP_DIR/caffeinate-agents.sh.previous"
  echo "Previous script saved to $APP_DIR/caffeinate-agents.sh.previous"
fi
if [ ! -f "$APP_DIR/config" ]; then cp "$SRC_DIR/config.example" "$APP_DIR/config"; fi

# A disabled watcher stays disabled across upgrades.
disabled=0
if launchctl print-disabled "gui/$(id -u)" | grep -q '"com.caffeinate-agents" => true'; then disabled=1; fi
launchctl bootout "$SERVICE" 2>/dev/null || true
cp "$SRC_DIR/caffeinate-agents.sh" "$SRC_DIR/detect-agents.awk" "$APP_DIR/"
chmod 700 "$APP_DIR/caffeinate-agents.sh"

xml_escape() {
  printf '%s' "$1" | sed -e 's/\&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}
APP_XML=$(xml_escape "$APP_DIR")
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$APP_XML/caffeinate-agents.sh</string><string>--watch</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
    <key>StandardOutPath</key><string>$APP_XML/watcher.log</string>
    <key>StandardErrorPath</key><string>$APP_XML/watcher.log</string>
</dict>
</plist>
PLIST_EOF
plutil -lint "$PLIST" >/dev/null
if [ "$disabled" = 0 ]; then
  launchctl enable "$SERVICE"
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "Watcher installed and running; starts automatically at login."
else
  echo "Watcher updated; your disabled setting was preserved."
fi

if [ -d /Applications/SwiftBar.app ] || [ -d "$HOME/Applications/SwiftBar.app" ]; then
  PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
  if [ -z "$PLUGIN_DIR" ]; then
    PLUGIN_DIR="$HOME/.swiftbar"
    defaults write com.ameba.SwiftBar PluginDirectory "$PLUGIN_DIR"
  fi
  mkdir -p "$PLUGIN_DIR"
  cp "$SRC_DIR/swiftbar/caffeinate-agents.10s.sh" "$PLUGIN_DIR/caffeinate-agents.10s.sh"
  chmod +x "$PLUGIN_DIR/caffeinate-agents.10s.sh"
  printf '%s\n' "$PLUGIN_DIR" > "$APP_DIR/swiftbar-directory"
  open -a SwiftBar 2>/dev/null || true
  echo "SwiftBar plugin installed to $PLUGIN_DIR"
else
  echo "Optional menu bar: brew install --cask swiftbar, then rerun ./install.sh"
fi
printf '\nConfig: %s/config\nStatus: %s/caffeinate-agents.sh --status\n' "$APP_DIR" "$APP_DIR"
echo "If you customized the old script or LaunchAgent, move those settings into config."
