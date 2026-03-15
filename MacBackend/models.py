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
