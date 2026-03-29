"""Control the Codex desktop GUI via a native Swift helper binary.

The Codex Electron app does not expose a local API, so we automate it
through macOS CGEvents (keyboard simulation).

The icodex_keystroke helper binary lives inside iCodex-Connect.app's
Contents/MacOS/ directory. Because it's part of the .app bundle, the
user just adds "iCodex-Connect" in Accessibility settings — one toggle.

The helper handles all CGEvent posting; this module just calls it.

Requirements:
  - iCodex-Connect.app must be added to
    System Settings → Privacy & Security → Accessibility.
  - The Codex app must be running.
"""

from __future__ import annotations

import json
import logging
import subprocess
import time
from pathlib import Path

logger = logging.getLogger("icodex.gui")

CODEX_BUNDLE_ID = "com.openai.codex"
CODEX_APP_NAME = "Codex"
THREAD_OPEN_TIMEOUT_SECONDS = 8.0
THREAD_FOCUS_SETTLE_SECONDS = 0.7
THREAD_FOCUS_CACHE_SECONDS = 5.0

_last_focused_thread_id: str | None = None
_last_focused_at: float = 0.0
_keepawake_proc: subprocess.Popen[str] | None = None

# ── Locate the native helper ────────────────────────────────────────────────

def _find_helper() -> str | None:
    """Find the icodex_keystroke binary.

    Search order:
      1. Inside the running .app bundle (Contents/MacOS/icodex_keystroke)
      2. Next to this script (dev/testing)
      3. In PATH
    """
    # 1. .app bundle — walk up from this file to find Contents/MacOS
    here = Path(__file__).resolve().parent
    # When bundled: .../iCodex-Connect.app/Contents/Resources/MacBackend/codex_gui.py
    app_macos = here.parent.parent / "MacOS" / "icodex_keystroke"
    if app_macos.is_file():
        return str(app_macos)

    # 2. Next to this script (dev builds)
    local = here / "icodex_keystroke_bin"
    if local.is_file():
        return str(local)

    # 3. In PATH
    import shutil
    found = shutil.which("icodex_keystroke")
    if found:
        return found

    return None


_HELPER = _find_helper()

SUPPORTED_GUI_ACTIONS = (
    "enter",
    "tab",
    "shift_tab",
    "space",
    "escape",
    "up",
    "down",
    "left",
    "right",
    "page_up",
    "page_down",
    "jump_top",
    "jump_bottom",
)

GUI_KEY_ACTIONS = set(SUPPORTED_GUI_ACTIONS)

if _HELPER:
    logger.info("Native keystroke helper: %s", _HELPER)
else:
    logger.warning("icodex_keystroke helper not found — GUI control unavailable")


