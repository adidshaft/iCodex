"""FastAPI application – REST + WebSocket endpoints for Codex local data."""

from __future__ import annotations
import asyncio
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
    AuditEvent,
    BuildInfo,
    PermissionDiagnostics,
    PreviewSnapshot,
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
APP_VERSION = "2.2.0"
RELEASE_TAG = "main-build"
RELEASE_URL = f"https://github.com/adidshaft/iCodex/releases/tag/{RELEASE_TAG}"
DOWNLOAD_URL = f"https://github.com/adidshaft/iCodex/releases/download/{RELEASE_TAG}/iCodex-Connect.dmg"
WEBSITE_URL = "https://icodex.kyokasuigetsu.xyz/"
AUDIT_LOG_FILE = Path.home() / ".codex" / "icodex_audit.jsonl"

security = HTTPBearer(auto_error=False)

# ── Device tracking ──────────────────────────────────────────────────────────

# {device_id: {id, ip, name, user_agent, last_seen, connected_at, capabilities}}
_connected_devices: dict[str, dict] = {}
_connected_ws_devices: dict[str, int] = {}
DEVICE_TIMEOUT = 120  # seconds — prune devices not seen in this window


def _version_tuple(value: str) -> tuple[int, int, int]:
    parts = [int(part) if part.isdigit() else 0 for part in value.split(".")[:3]]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def _audit_log_path() -> Path:
    AUDIT_LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    return AUDIT_LOG_FILE


def _record_audit_event(
    action: str,
    outcome: str,
    *,
    auth_context: dict | None = None,
    thread_id: str | None = None,
    details: dict | None = None,
    latency_ms: float = 0.0,
) -> None:
    payload = {
        "timestamp": time.time(),
        "action": action,
        "outcome": outcome,
        "thread_id": thread_id,
        "device_id": (auth_context or {}).get("device_id", ""),
        "device_name": (auth_context or {}).get("device_name", ""),
        "latency_ms": round(latency_ms, 2),
        "details": details or {},
    }
    try:
        with _audit_log_path().open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, ensure_ascii=False) + "\n")
    except Exception:
        logger.debug("Failed to append audit event", exc_info=True)


def _recent_audit_events(limit: int = 100) -> list[dict]:
    if not AUDIT_LOG_FILE.exists():
        return []
    try:
        lines = AUDIT_LOG_FILE.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    events: list[dict] = []
    for line in reversed(lines[-limit:]):
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return list(reversed(events))


def _build_info(client_version: str = "") -> dict:
    server_version = APP_VERSION
    client_version = client_version or ""
    update_available = bool(client_version) and _version_tuple(server_version) > _version_tuple(client_version)
    compatible = True
    if client_version:
        compatible = _version_tuple(client_version)[0] == _version_tuple(server_version)[0]
    message = "Up to date"
    if update_available:
        message = "A newer iCodex-Connect build is available."
    return {
        "api_version": server_version,
        "app_version": server_version,
        "client_version": client_version,
        "release_tag": RELEASE_TAG,
        "release_url": RELEASE_URL,
        "download_url": DOWNLOAD_URL,
        "website_url": WEBSITE_URL,
        "compatible": compatible,
        "requires_update": update_available,
        "update_message": message,
        "notes": [
            "Remote control and pairing are supported on the current build.",
            "Accessibility is required for GUI control.",
        ],
    }


