# caffeinate-agents

Keep your Mac awake while coding agent CLI sessions are open. Release the sleep hold when they exit, or when the battery gets low.

Works with **Claude Code, Codex CLI, Gemini CLI, OpenCode, GitHub Copilot CLI, Aider, and Cursor CLI**. Detection follows the agent process, so changing models or providers requires no update. Includes an optional SwiftBar menu, a command wrapper, and timed holds for desktop workflows.

Originally built with Claude after seeing a “caffeinate while agents are running” toggle in another app. Free to use, fork, and adapt.

## Install or update

Requires macOS and its built-in Bash, `awk`, `caffeinate`, `pmset`, and `launchd`. No Python, Node, or Homebrew dependency at runtime. Run as your login user, without `sudo`.

```bash
git clone https://github.com/rileycx/caffeinate-agents.git
cd caffeinate-agents
./install.sh
```

To update an existing checkout:

```bash
git pull --ff-only
./install.sh
```

Your settings in `~/.caffeinate-agents/config` survive updates. When upgrading the original version, the old watcher script is saved as `caffeinate-agents.sh.previous`; move any custom settings from that script or the old LaunchAgent into `config`. Updates preserve the watcher's disabled setting.

For the optional menu bar plugin, install [SwiftBar](https://github.com/swiftbar/SwiftBar), then rerun the installer:

```bash
brew install --cask swiftbar
./install.sh
```

## Automatic detection

The watcher starts at login and checks **your user account's processes** every 10 seconds. It recognizes native CLI executables and common Node/Bun/Python entrypoints, including npm/npx installations. It reports only agent names and PIDs; prompts and full command lines are not written to disk.

| Agent | Recognized entrypoints |
| --- | --- |
| Claude Code | `claude`, `@anthropic-ai/claude-code/cli.js` |
| Codex CLI | `codex`, `@openai/codex/bin/codex.js` |
| Gemini CLI | `gemini`, `@google/gemini-cli/dist/index.js` |
| OpenCode | `opencode`, `opencode-ai/bin/opencode` |
| GitHub Copilot CLI | `copilot`, `@github/copilot/index.js` or `cli.js` |
| Aider | `aider`, `python -m aider` |
| Cursor CLI | `cursor-agent`, `agent` or `index.js` under `.cursor/` |

Known server commands such as `codex app-server`, `codex exec-server`, `claude daemon`, `claude remote-control`, and `opencode serve/web` are excluded. A generic Node process, an editor window, or a command whose prompt happens to mention an agent does not count.

**An open CLI session counts even while waiting for input or approval.** Process detection cannot distinguish model reasoning from an idle prompt. Close the session to release its hold. Background server activity, detached work after a CLI exits, desktop apps, and browser tabs are not automatically tracked. Use a timed hold for those workflows. Unusual launchers, runtime flags, or executable paths containing spaces may need `--run`.

The supported command forms are based on the [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference), [Codex CLI reference](https://developers.openai.com/codex/cli/reference), [Gemini installation guide](https://geminicli.com/docs/get-started/installation/), [OpenCode CLI docs](https://opencode.ai/docs/cli/), [Copilot installation guide](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli), and [Cursor CLI docs](https://cursor.com/docs/cli/overview). Fixtures test the recognized process shapes; not every agent distribution is integration-tested.

## Run any command

Use the wrapper for an unsupported CLI, a custom agent script, or a whole sequence of work. It passes arguments, stdin, terminal signals, and the exit status through to the command:

```bash
~/.caffeinate-agents/caffeinate-agents.sh --run codex exec "Finish the migration and run tests"
~/.caffeinate-agents/caffeinate-agents.sh --run python3 my_agent.py
~/.caffeinate-agents/caffeinate-agents.sh --run bash -c 'my-agent && npm test'
```

The monitor follows the command's PID and start time and releases within two seconds of its exit. It covers that command's lifetime, including child work it waits for; detached children that outlive it are not covered. The automatic watcher can independently hold awake for other matching sessions.

For a desktop agent or browser task, start a bounded hold in a terminal:

```bash
# Stay awake for one hour; Ctrl-C ends it early.
~/.caffeinate-agents/caffeinate-agents.sh --hold 3600
```

Both modes work without installing the login watcher: run `./caffeinate-agents.sh` from this checkout. They still respect the battery floor and work even if automatic detection is disabled. The maximum timed hold is 24 hours.

## Status and controls

```bash
# Inspect detection without creating a sleep hold.
~/.caffeinate-agents/caffeinate-agents.sh --check

# Show this tool's current holds and battery pauses.
~/.caffeinate-agents/caffeinate-agents.sh --status

# These settings persist across login.
~/.caffeinate-agents/caffeinate-agents.sh --disable
~/.caffeinate-agents/caffeinate-agents.sh --enable
```

SwiftBar displays the same status: green for an active hold, amber for a battery pause, and gray otherwise. It shows detected agents and lets you toggle automatic detection, edit settings, and reload the watcher. Other applications' `caffeinate` processes do not affect its status. Disabling automatic detection leaves explicitly started wrappers and timers running.

## Configure

Edit `~/.caffeinate-agents/config`. It contains shell assignments and is sourced as your user, so only put trusted content there. Environment variables override file settings for manual invocations.

| Variable | Default | Meaning |
| --- | --- | --- |
| `AGENT_PROCESSES` | `claude codex gemini opencode copilot aider cursor-agent` | Agent names to detect; an empty string disables automatic process matches |
| `EXTRA_AGENT_PROCESSES` | empty | Additional exact executable names, separated by spaces |
| `BATTERY_FLOOR` | `10` | On battery, release below this percentage; exactly 10% is allowed |
| `INTERVAL` | `10` | Poll interval in seconds, from 1 to 3600 |
| `HOLD` | `25` | Each assertion's maximum lifetime; must exceed `INTERVAL`, at most 86400 |

For example:

```bash
AGENT_PROCESSES="claude codex gemini"
EXTRA_AGENT_PROCESSES="my-agent"
BATTERY_FLOOR=20
```

Names are literal executable basenames, not regular expressions. Avoid adding `node`, `python`, or GUI app names: doing so would keep the Mac awake for unrelated work too.

Apply changes to the installed watcher:

```bash
~/.caffeinate-agents/caffeinate-agents.sh --restart
```

A restart also enables a disabled watcher. Running wrappers and timers read configuration at startup; restart those commands to apply changes. Logs live in `~/.caffeinate-agents/watcher.log` and `wrapper.log`. For isolated manual runs/tests, `CAFFEINATE_AGENTS_HOME` can point at another configuration and state directory; installer and service controls always target the standard login installation.

## Sleep and battery behavior

Each hold uses `caffeinate -i -t 25`: it prevents **idle system sleep**, while allowing the display to turn off and lock normally. The watcher starts a replacement before releasing the previous hold. Normal exit releases immediately; if a watcher crashes or is force-killed, its last hold expires within `HOLD` seconds.

AC power allows a hold regardless of charge. On battery, charge below the floor releases it at the next check. Unavailable or unreadable power status also releases it. Work can continue running after a battery pause; this tool does not stop agent processes or force the Mac to sleep.

Closing the lid or choosing Sleep can still suspend the Mac. This tool does not override those actions or protect against network loss. macOS and other applications may independently prevent sleep after this tool releases its hold.

## Uninstall

```bash
./uninstall.sh          # Keep configuration and logs for reinstalling.
./uninstall.sh --purge  # Also remove saved configuration and logs.
```

Removes the login watcher and SwiftBar plugin. It does not kill other applications' sleep holds or uninstall SwiftBar. Separately started wrappers and timers continue until their command or timer ends; stop them before uninstalling if you want all of this tool's holds released immediately.

## Development

```bash
python3 -m unittest discover -s tests -v
```

Tests use mocked process, battery, sleep-hold, and service commands. CI runs on macOS (including the system Bash 3.2) and Linux. Python is only needed for tests.

## License

MIT — see [LICENSE](LICENSE).
