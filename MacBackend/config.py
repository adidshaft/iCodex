"""Central configuration for the Codex backend server."""

import os
from dotenv import load_dotenv

load_dotenv()

HOST: str = os.getenv("CODEX_HOST", "0.0.0.0")
PORT: int = int(os.getenv("CODEX_PORT", "8642"))
CODEX_CLI: str = os.getenv("CODEX_CLI_PATH", "codex")
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "info")
ALLOWED_ORIGINS: list[str] = os.getenv(
    "ALLOWED_ORIGINS", "*"
).split(",")

# Auth — the API key can be overridden via env var; otherwise generated/loaded
# by the auth module from ~/.codex/icodex_auth.json.
ICODEX_API_KEY: str | None = os.getenv("ICODEX_API_KEY")
