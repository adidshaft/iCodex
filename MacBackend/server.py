"""FastAPI application – REST + WebSocket endpoints for Codex local data."""

from __future__ import annotations
import asyncio
import hashlib
import logging
import os
import shutil
import socket
import subprocess
import sys
import time
import json
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncGenerator, Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Query, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel

from config import HOST, PORT, ALLOWED_ORIGINS
from models import (
    ThreadResponse,
    ThreadDetailResponse,
    ConversationMessage,
    CodexModel,
    CodexConfig,
    ServerStatus,
    ThreadStats,
    NetworkInfo,
    SystemDiagnostics,
)
import codex_data
import codex_gui
import auth as auth_module
from file_watcher import watcher_service

logger = logging.getLogger("icodex")

# Auth state — populated at startup
_setup_passcode: str = ""
_api_key: str = ""

security = HTTPBearer(auto_error=False)

# ── Device tracking ──────────────────────────────────────────────────────────

# {device_id: {id, ip, name, user_agent, last_seen, connected_at}}
_connected_devices: dict[str, dict] = {}
_connected_ws_devices: dict[str, int] = {}
DEVICE_TIMEOUT = 120  # seconds — prune devices not seen in this window


def _device_id_for_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()[:12]


def _track_device(request: Request, token: str) -> None:
    """Record/update a device entry from an authenticated request."""
    ip = request.client.host if request.client else "unknown"
    ua = request.headers.get("user-agent", "")
    name = request.headers.get("x-device-name", "")

    device_id = _device_id_for_token(token)
    now = time.time()

    existing = _connected_devices.get(device_id)
    _connected_devices[device_id] = {
        "id": device_id,
        "ip": ip,
        "name": name or (existing["name"] if existing else f"Device ({ip})"),
        "user_agent": ua,
        "last_seen": now,
        "connected_at": existing["connected_at"] if existing else now,
    }

    # Prune stale devices
    stale = [did for did, d in _connected_devices.items() if now - d["last_seen"] > DEVICE_TIMEOUT]
    for did in stale:
        _connected_devices.pop(did, None)


def _track_websocket_device(token: str) -> str:
    device_id = _device_id_for_token(token)
    _connected_ws_devices[device_id] = _connected_ws_devices.get(device_id, 0) + 1
    return device_id


def _untrack_websocket_device(device_id: str) -> None:
    count = _connected_ws_devices.get(device_id, 0)
    if count <= 1:
        _connected_ws_devices.pop(device_id, None)
    else:
        _connected_ws_devices[device_id] = count - 1


def _has_remote_presence() -> bool:
    now = time.time()
    stale = [did for did, d in _connected_devices.items() if now - d["last_seen"] > DEVICE_TIMEOUT]
    for did in stale:
        _connected_devices.pop(did, None)
    return bool(_connected_devices) or bool(_connected_ws_devices)


async def _remote_awake_loop() -> None:
    while True:
        try:
            stats = await asyncio.to_thread(codex_data.get_thread_stats)
            has_running_threads = stats.get("running_threads", 0) > 0
            codex_gui.ensure_remote_awake(_has_remote_presence() or has_running_threads)
        except Exception:
            logger.debug("Remote keep-awake loop failed", exc_info=True)
        await asyncio.sleep(20)


def _disconnect_device(device_id: str) -> bool:
    return _connected_devices.pop(device_id, None) is not None


def _disconnect_all_devices() -> int:
    count = len(_connected_devices)
    _connected_devices.clear()
    return count


# ── Auth dependency ───────────────────────────────────────────────────────────


