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
import time
import hashlib
from pathlib import Path


AUTH_FILE = Path.home() / ".codex" / "icodex_auth.json"
PASSCODE_TTL_SECONDS = 24 * 60 * 60
ALL_CAPABILITIES = ["view", "reply", "control", "launch", "configure"]
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
        _normalize_state(_state)
        return _state

    # Try loading from file
    if AUTH_FILE.exists():
        try:
            with open(AUTH_FILE, "r") as f:
                _state = json.load(f)
            _normalize_state(_state)
            return _state
        except (json.JSONDecodeError, OSError):
            pass

    # Generate new key on first run
    api_key = secrets.token_urlsafe(32)
    _state = {"api_key": api_key, "setup_complete": False}
    _normalize_state(_state)
    _save_state()
    return _state


def _save_state() -> None:
    _normalize_state(_state)
    _ensure_codex_dir()
    with open(AUTH_FILE, "w") as f:
        json.dump(_state, f, indent=2)
    # Restrict permissions to owner only
    try:
        os.chmod(AUTH_FILE, 0o600)
    except OSError:
        pass


def _normalize_state(state: dict) -> None:
    state.setdefault("trusted_devices", {})
    if not isinstance(state["trusted_devices"], dict):
        state["trusted_devices"] = {}
    for device_id, raw in list(state["trusted_devices"].items()):
        device = dict(raw or {})
        device["id"] = device.get("id") or device_id
        device["name"] = device.get("name") or "Trusted device"
        device["capabilities"] = _sanitize_capabilities(device.get("capabilities"))
        device.setdefault("created_at", time.time())
        device.setdefault("updated_at", device["created_at"])
        device.setdefault("last_paired_at", device["created_at"])
        device.setdefault("last_seen_at", 0)
        state["trusted_devices"][device_id] = device


def _sanitize_capabilities(raw: object) -> list[str]:
    if not isinstance(raw, list):
        return list(ALL_CAPABILITIES)
    normalized = [str(item) for item in raw if str(item) in ALL_CAPABILITIES]
    if "view" not in normalized:
        normalized.insert(0, "view")
    seen: set[str] = set()
    return [item for item in normalized if not (item in seen or seen.add(item))]


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _device_id_for_installation(installation_id: str) -> str:
    return hashlib.sha256(installation_id.encode()).hexdigest()[:12]


def _new_installation_id() -> str:
    return secrets.token_urlsafe(16)


def get_api_key() -> str:
    """Return the current API key."""
    state = _load_state()
    return state["api_key"]


def verify_token(token: str) -> bool:
    """Check if a Bearer token matches the API key."""
    return get_device_for_token(token) is not None


def get_device_for_token(token: str) -> dict | None:
    """Return the trusted device record for a token, if any."""
    state = _load_state()
    if secrets.compare_digest(token, state["api_key"]):
        return {
            "id": "legacy-master",
            "name": "Legacy Full Access",
            "capabilities": list(ALL_CAPABILITIES),
            "legacy": True,
        }
    token_hash = _hash_token(token)
    for device in state.get("trusted_devices", {}).values():
        if device.get("revoked_at"):
            continue
        stored_hash = device.get("token_hash")
        if stored_hash and secrets.compare_digest(token_hash, stored_hash):
            return dict(device)
    return None


def list_trusted_devices(include_revoked: bool = False) -> list[dict]:
    state = _load_state()
    devices = []
    for device in state.get("trusted_devices", {}).values():
        if device.get("revoked_at") and not include_revoked:
            continue
        sanitized = {k: v for k, v in device.items() if k != "token_hash"}
        devices.append(sanitized)
    return sorted(devices, key=lambda item: float(item.get("updated_at", 0) or 0), reverse=True)


def record_device_activity(device_id: str, *, name: str | None = None) -> None:
    state = _load_state()
    device = state.get("trusted_devices", {}).get(device_id)
    if not device:
        return
    now = time.time()
    previous_seen = float(device.get("last_seen_at", 0) or 0)
    device["last_seen_at"] = now
    if name:
        device["name"] = name
    if name or (now - previous_seen) >= 30:
        device["updated_at"] = now
        _save_state()