def _permission_diagnostics(auth_context: dict) -> dict:
    helper_found = bool(getattr(codex_gui, "_HELPER", None))
    session_state = codex_gui.get_session_state()
    accessibility = codex_gui.probe_accessibility()
    codex_running = codex_gui.is_gui_running()
    capabilities = auth_context.get("capabilities", [])
    missing = [cap for cap in auth_module.ALL_CAPABILITIES if cap not in capabilities]
    can_control = "control" in capabilities and accessibility.get("success", False) and codex_running and session_state.get("available", True)
    can_launch = "launch" in capabilities
    can_configure = "configure" in capabilities
    can_reply = "reply" in capabilities
    issues: list[str] = []
    advice: list[str] = []
    if not helper_found:
        issues.append("Native keystroke helper is missing from the installed app bundle.")
        advice.append("Reinstall iCodex-Connect from the latest DMG.")
    if not accessibility.get("success", False):
        issues.append("Accessibility permission is not granted.")
        advice.append("Open System Settings → Privacy & Security → Accessibility and enable iCodex-Connect.")
    if session_state.get("locked"):
        issues.append("macOS is locked or not on console.")
        advice.append("Unlock the Mac before sending remote GUI actions.")
    if not codex_running:
        issues.append("Codex desktop app is not currently running.")
        advice.append("Open Codex on the Mac before trying remote GUI control.")
    if missing:
        advice.append("Use Trusted Devices to grant or revoke device-level permissions.")
    return {
        "device_id": auth_context.get("device_id", ""),
        "device_name": auth_context.get("device_name", ""),
        "capabilities": capabilities,
        "missing_capabilities": missing,
        "accessibility_granted": accessibility.get("success", False),
        "screen_locked": bool(session_state.get("locked")),
        "codex_running": codex_running,
        "gui_ready": can_control and codex_running and accessibility.get("success", False),
        "helper_found": helper_found,
        "can_reply": can_reply,
        "can_control": can_control,
        "can_launch": can_launch,
        "can_configure": can_configure,
        "issues": issues,
        "advice": advice,
        "session_state": session_state,
    }


def _prune_stale_devices() -> None:
    now = time.time()
    stale = [did for did, d in _connected_devices.items() if now - d["last_seen"] > DEVICE_TIMEOUT]
    for did in stale:
        _connected_devices.pop(did, None)


def _track_device(request: Request, auth_context: dict) -> None:
    """Record/update a device entry from an authenticated request."""
    ip = request.client.host if request.client else "unknown"
    ua = request.headers.get("user-agent", "")
    name = request.headers.get("x-device-name", "")
    device_id = auth_context["device_id"]
    now = time.time()

    existing = _connected_devices.get(device_id)
    trusted_name = auth_context.get("device_name", "")
    resolved_name = trusted_name or name or (existing["name"] if existing else f"Device ({ip})")
    _connected_devices[device_id] = {
        "id": device_id,
        "ip": ip,
        "name": resolved_name,
        "user_agent": ua,
        "last_seen": now,
        "connected_at": existing["connected_at"] if existing else now,
        "capabilities": auth_context.get("capabilities", []),
    }
    auth_module.record_device_activity(device_id, name=trusted_name or None)
    _prune_stale_devices()


def _track_websocket_device(device_id: str) -> str:
    _connected_ws_devices[device_id] = _connected_ws_devices.get(device_id, 0) + 1
    return device_id


def _untrack_websocket_device(device_id: str) -> None:
    count = _connected_ws_devices.get(device_id, 0)
    if count <= 1:
        _connected_ws_devices.pop(device_id, None)
    else:
        _connected_ws_devices[device_id] = count - 1


def _has_remote_presence() -> bool:
    _prune_stale_devices()
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


def _trusted_device_snapshots(current_device_id: str | None = None) -> list[dict]:
    _prune_stale_devices()
    devices = []
    for device in auth_module.list_trusted_devices():
        device_id = device["id"]
        live = _connected_devices.get(device_id)
        connected = bool(live) or _connected_ws_devices.get(device_id, 0) > 0
        devices.append({
            **device,
            "current": device_id == current_device_id,
            "connected": connected,
            "active_websockets": _connected_ws_devices.get(device_id, 0),
            "ip": live.get("ip") if live else None,
            "last_seen": live.get("last_seen") if live else device.get("last_seen_at"),
            "connected_at": live.get("connected_at") if live else None,
        })
    return devices


# ── Auth dependency ───────────────────────────────────────────────────────────