def _run_helper(*args: str, timeout: int = 10) -> dict:
    """Run the native helper and return {"success": bool, ...}."""
    if not _HELPER:
        return {"success": False, "error": "Native keystroke helper not found."}
    try:
        r = subprocess.run(
            [_HELPER, *args],
            capture_output=True, text=True, timeout=timeout,
        )
        output = r.stdout.strip()
        if r.returncode == 0:
            return {"success": True, "output": output}
        return {
            "success": False,
            "error": r.stderr.strip() or f"Helper exited with code {r.returncode}",
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Timed out waiting for keystroke helper"}
    except Exception as exc:
        return {"success": False, "error": str(exc)}


def _wake_display() -> None:
    """Nudge macOS to keep the user session active during remote control."""
    try:
        subprocess.run(
            ["caffeinate", "-u", "-t", "30"],
            capture_output=True,
            text=True,
            timeout=3,
        )
    except Exception:
        pass


def ensure_remote_awake(active: bool) -> None:
    """Hold a display/idle assertion while a remote session is active."""
    global _keepawake_proc

    if active:
        _wake_display()
        if _keepawake_proc is None or _keepawake_proc.poll() is not None:
            try:
                _keepawake_proc = subprocess.Popen(
                    ["caffeinate", "-d", "-i", "-m", "-s"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    text=True,
                )
                logger.info("Started remote keep-awake assertion")
            except Exception as exc:
                logger.warning("Could not start keep-awake assertion: %s", exc)
        return

    if _keepawake_proc is not None and _keepawake_proc.poll() is None:
        _keepawake_proc.terminate()
        try:
            _keepawake_proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            _keepawake_proc.kill()
        logger.info("Stopped remote keep-awake assertion")
    _keepawake_proc = None


def get_session_state() -> dict:
    """Return best-effort details about whether the GUI session is interactable."""
    state = {
        "locked": False,
        "on_console": True,
        "login_done": True,
        "screensaver_running": False,
    }

    try:
        from Quartz import CGSessionCopyCurrentDictionary  # type: ignore

        session = dict(CGSessionCopyCurrentDictionary() or {})
        state["on_console"] = bool(session.get("kCGSSessionOnConsoleKey", True))
        state["login_done"] = bool(session.get("kCGSessionLoginDoneKey", True))
        state["locked"] = bool(session.get("CGSSessionScreenIsLocked", False))
    except Exception:
        logger.debug("Quartz session state unavailable", exc_info=True)

    try:
        result = subprocess.run(
            ["pgrep", "-x", "ScreenSaverEngine"],
            capture_output=True,
            timeout=3,
        )
        state["screensaver_running"] = result.returncode == 0
    except Exception:
        pass

    state["locked"] = bool(state["locked"]) or not bool(state["on_console"]) or not bool(state["login_done"])
    state["available"] = not state["locked"]
    return state


def get_remote_status() -> dict:
    """Return a lightweight snapshot of GUI remote-control availability."""
    session_state = get_session_state()
    codex_running = is_gui_running()
    return {
        "success": True,
        "session_state": session_state,
        "codex_running": codex_running,
        "remote_ready": codex_running and bool(session_state.get("available")),
        "supported_actions": list(SUPPORTED_GUI_ACTIONS),
    }


# ── Public API ───────────────────────────────────────────────────────────────


def is_gui_running() -> bool:
    """Return True if the Codex desktop app is running.

    ``pgrep -f com.openai.codex`` is unreliable because the bundle id does not
    appear in the live process command line on every machine. Prefer the
    bundle-id check that macOS itself understands, then fall back to process
    name/path matching.
    """
    try:
        r = subprocess.run(
            ["osascript", "-e", f'application id "{CODEX_BUNDLE_ID}" is running'],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if r.returncode == 0 and r.stdout.strip().lower() == "true":
            return True
    except Exception:
        pass

    for cmd in (
        ["pgrep", "-x", CODEX_APP_NAME],
        ["pgrep", "-f", "/Applications/Codex.app/Contents/MacOS/Codex"],
    ):
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=3)
            if r.returncode == 0:
                return True
        except Exception:
            continue

    return False


def check_accessibility() -> dict:
    """Check if we have Accessibility access (post-event permission)."""
    result = _run_helper("check", timeout=5)
    if not result["success"]:
        return result
    if result.get("output") == "granted":
        return {"success": True}
    # Not granted — request it
    _run_helper("request", timeout=5)
    return {
        "success": False,
        "error": "Accessibility permission not yet granted for iCodex-Connect.",
    }


def _ensure_interactable_session() -> dict:
    """Wake a sleepy screen and fail clearly if macOS is still locked."""
    _wake_display()
    state = get_session_state()
    if state.get("locked"):
        return {
            "success": False,
            "error": (
                "Mac is locked. iCodex can wake the display, but macOS blocks GUI control "
                "until the session is unlocked."
            ),
            "session_state": state,
        }
    return {"success": True, "session_state": state}


def _focus_target(thread_id: str | None) -> dict:
    session = _ensure_interactable_session()
    if not session["success"]:
        return session

    if thread_id:
        return _focus_thread(thread_id)
    if not is_gui_running():
        return {"success": False, "error": "Codex app is not running."}
    return {"success": True}


def _focus_thread(thread_id: str) -> dict:
    """Open the target Codex thread before sending any GUI automation."""
    global _last_focused_at, _last_focused_thread_id

    if (
        _last_focused_thread_id == thread_id
        and time.time() - _last_focused_at < THREAD_FOCUS_CACHE_SECONDS
    ):
        activate = _run_helper("activate", CODEX_BUNDLE_ID, timeout=5)
        if not activate["success"]:
            return {"success": False, "error": "Could not activate Codex window."}
        _last_focused_at = time.time()
        time.sleep(0.15)
        return {"success": True}

    deeplink = f"codex://threads/{thread_id}"

    try:
        result = subprocess.run(
            ["open", deeplink],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Timed out opening Codex thread."}
    except Exception as exc:
        return {"success": False, "error": str(exc)}

    if result.returncode != 0:
        return {
            "success": False,
            "error": result.stderr.strip() or "Could not open Codex thread.",
        }

    deadline = time.time() + THREAD_OPEN_TIMEOUT_SECONDS
    while time.time() < deadline:
        if is_gui_running():
            break
        time.sleep(0.2)

    if not is_gui_running():
        return {"success": False, "error": "Codex app did not become available."}

    activate = _run_helper("activate", CODEX_BUNDLE_ID, timeout=5)
    if not activate["success"]:
        return {"success": False, "error": "Could not activate Codex window."}

    # Give Codex a moment to route the deeplink to the requested thread.
    time.sleep(THREAD_FOCUS_SETTLE_SECONDS)
    _last_focused_thread_id = thread_id
    _last_focused_at = time.time()
    return {"success": True}


def send_message(message: str, thread_id: str | None = None) -> dict:
    """Paste *message* into the selected Codex thread and press Return."""
    focus = _focus_target(thread_id)
    if not focus["success"]:
        return focus

    result = _run_helper("send", CODEX_BUNDLE_ID, message, timeout=15)
    if result["success"]:
        logger.info("Message sent to Codex GUI via native helper")
    else:
        logger.warning("Failed to send message: %s", result.get("error"))
    return result


def perform_key_action(action: str, thread_id: str | None = None) -> dict:
    """Send a supported navigation or confirmation key to the selected thread."""
    if action not in GUI_KEY_ACTIONS:
        return {"success": False, "error": f"Unsupported GUI action: {action}"}
    focus = _focus_target(thread_id)
    if not focus["success"]:
        return focus

    result = _run_helper("key", action, timeout=5)
    if result["success"]:
        logger.info("GUI key action sent to Codex: %s", action)
    else:
        logger.warning("Failed GUI key action %s: %s", action, result.get("error"))
    return result


def list_controls(thread_id: str | None = None) -> dict:
    """Return the currently mirrored set of GUI controls for the selected thread."""
    focus = _focus_target(thread_id)
    if not focus["success"]:
        return focus

    result = _run_helper("list_controls", CODEX_BUNDLE_ID, timeout=10)
    if not result["success"]:
        return result

    try:
        controls = json.loads(result.get("output") or "[]")
    except json.JSONDecodeError:
        return {"success": False, "error": "Could not decode GUI controls from helper."}

    return {"success": True, "controls": controls}


def press_control(control_id: str, thread_id: str | None = None) -> dict:
    """Press one mirrored GUI control in the selected Codex thread."""
    focus = _focus_target(thread_id)
    if not focus["success"]:
        return focus

    result = _run_helper("press_control", CODEX_BUNDLE_ID, control_id, timeout=10)
    if result["success"]:
        logger.info("Pressed GUI control %s", control_id)
    else:
        logger.warning("Failed to press GUI control %s: %s", control_id, result.get("error"))
    return result


def _press_matching_control(keywords: list[str]) -> dict:
    result = _run_helper("press_matching", CODEX_BUNDLE_ID, *keywords, timeout=10)
    if result["success"]:
        logger.info("Pressed matching GUI control for keywords: %s", ",".join(keywords))
    return result


def interrupt(thread_id: str | None = None) -> dict:
    """Press Escape in the selected Codex thread to interrupt execution."""
    focus = _focus_target(thread_id)
    if not focus["success"]:
        return focus

    click_result = _press_matching_control(["interrupt", "stop", "cancel", "abort"])
    if click_result["success"]:
        return click_result

    result = _run_helper("escape", timeout=5)
    if result["success"]:
        logger.info("Interrupt (Escape) sent to Codex GUI")
    return result


def stop(thread_id: str | None = None) -> dict:
    """Send Ctrl-C to the selected Codex thread."""
    focus = _focus_target(thread_id)
    if not focus["success"]:
        return focus

    click_result = _press_matching_control(["stop", "interrupt", "cancel", "abort"])
    if click_result["success"]:
        return click_result

    result = _run_helper("ctrl_c", timeout=5)
    if result["success"]:
        logger.info("Stop (Ctrl-C) sent to Codex GUI")
    return result