def update_device(device_id: str, *, name: str | None = None, capabilities: list[str] | None = None) -> dict | None:
    state = _load_state()
    device = state.get("trusted_devices", {}).get(device_id)
    if not device or device.get("revoked_at"):
        return None
    if name is not None:
        trimmed = name.strip()
        if trimmed:
            device["name"] = trimmed
    if capabilities is not None:
        device["capabilities"] = _sanitize_capabilities(capabilities)
    device["updated_at"] = time.time()
    _save_state()
    return {k: v for k, v in device.items() if k != "token_hash"}


def revoke_device(device_id: str) -> bool:
    state = _load_state()
    device = state.get("trusted_devices", {}).get(device_id)
    if not device or device.get("revoked_at"):
        return False
    device["revoked_at"] = time.time()
    device["updated_at"] = time.time()
    device.pop("token_hash", None)
    _save_state()
    return True


def generate_setup_passcode() -> str:
    """Generate a 6-digit setup passcode for initial pairing.

    The passcode is displayed in the terminal and the user enters it
    in the iOS app to exchange it for the API key.
    """
    passcode = "".join(random.choices(string.digits, k=6))
    state = _load_state()
    state["setup_passcode"] = passcode
    state["setup_passcode_generated_at"] = time.time()
    _state.update(state)
    _save_state()
    return passcode


def _is_passcode_expired(state: dict) -> bool:
    generated_at = float(state.get("setup_passcode_generated_at", 0) or 0)
    if generated_at <= 0:
        return True
    return time.time() - generated_at > PASSCODE_TTL_SECONDS


def ensure_setup_passcode() -> str:
    """Return the active setup passcode, rotating it if missing or older than 24h."""
    state = _load_state()
    stored = state.get("setup_passcode")
    if not stored or _is_passcode_expired(state):
        return generate_setup_passcode()
    return stored


def get_setup_passcode_metadata() -> dict:
    """Return the active setup passcode and its freshness metadata."""
    state = _load_state()
    passcode = ensure_setup_passcode()
    generated_at = float(state.get("setup_passcode_generated_at", 0) or 0)
    expires_at = generated_at + PASSCODE_TTL_SECONDS if generated_at else 0
    remaining = max(0.0, expires_at - time.time()) if expires_at else 0.0
    return {
        "passcode": passcode,
        "generated_at": generated_at,
        "expires_at": expires_at,
        "seconds_remaining": remaining,
        "expired": _is_passcode_expired(state),
    }


def exchange_passcode(
    passcode: str,
    *,
    device_name: str = "",
    installation_id: str = "",
) -> dict | None:
    """Exchange a setup passcode for the API key.

    Returns a device-scoped API token if the passcode is correct, None otherwise.
    """
    state = _load_state()
    stored = state.get("setup_passcode")
    if not stored or _is_passcode_expired(state):
        generate_setup_passcode()
        return None
    if not secrets.compare_digest(passcode, stored):
        return None

    installation_id = installation_id.strip() or _new_installation_id()
    device_id = _device_id_for_installation(installation_id)
    trusted_devices = state.setdefault("trusted_devices", {})
    existing = trusted_devices.get(device_id, {})
    token = secrets.token_urlsafe(32)
    now = time.time()

    trusted_devices[device_id] = {
        "id": device_id,
        "name": existing.get("name") or device_name.strip() or "Trusted device",
        "capabilities": _sanitize_capabilities(existing.get("capabilities")),
        "created_at": existing.get("created_at", now),
        "updated_at": now,
        "last_paired_at": now,
        "last_seen_at": now,
        "revoked_at": None,
        "token_hash": _hash_token(token),
    }

    state["setup_complete"] = True
    _state.update(state)
    _save_state()
    return {
        "api_key": token,
        "device_id": device_id,
        "device_name": trusted_devices[device_id]["name"],
        "capabilities": trusted_devices[device_id]["capabilities"],
    }


def is_setup_complete() -> bool:
    """Check whether at least one client has paired."""
    state = _load_state()
    return state.get("setup_complete", False)


def init_auth() -> tuple[str, str]:
    """Initialize auth on server startup.

    Returns (api_key, setup_passcode).
    """
    api_key = get_api_key()
    passcode = ensure_setup_passcode()
    return api_key, passcode
