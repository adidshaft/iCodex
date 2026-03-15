"""Manages Codex CLI subprocesses and streams output."""

from __future__ import annotations
import asyncio
import datetime
import uuid
import shlex
from typing import Optional
from models import TaskStatus, TaskResult
from config import CODEX_CLI


class CodexTask:
    """Represents one Codex CLI invocation."""

    def __init__(self, prompt: str, model: str, working_dir: Optional[str], approval_mode: str):
        self.task_id: str = uuid.uuid4().hex[:12]
        self.prompt = prompt
        self.model = model
        self.working_dir = working_dir
        self.approval_mode = approval_mode
        self.status: TaskStatus = TaskStatus.PENDING
        self.output_lines: list[str] = []
        self.error: Optional[str] = None
        self.created_at = datetime.datetime.now(datetime.timezone.utc)
        self.finished_at: Optional[datetime.datetime] = None
        self._process: Optional[asyncio.subprocess.Process] = None
        self._subscribers: list[asyncio.Queue] = []

    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue()
        self._subscribers.append(q)
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        self._subscribers = [s for s in self._subscribers if s is not q]

    async def _broadcast(self, line: str) -> None:
        self.output_lines.append(line)
        for q in self._subscribers:
            await q.put(line)

    async def run(self) -> None:
        self.status = TaskStatus.RUNNING
        cmd = (
            f"{CODEX_CLI} --quiet "
            f"--model {shlex.quote(self.model)} "
            f"--approval-mode {shlex.quote(self.approval_mode)} "
            f"{shlex.quote(self.prompt)}"
        )
        try:
            self._process = await asyncio.create_subprocess_shell(
                cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                cwd=self.working_dir,
            )
            assert self._process.stdout is not None
            async for raw_line in self._process.stdout:
                decoded = raw_line.decode(errors="replace").rstrip("\n")
                await self._broadcast(decoded)
            await self._process.wait()
            if self._process.returncode == 0:
                self.status = TaskStatus.COMPLETED
            else:
                self.status = TaskStatus.FAILED
                self.error = f"Process exited with code {self._process.returncode}"
        except Exception as exc:
            self.status = TaskStatus.FAILED
            self.error = str(exc)
        finally:
            self.finished_at = datetime.datetime.now(datetime.timezone.utc)
            # signal end-of-stream
            for q in self._subscribers:
                await q.put(None)

    async def cancel(self) -> None:
        if self._process and self._process.returncode is None:
            self._process.terminate()
            self.status = TaskStatus.CANCELLED
            self.finished_at = datetime.datetime.now(datetime.timezone.utc)

    def to_result(self) -> TaskResult:
        return TaskResult(
            task_id=self.task_id,
            status=self.status,
            created_at=self.created_at.isoformat(),
            finished_at=self.finished_at.isoformat() if self.finished_at else None,
            prompt=self.prompt,
            output="\n".join(self.output_lines),
            error=self.error,
        )


class TaskManager:
    """Registry of all Codex tasks."""

    def __init__(self) -> None:
        self._tasks: dict[str, CodexTask] = {}

    async def create_task(
        self, prompt: str, model: str, working_dir: Optional[str], approval_mode: str
    ) -> CodexTask:
        task = CodexTask(prompt, model, working_dir, approval_mode)
        self._tasks[task.task_id] = task
        asyncio.create_task(task.run())
        return task

    def get_task(self, task_id: str) -> Optional[CodexTask]:
        return self._tasks.get(task_id)

    def list_tasks(self) -> list[CodexTask]:
        return list(self._tasks.values())

    def active_count(self) -> int:
        return sum(1 for t in self._tasks.values() if t.status == TaskStatus.RUNNING)
