"""Regression tests using fake OS commands; never change the host's power/service state."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "caffeinate-agents.sh"
NAMES = "claude codex gemini opencode copilot aider cursor-agent"


class DetectionTests(unittest.TestCase):
    def detect(self, command, names=NAMES, extra="", uid=501, state="S"):
        result = subprocess.run(
            ["awk", "-v", "user_id=501", "-v", f"names={names}",
             "-v", f"extra={extra}", "-f", str(ROOT / "detect-agents.awk")],
            input=f"123 {uid} {state} {command}\n", text=True, capture_output=True, check=True)
        return result.stdout.strip()

    def test_native_agents_and_model_independence(self):
        for name in NAMES.split():
            with self.subTest(name=name):
                self.assertEqual(self.detect(f"/opt/homebrew/bin/{name} --model any-future-model"), f"123\t{name}")

    def test_runtime_entrypoints(self):
        cases = {
            "node /usr/lib/node_modules/@anthropic-ai/claude-code/cli.js -p test": "claude",
            "node /usr/lib/node_modules/@openai/codex/bin/codex.js exec test": "codex",
            "node /Users/test/.npm/_npx/hash/node_modules/@google/gemini-cli/dist/index.js": "gemini",
            "bun /usr/lib/node_modules/@github/copilot/index.js": "copilot",
            "node /usr/lib/node_modules/opencode-ai/bin/opencode run test": "opencode",
            "/usr/bin/python3 /Users/test/.local/bin/aider": "aider",
            "python3.12 -m aider": "aider",
            "python3 -u -m aider": "aider",
            "node --enable-source-maps /usr/lib/node_modules/@google/gemini-cli/dist/index.js": "gemini",
            "/Users/test/.cursor/versions/latest/agent -p test": "cursor-agent",
            "node /Users/test/.cursor/versions/latest/index.js -p test": "cursor-agent",
        }
        for command, name in cases.items():
            with self.subTest(command=command):
                self.assertEqual(self.detect(command), f"123\t{name}")

    def test_false_positives(self):
        for command in [
            "node server.js", "node -e claude", "python3 unrelated.py codex",
            "bash -c codex", "rg claude", "vim /tmp/codex", "agent unrelated-task",
            "claude-helper", "codex-code-mode-host", "/Applications/Cursor.app/Contents/MacOS/Cursor",
            "node /tmp/@openai/codex/bin/codex.js.bak", "sleep 5", "",
        ]:
            with self.subTest(command=command):
                self.assertEqual(self.detect(command), "")
        self.assertEqual(self.detect("codex", uid=502), "")
        self.assertEqual(self.detect("codex", state="Z"), "")
        self.assertEqual(self.detect("codex", state="T"), "")

    def test_servers_and_prompts(self):
        for command in ["codex app-server --listen stdio://", "codex exec-server", "codex mcp-server",
                        "claude daemon start", "claude remote-control", "claude gateway", "opencode serve",
                        "opencode web", "codex --version", "node /bin/codex app-server",
                        "codex -c model=example --enable daemon app-server",
                        "codex --config=model=example app-server", "claude --dangerously-skip-permissions daemon start"]:
            with self.subTest(command=command):
                self.assertEqual(self.detect(command), "")
        self.assertEqual(self.detect("codex exec explain app-server"), "123\tcodex")
        self.assertEqual(self.detect("claude -p explain daemon"), "123\tclaude")

    def test_configuration(self):
        self.assertEqual(self.detect("codex", names="claude"), "")
        self.assertEqual(self.detect("codex", names=""), "")
        self.assertEqual(self.detect("/bin/my-agent", extra="my-agent"), "123\tmy-agent")
        self.assertEqual(self.detect("/bin/my-agent-helper", extra="my-agent"), "")


class WatcherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="caffeinate test ")
        self.base = Path(self.temp.name)
        self.app = self.base / "app"
        self.bin = self.base / "bin"
        self.app.mkdir()
        self.bin.mkdir()
        self.env = dict(os.environ, CAFFEINATE_AGENTS_HOME=str(self.app),
                        PATH=f"{self.bin}:{os.environ['PATH']}", INTERVAL="1", HOLD="3",
                        AGENT_PROCESSES=NAMES, EXTRA_AGENT_PROCESSES="", BATTERY_FLOOR="10",
                        TEST_DATA=str(self.base))
        self.processes = []
        self.write("processes", f"987 {os.getuid()} S /bin/codex exec test\n")
        self.write("battery", "Now drawing from 'AC Power'\n")
        self.stub("uname", "echo Darwin")
        self.stub("launchctl", "exit 1")
        self.stub("ps", f'if [ "$1" = -axww ]; then cat "$TEST_DATA/processes"; else exec {shutil.which("ps")} "$@"; fi')
        self.stub("pmset", 'cat "$TEST_DATA/battery"')
        self.stub("caffeinate", 'echo "$$ $*" >> "$TEST_DATA/holds"\nexec sleep "$3"')

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)
            process.stderr.close()
        self.temp.cleanup()

    def write(self, name, value):
        (self.base / name).write_text(value)

    def stub(self, name, body):
        file = self.bin / name
        file.write_text("#!/bin/bash\n" + body + "\n")
        file.chmod(0o755)

    def run_cli(self, *args, env=None, **kwargs):
        return subprocess.run(["/bin/bash", str(CLI), *args], env=env or self.env,
                              text=True, capture_output=True, timeout=8, **kwargs)

    def start(self, *args):
        process = subprocess.Popen(["/bin/bash", str(CLI), *args], env=self.env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        self.processes.append(process)
        return process

    def wait_for(self, predicate, timeout=5):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if predicate():
                return
            time.sleep(0.05)
        self.fail("Condition did not become true")

    def status(self):
        return self.run_cli("--status").stdout

    def test_awake_idle_and_signal_cleanup(self):
        watcher = self.start()
        self.wait_for(lambda: "Awake:" in self.status())
        self.assertIn("codex (PID 987)", self.status())
        self.wait_for(lambda: (self.base / "holds").exists())
        self.assertIn("-i -t 3", (self.base / "holds").read_text())
        self.write("processes", "")
        self.wait_for(lambda: "Idle:" in self.status())
        self.write("processes", f"988 {os.getuid()} S claude\n")
        self.wait_for(lambda: "Awake:" in self.status())
        watcher.terminate()
        self.assertEqual(watcher.wait(timeout=3), 143)
        self.assertFalse(list(self.app.glob("run/*/status")))
        for line in (self.base / "holds").read_text().splitlines():
            with self.assertRaises(ProcessLookupError):
                os.kill(int(line.split()[0]), 0)

    def test_battery_threshold_and_unknown_status(self):
        self.write("battery", "Now drawing from 'Battery Power'\n9%; discharging\n")
        self.start()
        self.wait_for(lambda: "Paused:" in self.status())
        self.assertFalse((self.base / "holds").exists())
        self.write("battery", "Now drawing from 'Battery Power'\n10%; discharging\n")
        self.wait_for(lambda: "Awake:" in self.status())
        self.write("battery", "unknown")
        self.wait_for(lambda: "Paused:" in self.status())
        self.write("battery", "Now drawing from 'AC Power'\n1%; charging\n")
        self.wait_for(lambda: "Awake:" in self.status())

    def test_invalid_configuration(self):
        for key, value in [("INTERVAL", "0"), ("HOLD", "1"), ("BATTERY_FLOOR", "101"),
                           ("HOLD", "abc"), ("INTERVAL", "08"), ("AGENT_PROCESSES", "claude.*")]:
            with self.subTest(key=key, value=value):
                result = self.run_cli("--check", env=dict(self.env, **{key: value}))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("caffeinate-agents:", result.stderr)

    def test_config_and_environment_precedence(self):
        (self.app / "config").write_text('AGENT_PROCESSES="claude"\n')
        self.assertIn("codex", self.run_cli("--check").stdout)
        env = dict(self.env)
        del env["AGENT_PROCESSES"]
        self.assertEqual(self.run_cli("--check", env=env).stdout, "")
        self.assertEqual(self.run_cli("--check", env=dict(env, AGENT_PROCESSES="")).stdout, "")

    def test_timed_hold_and_status_expiry(self):
        started = time.monotonic()
        watcher = self.start("--hold", "1")
        self.wait_for(lambda: "Awake: timed hold" in self.status())
        self.assertEqual(watcher.wait(timeout=4), 0)
        self.assertGreaterEqual(time.monotonic() - started, 0.9)
        self.assertNotIn("Awake:", self.status())
        stale = self.app / "run" / "stale"
        stale.mkdir(parents=True)
        (stale / "status").write_text(f"{os.getpid()}\t1\tAwake\t0\tstale\n")
        self.assertNotIn("stale", self.status())

    def test_wrapper_preserves_io_arguments_exit_status_and_releases(self):
        result = self.run_cli("--run", "/bin/bash", "-c", 'read -r line; printf "%s|%s" "$line" "$1"; sleep 1; exit 7',
                              "test", "literal $value with spaces", input="hello\n")
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(result.stdout, "hello|literal $value with spaces")
        self.assertTrue((self.base / "holds").exists())
        self.wait_for(lambda: not list(self.app.glob("run/*/status")))

    def test_wrapper_respects_battery_floor(self):
        self.write("battery", "Now drawing from 'Battery Power'\n5%; discharging\n")
        result = self.run_cli("--run", "/bin/sleep", "1")
        self.assertEqual(result.returncode, 0)
        self.assertFalse((self.base / "holds").exists())
        self.wait_for(lambda: not list(self.app.glob("run/*/status")))


    def test_failed_hold_is_not_reported_as_awake(self):
        self.stub("caffeinate", "exit 1")
        self.start()
        self.wait_for(lambda: "Error: sleep hold exited" in self.status())

    def test_concurrent_holds_are_independent(self):
        first = self.start("--hold", "20")
        second = self.start("--hold", "20")
        self.wait_for(lambda: self.status().count("Awake:") == 2)
        first.terminate()
        first.wait(timeout=3)
        self.assertEqual(self.status().count("Awake:"), 1)
        self.assertIsNone(second.poll())

    def test_wrapper_handles_missing_command_and_termination(self):
        result = self.run_cli("--run", "command-that-does-not-exist-caffeinate-test")
        self.assertEqual(result.returncode, 127)
        wrapped = self.start("--run", "/bin/sleep", "30")
        self.wait_for(lambda: "Awake:" in self.status())
        wrapped.terminate()
        self.assertEqual(wrapped.wait(timeout=3), -signal.SIGTERM)
        self.wait_for(lambda: not list(self.app.glob("run/*/status")))


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="caffeinate install & test ")
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.app = self.home / ".caffeinate-agents"
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:{os.environ['PATH']}",
                        TEST_DATA=str(self.base), CAFFEINATE_AGENTS_HOME=str(self.app))
        for key in ("AGENT_PROCESSES", "EXTRA_AGENT_PROCESSES", "HOLD", "INTERVAL", "BATTERY_FLOOR"):
            self.env.pop(key, None)
        self.stub("uname", "echo Darwin")
        self.stub("id", "echo 501")
        self.stub("ps", "exit 0")
        self.stub("open", "exit 0")
        self.stub("defaults", 'if [ "$1" = read ]; then echo "$TEST_DATA/plugins"; fi')
        self.stub("plutil", "exit 0")
        self.stub("launchctl", '''echo "$*" >> "$TEST_DATA/services"
case "$1" in
  print-disabled) if [ -f "$TEST_DATA/disabled" ]; then echo '"com.caffeinate-agents" => true'; fi ;;
  print) exit 1 ;;
esac''')

    def tearDown(self):
        self.temp.cleanup()

    def stub(self, name, body):
        file = self.bin / name
        file.write_text("#!/bin/bash\n" + body + "\n")
        file.chmod(0o755)

    def script(self, script, *args):
        result = subprocess.run(["/bin/bash", str(ROOT / script), *args], env=self.env,
                                text=True, capture_output=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_install_upgrade_xml_and_preserved_config(self):
        import plistlib
        self.script("install.sh")
        plist = self.home / "Library/LaunchAgents/com.caffeinate-agents.plist"
        data = plistlib.loads(plist.read_bytes())
        self.assertEqual(data["ProgramArguments"][1], str(self.app / "caffeinate-agents.sh"))
        self.assertEqual(data["EnvironmentVariables"]["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
        (self.app / "config").write_text("BATTERY_FLOOR=37\n")
        self.script("install.sh")
        self.assertEqual((self.app / "config").read_text(), "BATTERY_FLOOR=37\n")
        self.assertIn("bootstrap gui/501", (self.base / "services").read_text())

    def test_disabled_setting_survives_upgrade(self):
        (self.base / "disabled").touch()
        self.script("install.sh")
        calls = (self.base / "services").read_text()
        self.assertNotIn("bootstrap", calls)
        self.assertNotIn("enable gui", calls)

    def test_legacy_script_is_backed_up(self):
        self.app.mkdir()
        (self.app / "caffeinate-agents.sh").write_text("# legacy customized script\n")
        self.script("install.sh")
        self.assertEqual((self.app / "caffeinate-agents.sh.previous").read_text(), "# legacy customized script\n")

    def test_uninstall_preserves_config_and_does_not_kill_unrelated_holds(self):
        self.script("install.sh")
        self.stub("pkill", 'touch "$TEST_DATA/unwanted-pkill"; exit 1')
        self.script("uninstall.sh")
        self.assertTrue((self.app / "config").exists())
        self.assertFalse((self.app / "caffeinate-agents.sh").exists())
        self.assertFalse((self.base / "unwanted-pkill").exists())
        self.assertFalse((self.home / "Library/LaunchAgents/com.caffeinate-agents.plist").exists())
        self.script("uninstall.sh", "--purge")
        self.assertFalse(self.app.exists())

    def test_service_controls_persist_and_use_modern_launchctl(self):
        self.script("install.sh")
        self.script("caffeinate-agents.sh", "--disable")
        self.script("caffeinate-agents.sh", "--enable")
        self.script("caffeinate-agents.sh", "--restart")
        calls = (self.base / "services").read_text()
        self.assertIn("disable gui/501/com.caffeinate-agents", calls)
        self.assertIn("enable gui/501/com.caffeinate-agents", calls)
        self.assertIn("kickstart gui/501/com.caffeinate-agents", calls)
        self.assertNotIn("unload", calls)


if __name__ == "__main__":
    unittest.main()
