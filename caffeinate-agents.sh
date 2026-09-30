#!/bin/bash
# macOS Bash 3.2 compatible; no package manager or language runtime required.
set -uo pipefail
umask 077

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${CAFFEINATE_AGENTS_HOME:-$HOME/.caffeinate-agents}"
CONFIG="$APP_DIR/config"
LABEL="com.caffeinate-agents"
SERVICE="gui/$(id -u)/$LABEL"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

die() { printf 'caffeinate-agents: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'HELP'
Usage: caffeinate-agents.sh [COMMAND]
  --watch                Watch supported agent CLI processes (default)
  --check                Print detected agent names and PIDs; do not hold awake
  --status               Show this tool's live holds and watcher status
  --run COMMAND [ARG...]  Hold awake for any command, preserving its exit status
  --hold SECONDS         Hold awake for a fixed duration (e.g. desktop agent work)
  --enable               Enable the installed watcher, including at next login
  --disable              Disable the installed watcher, including at next login
  --restart              Reload the installed watcher and its configuration
  --help                 Show this help

Configuration: ~/.caffeinate-agents/config (shell assignments).
All holds respect the battery floor. Process detection tracks open sessions,
including sessions waiting for input; it cannot determine whether a model is busy.
HELP
}

is_uint() { [[ "$1" =~ ^(0|[1-9][0-9]{0,10})$ ]]; }

load_config() {
  # Environment values take precedence over the user's configuration.
  local key
  local saved=()
  for key in AGENT_PROCESSES EXTRA_AGENT_PROCESSES BATTERY_FLOOR INTERVAL HOLD; do
    if [ "${!key+x}" = x ]; then saved+=("$key=${!key}"); fi
  done
  if [ -f "$CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG" || die "Could not load $CONFIG"
  fi
  for key in ${saved[@]+"${saved[@]}"}; do export "$key"; done
  AGENT_PROCESSES="${AGENT_PROCESSES-claude codex gemini opencode copilot aider cursor-agent}"
  EXTRA_AGENT_PROCESSES="${EXTRA_AGENT_PROCESSES-}"
  BATTERY_FLOOR="${BATTERY_FLOOR:-10}"
  INTERVAL="${INTERVAL:-10}"
  HOLD="${HOLD:-25}"
  for key in BATTERY_FLOOR INTERVAL HOLD; do
    is_uint "${!key}" || die "$key must be a non-negative integer (no leading zeros)."
  done
  [ "$BATTERY_FLOOR" -le 100 ] || die "BATTERY_FLOOR must be between 0 and 100."
  [ "$INTERVAL" -ge 1 ] && [ "$INTERVAL" -le 3600 ] || die "INTERVAL must be between 1 and 3600."
  [ "$HOLD" -gt "$INTERVAL" ] && [ "$HOLD" -le 86400 ] || die "HOLD must exceed INTERVAL and be at most 86400."
  for key in $AGENT_PROCESSES $EXTRA_AGENT_PROCESSES; do
    [[ "$key" =~ ^[a-zA-Z0-9_.-]+$ ]] || die "Invalid process name: $key (use executable names, not patterns)."
  done
}

detect_agents() {
  ps -axww -o pid=,uid=,stat=,args= | awk \
    -v user_id="$(id -u)" -v names="$AGENT_PROCESSES" \
    -v extra="$EXTRA_AGENT_PROCESSES" -f "$SRC_DIR/detect-agents.awk"
}

service_action() {
  [ -f "$PLIST" ] || die "Watcher is not installed. Run ./install.sh first."
  case "$1" in
    --disable)
      launchctl disable "$SERVICE" || exit 1
      launchctl bootout "$SERVICE" 2>/dev/null || true
      ;;
    --enable|--restart)
      launchctl enable "$SERVICE" || exit 1
      if [ "$1" = --restart ]; then launchctl bootout "$SERVICE" 2>/dev/null || true; fi
      if ! launchctl print "$SERVICE" >/dev/null 2>&1; then
        launchctl bootstrap "gui/$(id -u)" "$PLIST" || exit 1
      fi
      launchctl kickstart "$SERVICE" || exit 1
      ;;
  esac
}

