"""Read Codex local data: threads, sessions, models, config."""

from __future__ import annotations
import asyncio
import json
import sqlite3
import subprocess
import os
import time
from pathlib import Path
from typing import Optional

try:
    import tomllib
except ImportError:
    import tomli as tomllib  # type: ignore[no-redef]

CODEX_DIR = Path.home() / ".codex"
STATE_DB = CODEX_DIR / "state_5.sqlite"
SESSIONS_DIR = CODEX_DIR / "sessions"
SESSION_INDEX = CODEX_DIR / "session_index.jsonl"
MODELS_CACHE = CODEX_DIR / "models_cache.json"
CONFIG_FILE = CODEX_DIR / "config.toml"
CODEX_CLI = "/Applications/Codex.app/Contents/Resources/codex"

ACTIVE_THRESHOLD_SECONDS = 300  # 5 minutes — Codex GUI threads can be idle waiting for input


def _get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(str(STATE_DB), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


# ── Thread activity detection ────────────────────────────────────────────────


def _get_active_thread_ids() -> set[str]:
    active: set[str] = set()
    if not SESSIONS_DIR.exists():
        return active
    now = time.time()
    for jsonl_file in SESSIONS_DIR.rglob("*.jsonl"):
        try:
            mtime = jsonl_file.stat().st_mtime
            if now - mtime < ACTIVE_THRESHOLD_SECONDS:
                tid = _extract_thread_id(jsonl_file.name)
                if tid:
                    active.add(tid)
        except OSError:
            pass
    return active


def _extract_thread_id(filename: str) -> Optional[str]:
    name = filename.replace(".jsonl", "")
    parts = name.split("-")
    if len(parts) >= 5:
        uuid = "-".join(parts[-5:])
        if len(uuid) == 36:
            return uuid
    return None


# ── Git diff stats ───────────────────────────────────────────────────────────


def get_git_diff_stats(cwd: str, git_sha: Optional[str]) -> Optional[dict]:
    if not git_sha or not os.path.isdir(cwd):
        return None
    try:
        result = subprocess.run(
            ["git", "diff", "--shortstat", git_sha, "HEAD"],
            cwd=cwd, capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0:
            return None
        output = result.stdout.strip()
        if not output:
            return None
        stats = {"insertions": 0, "deletions": 0, "files_changed": 0}
        for part in output.split(","):
            part = part.strip()
            if "insertion" in part:
                stats["insertions"] = int(part.split()[0])
            elif "deletion" in part:
                stats["deletions"] = int(part.split()[0])
            elif "file" in part:
                stats["files_changed"] = int(part.split()[0])
        return stats
    except Exception:
        return None


# ── Threads ──────────────────────────────────────────────────────────────────


def list_threads(
    include_archived: bool = False,
    source: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
) -> list[dict]:
    conn = _get_db()
    try:
        query = "SELECT * FROM threads"
        conditions = []
        params: list = []

        if not include_archived:
            conditions.append("archived = 0")
        if source:
            conditions.append("source = ?")
            params.append(source)

        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        query += " ORDER BY updated_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        rows = conn.execute(query, params).fetchall()
        threads = [dict(r) for r in rows]

        active_ids = _get_active_thread_ids()
        session_names = get_session_index()
        for t in threads:
            t["is_running"] = t["id"] in active_ids
            # Use short session name if available
            if t["id"] in session_names:
                t["title"] = session_names[t["id"]]
            if not t["is_running"] and t.get("git_sha"):
                t["git_stats"] = get_git_diff_stats(t["cwd"], t["git_sha"])
            else:
                t["git_stats"] = None

        return threads
    finally:
        conn.close()


def get_thread(thread_id: str) -> Optional[dict]:
    conn = _get_db()
    try:
        row = conn.execute("SELECT * FROM threads WHERE id = ?", (thread_id,)).fetchone()
        if not row:
            return None
        t = dict(row)
        # Use short session name if available
        session_names = get_session_index()
        if t["id"] in session_names:
            t["title"] = session_names[t["id"]]
        active_ids = _get_active_thread_ids()
        t["is_running"] = t["id"] in active_ids
        if not t["is_running"] and t.get("git_sha"):
            t["git_stats"] = get_git_diff_stats(t["cwd"], t["git_sha"])
        else:
            t["git_stats"] = None
        return t
    finally:
        conn.close()


def get_thread_stats() -> dict:
    conn = _get_db()
    try:
        total = conn.execute("SELECT COUNT(*) FROM threads").fetchone()[0]
        active = conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 0").fetchone()[0]
        archived = conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 1").fetchone()[0]
        total_tokens = conn.execute("SELECT COALESCE(SUM(tokens_used), 0) FROM threads").fetchone()[0]
        sources = conn.execute(
            "SELECT source, COUNT(*) as count FROM threads GROUP BY source"
        ).fetchall()
        running_count = len(_get_active_thread_ids())
        return {
            "total_threads": total,
            "active_threads": active,
            "archived_threads": archived,
            "total_tokens_used": total_tokens,
            "running_threads": running_count,
            "sources": {r["source"]: r["count"] for r in sources},
        }
    finally:
        conn.close()


# ── Session / Conversation Messages ─────────────────────────────────────────


def _find_session_file(thread_id: str) -> Optional[Path]:
    for jsonl_file in SESSIONS_DIR.rglob(f"*{thread_id}*.jsonl"):
        return jsonl_file
    archived_dir = CODEX_DIR / "archived_sessions"
    if archived_dir.exists():
        for jsonl_file in archived_dir.rglob(f"*{thread_id}*.jsonl"):
            return jsonl_file
    return None


def get_thread_messages(thread_id: str) -> list[dict]:
    """Parse the JSONL session file. Uses event_msg (preferred) with response_item fallback."""
    session_file = _find_session_file(thread_id)
    if not session_file:
        return []

    event_messages: list[dict] = []
    response_messages: list[dict] = []
    has_event_msgs = False

    for line in session_file.read_text().strip().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        event_type = event.get("type", "")
        timestamp = event.get("timestamp")

        if event_type == "event_msg":
            payload = event.get("payload", {})
            msg_type = payload.get("type", "")

            if msg_type == "user_message":
                has_event_msgs = True
                event_messages.append({
                    "role": "user",
                    "content": payload.get("message", ""),
                    "timestamp": timestamp,
                    "type": "message",
                })
            elif msg_type == "agent_message":
                has_event_msgs = True
                event_messages.append({
                    "role": "assistant",
                    "content": payload.get("message", ""),
                    "timestamp": timestamp,
                    "type": "message",
                })
            elif msg_type == "task_started":
                event_messages.append({
                    "role": "system",
                    "content": "Task started",
                    "timestamp": timestamp,
                    "type": "status",
                })
            elif msg_type == "task_complete":
                event_messages.append({
                    "role": "system",
                    "content": "Task complete",
                    "timestamp": timestamp,
                    "type": "status",
                })
            elif msg_type == "turn_aborted":
                reason = payload.get("reason", "unknown")
                event_messages.append({
                    "role": "system",
                    "content": f"Turn aborted: {reason}",
                    "timestamp": timestamp,
                    "type": "status",
                })

        elif event_type == "response_item":
            item = event.get("payload", event)
            role = item.get("role", "unknown")
            # Skip developer/system prompt messages
            if role not in ("user", "assistant"):
                continue
            content_parts = item.get("content") or []
            text_parts = []
            for part in content_parts:
                if isinstance(part, dict):
                    ptype = part.get("type", "")
                    if ptype in ("input_text", "output_text", "text"):
                        text_parts.append(part.get("text", ""))
                elif isinstance(part, str):
                    text_parts.append(part)
            if text_parts:
                response_messages.append({
                    "role": role,
                    "content": "\n".join(text_parts),
                    "timestamp": timestamp,
                    "type": "message",
                })

    # Prefer event_msg if available (cleaner, no duplicates)
    return event_messages if has_event_msgs else response_messages


# ── Models ───────────────────────────────────────────────────────────────────


def list_models() -> list[dict]:
    if not MODELS_CACHE.exists():
        return []
    try:
        data = json.loads(MODELS_CACHE.read_text())
        return data.get("models", [])
    except (json.JSONDecodeError, KeyError):
        return []


# ── Config ───────────────────────────────────────────────────────────────────


def get_config() -> dict:
    if not CONFIG_FILE.exists():
        return {}
    try:
        return tomllib.loads(CONFIG_FILE.read_text())
    except Exception:
        return {}


def update_config(model: Optional[str] = None, reasoning_effort: Optional[str] = None) -> dict:
    config = get_config()
    if model:
        config["model"] = model
    if reasoning_effort:
        config["model_reasoning_effort"] = reasoning_effort

    lines = []
    for key, value in config.items():
        if isinstance(value, dict):
            lines.append(f"\n[{key}]")
            for k2, v2 in value.items():
                if isinstance(v2, dict):
                    lines.append(f"\n[{key}.{k2}]")
                    for k3, v3 in v2.items():
                        lines.append(f'{k3} = "{v3}"')
                else:
                    lines.append(f'{k2} = "{v2}"')
        elif isinstance(value, str):
            lines.append(f'{key} = "{value}"')
        else:
            lines.append(f"{key} = {value}")

    CONFIG_FILE.write_text("\n".join(lines) + "\n")
    return get_config()


# ── Codex CLI + GUI integration ──────────────────────────────────────────────

import codex_gui

_running_processes: dict[str, asyncio.subprocess.Process] = {}


def _thread_prefers_gui(thread: Optional[dict]) -> bool:
    """Local Codex desktop threads should stay bound to the GUI."""
    return bool(thread) and thread.get("source") == "vscode"


async def exec_new_task(
    prompt: str,
    cwd: str,
    model: Optional[str] = None,
    full_auto: bool = False,
) -> dict:
    """Start a new Codex task using `codex exec`."""
    cmd = [CODEX_CLI, "exec", "--json"]
    if model:
        cmd.extend(["-m", model])
    if full_auto:
        cmd.append("--full-auto")
    cmd.extend(["-C", cwd, prompt])

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=cwd,
    )

    task_id = f"exec-{int(time.time())}"
    _running_processes[task_id] = proc
    return {"task_id": task_id, "status": "started", "pid": proc.pid}


async def resume_thread(
    thread_id: str,
    prompt: str,
    cwd: Optional[str] = None,
) -> dict:
    """Send a message to a thread.

    Strategy:
      1. If we own the running process → report busy.
      2. If this is a local Codex desktop thread → focus that exact GUI
         thread via deeplink and send the message there.
      3. Otherwise → resume via ``codex exec resume``.
    """
    thread = get_thread(thread_id)
    working_dir = cwd or (thread.get("cwd") if thread else None) or os.path.expanduser("~")

    # ── Threads we own must not be steered through GUI automation ─────
    proc = _running_processes.get(thread_id)
    if proc and proc.returncode is None:
        return {
            "thread_id": thread_id,
            "status": "busy",
            "message": "Thread is still processing. Wait for it to finish or interrupt it first.",
        }

    # ── Local Codex desktop thread → keep continuity in the GUI ───────
    if _thread_prefers_gui(thread):
        result = codex_gui.send_message(prompt, thread_id=thread_id)
        if result["success"]:
            return {
                "thread_id": thread_id,
                "status": "sent_to_gui",
                "message": "Message sent to the matching Codex desktop thread.",
            }
        return {
            "thread_id": thread_id,
            "status": "gui_error",
            "message": result.get("error", "Could not send message to Codex GUI."),
        }

    # ── Thread is idle → resume via CLI ───────────────────────────────
    cmd = [CODEX_CLI, "exec", "resume", thread_id, prompt, "--json", "--full-auto"]

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=working_dir,
    )
    _running_processes[thread_id] = proc
    return {"thread_id": thread_id, "status": "resumed", "method": "exec", "pid": proc.pid}


