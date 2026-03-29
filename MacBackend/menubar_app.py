"""iCodex menu bar app — clean status icon with server controls and device management."""

from __future__ import annotations

import atexit
import json
import os
import signal
import socket
import subprocess
import sys
import time as _time
import urllib.request
from pathlib import Path
from urllib.parse import urlencode

import rumps

PORT = 8642
BACKEND_DIR = Path(__file__).resolve().parent
AUTH_FILE = Path.home() / ".codex" / "icodex_auth.json"
DATA_DIR = Path.home() / "Library" / "Application Support" / "iCodex-Connect"
LOG_DIR = DATA_DIR / "logs"
VOLUMES_DIR = Path("/Volumes")

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


def _app_bundle_dir() -> Path | None:
    for parent in BACKEND_DIR.parents:
        if parent.suffix == ".app":
            return parent
    return None


APP_BUNDLE_DIR = _app_bundle_dir()
APP_NAME = APP_BUNDLE_DIR.stem if APP_BUNDLE_DIR else "iCodex-Connect"


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


def _build_pairing_url(host: str, port: int, passcode: str) -> str:
    query = urlencode({
        "host": host,
        "port": str(port),
        "passcode": passcode,
    })
    return f"icodex://pair?{query}"


def _generate_qr_image(payload: str, scale: float = 10.0):
    try:
        import Quartz
        from AppKit import NSImage, NSZeroSize
        from Foundation import NSData

        data = payload.encode("utf-8")
        ns_data = NSData.dataWithBytes_length_(data, len(data))
        qr_filter = Quartz.CIFilter.filterWithName_("CIQRCodeGenerator")
        qr_filter.setDefaults()
        qr_filter.setValue_forKey_(ns_data, "inputMessage")
        qr_filter.setValue_forKey_("M", "inputCorrectionLevel")

        image = qr_filter.outputImage()
        transform = Quartz.CGAffineTransformMakeScale(scale, scale)
        scaled = image.imageByApplyingTransform_(transform)

        context = Quartz.CIContext.contextWithOptions_(None)
        cg_image = context.createCGImage_fromRect_(scaled, scaled.extent())
        return NSImage.alloc().initWithCGImage_size_(cg_image, NSZeroSize)
    except Exception:
        return None


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


def _is_installed_in_applications(app_dir: Path | None) -> bool:
    if app_dir is None:
        return False
    try:
        normalized = app_dir.resolve()
        system_applications = Path("/Applications").resolve()
        user_applications = (Path.home() / "Applications").resolve()
        normalized_path = normalized.as_posix() + "/"
        return (
            normalized_path.startswith(system_applications.as_posix() + "/")
            or normalized_path.startswith(user_applications.as_posix() + "/")
        )
    except Exception:
        return False


def _volume_root_for_path(path: Path | None) -> Path | None:
    if path is None:
        return None
    try:
        normalized = path.resolve()
    except Exception:
        normalized = path
    parts = normalized.parts
    if len(parts) >= 3 and parts[1] == "Volumes":
        return Path("/", parts[1], parts[2])
    return None


def _installer_volumes(app_name: str, excluding_app_dir: Path | None = None) -> list[Path]:
    current_volume = _volume_root_for_path(excluding_app_dir)
    if not VOLUMES_DIR.exists():
        return []

    volumes: list[Path] = []
    for volume in VOLUMES_DIR.iterdir():
        try:
            if current_volume and volume.resolve() == current_volume.resolve():
                continue
        except Exception:
            pass

        bundled_app = volume / f"{app_name}.app"
        install_note = volume / f"Install {app_name}.txt"
        applications_alias = volume / "Applications"
        name_matches = volume.name == app_name or volume.name.startswith(f"{app_name} ")
        looks_like_installer = (
            bundled_app.exists()
            and (
                name_matches
                or install_note.exists()
                or applications_alias.exists()
            )
        )
        if looks_like_installer:
            volumes.append(volume)
    return volumes


