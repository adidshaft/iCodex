"""iCodex menu bar app — clean status icon with server controls and device management."""

from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import sys
import time as _time
import urllib.request
from pathlib import Path

import rumps

PORT = 8642
BACKEND_DIR = Path(__file__).resolve().parent
AUTH_FILE = Path.home() / ".codex" / "icodex_auth.json"
DATA_DIR = Path.home() / "Library" / "Application Support" / "iCodex-Connect"
LOG_DIR = DATA_DIR / "logs"

# ── Python discovery chain ────────────────────────────────────────────────────
# 1. app-support venv  2. venv in current dir  3. running interpreter

_VENV_CANDIDATES = [
    DATA_DIR / "venv" / "bin" / "python",
    BACKEND_DIR / "venv" / "bin" / "python",
    Path.home() / "Library" / "iCodex" / "MacBackend" / "venv" / "bin" / "python",
]

PYTHON = sys.executable  # default: the embedded/running Python
for _p in _VENV_CANDIDATES:
    if _p.is_file():
        PYTHON = str(_p)
        break


# ── Auto-setup helpers ────────────────────────────────────────────────────────


def _ensure_dependencies():
    """Create venv + install deps if missing. Best-effort, won't block startup."""
    venv_dir = BACKEND_DIR / "venv"
    req_file = BACKEND_DIR / "requirements.txt"

    if (venv_dir / "bin" / "python").exists():
        return  # already set up

    try:
        subprocess.run(
            [sys.executable, "-m", "venv", str(venv_dir)],
            check=True, timeout=60, capture_output=True,
        )
        pip = str(venv_dir / "bin" / "pip")
        subprocess.run(
            [pip, "install", "-q", "--upgrade", "pip"],
            check=True, timeout=120, capture_output=True,
        )
        if req_file.exists():
            subprocess.run(
                [pip, "install", "-q", "-r", str(req_file)],
                check=True, timeout=300, capture_output=True,
            )
        # Update PYTHON to use the new venv
        global PYTHON
        PYTHON = str(venv_dir / "bin" / "python")
    except Exception:
        pass


def _free_port(port: int) -> None:
    """Kill whatever is occupying *port*. Waits up to 2 s for release."""
    try:
        result = subprocess.run(
            ["lsof", f"-ti:{port}"],
            capture_output=True, text=True, timeout=5,
        )
        for pid in result.stdout.strip().splitlines():
            pid = pid.strip()
            if pid:
                try:
                    os.kill(int(pid), signal.SIGTERM)
                except (ProcessLookupError, ValueError):
                    pass
        _time.sleep(1)
        # Force-kill if still alive
        result = subprocess.run(
            ["lsof", f"-ti:{port}"],
            capture_output=True, text=True, timeout=5,
        )
        for pid in result.stdout.strip().splitlines():
            pid = pid.strip()
            if pid:
                try:
                    os.kill(int(pid), signal.SIGKILL)
                except (ProcessLookupError, ValueError):
                    pass
        _time.sleep(0.5)
    except Exception:
        pass


# ── Small utilities ───────────────────────────────────────────────────────────


def _get_local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(2)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def _is_port_in_use(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("127.0.0.1", port)) == 0


def _read_passcode() -> str:
    try:
        data = json.loads(AUTH_FILE.read_text())
        return data.get("setup_passcode", "------")
    except Exception:
        return "------"


def _copy(text: str) -> None:
    try:
        subprocess.run(["pbcopy"], input=text.encode(), check=True, timeout=5)
    except Exception:
        pass


def _server_get(path: str) -> object:
    """GET a JSON endpoint from the local server (internal use)."""
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{PORT}{path}")
        req.add_header("X-Internal", "menubar")
        with urllib.request.urlopen(req, timeout=2) as resp:
            return json.loads(resp.read())
    except Exception:
        return None


def _server_post(path: str) -> bool:
    try:
        req = urllib.request.Request(
            f"http://127.0.0.1:{PORT}{path}",
            data=b"",
            method="POST",
        )
        req.add_header("X-Internal", "menubar")
        urllib.request.urlopen(req, timeout=5)
        return True
    except Exception:
        return False