async def stop_task(task_id: str) -> dict:
    """Stop a running thread.

    1. If we own the process → SIGTERM it.
    2. If thread is running (in GUI) → send Ctrl-C via AppleScript.
    3. Otherwise → not running.
    """
    # Try our own process first
    proc = _running_processes.get(task_id)
    if proc and proc.returncode is None:
        proc.terminate()
        try:
            await asyncio.wait_for(proc.wait(), timeout=5)
        except asyncio.TimeoutError:
            proc.kill()
        _running_processes.pop(task_id, None)
        return {"status": "stopped", "method": "process"}

    # For Codex desktop threads, try the GUI even if our activity heuristic lags.
    thread = get_thread(task_id)
    if thread and _thread_prefers_gui(thread) and codex_gui.is_gui_running():
        result = codex_gui.stop(task_id)
        if result["success"]:
            return {"status": "stopped", "method": "gui"}
        return {"status": "gui_error", "error": result.get("error", "")}

    return {"status": "not_running"}


def interrupt_thread(thread_id: str) -> dict:
    """Interrupt a running thread.

    1. If we own the process → SIGINT it.
    2. If thread is running (in GUI) → send Escape via AppleScript.
    3. Otherwise → not running.
    """
    # Try our own process first
    proc = _running_processes.get(thread_id)
    if proc and proc.returncode is None:
        proc.send_signal(2)  # SIGINT
        return {"status": "interrupted", "method": "process"}

    # For Codex desktop threads, try the GUI even if our activity heuristic lags.
    thread = get_thread(thread_id)
    if thread and _thread_prefers_gui(thread) and codex_gui.is_gui_running():
        result = codex_gui.interrupt(thread_id)
        if result["success"]:
            return {"status": "interrupted", "method": "gui"}
        return {"status": "gui_error", "error": result.get("error", "")}

    return {"status": "not_running"}


