#!/bin/bash
# caffeinate-agents — keep your Mac awake while AI agents are running.
# https://github.com/rileycx/caffeinate-agents
#
# Watches for running agent processes (default: `claude`) and holds the Mac
# awake only while one is active. Releases automatically when nothing is
# running, or when on battery below a floor (default 10%).
#
# Self-healing: each "stay awake" hold is a time-bounded `caffeinate -t` that's
# refreshed every loop. So even if this watcher is force-killed, the last hold
# expires on its own within HOLD seconds — no orphan can keep your Mac awake
# forever.

# Space-separated list of process names to watch (exact match, like `pgrep -x`).
# Override by exporting AGENT_PROCESSES, or edit this line. Examples: "claude"
# or "claude node cursor".
AGENT_PROCESSES="${AGENT_PROCESSES:-claude}"

# On battery, stop holding awake once charge drops below this percentage.
BATTERY_FLOOR="${BATTERY_FLOOR:-10}"

INTERVAL="${INTERVAL:-20}"   # seconds between checks
HOLD="${HOLD:-35}"           # caffeinate lifetime per refresh (must be > INTERVAL)
CAF_PID=""

agents_running() {
  local p
  for p in $AGENT_PROCESSES; do
    pgrep -x "$p" >/dev/null 2>&1 && return 0
  done
  return 1
}

stop_caffeinate() {
  [ -n "$CAF_PID" ] && kill "$CAF_PID" 2>/dev/null
  CAF_PID=""
}

cleanup() { stop_caffeinate; exit 0; }
trap cleanup TERM INT

while true; do
  awake=0
  if agents_running; then
    batt=$(pmset -g batt)
    pct=$(printf '%s' "$batt" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
    if printf '%s' "$batt" | grep -q "AC Power" || [ "${pct:-100}" -ge "$BATTERY_FLOOR" ]; then
      awake=1
    fi
  fi

  if [ "$awake" = 1 ]; then
    # start a fresh bounded hold, then retire the previous one
    caffeinate -i -t "$HOLD" &
    new=$!
    [ -n "$CAF_PID" ] && kill "$CAF_PID" 2>/dev/null
    CAF_PID=$new
  else
    stop_caffeinate
  fi

  # interruptible sleep so the TERM trap fires immediately on unload
  sleep "$INTERVAL" &
  wait $!
done
