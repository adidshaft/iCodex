# CodexManagerSystem

A two-part system for managing the Codex CLI remotely: a **macOS Menu Bar backend** (Python/FastAPI) and a **native iOS frontend** (SwiftUI).

## Project Structure

```
CodexManagerSystem/
├── MacBackend/
│   ├── venv/                  Python virtual environment (pre-installed)
│   ├── config.py              Env-based configuration
│   ├── models.py              Pydantic request/response models
│   ├── codex_runner.py        Async Codex CLI task manager with streaming
│   ├── server.py              FastAPI REST + WebSocket endpoints
│   ├── menubar_app.py         Rumps macOS status bar app (Start/Stop/Quit)
│   ├── requirements.txt
│   ├── .env                   Local environment config
│   └── .env.example           Template for environment variables
└── iOSFrontend/
    ├── CodexManagerApp.swift  App entry point
    ├── Models/                CodexTask, CommandRequest, LogMessage, ServerStatus
    ├── ViewModels/            DashboardViewModel, NewTaskViewModel, TaskDetailViewModel
    ├── Views/                 ContentView, DashboardView, NewTaskView, TaskDetailView, SettingsView
    │   └── Components/        TaskRowView, LabeledRow
    ├── Services/              APIService, WebSocketService, ServerConfig
    └── Utilities/
```

## Prerequisites

- **macOS** with Python 3.10+
- **Codex CLI** installed and available in your PATH
- **Xcode 15+** (for the iOS app)

## macOS Backend Setup

### Option A: Menu Bar App

```bash
cd CodexManagerSystem/MacBackend
source venv/bin/activate
python menubar_app.py
```

A brain icon (🧠) appears in your menu bar with these options:

- **Start Server** – launches the FastAPI server on port 8642
- **Stop Server** – shuts down the server
- **Quit** – exits the menu bar app

### Option B: Run the Server Directly

```bash
cd CodexManagerSystem/MacBackend
source venv/bin/activate
python server.py
```

The server starts at `http://0.0.0.0:8642`. Interactive API docs are available at `http://localhost:8642/docs`.

### Environment Variables

Copy `.env.example` to `.env` and edit as needed:

| Variable | Default | Description |
|---|---|---|
| `CODEX_HOST` | `0.0.0.0` | Host to bind the server |
| `CODEX_PORT` | `8642` | Port number |
| `CODEX_CLI_PATH` | `codex` | Path to the Codex CLI binary |
| `LOG_LEVEL` | `info` | Uvicorn log level |
| `ALLOWED_ORIGINS` | `*` | Comma-separated CORS origins |

## API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Server status, uptime, active task count |
| `POST` | `/tasks` | Create a new Codex task |
| `GET` | `/tasks` | List all tasks |
| `GET` | `/tasks/{task_id}` | Get full result for a task |
| `POST` | `/tasks/{task_id}/cancel` | Cancel a running task |
| `WS` | `/ws/logs/{task_id}` | Stream live logs for a specific task |
| `WS` | `/ws/logs` | Stream live logs for all running tasks |

### Example: Create a Task

```bash
curl -X POST http://localhost:8642/tasks \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Explain this codebase", "model": "o4-mini", "approval_mode": "suggest"}'
```

## iOS App Setup

1. Open **Xcode** and create a new project (iOS → App → SwiftUI)
2. Delete the auto-generated `ContentView.swift`
3. Drag the entire `iOSFrontend/` folder into the Xcode project navigator
4. When prompted, select **"Copy items if needed"** and **"Create groups"**
5. Build and run on a simulator or physical device

### Connecting to Your Mac

1. Open the **Settings** tab in the iOS app
2. Enter your Mac's local IP address (find it via `ifconfig en0` or System Settings → Wi-Fi)
3. Keep the port as `8642` (or whatever you configured)
4. Tap **Test Connection** to verify

> Both devices must be on the same local network.

## iOS App Screens

- **Dashboard** – Server health, uptime, and a list of all tasks with live status indicators. Pull to refresh.
- **New Task** – Compose a prompt, pick a model (`o4-mini`, `o3`, `gpt-4.1`, `codex-mini-latest`), set approval mode, and run.
- **Task Detail** – Real-time streaming logs via WebSocket, task metadata, and a cancel button for running tasks.
- **Settings** – Configure server host/port and test the connection.

## Reinstalling Dependencies

If the virtual environment is missing or broken:

```bash
cd CodexManagerSystem/MacBackend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```
