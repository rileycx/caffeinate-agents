# caffeinate-agents

Keep your Mac awake while AI coding agents are running — and let it sleep the moment they stop.

> Built in about 5 prompts with [Claude](https://claude.com/claude-code). I saw a "caffeinate while agents are running" toggle in another app, thought it was a good idea, and asked Claude to recreate it. This repo is the result: the scripts, an installer, and an optional menu bar toggle. Free to use, fork, and steal.

## What it does

If you kick off a long agent run and walk away, your Mac sleeps and the work stalls. This fixes that:

- **Stays awake only while agents run.** Watches for a running `claude` process (configurable) and holds the Mac awake. When the agent finishes, normal sleep resumes — it doesn't keep your Mac up all day.
- **Battery cutoff.** On battery below 10%, it backs off and lets the Mac sleep, so it won't drain a dying laptop.
- **Optional menu bar toggle.** If you have [SwiftBar](https://github.com/swiftbar/SwiftBar), you get a ☕️ icon showing status with an on/off switch.
- **Self-healing.** Each "stay awake" hold is short-lived and refreshed every 20s, so even a hard crash can't leave your Mac stuck awake.

It's a thin wrapper around macOS's built-in `caffeinate`, `pmset`, and `launchd`. No daemon you have to trust, ~60 lines of bash.

## Install

```bash
git clone https://github.com/rileycx/caffeinate-agents.git
cd caffeinate-agents
./install.sh
```

That's it. The watcher auto-starts on login. Want the menu bar toggle too? Install SwiftBar first, then re-run the installer:

```bash
brew install --cask swiftbar
./install.sh
```

## Usage

Nothing to do — it runs in the background. While an agent is working, your Mac stays awake; when it stops, your Mac sleeps as usual.

With SwiftBar, click the ☕️ in your menu bar to see status or flip the automation off/on:

- **● Keeping Mac awake** — an agent is running, Mac held awake
- **○ Idle — no agents running** — automation on, nothing to do
- **○ Disabled** — automation off

## Configure

Defaults live at the top of `~/.caffeinate-agents/caffeinate-agents.sh`. Override with environment variables in the LaunchAgent, or just edit the file:

| Variable | Default | Meaning |
|---|---|---|
| `AGENT_PROCESSES` | `claude` | Space-separated process names to watch (e.g. `"claude node cursor"`) |
| `BATTERY_FLOOR` | `10` | On battery, stop holding awake below this % |
| `INTERVAL` | `20` | Seconds between checks |
| `HOLD` | `35` | Seconds each awake-hold lasts before refresh (must be > `INTERVAL`) |

After editing, reload it:

```bash
launchctl unload ~/Library/LaunchAgents/com.caffeinate-agents.plist
launchctl load   ~/Library/LaunchAgents/com.caffeinate-agents.plist
```

## How it works

A small `launchd` agent runs a loop. Every 20 seconds it checks:

1. Is any watched process running? (`pgrep -x claude`)
2. Are we on AC power, or above the battery floor?

If both are true, it holds a `caffeinate -i -t 35` (prevent idle sleep for 35s) and refreshes it each loop. If not, it drops the hold. Because the hold is time-bounded, a crashed or force-killed watcher can never keep your Mac awake longer than `HOLD` seconds.

## Uninstall

```bash
./uninstall.sh
```

Removes the LaunchAgent, the watcher, and the SwiftBar plugin. Leaves SwiftBar itself installed.

## Requirements

macOS (uses `caffeinate`, `pmset`, `launchd`). SwiftBar is optional, only for the menu bar toggle.

## License

MIT — see [LICENSE](LICENSE).