async def require_auth(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> dict:
    """Validate Bearer token and track the calling device."""
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=401,
            detail="Missing authentication token. Provide Authorization: Bearer <api_key> header.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    device = auth_module.get_device_for_token(credentials.credentials)
    if not device:
        raise HTTPException(
            status_code=401,
            detail="Invalid API key. Re-pair your device using the setup passcode.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    auth_context = {
        "token": credentials.credentials,
        "device_id": device["id"],
        "device_name": device.get("name", ""),
        "capabilities": device.get("capabilities", list(auth_module.ALL_CAPABILITIES)),
        "legacy": bool(device.get("legacy")),
    }
    _track_device(request, auth_context)
    return auth_context


def _require_capability(auth_context: dict, capability: str) -> None:
    if capability in auth_context.get("capabilities", []):
        return
    raise HTTPException(
        status_code=403,
        detail=(
            f"This device does not have the '{capability}' permission. "
            "Open Trusted Devices in iCodex Settings to adjust its access."
        ),
    )

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


app = FastAPI(title="iCodex API", version=APP_VERSION, lifespan=lifespan)

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
        version=APP_VERSION,
        stats=stats,
        uptime_seconds=round(time.time() - _start_time, 2),
    )


# ── Auth ─────────────────────────────────────────────────────────────────────


class SetupRequest(BaseModel):
    passcode: str
    device_name: str = ""


class AuthResponse(BaseModel):
    api_key: str
    device_id: str
    device_name: str
    capabilities: list[str]
    message: str = "Authentication successful"


@app.post("/auth/setup", response_model=AuthResponse)
async def auth_setup(req: SetupRequest, request: Request) -> AuthResponse:
    """Exchange a 6-digit setup passcode for a device-scoped API key."""
    setup = auth_module.exchange_passcode(
        req.passcode,
        device_name=req.device_name,
        installation_id=request.headers.get("x-device-installation-id", ""),
    )
    if setup is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired setup passcode. Check the code displayed on your Mac.",
        )
    ip = request.client.host if request.client else "unknown"
    device_id = setup["device_id"]
    now = time.time()
    _connected_devices[device_id] = {
        "id": device_id,
        "ip": ip,
        "name": setup["device_name"] or req.device_name or f"Device ({ip})",
        "user_agent": request.headers.get("user-agent", ""),
        "last_seen": now,
        "connected_at": now,
        "capabilities": setup["capabilities"],
    }
    response = AuthResponse(
        api_key=setup["api_key"],
        device_id=device_id,
        device_name=setup["device_name"],
        capabilities=setup["capabilities"],
    )
    _record_audit_event(
        "auth.setup",
        "paired",
        auth_context={"device_id": device_id, "device_name": response.device_name, "capabilities": response.capabilities},
        details={"ip": ip, "user_agent": request.headers.get("user-agent", "")},
    )
    return response


@app.get("/auth/verify")
async def auth_verify(auth_context: dict = Depends(require_auth)) -> dict:
    payload = {
        "authenticated": True,
        "message": "Token is valid",
        "device_id": auth_context["device_id"],
        "device_name": auth_context.get("device_name", ""),
        "capabilities": auth_context.get("capabilities", []),
    }
    _record_audit_event("auth.verify", "ok", auth_context=auth_context)
    return payload


@app.post("/auth/disconnect")
async def auth_disconnect(_request: Request, auth_context: dict = Depends(require_auth)) -> dict:
    """Explicitly disconnect the currently authenticated device."""
    device_id = auth_context["device_id"]
    removed_http = _connected_devices.pop(device_id, None) is not None
    removed_ws = _connected_ws_devices.pop(device_id, None) is not None
    payload = {"disconnected": removed_http or removed_ws, "device_id": device_id}
    _record_audit_event("auth.disconnect", "disconnected" if payload["disconnected"] else "noop", auth_context=auth_context)
    return payload


class TrustedDeviceUpdateRequest(BaseModel):
    name: Optional[str] = None
    capabilities: Optional[list[str]] = None