def perform_gui_action(thread_id: str, action: str) -> dict:
    """Send a navigation or confirmation key to a running Codex desktop thread."""
    proc = _running_processes.get(thread_id)
    if proc and proc.returncode is None:
        return {
            "status": "process_running",
            "error": "This thread is running as a managed CLI task. GUI controls only work with the Codex desktop app.",
        }

    thread = get_thread(thread_id)
    if not thread:
        return {"status": "not_running"}
    if not _thread_prefers_gui(thread):
        return {"status": "gui_unavailable", "error": "This thread is not backed by the Codex desktop GUI."}

    if not codex_gui.is_gui_running():
        return {"status": "gui_unavailable", "error": "Codex desktop app is not running."}

    result = codex_gui.perform_key_action(action, thread_id=thread_id)
    if result["success"]:
        return {"status": "sent", "method": "gui", "action": action}
    return {"status": "gui_error", "error": result.get("error", "")}


def get_thread_gui_controls(thread_id: str) -> dict:
    """Return the currently mirrored GUI controls for a Codex desktop thread."""
    proc = _running_processes.get(thread_id)
    if proc and proc.returncode is None:
        return {
            "status": "process_running",
            "error": "This thread is running as a managed CLI task. GUI choices are only available for the Codex desktop app.",
        }

    thread = get_thread(thread_id)
    if not thread:
        return {"status": "not_found"}
    if not _thread_prefers_gui(thread):
        return {"status": "gui_unavailable", "error": "This thread is not backed by the Codex desktop GUI."}
    if not codex_gui.is_gui_running():
        return {"status": "gui_unavailable", "error": "Codex desktop app is not running."}

    result = codex_gui.list_controls(thread_id=thread_id)
    if result["success"]:
        return {
            "status": "available",
            "method": "gui",
            "controls": result.get("controls", []),
        }
    return {"status": "gui_error", "error": result.get("error", "")}