# ── Accessibility permission ──────────────────────────────────────────────────


def _find_keystroke_helper() -> str | None:
    """Find the icodex_keystroke binary inside the .app bundle or nearby."""
    from pathlib import Path
    here = Path(__file__).resolve().parent
    # Inside .app bundle: .../Contents/Resources/MacBackend/ → ../../MacOS/
    app_helper = here.parent.parent / "MacOS" / "icodex_keystroke"
    if app_helper.is_file():
        return str(app_helper)
    # Dev: next to this file
    local = here / "icodex_keystroke_bin"
    if local.is_file():
        return str(local)
    return None

_KEYSTROKE_HELPER = _find_keystroke_helper()


def _check_accessibility() -> bool:
    """Return True if iCodex-Connect has Accessibility (post-event) access.

    Uses the native icodex_keystroke helper which lives inside the .app
    bundle, so its permission maps to iCodex-Connect in System Settings.
    """
    if not _KEYSTROKE_HELPER:
        return False
    try:
        r = subprocess.run(
            [_KEYSTROKE_HELPER, "check"],
            capture_output=True, text=True, timeout=5,
        )
        return r.stdout.strip() == "granted"
    except Exception:
        return False


def _request_accessibility():
    """Trigger the macOS native Accessibility permission prompt."""
    if not _KEYSTROKE_HELPER:
        return
    try:
        subprocess.run(
            [_KEYSTROKE_HELPER, "request"],
            capture_output=True, timeout=5,
        )
    except Exception:
        pass


def _open_accessibility_settings():
    """Open System Settings → Privacy & Security → Accessibility pane."""
    subprocess.run(
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"],
        check=False,
    )



# ── Menu-bar App ──────────────────────────────────────────────────────────────


# Status icons (menu-bar title text)
ICON_RUNNING_CONNECTED = "◉"   # server up + device paired
ICON_RUNNING            = "◎"   # server up, no device
ICON_STOPPED            = "○"   # server down

A11Y_CACHE_SECONDS = 30
A11Y_PENDING_POLL_SECONDS = 5
A11Y_PENDING_WATCH_SECONDS = 60


