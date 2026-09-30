#!/bin/bash
# <bitbar.title>Caffeinate Agents</bitbar.title>
# <bitbar.version>2.0</bitbar.version>
# <bitbar.desc>Agent sessions, battery-aware holds, and a persistent on/off switch.</bitbar.desc>
# <bitbar.author>caffeinate-agents</bitbar.author>

APP_DIR="$HOME/.caffeinate-agents"
CLI="$APP_DIR/caffeinate-agents.sh"
if [ ! -x "$CLI" ]; then
  echo '☕ | color=gray'
  echo '---'
  echo 'Caffeinate Agents is not installed'
  exit 0
fi
case "${1:-}" in
  enable|disable) exec "$CLI" "--$1" ;;
esac

status=$("$CLI" --status)
if printf '%s\n' "$status" | grep -q '^Awake:'; then
  echo '☕ | color=#2e8b57'
elif printf '%s\n' "$status" | grep -q '^Paused:'; then
  echo '☕ | color=#cc8400'
else
  echo '☕ | color=gray'
fi
echo '---'
echo 'Caffeinate Agents | size=13'
echo '---'
printf '%s\n' "$status"
echo '---'
if printf '%s\n' "$status" | grep -q '^Watcher: enabled$'; then
  echo "Disable automatic detection | bash=\"$0\" param1=disable terminal=false refresh=true"
else
  echo "Enable automatic detection | bash=\"$0\" param1=enable terminal=false refresh=true"
fi
echo "Edit configuration | bash=/usr/bin/open param1=-t param2=\"$APP_DIR/config\" terminal=false"
echo "Reload configuration | bash=\"$CLI\" param1=--restart terminal=false refresh=true"
echo "View log | bash=/usr/bin/open param1=-a param2=Console param3=\"$APP_DIR/watcher.log\" terminal=false"
echo 'Refresh | refresh=true'