@app.get("/devices")
async def list_devices(auth_context: dict = Depends(require_auth)) -> list[dict]:
    _require_capability(auth_context, "view")
    devices = _trusted_device_snapshots(current_device_id=auth_context["device_id"])
    _record_audit_event("devices.list", "ok", auth_context=auth_context, details={"count": len(devices)})
    return devices


@app.put("/devices/{device_id}")
async def update_device(device_id: str, req: TrustedDeviceUpdateRequest, auth_context: dict = Depends(require_auth)) -> dict:
    _require_capability(auth_context, "configure")
    updated = auth_module.update_device(device_id, name=req.name, capabilities=req.capabilities)
    if updated is None:
        raise HTTPException(status_code=404, detail="Trusted device not found")
    live = _connected_devices.get(device_id)
    if live:
        if req.name:
            live["name"] = updated["name"]
        live["capabilities"] = updated.get("capabilities", live.get("capabilities", []))
    payload = {
        **updated,
        "current": device_id == auth_context["device_id"],
        "connected": device_id in _connected_devices or _connected_ws_devices.get(device_id, 0) > 0,
        "active_websockets": _connected_ws_devices.get(device_id, 0),
        "ip": live.get("ip") if live else None,
        "last_seen": live.get("last_seen") if live else updated.get("last_seen_at"),
        "connected_at": live.get("connected_at") if live else None,
    }
    _record_audit_event("devices.update", "ok", auth_context=auth_context, details={"device_id": device_id, "name": req.name, "capabilities": req.capabilities})
    return payload


@app.post("/devices/{device_id}/revoke")
async def revoke_device(device_id: str, auth_context: dict = Depends(require_auth)) -> dict:
    _require_capability(auth_context, "configure")
    revoked = auth_module.revoke_device(device_id)
    if not revoked:
        raise HTTPException(status_code=404, detail="Trusted device not found")
    _connected_devices.pop(device_id, None)
    _connected_ws_devices.pop(device_id, None)
    payload = {"revoked": True, "device_id": device_id}
    _record_audit_event("devices.revoke", "ok", auth_context=auth_context, details={"device_id": device_id})
    return payload


# ── Network Info ─────────────────────────────────────────────────────────────


@app.get("/network-info", response_model=NetworkInfo)
async def network_info(_token: str = Depends(require_auth)) -> NetworkInfo:
    _require_capability(_token, "view")
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
    _require_capability(_token, "view")
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
    accessibility = codex_gui.probe_accessibility()
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


@app.get("/build-info", response_model=BuildInfo)
async def build_info(client_version: str = Query("", description="Optional client build version to compare")) -> BuildInfo:
    info = _build_info(client_version)
    return BuildInfo(**info)


@app.get("/compatibility", response_model=BuildInfo)
async def compatibility(client_version: str = Query("", description="Client build version")) -> BuildInfo:
    info = _build_info(client_version)
    return BuildInfo(**info)


@app.get("/permissions/diagnostics", response_model=PermissionDiagnostics)
async def permission_diagnostics(auth_context: dict = Depends(require_auth)) -> PermissionDiagnostics:
    info = _permission_diagnostics(auth_context)
    _record_audit_event("diagnostics.permissions", "ok", auth_context=auth_context, details={"gui_ready": info["gui_ready"]})
    return PermissionDiagnostics(**{k: v for k, v in info.items() if k != "session_state"})


@app.get("/audit-log", response_model=list[AuditEvent])
async def audit_log(
    auth_context: dict = Depends(require_auth),
    limit: int = Query(100, ge=1, le=500),
) -> list[AuditEvent]:
    _require_capability(auth_context, "view")
    events = _recent_audit_events(limit=limit)
    _record_audit_event("audit.log", "ok", auth_context=auth_context, details={"count": len(events), "limit": limit})
    return [AuditEvent(**event) for event in events]


