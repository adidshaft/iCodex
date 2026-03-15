"""Authentication module for iCodex API.

Handles API key generation, storage, and verification.
Keys are stored in ~/.codex/icodex_auth.json.
"""

from __future__ import annotations

import json
import os
import random
import secrets
import string
from pathlib import Path


AUTH_FILE = Path.home() / ".codex" / "icodex_auth.json"
_state: dict = {}


def _ensure_codex_dir() -> None:
    AUTH_FILE.parent.mkdir(parents=True, exist_ok=True)


def _load_state() -> dict:
    global _state
    if _state:
        return _state

    # Check environment variable first
    env_key = os.getenv("ICODEX_API_KEY")
    if env_key:
        _state = {"api_key": env_key, "setup_complete": True}
        return _state

    # Try loading from file
    if AUTH_FILE.exists():
        try:
            with open(AUTH_FILE, "r") as f:
                _state = json.load(f)
            return _state
        except (json.JSONDecodeError, OSError):
            pass

    # Generate new key on first run
    api_key = secrets.token_urlsafe(32)
    _state = {"api_key": api_key, "setup_complete": False}
    _save_state()
    return _state


def _save_state() -> None:
    _ensure_codex_dir()
    with open(AUTH_FILE, "w") as f:
        json.dump(_state, f, indent=2)
    # Restrict permissions to owner only
    try:
        os.chmod(AUTH_FILE, 0o600)
    except OSError:
        pass


def get_api_key() -> str:
    """Return the current API key."""
    state = _load_state()
    return state["api_key"]


def verify_token(token: str) -> bool:
    """Check if a Bearer token matches the API key."""
    return secrets.compare_digest(token, get_api_key())


def generate_setup_passcode() -> str:
    """Generate a 6-digit setup passcode for initial pairing.

    The passcode is displayed in the terminal and the user enters it
    in the iOS app to exchange it for the API key.
    """
    passcode = "".join(random.choices(string.digits, k=6))
    state = _load_state()
    state["setup_passcode"] = passcode
    _state.update(state)
    _save_state()
    return passcode


def exchange_passcode(passcode: str) -> str | None:
    """Exchange a setup passcode for the API key.

    Returns the API key if the passcode is correct, None otherwise.
    After a successful exchange a fresh passcode is generated so additional
    devices can pair without a server restart.
    """
    state = _load_state()
    stored = state.get("setup_passcode")
    if not stored or not secrets.compare_digest(passcode, stored):
        return None

    # Mark setup as complete, generate fresh passcode for next device
    state["setup_complete"] = True
    _state.update(state)
    _save_state()
    api_key = state["api_key"]
    generate_setup_passcode()  # fresh code for the menu bar
    return api_key


def is_setup_complete() -> bool:
    """Check whether at least one client has paired."""
    state = _load_state()
    return state.get("setup_complete", False)


def init_auth() -> tuple[str, str]:
    """Initialize auth on server startup.

    Returns (api_key, setup_passcode).
    """
    api_key = get_api_key()
    passcode = generate_setup_passcode()
    return api_key, passcode