class ICodexMenuBarApp(rumps.App):
    def __init__(self):
        super().__init__(name="iCodex", title=ICON_STOPPED, quit_button=None)

        self._server_proc: subprocess.Popen | None = None
        self._devices: list[dict] = []

        # ── Menu items ────────────────────────────────────────────────────
        self.status_item = rumps.MenuItem("Server: Starting…")
        self.status_item.set_callback(None)

        self.start_stop_item = rumps.MenuItem(
            "▶  Start Server", callback=self.on_start_stop,
        )

        local_ip = _get_local_ip()
        self.url_item = rumps.MenuItem(
            f"  http://{local_ip}:{PORT}  ⧉",
            callback=self.on_copy_url,
        )

        self.passcode_item = rumps.MenuItem(
            f"  Passcode: ------  ⧉",
            callback=self.on_copy_passcode,
        )

        self.devices_menu = rumps.MenuItem("Devices (0)")
        # Don't call _rebuild_devices_menu() here — NSMenu isn't created until run()

        self.a11y_item = rumps.MenuItem(
            "⚠ Accessibility: Checking…",
            callback=self.on_open_accessibility,
        )

        self.quit_item = rumps.MenuItem("Quit iCodex", callback=self.on_quit)

        self.menu = [
            self.status_item,
            None,
            self.start_stop_item,
            None,
            self.url_item,
            self.passcode_item,
            None,
            self.a11y_item,
            self.devices_menu,
            None,
            self.quit_item,
        ]

        # ── Auto-setup ────────────────────────────────────────────────────
        _ensure_dependencies()

        self._a11y_granted: bool | None = None  # cached result
        self._a11y_last_check: float = 0
        self._a11y_watch_until: float = 0
        self._startup_a11y_guidance_timer: rumps.Timer | None = None
        self._show_startup_a11y_guidance = os.environ.get("ICODEX_SHOW_A11Y_GUIDANCE") == "1"

        # ── Auto-start server ─────────────────────────────────────────────
        if not _is_port_in_use(PORT):
            self._start_server()
        # else: adopt whatever is already on the port

        # ── Periodic refresh ──────────────────────────────────────────────
        self._timer = rumps.Timer(self._refresh, 5)
        self._timer.start()
        self._refresh(None)
        if self._show_startup_a11y_guidance:
            self._startup_a11y_guidance_timer = rumps.Timer(self._show_a11y_guidance_once, 1)
            self._startup_a11y_guidance_timer.start()

    # ── Refresh loop ──────────────────────────────────────────────────────

    def _show_a11y_guidance_once(self, _sender):
        if self._startup_a11y_guidance_timer is not None:
            self._startup_a11y_guidance_timer.stop()
            self._startup_a11y_guidance_timer = None

        if _check_accessibility():
            self._a11y_granted = True
            self._a11y_last_check = _time.time()
            self._a11y_watch_until = 0
            self._refresh(None)
            return

        rumps.notification(
            "iCodex-Connect",
            "Grant Accessibility",
            "System Settings is opening. Add iCodex-Connect and toggle it ON, then return to the menu bar.",
        )
        _open_accessibility_settings()

    def _refresh(self, _sender):
        running = _is_port_in_use(PORT)
        passcode = _read_passcode()
        local_ip = _get_local_ip()

        # Fetch device list from server
        if running:
            data = _server_get("/internal/devices")
            self._devices = data if isinstance(data, list) else []
        else:
            self._devices = []

        has_devices = len(self._devices) > 0

        # ── Menu-bar icon ─────────────────────────────────────────────────
        if running and has_devices:
            self.title = ICON_RUNNING_CONNECTED
        elif running:
            self.title = ICON_RUNNING
        else:
            self.title = ICON_STOPPED

        # ── Menu text ─────────────────────────────────────────────────────
        if running:
            self.status_item.title = "Server: Running"
            self.start_stop_item.title = "■  Stop Server"
        else:
            self.status_item.title = "Server: Stopped"
            self.start_stop_item.title = "▶  Start Server"

        self.url_item.title = f"  http://{local_ip}:{PORT}  ⧉"
        self.passcode_item.title = f"  Passcode: {passcode}  ⧉"

        # ── Accessibility status (cached, re-check every 30s) ────────────
        now = _time.time()
        poll_interval = (
            A11Y_PENDING_POLL_SECONDS
            if now < self._a11y_watch_until
            else A11Y_CACHE_SECONDS
        )
        if self._a11y_granted is None or now - self._a11y_last_check > poll_interval:
            self._a11y_granted = _check_accessibility()
            self._a11y_last_check = now
            if self._a11y_granted:
                self._a11y_watch_until = 0
        if self._a11y_granted:
            self.a11y_item.title = "✓ Accessibility: Granted"
        else:
            self.a11y_item.title = "⚠ Accessibility: Not Granted (click to fix)"

        # ── Devices submenu ───────────────────────────────────────────────
        self._rebuild_devices_menu()

        # ── Subprocess health check ───────────────────────────────────────
        if self._server_proc is not None and self._server_proc.poll() is not None:
            self._server_proc = None
            # Auto-restart if it crashed
            if not _is_port_in_use(PORT):
                self._start_server()

    def _rebuild_devices_menu(self):
        # clear() requires the underlying NSMenu to exist (only after run())
        try:
            self.devices_menu.clear()
        except AttributeError:
            return
        count = len(self._devices)
        self.devices_menu.title = f"Devices ({count})"

        if self._devices:
            for dev in self._devices:
                name = dev.get("name", dev.get("ip", "Unknown"))
                dev_id = dev.get("id", "")
                ip = dev.get("ip", "")
                label = f"  {name}" + (f"  ({ip})" if ip else "")
                item = rumps.MenuItem(
                    label,
                    callback=lambda s, did=dev_id: self._disconnect_device(did),
                )
                self.devices_menu.add(item)
            self.devices_menu.add(None)
            self.devices_menu.add(
                rumps.MenuItem("Disconnect All", callback=self.on_disconnect_all)
            )
        else:
            placeholder = rumps.MenuItem("  No devices connected")
            placeholder.set_callback(None)
            self.devices_menu.add(placeholder)

    # ── Server lifecycle ──────────────────────────────────────────────────

    def _start_server(self):
        # Auto-cleanup port if something is lingering
        if _is_port_in_use(PORT):
            _free_port(PORT)
            if _is_port_in_use(PORT):
                rumps.notification(
                    "iCodex", "Port Busy",
                    f"Port {PORT} is occupied and could not be freed.",
                )
                return

        try:
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            log_out = open(LOG_DIR / "icodex.log", "a")
            log_err = open(LOG_DIR / "icodex_error.log", "a")

            env = os.environ.copy()
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:" + env.get("PATH", "")
            # Remove Python env vars set by our launcher for the embedded binary.
            # The venv Python manages its own paths and these would interfere.
            env.pop("PYTHONHOME", None)
            env.pop("PYTHONPATH", None)

            self._server_proc = subprocess.Popen(
                [PYTHON, str(BACKEND_DIR / "server.py")],
                cwd=str(BACKEND_DIR),
                stdout=log_out,
                stderr=log_err,
                start_new_session=True,
                env=env,
            )
            local_ip = _get_local_ip()
            passcode = _read_passcode()
            rumps.notification(
                "iCodex-Connect", "Server Running",
                f"IP: {local_ip}  |  Passcode: {passcode}\nEnter this on your iPhone to connect.",
            )
        except Exception as exc:
            rumps.notification("iCodex", "Start Failed", str(exc))

    def _stop_server(self):
        # Graceful shutdown of our child process
        if self._server_proc is not None:
            try:
                self._server_proc.terminate()
                self._server_proc.wait(timeout=5)
            except Exception:
                try:
                    self._server_proc.kill()
                except Exception:
                    pass
            self._server_proc = None

        # Also kill anything still holding the port
        _free_port(PORT)

    # ── Menu callbacks ────────────────────────────────────────────────────

    def on_start_stop(self, _sender):
        if _is_port_in_use(PORT):
            self._stop_server()
            rumps.notification("iCodex", "Server Stopped", "")
        else:
            self._start_server()
        self._refresh(None)

    def on_copy_url(self, _sender):
        url = f"http://{_get_local_ip()}:{PORT}"
        _copy(url)
        rumps.notification("iCodex", "Copied", url)

    def on_copy_passcode(self, _sender):
        passcode = _read_passcode()
        _copy(passcode)
        rumps.notification("iCodex", "Copied", f"Passcode: {passcode}")

    def on_open_accessibility(self, _sender):
        if _check_accessibility():
            self._a11y_granted = True
            self._a11y_last_check = _time.time()
            self._a11y_watch_until = 0
            rumps.notification("iCodex", "Accessibility", "Permission already granted.")
        else:
            _request_accessibility()
            rumps.notification(
                "iCodex", "Grant Accessibility",
                "Click '+' → select iCodex-Connect from Applications → toggle ON.",
            )
            _open_accessibility_settings()
            self._a11y_granted = None
            self._a11y_last_check = 0
            self._a11y_watch_until = _time.time() + A11Y_PENDING_WATCH_SECONDS
        self._refresh(None)

    def _disconnect_device(self, device_id: str):
        ok = _server_post(f"/internal/devices/{device_id}/disconnect")
        if ok:
            rumps.notification("iCodex", "Disconnected", "Device removed.")
        else:
            rumps.notification("iCodex", "Error", "Could not disconnect device.")
        self._refresh(None)

    def on_disconnect_all(self, _sender):
        _server_post("/internal/devices/disconnect-all")
        rumps.notification("iCodex", "Disconnected", "All devices removed.")
        self._refresh(None)

    def on_quit(self, _sender):
        self._stop_server()
        rumps.quit_application()


if __name__ == "__main__":
    ICodexMenuBarApp().run()