@app.get("/qa/status")
async def qa_status(auth_context: dict = Depends(require_auth)) -> dict:
    _require_capability(auth_context, "view")
    diagnostics = _permission_diagnostics(auth_context)
    build = _build_info()
    pairing = auth_module.get_setup_passcode_metadata()
    state = codex_gui.get_remote_status()
    payload = {
        "build": build,
        "permissions": diagnostics,
        "pairing": {
            "passcode": pairing["passcode"],
            "generated_at": pairing["generated_at"],
            "expires_at": pairing["expires_at"],
            "seconds_remaining": pairing["seconds_remaining"],
            "expired": pairing["expired"],
        },
        "remote": state,
        "device_count": len(_trusted_device_snapshots(auth_context.get("device_id"))),
        "audit_log_available": AUDIT_LOG_FILE.exists(),
    }
    _record_audit_event("qa.status", "ok", auth_context=auth_context)
    return payload


@app.get("/qa/expiry")
async def qa_expiry(auth_context: dict = Depends(require_auth)) -> dict:
    _require_capability(auth_context, "view")
    pairing = auth_module.get_setup_passcode_metadata()
    payload = {
        "passcode": pairing["passcode"],
        "generated_at": pairing["generated_at"],
        "expires_at": pairing["expires_at"],
        "seconds_remaining": pairing["seconds_remaining"],
        "expired": pairing["expired"],
        "trusted_devices": len(auth_module.list_trusted_devices()),
    }
    _record_audit_event("qa.expiry", "ok", auth_context=auth_context)
    return payload


@app.get("/qa/afk")
async def qa_afk(auth_context: dict = Depends(require_auth)) -> dict:
    _require_capability(auth_context, "view")
    remote = codex_gui.get_remote_status()
    payload = {
        "session_state": remote.get("session_state", {}),
        "codex_running": remote.get("codex_running", False),
        "remote_ready": remote.get("remote_ready", False),
        "keep_awake_active": _has_remote_presence(),
    }
    _record_audit_event("qa.afk", "ok", auth_context=auth_context)
    return payload


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
        **_build_info(),
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
    auth_context: dict = Depends(require_auth),
) -> list[ThreadResponse]:
    _require_capability(auth_context, "view")
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
async def get_thread(thread_id: str, auth_context: dict = Depends(require_auth)) -> ThreadDetailResponse:
    _require_capability(auth_context, "view")
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")
    return _thread_to_detail(thread)


@app.get("/threads/{thread_id}/messages", response_model=list[ConversationMessage])
async def get_thread_messages(thread_id: str, auth_context: dict = Depends(require_auth)) -> list[ConversationMessage]:
    _require_capability(auth_context, "view")
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
async def reply_to_thread(thread_id: str, req: ReplyRequest, auth_context: dict = Depends(require_auth)) -> dict:
    """Resume an existing thread with a new message.

    • If the thread is actively running (in GUI or CLI), returns an error
      explaining the user must wait or interrupt first.
    • Otherwise, resumes the thread via ``codex exec resume``.
    """
    _require_capability(auth_context, "reply")
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    result = await codex_data.resume_thread(
        thread_id=thread_id,
        prompt=req.message,
        cwd=thread["cwd"],
    )
    _record_audit_event(
        "thread.reply",
        result.get("status", "unknown"),
        auth_context=auth_context,
        thread_id=thread_id,
        details={"mode": result.get("method", ""), "prompt_len": len(req.message)},
    )
    return result


@app.post("/threads/{thread_id}/gui-action", status_code=200)
async def thread_gui_action(thread_id: str, req: GUIActionRequest, auth_context: dict = Depends(require_auth)) -> dict:
    """Send a supported GUI navigation action to a running Codex desktop thread."""
    _require_capability(auth_context, "control")
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

    _record_audit_event(
        "thread.gui_action",
        status,
        auth_context=auth_context,
        thread_id=thread_id,
        details={"action": req.action},
    )
    return result