def press_thread_gui_control(thread_id: str, control_id: str) -> dict:
    """Press one mirrored GUI control for a Codex desktop thread."""
    proc = _running_processes.get(thread_id)
    if proc and proc.returncode is None:
        return {
            "status": "process_running",
            "error": "This thread is running as a managed CLI task. GUI choices are only available for the Codex desktop app.",
        }

    thread = get_thread(thread_id)
    if not thread:
        return {"status": "not_found"}
    if not _thread_prefers_gui(thread):
        return {"status": "gui_unavailable", "error": "This thread is not backed by the Codex desktop GUI."}
    if not codex_gui.is_gui_running():
        return {"status": "gui_unavailable", "error": "Codex desktop app is not running."}

    result = codex_gui.press_control(control_id=control_id, thread_id=thread_id)
    if result["success"]:
        return {"status": "pressed", "method": "gui", "control_id": control_id}
    return {"status": "gui_error", "error": result.get("error", "")}


def get_running_tasks() -> list[str]:
    return [tid for tid, p in _running_processes.items() if p.returncode is None]



# ── Session Index ────────────────────────────────────────────────────────────


def get_session_index() -> dict[str, str]:
    index: dict[str, str] = {}
    if not SESSION_INDEX.exists():
        return index
    for line in SESSION_INDEX.read_text().strip().splitlines():
        try:
            entry = json.loads(line)
            tid = entry.get("id", "")
            name = entry.get("thread_name", "")
            if tid and name:
                index[tid] = name
        except json.JSONDecodeError:
            continue
    return index