async def require_auth(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> str:
    """Validate Bearer token and track the calling device."""
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=401,
            detail="Missing authentication token. Provide Authorization: Bearer <api_key> header.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not auth_module.verify_token(credentials.credentials):
        raise HTTPException(
            status_code=401,
            detail="Invalid API key. Re-pair your device using the setup passcode.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    _track_device(request, credentials.credentials)
    return credentials.credentials

_start_time: float = 0.0


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


def _get_all_local_ips() -> list[str]:
    ips: list[str] = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    if not ips:
        ips.append(_get_local_ip())
    return ips


def _check_codex_cli() -> dict:
    cli_path = codex_data.CODEX_CLI
    if os.path.isfile(cli_path) and os.access(cli_path, os.X_OK):
        return {"installed": True, "path": cli_path}
    which = shutil.which(cli_path)
    if which:
        return {"installed": True, "path": which}
    return {"installed": False, "path": cli_path, "error": "Codex CLI not found"}


def _check_codex_data() -> dict:
    codex_dir = codex_data.CODEX_DIR
    state_db = codex_data.STATE_DB
    result: dict = {"codex_dir_exists": codex_dir.exists(), "db_exists": state_db.exists()}
    if not codex_dir.exists():
        result["error"] = f"Codex data directory not found at {codex_dir}. Is Codex app installed?"
    elif not state_db.exists():
        result["error"] = f"Codex database not found at {state_db}. Run Codex at least once."
    return result


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    global _start_time, _setup_passcode, _api_key
    _start_time = time.time()

    if not _api_key:
        _api_key, _setup_passcode = auth_module.init_auth()

    cli_status = _check_codex_cli()
    if not cli_status.get("installed"):
        logger.warning("Codex CLI not found at '%s'. Task execution will not work.", cli_status["path"])
    data_status = _check_codex_data()
    if not data_status.get("db_exists"):
        logger.warning("Codex data: %s", data_status.get("error", "unknown issue"))

    local_ip = _get_local_ip()
    logger.info("iCodex API starting on http://%s:%d", local_ip, PORT)

    loop = asyncio.get_running_loop()
    remote_awake_task = asyncio.create_task(_remote_awake_loop())
    try:
        watcher_service.start(loop)
    except Exception as exc:
        logger.warning("File watcher failed to start: %s", exc)
    yield
    remote_awake_task.cancel()
    try:
        await remote_awake_task
    except asyncio.CancelledError:
        pass
    codex_gui.ensure_remote_awake(False)
    watcher_service.stop()


app = FastAPI(title="iCodex API", version="2.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Internal helpers (menu-bar → server, no auth) ────────────────────────────


def _require_internal(request: Request) -> None:
    """Only allow requests from localhost with internal header."""
    client_ip = request.client.host if request.client else ""
    internal = request.headers.get("x-internal", "")
    if client_ip not in ("127.0.0.1", "::1", "localhost") or internal != "menubar":
        raise HTTPException(status_code=403, detail="Internal only")


# ── Helpers ──────────────────────────────────────────────────────────────────


def _thread_to_response(t: dict) -> ThreadResponse:
    return ThreadResponse(
        id=t["id"],
        title=t["title"],
        source=t["source"],
        model_provider=t["model_provider"],
        cwd=t["cwd"],
        created_at=t["created_at"],
        updated_at=t["updated_at"],
        approval_mode=t["approval_mode"],
        tokens_used=t["tokens_used"],
        archived=bool(t["archived"]),
        git_branch=t.get("git_branch"),
        git_origin_url=t.get("git_origin_url"),
        cli_version=t.get("cli_version", ""),
        first_user_message=t.get("first_user_message", ""),
        agent_nickname=t.get("agent_nickname"),
        is_running=t.get("is_running", False),
        git_stats=t.get("git_stats"),
    )


def _thread_to_detail(t: dict) -> ThreadDetailResponse:
    return ThreadDetailResponse(
        id=t["id"],
        title=t["title"],
        source=t["source"],
        model_provider=t["model_provider"],
        cwd=t["cwd"],
        created_at=t["created_at"],
        updated_at=t["updated_at"],
        approval_mode=t["approval_mode"],
        tokens_used=t["tokens_used"],
        archived=bool(t["archived"]),
        git_branch=t.get("git_branch"),
        git_origin_url=t.get("git_origin_url"),
        cli_version=t.get("cli_version", ""),
        first_user_message=t.get("first_user_message", ""),
        agent_nickname=t.get("agent_nickname"),
        rollout_path=t.get("rollout_path", ""),
        sandbox_policy=t.get("sandbox_policy", ""),
        git_sha=t.get("git_sha"),
        agent_role=t.get("agent_role"),
        memory_mode=t.get("memory_mode", "enabled"),
        is_running=t.get("is_running", False),
        git_stats=t.get("git_stats"),
    )


# ── Health (no auth) ─────────────────────────────────────────────────────────


@app.get("/health", response_model=ServerStatus)
async def health() -> ServerStatus:
    try:
        stats_data = await asyncio.to_thread(codex_data.get_thread_stats)
        stats = ThreadStats(**stats_data)
    except Exception as exc:
        logger.error("Failed to read thread stats: %s", exc)
        stats = None
    return ServerStatus(
        version="2.1.0",
        stats=stats,
        uptime_seconds=round(time.time() - _start_time, 2),
    )


# ── Auth ─────────────────────────────────────────────────────────────────────


class SetupRequest(BaseModel):
    passcode: str
    device_name: str = ""


class AuthResponse(BaseModel):
    api_key: str
    message: str = "Authentication successful"


@app.post("/auth/setup", response_model=AuthResponse)
async def auth_setup(req: SetupRequest, request: Request) -> AuthResponse:
    """Exchange a 6-digit setup passcode for the API key."""
    api_key = auth_module.exchange_passcode(req.passcode)
    if api_key is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired setup passcode. Check the code displayed on your Mac.",
        )
    # Track this device immediately
    ip = request.client.host if request.client else "unknown"
    device_id = hashlib.sha256(api_key.encode()).hexdigest()[:12]
    _connected_devices[device_id] = {
        "id": device_id,
        "ip": ip,
        "name": req.device_name or f"Device ({ip})",
        "user_agent": request.headers.get("user-agent", ""),
        "last_seen": time.time(),
        "connected_at": time.time(),
    }
    return AuthResponse(api_key=api_key)


@app.get("/auth/verify")
async def auth_verify(_token: str = Depends(require_auth)) -> dict:
    return {"authenticated": True, "message": "Token is valid"}


# ── Network Info ─────────────────────────────────────────────────────────────


@app.get("/network-info", response_model=NetworkInfo)
async def network_info(_token: str = Depends(require_auth)) -> NetworkInfo:
    ip = _get_local_ip()
    all_ips = _get_all_local_ips()
    hostname = socket.gethostname()
    return NetworkInfo(
        local_ip=ip, all_ips=all_ips, hostname=hostname,
        port=PORT, url=f"http://{ip}:{PORT}",
    )


# ── Diagnostics ──────────────────────────────────────────────────────────────


@app.get("/diagnostics")
async def diagnostics(_token: str = Depends(require_auth)) -> dict:
    cli = _check_codex_cli()
    data = _check_codex_data()
    issues: list[str] = []
    if not cli.get("installed"):
        issues.append("Codex CLI binary not found. Install Codex app or set CODEX_CLI_PATH.")
    if not data.get("codex_dir_exists"):
        issues.append("~/.codex/ directory missing. Install and run Codex at least once.")
    elif not data.get("db_exists"):
        issues.append("Codex database not found. Run Codex at least once to initialize data.")

    # Check GUI control capability
    import codex_gui
    gui_running = codex_gui.is_gui_running()
    accessibility = codex_gui.check_accessibility()
    if gui_running and not accessibility.get("success"):
        issues.append(
            "Accessibility permission needed for GUI control. "
            "Go to System Settings → Privacy & Security → Accessibility "
            "→ click '+' → add iCodex-Connect → toggle ON."
        )

    return {
        "codex_cli_installed": cli.get("installed", False),
        "codex_cli_path": cli.get("path", ""),
        "codex_dir_exists": data.get("codex_dir_exists", False),
        "db_exists": data.get("db_exists", False),
        "server_port": PORT,
        "local_ip": _get_local_ip(),
        "codex_gui_running": gui_running,
        "gui_control_available": gui_running and accessibility.get("success", False),
        "issues": issues,
    }


# ── Internal endpoints (menu-bar only, no auth) ──────────────────────────────


@app.get("/internal/devices")
async def internal_list_devices(request: Request) -> list[dict]:
    """List connected devices (called by menu-bar app)."""
    _require_internal(request)
    now = time.time()
    return [
        d for d in _connected_devices.values()
        if now - d["last_seen"] < DEVICE_TIMEOUT
    ]


@app.get("/internal/pairing-status")
async def internal_pairing_status(request: Request) -> dict:
    """Current server/pairing snapshot for the native menu-bar app."""
    global _setup_passcode
    _require_internal(request)
    _setup_passcode = auth_module.ensure_setup_passcode()
    now = time.time()
    devices = [
        d for d in _connected_devices.values()
        if now - d["last_seen"] < DEVICE_TIMEOUT
    ]
    return {
        "running": True,
        "local_ip": _get_local_ip(),
        "port": PORT,
        "passcode": _setup_passcode,
        "devices": devices,
    }


@app.post("/internal/devices/{device_id}/disconnect")
async def internal_disconnect_device(device_id: str, request: Request) -> dict:
    _require_internal(request)
    ok = _disconnect_device(device_id)
    return {"disconnected": ok}


@app.post("/internal/devices/disconnect-all")
async def internal_disconnect_all(request: Request) -> dict:
    _require_internal(request)
    count = _disconnect_all_devices()
    return {"disconnected": count}


# ── Threads ──────────────────────────────────────────────────────────────────


@app.get("/threads", response_model=list[ThreadResponse])
async def list_threads(
    include_archived: bool = Query(False),
    source: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    _token: str = Depends(require_auth),
) -> list[ThreadResponse]:
    if not codex_data.STATE_DB.exists():
        raise HTTPException(
            status_code=503,
            detail="Codex database not found. Please install and run Codex at least once.",
        )
    try:
        threads = codex_data.list_threads(
            include_archived=include_archived, source=source,
            limit=limit, offset=offset,
        )
    except Exception as exc:
        logger.error("Failed to list threads: %s", exc)
        raise HTTPException(status_code=500, detail=f"Database error: {exc}")
    return [_thread_to_response(t) for t in threads]


@app.get("/threads/{thread_id}", response_model=ThreadDetailResponse)
async def get_thread(thread_id: str, _token: str = Depends(require_auth)) -> ThreadDetailResponse:
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")
    return _thread_to_detail(thread)


@app.get("/threads/{thread_id}/messages", response_model=list[ConversationMessage])
async def get_thread_messages(thread_id: str, _token: str = Depends(require_auth)) -> list[ConversationMessage]:
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")
    messages = codex_data.get_thread_messages(thread_id)
    return [ConversationMessage(**m) for m in messages]


# ── Reply / Send message to thread ──────────────────────────────────────────


class ReplyRequest(BaseModel):
    message: str


class GUIActionRequest(BaseModel):
    action: str


class GUIControlPressRequest(BaseModel):
    control_id: str


@app.post("/threads/{thread_id}/reply", status_code=200)
async def reply_to_thread(thread_id: str, req: ReplyRequest, _token: str = Depends(require_auth)) -> dict:
    """Resume an existing thread with a new message.

    • If the thread is actively running (in GUI or CLI), returns an error
      explaining the user must wait or interrupt first.
    • Otherwise, resumes the thread via ``codex exec resume``.
    """
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    result = await codex_data.resume_thread(
        thread_id=thread_id,
        prompt=req.message,
        cwd=thread["cwd"],
    )
    return result


@app.post("/threads/{thread_id}/gui-action", status_code=200)
async def thread_gui_action(thread_id: str, req: GUIActionRequest, _token: str = Depends(require_auth)) -> dict:
    """Send a supported GUI navigation action to a running Codex desktop thread."""
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    result = codex_data.perform_gui_action(thread_id, req.action)
    result["thread_id"] = thread_id

    status = result.get("status")
    if status == "sent":
        result["message"] = f"Sent {req.action.replace('_', ' ')} to Codex."
    elif status == "not_running":
        result["message"] = "Thread is not running."
    elif status == "process_running":
        result["message"] = result.get("error", "GUI controls are only available for Codex desktop threads.")
    elif status == "gui_unavailable":
        result["message"] = result.get("error", "Codex desktop app is not running.")
    elif status == "gui_error":
        result["message"] = result.get("error", "Could not send GUI action to Codex.")

    return result


@app.get("/threads/{thread_id}/gui-controls", status_code=200)
async def thread_gui_controls(thread_id: str, _token: str = Depends(require_auth)) -> dict:
    """Return the currently mirrored GUI choices for a Codex desktop thread."""
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    result = codex_data.get_thread_gui_controls(thread_id)
    result["thread_id"] = thread_id

    status = result.get("status")
    if status == "available":
        result["message"] = "Fetched GUI choices."
    elif status == "locked":
        result["message"] = result.get("error", "Mac is locked, so GUI control is unavailable.")
    elif status == "process_running":
        result["message"] = result.get("error", "GUI choices are only available for Codex desktop threads.")
    elif status == "gui_unavailable":
        result["message"] = result.get("error", "Codex desktop app is not running.")
    elif status == "gui_error":
        result["message"] = result.get("error", "Could not read GUI choices from Codex.")

    return result


@app.post("/threads/{thread_id}/gui-control-press", status_code=200)
async def thread_gui_control_press(
    thread_id: str,
    req: GUIControlPressRequest,
    _token: str = Depends(require_auth),
) -> dict:
    """Press one mirrored GUI choice for a Codex desktop thread."""
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    result = codex_data.press_thread_gui_control(thread_id, req.control_id)
    result["thread_id"] = thread_id

    status = result.get("status")
    if status == "pressed":
        result["message"] = "Pressed GUI choice."
    elif status == "process_running":
        result["message"] = result.get("error", "GUI choices are only available for Codex desktop threads.")
    elif status == "gui_unavailable":
        result["message"] = result.get("error", "Codex desktop app is not running.")
    elif status == "gui_error":
        result["message"] = result.get("error", "Could not press the selected GUI choice.")

    return result


class NewTaskRequest(BaseModel):
    prompt: str
    cwd: str
    model: Optional[str] = None
    full_auto: bool = False


@app.post("/tasks/exec", status_code=201)
async def exec_task(req: NewTaskRequest, _token: str = Depends(require_auth)) -> dict:
    cli = _check_codex_cli()
    if not cli.get("installed"):
        raise HTTPException(
            status_code=503,
            detail="Codex CLI not found. Install the Codex app or set CODEX_CLI_PATH.",
        )
    try:
        result = await codex_data.exec_new_task(
            prompt=req.prompt, cwd=req.cwd,
            model=req.model, full_auto=req.full_auto,
        )
    except FileNotFoundError:
        raise HTTPException(status_code=503, detail="Codex CLI binary not found at expected path.")
    except Exception as exc:
        logger.error("Failed to exec task: %s", exc)
        raise HTTPException(status_code=500, detail=f"Failed to start task: {exc}")
    return result


@app.post("/tasks/{task_id}/stop", status_code=200)
async def stop_task(task_id: str, _token: str = Depends(require_auth)) -> dict:
    result = await codex_data.stop_task(task_id)
    result["task_id"] = task_id
    return result


@app.post("/threads/{thread_id}/stop", status_code=200)
async def stop_thread(thread_id: str, _token: str = Depends(require_auth)) -> dict:
    """Stop a running thread.

    Tries our own process first, then falls back to sending Ctrl-C
    to the Codex GUI via AppleScript.
    """
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    result = await codex_data.stop_task(thread_id)
    result["thread_id"] = thread_id

    status = result.get("status")
    if status == "stopped":
        result["message"] = "Thread stopped."
    elif status == "gui_error":
        result["message"] = result.get("error", "Could not stop via Codex GUI.")
    elif status == "not_running":
        result["message"] = "Thread is not currently running."
    return result


@app.post("/threads/{thread_id}/interrupt", status_code=200)
async def interrupt_thread(thread_id: str, _token: str = Depends(require_auth)) -> dict:
    """Interrupt the current command in a running thread.

    Tries our own process first, then falls back to sending Escape
    to the Codex GUI via AppleScript.
    """
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    result = codex_data.interrupt_thread(thread_id)
    result["thread_id"] = thread_id

    status = result.get("status")
    if status == "interrupted":
        result["message"] = "Interrupt signal sent."
    elif status == "gui_error":
        result["message"] = result.get("error", "Could not interrupt via Codex GUI.")
    elif status == "not_running":
        result["message"] = "Thread is not currently running."
    return result


# ── Models ───────────────────────────────────────────────────────────────────


@app.get("/models", response_model=list[CodexModel])
async def list_models(_token: str = Depends(require_auth)) -> list[CodexModel]:
    models = codex_data.list_models()
    return [CodexModel(**m) for m in models]


# ── Config ───────────────────────────────────────────────────────────────────


@app.get("/config", response_model=CodexConfig)
async def get_config(_token: str = Depends(require_auth)) -> CodexConfig:
    cfg = codex_data.get_config()
    return CodexConfig(
        model=cfg.get("model", ""),
        model_reasoning_effort=cfg.get("model_reasoning_effort", ""),
        mcp_servers=cfg.get("mcp_servers", {}),
    )


class ConfigUpdateRequest(BaseModel):
    model: Optional[str] = None
    model_reasoning_effort: Optional[str] = None


@app.put("/config", response_model=CodexConfig)
async def update_config(req: ConfigUpdateRequest, _token: str = Depends(require_auth)) -> CodexConfig:
    cfg = codex_data.update_config(
        model=req.model, reasoning_effort=req.model_reasoning_effort,
    )
    return CodexConfig(
        model=cfg.get("model", ""),
        model_reasoning_effort=cfg.get("model_reasoning_effort", ""),
        mcp_servers=cfg.get("mcp_servers", {}),
    )


# ── Stats ────────────────────────────────────────────────────────────────────


@app.get("/stats", response_model=ThreadStats)
async def get_stats(_token: str = Depends(require_auth)) -> ThreadStats:
    return ThreadStats(**(await asyncio.to_thread(codex_data.get_thread_stats)))


# ── WebSocket: real-time updates ─────────────────────────────────────────────


@app.websocket("/ws/live")
async def ws_live(websocket: WebSocket, token: str = "") -> None:
    """Push real-time updates: thread list changes + new messages."""
    if not token or not auth_module.verify_token(token):
        await websocket.close(code=4001, reason="Unauthorized")
        return
    device_id = _track_websocket_device(token)
    await websocket.accept()
    queue = watcher_service.subscribe()

    try:
        while True:
            data = await queue.get()
            if data["type"] == "threads_changed":
                threads = await asyncio.to_thread(codex_data.list_threads, limit=50)
                await websocket.send_text(json.dumps({
                    "type": "threads_update",
                    "threads": [_thread_to_response(t).model_dump() for t in threads],
                }))
            elif data["type"] == "new_message":
                thread_id = data.get("thread_id")
                event = data.get("event", {})
                msg = _parse_event_to_message(event)
                if msg and thread_id:
                    await websocket.send_text(json.dumps({
                        "type": "new_message",
                        "thread_id": thread_id,
                        "message": msg,
                    }))
    except WebSocketDisconnect:
        pass
    finally:
        _untrack_websocket_device(device_id)
        watcher_service.unsubscribe(queue)


@app.websocket("/ws/thread/{thread_id}")
async def ws_thread(websocket: WebSocket, thread_id: str, token: str = "") -> None:
    """Stream real-time messages for a specific thread."""
    if not token or not auth_module.verify_token(token):
        await websocket.close(code=4001, reason="Unauthorized")
        return
    device_id = _track_websocket_device(token)

    thread = await asyncio.to_thread(codex_data.get_thread, thread_id)
    if thread is None:
        _untrack_websocket_device(device_id)
        await websocket.close(code=4004, reason="Thread not found")
        return

    await websocket.accept()
    queue = watcher_service.subscribe()

    try:
        while True:
            data = await queue.get()
            if data["type"] == "new_message" and data.get("thread_id") == thread_id:
                event = data.get("event", {})
                msg = _parse_event_to_message(event)
                if msg:
                    await websocket.send_text(json.dumps({
                        "type": "new_message",
                        "message": msg,
                    }))
            elif data["type"] == "threads_changed":
                t = await asyncio.to_thread(codex_data.get_thread, thread_id)
                if t:
                    await websocket.send_text(json.dumps({
                        "type": "thread_status",
                        "is_running": t.get("is_running", False),
                        "tokens_used": t["tokens_used"],
                    }))
    except WebSocketDisconnect:
        pass
    finally:
        _untrack_websocket_device(device_id)
        watcher_service.unsubscribe(queue)


def _parse_event_to_message(event: dict) -> Optional[dict]:
    event_type = event.get("type", "")

    if event_type == "response_item":
        item = event.get("payload", event)
        role = item.get("role", "unknown")
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
            return {
                "role": role,
                "content": "\n".join(text_parts),
                "timestamp": event.get("timestamp"),
                "type": event_type,
            }

    elif event_type == "event_msg":
        payload = event.get("payload", {})
        event_name = payload.get("event", "")
        if event_name:
            return {
                "role": "system",
                "content": event_name.replace("_", " ").title(),
                "timestamp": event.get("timestamp"),
                "type": "event",
            }

    return None


def _is_port_in_use(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("127.0.0.1", port)) == 0


def start_server() -> None:
    import uvicorn

    logging.basicConfig(level=logging.INFO)

    if _is_port_in_use(PORT):
        logger.error(
            "Port %d is already in use. Another iCodex instance may be running. "
            "Kill it with: lsof -ti:%d | xargs kill -9",
            PORT, PORT,
        )
        raise SystemExit(1)

    global _api_key, _setup_passcode

    local_ip = _get_local_ip()
    _api_key, _setup_passcode = auth_module.init_auth()

    print(f"\n{'='*54}")
    print(f"  iCodex API Server v2.1.0")
    print(f"  Local:   http://127.0.0.1:{PORT}")
    print(f"  Network: http://{local_ip}:{PORT}")
    print(f"{'─'*54}")
    print(f"  Setup Passcode:  {_setup_passcode}")
    print(f"{'─'*54}")
    print(f"  Enter the 6-digit passcode in the iOS app to pair.")
    print(f"{'='*54}\n")

    uvicorn.run(app, host=HOST, port=PORT, log_level="info")


if __name__ == "__main__":
    start_server()