@app.get("/threads/{thread_id}/gui-controls", status_code=200)
async def thread_gui_controls(thread_id: str, auth_context: dict = Depends(require_auth)) -> dict:
    """Return the currently mirrored GUI choices for a Codex desktop thread."""
    _require_capability(auth_context, "view")
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    result = codex_data.get_thread_gui_controls(thread_id)
    result["thread_id"] = thread_id
    result["device_capabilities"] = auth_context.get("capabilities", [])
    result["current_device_id"] = auth_context.get("device_id")

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

    _record_audit_event(
        "thread.gui_controls",
        status or "unknown",
        auth_context=auth_context,
        thread_id=thread_id,
        details={"remote_ready": result.get("remote_ready", False)},
    )
    return result


@app.get("/threads/{thread_id}/preview", response_model=PreviewSnapshot)
async def thread_preview(thread_id: str, auth_context: dict = Depends(require_auth)) -> PreviewSnapshot:
    """Return a lightweight screenshot thumbnail for the active Codex GUI window."""
    _require_capability(auth_context, "view")
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    result = codex_gui.capture_thread_preview(thread_id)
    if result.get("success"):
        payload = PreviewSnapshot(
            thread_id=thread_id,
            available=True,
            image_base64=result.get("image_base64", ""),
            mime_type=result.get("mime_type", "image/png"),
            width=int(result.get("width", 0) or 0),
            height=int(result.get("height", 0) or 0),
            captured_at=float(result.get("captured_at", time.time()) or time.time()),
        )
    else:
        payload = PreviewSnapshot(thread_id=thread_id, available=False, captured_at=time.time())

    _record_audit_event(
        "thread.preview",
        "ok" if payload.available else "unavailable",
        auth_context=auth_context,
        thread_id=thread_id,
        details={"available": payload.available},
    )
    return payload


@app.post("/threads/{thread_id}/gui-control-press", status_code=200)
async def thread_gui_control_press(
    thread_id: str,
    req: GUIControlPressRequest,
    auth_context: dict = Depends(require_auth),
) -> dict:
    """Press one mirrored GUI choice for a Codex desktop thread."""
    _require_capability(auth_context, "control")
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

    _record_audit_event(
        "thread.gui_control_press",
        status,
        auth_context=auth_context,
        thread_id=thread_id,
        details={"control_id": req.control_id},
    )
    return result


@app.post("/threads/{thread_id}/control/{action}", status_code=200)
async def fast_thread_control(
    thread_id: str,
    action: str,
    auth_context: dict = Depends(require_auth),
) -> dict:
    """Low-latency control path for stop/interrupt and GUI keys."""
    _require_capability(auth_context, "control")
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    started = time.perf_counter()
    if action == "stop":
        result = await codex_data.stop_task(thread_id)
    elif action == "interrupt":
        result = codex_data.interrupt_thread(thread_id)
    elif action in codex_gui.GUI_KEY_ACTIONS:
        result = codex_data.perform_gui_action(thread_id, action)
    else:
        raise HTTPException(status_code=400, detail=f"Unsupported control action: {action}")

    latency_ms = (time.perf_counter() - started) * 1000
    result["thread_id"] = thread_id
    result["action"] = action
    result["latency_ms"] = round(latency_ms, 2)

    status = result.get("status", "unknown")
    if status in {"stopped", "interrupted", "sent"}:
        result["message"] = result.get("message", f"Control action '{action}' sent.")
    elif status == "process_running":
        result["message"] = result.get("error", "This thread is managed by CLI and cannot use GUI control.")
    elif status == "gui_error":
        result["message"] = result.get("error", "Could not send the control action.")

    _record_audit_event(
        "thread.fast_control",
        status,
        auth_context=auth_context,
        thread_id=thread_id,
        latency_ms=latency_ms,
        details={"action": action},
    )
    return result


