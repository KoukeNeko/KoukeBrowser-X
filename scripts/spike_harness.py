"""
Shared plumbing for driving the app through its DebugAutomation harness.

The command-line build is ad-hoc signed without entitlements, so it is not
sandboxed: it writes its harness directory under TMPDIR instead of a container,
and it coexists with an instance launched from Xcode because the two watch
different directories. Nothing here disturbs an app you already have running.
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_PATH = REPO_ROOT / "build" / "DerivedData" / "Build" / "Products" / "Debug" / "Ciruvo.app"
APP_BINARY = APP_PATH / "Contents" / "MacOS" / "Ciruvo"
FIXTURES_DIR = REPO_ROOT / "scripts" / "fixtures"

LAUNCH_LOG = Path(tempfile.gettempdir()) / "kouke-harness-launch.log"
WORKING_DIR_LOG_PATTERN = re.compile(r"DebugAutomation: watching (.+)$", re.MULTILINE)

APP_LAUNCH_TIMEOUT_SECONDS = 45
APP_PING_TIMEOUT_SECONDS = 3
COMMAND_TIMEOUT_SECONDS = 45
POLL_INTERVAL_SECONDS = 0.25

GREEN, RED, YELLOW, RESET = "\033[32m", "\033[31m", "\033[33m", "\033[0m"


class SpikeFailure(Exception):
    """A check failed or the harness could not continue."""


def wait_until(produce_value, is_acceptable, timeout=10.0, interval=0.25):
    """Polls until a value is acceptable, then returns it.

    Preferred over a fixed sleep: the app's timing shifts with machine load, and
    a sleep long enough to be reliable there wastes time on every other run.
    Returns the last value seen when the timeout expires, so the caller's own
    assertion reports the real mismatch rather than a timeout.
    """
    deadline = time.time() + timeout
    value = produce_value()
    while time.time() < deadline:
        if is_acceptable(value):
            return value
        time.sleep(interval)
        value = produce_value()
    return value


def check(description, passed, detail=""):
    """Prints one assertion line and returns whether it passed."""
    marker = f"{GREEN}PASS{RESET}" if passed else f"{RED}FAIL{RESET}"
    suffix = f"  ({detail})" if detail else ""
    print(f"  [{marker}] {description}{suffix}")
    return passed


class FixtureServer:
    """Serves fixture pages over HTTP.

    Extensions are not granted access to file:// URLs, so a page loaded from
    disk never receives its content scripts. Real login pages arrive over HTTP
    anyway, which makes this both necessary and more faithful.
    """

    def __init__(self, directory):
        self._server = ThreadingHTTPServer(
            ("127.0.0.1", 0),
            partial(SimpleHTTPRequestHandler, directory=str(directory)),
        )
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)

    def start(self):
        self._thread.start()
        return self

    @property
    def base_url(self):
        host, port = self._server.server_address
        return f"http://{host}:{port}"

    def stop(self):
        self._server.shutdown()
        self._server.server_close()


class HarnessClient:
    """Speaks the DebugAutomation command-file protocol."""

    def __init__(self, working_dir):
        self.working_dir = working_dir
        self.command_file = working_dir / "command.json"
        # Seeded from the clock so a previous run's higher sequence number
        # cannot make the app ignore this run's commands.
        self._sequence = int(time.time())

    def send(self, command, timeout=COMMAND_TIMEOUT_SECONDS, **arguments):
        self._sequence += 1
        sequence = self._sequence

        payload = {"seq": sequence, "cmd": command}
        payload.update(arguments)

        result_file = self.working_dir / f"result-{sequence}.json"
        result_file.unlink(missing_ok=True)

        self.command_file.write_text(json.dumps(payload))

        deadline = time.time() + timeout
        while time.time() < deadline:
            if result_file.exists():
                try:
                    result = json.loads(result_file.read_text())
                except json.JSONDecodeError:
                    time.sleep(POLL_INTERVAL_SECONDS)
                    continue
                if not result.get("ok"):
                    raise SpikeFailure(f"{command} failed: {result.get('message')}")
                return result.get("message", "")
            time.sleep(POLL_INTERVAL_SECONDS)

        raise SpikeFailure(f"{command} timed out after {timeout}s")


class AppSession:
    """Owns the app process launched for this run."""

    def __init__(self):
        self.process = None
        self.client = None
        self._temp_dir = None

    def start(self):
        if not APP_BINARY.exists():
            raise SpikeFailure(f"App not built. Run scripts/build.sh first (looked in {APP_PATH})")

        LAUNCH_LOG.unlink(missing_ok=True)
        log_handle = LAUNCH_LOG.open("w")

        # Every unsandboxed instance derives its harness directory from
        # NSTemporaryDirectory(), so instances left over from earlier runs would
        # otherwise poll the same command file and race to answer. A private
        # directory gives this run one nothing else is watching.
        self._temp_dir = tempfile.mkdtemp(prefix="kouke-harness-")
        environment = {**os.environ, "KOUKE_DEBUG_DIR": self._temp_dir}

        # start_new_session keeps the app alive independently of this script's
        # process group, which would otherwise take it down on exit.
        self.process = subprocess.Popen(
            [str(APP_BINARY)],
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            env=environment,
        )

        working_dir = self._await_working_dir()
        print(f"App harness directory: {working_dir}")
        self.client = HarnessClient(working_dir)
        self._await_responsive()
        return self.client

    def _await_working_dir(self):
        deadline = time.time() + APP_LAUNCH_TIMEOUT_SECONDS
        while time.time() < deadline:
            if self.process.poll() is not None:
                raise SpikeFailure(f"App exited during launch; see {LAUNCH_LOG}")
            if LAUNCH_LOG.exists():
                match = WORKING_DIR_LOG_PATTERN.search(LAUNCH_LOG.read_text(errors="replace"))
                if match:
                    return Path(match.group(1).strip())
            time.sleep(POLL_INTERVAL_SECONDS)
        raise SpikeFailure(f"App never reported its harness directory; see {LAUNCH_LOG}")

    def _await_responsive(self):
        deadline = time.time() + APP_LAUNCH_TIMEOUT_SECONDS
        while time.time() < deadline:
            try:
                self.client.send("state", timeout=APP_PING_TIMEOUT_SECONDS)
                return
            except SpikeFailure:
                continue
        raise SpikeFailure("App never answered a state command")

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
        if self._temp_dir:
            shutil.rmtree(self._temp_dir, ignore_errors=True)
