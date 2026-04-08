"""Pydantic request / response models."""

from __future__ import annotations
from pydantic import BaseModel, Field
from typing import Optional


class GitStats(BaseModel):
    insertions: int = 0
    deletions: int = 0
    files_changed: int = 0


class ThreadResponse(BaseModel):
    id: str
    title: str
    source: str
    model_provider: str
    cwd: str
    created_at: int
    updated_at: int
    approval_mode: str
    tokens_used: int
    archived: bool
    git_branch: Optional[str] = None
    git_origin_url: Optional[str] = None
    cli_version: str = ""
    first_user_message: str = ""
    agent_nickname: Optional[str] = None
    is_running: bool = False
    git_stats: Optional[GitStats] = None


class ThreadDetailResponse(ThreadResponse):
    rollout_path: str = ""
    sandbox_policy: str = ""
    git_sha: Optional[str] = None
    agent_role: Optional[str] = None
    memory_mode: str = "enabled"


class ConversationMessage(BaseModel):
    role: str
    content: str
    timestamp: Optional[str] = None
    type: str = "message"


class CodexModel(BaseModel):
    slug: str
    display_name: str
    description: str = ""
    default_reasoning_level: str = ""
    supported_reasoning_levels: list[dict] = []


class CodexConfig(BaseModel):
    model: str = ""
    model_reasoning_effort: str = ""
    mcp_servers: dict = {}


class ThreadStats(BaseModel):
    total_threads: int
    active_threads: int
    archived_threads: int
    total_tokens_used: int
    running_threads: int = 0
    sources: dict[str, int]


class ServerStatus(BaseModel):
    status: str = "running"
    version: str = "1.0.0"
    stats: Optional[ThreadStats] = None
    uptime_seconds: float = 0.0


class NetworkInfo(BaseModel):
    local_ip: str
    all_ips: list[str] = []
    hostname: str = ""
    port: int = 8642
    url: str = ""


class SystemDiagnostics(BaseModel):
    codex_cli_installed: bool = False
    codex_cli_path: str = ""
    codex_dir_exists: bool = False
    db_exists: bool = False
    server_port: int = 8642
    local_ip: str = ""
    issues: list[str] = []


class BuildInfo(BaseModel):
    api_version: str = "2.2.0"
    app_version: str = "2.2.0"
    client_version: str = ""
    release_tag: str = "main-build"
    release_url: str = "https://github.com/adidshaft/iCodex/releases/tag/main-build"
    download_url: str = "https://github.com/adidshaft/iCodex/releases/download/main-build/iCodex-Connect.dmg"
    website_url: str = "https://icodex.kyokasuigetsu.xyz/"
    compatible: bool = True
    requires_update: bool = False
    update_message: str = ""
    notes: list[str] = Field(default_factory=list)


class PermissionDiagnostics(BaseModel):
    device_id: str = ""
    device_name: str = ""
    capabilities: list[str] = Field(default_factory=list)
    missing_capabilities: list[str] = Field(default_factory=list)
    accessibility_granted: bool = False
    screen_locked: bool = False
    codex_running: bool = False
    gui_ready: bool = False
    helper_found: bool = False
    can_reply: bool = False
    can_control: bool = False
    can_launch: bool = False
    can_configure: bool = False
    issues: list[str] = Field(default_factory=list)
    advice: list[str] = Field(default_factory=list)


class PreviewSnapshot(BaseModel):
    thread_id: str = ""
    available: bool = False
    image_base64: str = ""
    mime_type: str = "image/png"
    width: int = 0
    height: int = 0
    captured_at: float = 0.0


class AuditEvent(BaseModel):
    timestamp: float = 0.0
    action: str = ""
    outcome: str = ""
    thread_id: Optional[str] = None
    device_id: str = ""
    device_name: str = ""
    latency_ms: float = 0.0
    details: dict = Field(default_factory=dict)