@app.post("/threads/{thread_id}/recover", status_code=200)
async def recover_thread_focus(thread_id: str, auth_context: dict = Depends(require_auth)) -> dict:
    """Force Codex to recover a thread after focus loss or space changes."""
    _require_capability(auth_context, "control")
    thread = codex_data.get_thread(thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    result = codex_gui.recover_thread_focus(thread_id)
    result["thread_id"] = thread_id
    if result.get("success"):
        result["status"] = "recovered"
        result["message"] = "Recovered Codex thread focus."

    _record_audit_event(
        "thread.recover",
        result.get("status", "unknown"),
        auth_context=auth_context,
        thread_id=thread_id,
    )
    return result


class NewTaskRequest(BaseModel):
    prompt: str
    cwd: str
    model: Optional[str] = None
    full_auto: bool = False


@app.post("/tasks/exec", status_code=201)
async def exec_task(req: NewTaskRequest, auth_context: dict = Depends(require_auth)) -> dict:
    _require_capability(auth_context, "launch")
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
    _record_audit_event(
        "tasks.exec",
        "started",
        auth_context=auth_context,
        details={"cwd": req.cwd, "full_auto": req.full_auto, "model": req.model},
    )
    return result


@app.post("/tasks/{task_id}/stop", status_code=200)
async def stop_task(task_id: str, auth_context: dict = Depends(require_auth)) -> dict:
    _require_capability(auth_context, "control")
    result = await codex_data.stop_task(task_id)
    result["task_id"] = task_id
    _record_audit_event("tasks.stop", result.get("status", "unknown"), auth_context=auth_context, thread_id=task_id)
    return result


@app.post("/threads/{thread_id}/stop", status_code=200)
async def stop_thread(thread_id: str, auth_context: dict = Depends(require_auth)) -> dict:
    """Stop a running thread.

    Tries our own process first, then falls back to sending Ctrl-C
    to the Codex GUI via AppleScript.
    """
    _require_capability(auth_context, "control")
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
    _record_audit_event("thread.stop", status or "unknown", auth_context=auth_context, thread_id=thread_id)
    return result


@app.post("/threads/{thread_id}/interrupt", status_code=200)
async def interrupt_thread(thread_id: str, auth_context: dict = Depends(require_auth)) -> dict:
    """Interrupt the current command in a running thread.

    Tries our own process first, then falls back to sending Escape
    to the Codex GUI via AppleScript.
    """
    _require_capability(auth_context, "control")
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
    _record_audit_event("thread.interrupt", status or "unknown", auth_context=auth_context, thread_id=thread_id)
    return result


# ── Models ───────────────────────────────────────────────────────────────────


@app.get("/models", response_model=list[CodexModel])
async def list_models(auth_context: dict = Depends(require_auth)) -> list[CodexModel]:
    _require_capability(auth_context, "view")
    models = codex_data.list_models()
    return [CodexModel(**m) for m in models]


# ── Config ───────────────────────────────────────────────────────────────────


@app.get("/config", response_model=CodexConfig)
async def get_config(auth_context: dict = Depends(require_auth)) -> CodexConfig:
    _require_capability(auth_context, "view")
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
async def update_config(req: ConfigUpdateRequest, auth_context: dict = Depends(require_auth)) -> CodexConfig:
    _require_capability(auth_context, "configure")
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
async def get_stats(auth_context: dict = Depends(require_auth)) -> ThreadStats:
    _require_capability(auth_context, "view")
    return ThreadStats(**(await asyncio.to_thread(codex_data.get_thread_stats)))


# ── WebSocket: real-time updates ─────────────────────────────────────────────


@app.websocket("/ws/live")
async def ws_live(websocket: WebSocket, token: str = "") -> None:
    """Push real-time updates: thread list changes + new messages."""
    device = auth_module.get_device_for_token(token) if token else None
    if not device:
        await websocket.close(code=4001, reason="Unauthorized")
        return
    if "view" not in device.get("capabilities", []):
        await websocket.close(code=4003, reason="View access required")
        return
    device_id = _track_websocket_device(device["id"])
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
    device = auth_module.get_device_for_token(token) if token else None
    if not device:
        await websocket.close(code=4001, reason="Unauthorized")
        return
    if "view" not in device.get("capabilities", []):
        await websocket.close(code=4003, reason="View access required")
        return
    device_id = _track_websocket_device(device["id"])

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
    print(f"  iCodex API Server v{APP_VERSION}")
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