show_status() {
  local file pid updated state hold_pid detail now
  now=$(date +%s)
  if launchctl print "$SERVICE" >/dev/null 2>&1; then
    printf 'Watcher: enabled\n'
  else
    printf 'Watcher: disabled or not installed\n'
  fi
  for file in "$APP_DIR"/run/*/status; do
    [ -f "$file" ] || continue
    IFS=$'\t' read -r pid updated state hold_pid detail < "$file" || continue
    is_uint "$pid" && is_uint "$updated" || continue
    kill -0 "$pid" 2>/dev/null || continue
    # Each record carries a deadline, so a stuck watcher cannot report a live hold.
    [ "$updated" -ge "$now" ] || continue
    if [ "$state" = Awake ]; then
      if ! is_uint "$hold_pid" || [ "$hold_pid" -le 1 ] || ! kill -0 "$hold_pid" 2>/dev/null; then
        printf 'Error: sleep hold exited; watcher will retry\n'
        continue
      fi
    fi
    printf '%s: %s\n' "$state" "$detail"
  done
}

battery_allows_hold() {
  local batt pct
  batt=$(pmset -g batt 2>/dev/null) || return 1
  case "$batt" in *"AC Power"*) return 0 ;; esac
  pct=$(printf '%s\n' "$batt" | awk 'match($0, /[0-9]+%/) {print substr($0, RSTART, RLENGTH-1); exit}')
  is_uint "$pct" && [ "$pct" -le 100 ] && [ "$pct" -ge "$BATTERY_FLOOR" ]
}

CAF_PID=""
SLEEP_PID=""
RUN_DIR=""
stop_caffeinate() {
  if [ -n "$CAF_PID" ]; then
    kill "$CAF_PID" 2>/dev/null || true
    wait "$CAF_PID" 2>/dev/null || true
    CAF_PID=""
  fi
}
cleanup() {
  stop_caffeinate
  if [ -n "$SLEEP_PID" ]; then kill "$SLEEP_PID" 2>/dev/null || true; fi
  if [ -n "$RUN_DIR" ]; then rm -rf "$RUN_DIR"; fi
}

write_status() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$$" "$(($(date +%s) + HOLD))" "$1" "${CAF_PID:-0}" "$2" > "$RUN_DIR/status.tmp"
  mv "$RUN_DIR/status.tmp" "$RUN_DIR/status"
}

watch() {
  local mode="$1" target="${2:-}" identity="" matches detail state new deadline=0 remaining nap
  if [ "$mode" = pid ]; then
    identity=$(ps -p "$target" -o lstart=) || return 0
    [ "$INTERVAL" -le 2 ] || INTERVAL=2
  elif [ "$mode" = timed ]; then
    deadline=$(($(date +%s) + target))
  fi
  RUN_DIR="$APP_DIR/run/$$"
  mkdir -p "$RUN_DIR" || die "Cannot create $RUN_DIR"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  while true; do
    nap="$INTERVAL"
    case "$mode" in
      pid)
        [ "$(ps -p "$target" -o lstart= 2>/dev/null)" = "$identity" ] || break
        detail="command (PID $target)"
        ;;
      timed)
        remaining=$((deadline - $(date +%s)))
        [ "$remaining" -gt 0 ] || break
        [ "$nap" -le "$remaining" ] || nap="$remaining"
        detail="timed hold ($remaining seconds remaining)"
        ;;
      *)
        matches=$(detect_agents) || die "Unable to read the process list."
        detail=$(printf '%s\n' "$matches" | awk 'NF {printf "%s%s (PID %s)", sep, $2, $1; sep=", "}')
        ;;
    esac
    state="Idle"
    if [ -n "$detail" ]; then
      if battery_allows_hold; then
        # Start the replacement before releasing the old, always bounded hold.
        caffeinate -i -t "$HOLD" &
        new=$!
        stop_caffeinate
        CAF_PID="$new"
        state="Awake"
      else
        stop_caffeinate
        state="Paused"
        detail="battery below $BATTERY_FLOOR% or power status unavailable"
      fi
    else
      stop_caffeinate
      detail="no matching agent sessions"
    fi
    write_status "$state" "$detail"
    sleep "$nap" &
    SLEEP_PID=$!
    wait "$SLEEP_PID" || true
    SLEEP_PID=""
  done
}

case "${1:---watch}" in
  --help|-h) usage; exit 0 ;;
esac
[ "$(uname -s)" = Darwin ] || die "This tool requires macOS."
case "${1:---watch}" in
  --enable|--disable|--restart) service_action "$1"; exit $? ;;
  --status) show_status; exit 0 ;;
esac
load_config
case "${1:---watch}" in
  --watch) watch auto ;;
  --check) detect_agents ;;
  --run)
    shift
    [ "${1:-}" != -- ] || shift
    [ "$#" -gt 0 ] || die "--run requires a command."
    mkdir -p "$APP_DIR"
    # exec preserves stdin, terminal behavior, signals, and the command's exit code.
    # The monitor checks this PID and its start time, and exits after the command.
    /bin/bash "$SRC_DIR/caffeinate-agents.sh" --pid "$$" </dev/null >> "$APP_DIR/wrapper.log" 2>&1 &
    exec "$@"
    ;;
  --pid)
    is_uint "${2:-}" && [ "$2" -gt 1 ] || die "--pid requires a PID greater than 1."
    watch pid "$2"
    ;;
  --hold)
    is_uint "${2:-}" && [ "$2" -gt 0 ] && [ "$2" -le 86400 ] || die "--hold requires 1–86400 seconds."
    watch timed "$2"
    ;;
  *) usage >&2; exit 1 ;;
esac
