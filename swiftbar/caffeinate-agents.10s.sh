#!/bin/bash
# SwiftBar plugin: status + toggle for caffeinate-agents.
# <bitbar.title>Caffeinate Agents</bitbar.title>
# <bitbar.desc>Keeps Mac awake while AI agents run; toggle on/off.</bitbar.desc>
# <bitbar.author>caffeinate-agents</bitbar.author>

PLIST="$HOME/Library/LaunchAgents/com.caffeinate-agents.plist"
SELF="$0"

case "$1" in
  enable)  launchctl load   "$PLIST" 2>/dev/null; exit 0 ;;
  disable) launchctl unload "$PLIST" 2>/dev/null; exit 0 ;;
esac

launchctl list 2>/dev/null | grep -q caffeinate-agents && enabled=1 || enabled=0
pgrep -x caffeinate >/dev/null 2>&1 && active=1 || active=0
pgrep -x claude     >/dev/null 2>&1 && agents=1 || agents=0

if [ "$enabled" = 1 ]; then
  echo ":cup.and.saucer.fill: | sfcolor=#8a6d3b"
else
  echo ":moon.zzz.fill: | sfcolor=#888888"
fi

echo "---"
echo "Caffeinate while agents run | size=13"
echo "---"

if [ "$enabled" = 1 ]; then
  if [ "$active" = 1 ]; then
    echo "● Keeping Mac awake | color=#2e8b57"
  elif [ "$agents" = 1 ]; then
    echo "● Agents running (below battery floor) | color=#cc8400"
  else
    echo "○ Idle — no agents running | color=gray"
  fi
  echo "Disable | bash=\"$SELF\" param1=disable terminal=false refresh=true"
else
  echo "○ Disabled | color=gray"
  echo "Enable | bash=\"$SELF\" param1=enable terminal=false refresh=true"
fi

echo "---"
echo "View log | bash=/usr/bin/open param1=-a param2=Console param3=/tmp/caffeinate-agents.log terminal=false"
echo "Refresh | refresh=true"