def _eject_volume(volume: Path) -> bool:
    for args in (
        ["/usr/bin/hdiutil", "detach", volume.as_posix(), "-quiet"],
        ["/usr/bin/hdiutil", "detach", volume.as_posix(), "-force", "-quiet"],
    ):
        try:
            result = subprocess.run(
                args,
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode == 0:
                return True
        except Exception:
            continue
    return False


def _schedule_eject_volume(volume: Path, delay_seconds: int = 2) -> None:
    quoted = volume.as_posix().replace("'", "'\"'\"'")
    script = (
        f"sleep {delay_seconds}; "
        f"/usr/bin/hdiutil detach '{quoted}' -quiet || "
        f"/usr/bin/hdiutil detach '{quoted}' -force -quiet"
    )
    try:
        subprocess.Popen(
            ["/bin/sh", "-c", script],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


def _cleanup_installer_volumes(app_name: str, excluding_app_dir: Path | None = None) -> None:
    for volume in _installer_volumes(app_name, excluding_app_dir=excluding_app_dir):
        _eject_volume(volume)


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
        self._shutdown_handled = False
        self._pairing_qr_window = None
        self._pairing_qr_image_view = None
        self._pairing_qr_hint_label = None
        self._pairing_qr_detail_label = None

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

        self.qr_item = rumps.MenuItem(
            "  Show Pairing QR Code",
            callback=self.on_show_pairing_qr,
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
            self.qr_item,
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

        # If we're running from Applications, clean up stale installer volumes
        # left behind by previous DMG opens.
        if _is_installed_in_applications(APP_BUNDLE_DIR):
            _cleanup_installer_volumes(APP_NAME, excluding_app_dir=APP_BUNDLE_DIR)

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

        atexit.register(self._perform_shutdown_cleanup)
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            try:
                signal.signal(sig, self._handle_termination_signal)
            except Exception:
                pass

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
        self.qr_item.title = "  Show Pairing QR Code"

        if self._pairing_qr_window is not None:
            try:
                if self._pairing_qr_window.isVisible():
                    self._update_pairing_qr_window(local_ip, passcode)
            except Exception:
                pass

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

    def _perform_shutdown_cleanup(self):
        if self._shutdown_handled:
            return
        self._shutdown_handled = True
        self._stop_server()
        _cleanup_installer_volumes(APP_NAME, excluding_app_dir=APP_BUNDLE_DIR)
        if not _is_installed_in_applications(APP_BUNDLE_DIR):
            current_volume = _volume_root_for_path(APP_BUNDLE_DIR)
            if current_volume is not None:
                _schedule_eject_volume(current_volume)

    def _handle_termination_signal(self, _signum, _frame):
        self._perform_shutdown_cleanup()
        raise SystemExit(0)

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

    def _make_qr_label(self, text: str, frame):
        from AppKit import NSColor, NSFont, NSTextAlignmentCenter, NSTextField

        label = NSTextField.labelWithString_(text)
        label.setFrame_(frame)
        label.setAlignment_(NSTextAlignmentCenter)
        label.setTextColor_(NSColor.labelColor())
        label.setFont_(NSFont.systemFontOfSize_(13))
        return label

    def _ensure_pairing_qr_window(self):
        if self._pairing_qr_window is not None:
            return

        from AppKit import (
            NSApplication,
            NSBackingStoreBuffered,
            NSFont,
            NSImageView,
            NSTextAlignmentCenter,
            NSTextField,
            NSWindow,
            NSWindowStyleMaskClosable,
            NSWindowStyleMaskTitled,
        )
        from Foundation import NSMakeRect

        window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, 360, 420),
            NSWindowStyleMaskTitled | NSWindowStyleMaskClosable,
            NSBackingStoreBuffered,
            False,
        )
        window.setTitle_("Pair iPhone")
        window.setReleasedWhenClosed_(False)
        window.center()

        content = window.contentView()

        title = NSTextField.labelWithString_("Scan this QR with Camera or iCodex")
        title.setFrame_(NSMakeRect(26, 378, 308, 24))
        title.setAlignment_(NSTextAlignmentCenter)
        title.setFont_(NSFont.boldSystemFontOfSize_(17))
        content.addSubview_(title)

        image_view = NSImageView.alloc().initWithFrame_(NSMakeRect(70, 132, 220, 220))
        content.addSubview_(image_view)

        hint_label = self._make_qr_label("", NSMakeRect(26, 90, 308, 26))
        content.addSubview_(hint_label)

        detail_label = self._make_qr_label("", NSMakeRect(26, 56, 308, 22))
        detail_label.setFont_(NSFont.monospacedSystemFontOfSize_weight_(12, 0))
        content.addSubview_(detail_label)

        footnote = self._make_qr_label(
            "The QR fills in your Mac IP, port, and passcode automatically.",
            NSMakeRect(26, 20, 308, 30),
        )
        footnote.setLineBreakMode_(0)
        footnote.setUsesSingleLineMode_(False)
        footnote.setMaximumNumberOfLines_(2)
        content.addSubview_(footnote)

        self._pairing_qr_window = window
        self._pairing_qr_image_view = image_view
        self._pairing_qr_hint_label = hint_label
        self._pairing_qr_detail_label = detail_label

        NSApplication.sharedApplication().activateIgnoringOtherApps_(True)

    def _update_pairing_qr_window(self, local_ip: str, passcode: str):
        if not local_ip or local_ip == "127.0.0.1" or not passcode.isdigit():
            return

        self._ensure_pairing_qr_window()
        pairing_url = _build_pairing_url(local_ip, PORT, passcode)
        image = _generate_qr_image(pairing_url)
        if image is None:
            rumps.notification(
                "iCodex",
                "QR Code Unavailable",
                "Could not generate the pairing QR code on this Mac.",
            )
            return

        self._pairing_qr_image_view.setImage_(image)
        self._pairing_qr_hint_label.setStringValue_(f"Mac: {local_ip}:{PORT}")
        self._pairing_qr_detail_label.setStringValue_(f"Passcode: {passcode}")

    def on_show_pairing_qr(self, _sender):
        local_ip = _get_local_ip()
        passcode = _read_passcode()

        if local_ip == "127.0.0.1":
            rumps.notification(
                "iCodex",
                "QR Code Unavailable",
                "Connect your Mac to Wi-Fi so iCodex can generate a pairing QR code.",
            )
            return

        if not passcode.isdigit():
            rumps.notification(
                "iCodex",
                "QR Code Unavailable",
                "The current setup passcode is not ready yet.",
            )
            return

        self._update_pairing_qr_window(local_ip, passcode)
        self._pairing_qr_window.makeKeyAndOrderFront_(None)

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
        self._perform_shutdown_cleanup()
        rumps.quit_application()


if __name__ == "__main__":
    ICodexMenuBarApp().run()
