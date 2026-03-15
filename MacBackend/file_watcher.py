"""Watch ~/.codex/ for real-time changes and broadcast via WebSocket."""

from __future__ import annotations
import asyncio
import json
import os
import time
from pathlib import Path
from typing import Optional
from watchdog.observers.polling import PollingObserver
from watchdog.events import FileSystemEventHandler, FileSystemEvent

from codex_data import CODEX_DIR, SESSIONS_DIR, STATE_DB


class SessionFileWatcher(FileSystemEventHandler):
    """Watches JSONL session files for new lines."""

    def __init__(self, broadcast_callback):
        super().__init__()
        self._callback = broadcast_callback
        self._file_positions: dict[str, int] = {}

    def on_modified(self, event: FileSystemEvent) -> None:
        if event.is_directory:
            return
        path = event.src_path
        if not path.endswith(".jsonl"):
            return
        self._read_new_lines(path)

    def on_created(self, event: FileSystemEvent) -> None:
        if event.is_directory:
            return
        if event.src_path.endswith(".jsonl"):
            self._read_new_lines(event.src_path)

    def _read_new_lines(self, path: str) -> None:
        last_pos = self._file_positions.get(path, 0)
        try:
            with open(path, "r") as f:
                f.seek(last_pos)
                new_lines = f.readlines()
                self._file_positions[path] = f.tell()

            # Extract thread_id from filename: rollout-...-{uuid}.jsonl
            filename = os.path.basename(path)
            thread_id = self._extract_thread_id(filename)

            for line in new_lines:
                line = line.strip()
                if not line:
                    continue
                try:
                    event_data = json.loads(line)
                    self._callback({
                        "type": "new_message",
                        "thread_id": thread_id,
                        "event": event_data,
                    })
                except json.JSONDecodeError:
                    pass
        except OSError:
            pass

    @staticmethod
    def _extract_thread_id(filename: str) -> Optional[str]:
        # Format: rollout-2026-03-07T12-17-49-019cc70d-62d2-73f3-8461-d5d4a43eb904.jsonl
        # UUID is last 36 chars before .jsonl
        name = filename.replace(".jsonl", "")
        parts = name.split("-")
        if len(parts) >= 5:
            # Last 5 parts form the UUID
            uuid = "-".join(parts[-5:])
            if len(uuid) == 36:
                return uuid
        return None


class DBWatcher(FileSystemEventHandler):
    """Watches state_5.sqlite for thread changes."""

    def __init__(self, broadcast_callback):
        super().__init__()
        self._callback = broadcast_callback
        self._last_notify = 0.0

    def on_modified(self, event: FileSystemEvent) -> None:
        if event.is_directory:
            return
        # SQLite writes to -wal and -shm files too
        basename = os.path.basename(event.src_path)
        if "state_5" in basename:
            now = time.time()
            # Debounce: don't fire more than once per second
            if now - self._last_notify < 1.0:
                return
            self._last_notify = now
            self._callback({"type": "threads_changed"})


class FileWatcherService:
    """Manages file watchers and WebSocket subscriber broadcasting."""

    def __init__(self):
        self._subscribers: list[asyncio.Queue] = []
        self._observer = PollingObserver(timeout=2)
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=200)
        self._subscribers.append(q)
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        self._subscribers = [s for s in self._subscribers if s is not q]

    def _broadcast(self, data: dict) -> None:
        if self._loop is None:
            return
        for q in list(self._subscribers):
            try:
                self._loop.call_soon_threadsafe(self._safe_put, q, data)
            except RuntimeError:
                pass  # loop closed

    def _safe_put(self, q: asyncio.Queue, data: dict) -> None:
        try:
            q.put_nowait(data)
        except asyncio.QueueFull:
            # Drop oldest, put new
            try:
                q.get_nowait()
            except asyncio.QueueEmpty:
                pass
            try:
                q.put_nowait(data)
            except asyncio.QueueFull:
                pass

    def start(self, loop: asyncio.AbstractEventLoop) -> None:
        self._loop = loop

        # Watch session files
        session_handler = SessionFileWatcher(self._broadcast)
        if SESSIONS_DIR.exists():
            self._observer.schedule(session_handler, str(SESSIONS_DIR), recursive=True)

        # Watch SQLite DB
        db_handler = DBWatcher(self._broadcast)
        self._observer.schedule(db_handler, str(CODEX_DIR), recursive=False)

        self._observer.start()

    def stop(self) -> None:
        self._observer.stop()
        self._observer.join(timeout=5)


# Singleton
watcher_service = FileWatcherService()
