# CodexManagerSystem

A two-part system for managing Codex remotely: a **native macOS menu bar companion** backed by **Python/FastAPI**, and a **native iOS frontend** (SwiftUI).

## Project Structure

```
iCodex/
├── MacBackend/
│   ├── venv/                  Python virtual environment (pre-installed)
│   ├── config.py              Env-based configuration
│   ├── models.py              Pydantic request/response models
│   ├── codex_runner.py        Async Codex CLI task manager with streaming
│   ├── server.py              FastAPI REST + WebSocket endpoints
│   ├── icodex_keystroke.swift Native macOS menu bar app + GUI control helper
│   ├── build_dmg.sh           Builds the signed/notarized iCodex-Connect DMG
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

### Option A: Build the macOS companion app

```bash
cd MacBackend
bash build_dmg.sh
```

This creates:

- `MacBackend/build/iCodex-Connect.app`
- `MacBackend/build/iCodex-Connect-2.1.0.dmg`

Install `iCodex-Connect.app` into Applications and open it. A menu bar item appears with:

- **Start Server / Stop Server**
- **Pairing QR + passcode**
- **Accessibility status + fix**
- **Download Latest Build**
- **Quit iCodex**

### Option B: Run the Server Directly

```bash
cd MacBackend
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
2. Pair using the QR shown by the Mac menu bar app, or enter your Mac's host/port/passcode manually
3. Keep the port as `8642` unless you changed it
4. After pairing, the iPhone stores the connection and talks directly to your Mac

> Both devices must be on the same local network.

## iOS App Screens

- **Dashboard** – Server health, uptime, and a list of all tasks with live status indicators. Pull to refresh.
- **New Task** – Compose a prompt, pick a model (`o4-mini`, `o3`, `gpt-4.1`, `codex-mini-latest`), set approval mode, and run.
- **Task Detail** – Real-time streaming logs via WebSocket, task metadata, and a cancel button for running tasks.
- **Settings** – Configure server host/port and test the connection.

## Reinstalling Dependencies

If the virtual environment is missing or broken:

```bash
cd MacBackend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## macOS Release Signing

The rolling GitHub release for `iCodex-Connect` is intended to publish only
Developer ID signed and notarized macOS downloads.

Required GitHub Actions secrets:

- `MACOS_DEVELOPER_ID_CERT_P12_BASE64`
- `MACOS_DEVELOPER_ID_CERT_PASSWORD`
- `MACOS_DEVELOPER_ID_IDENTITY`
- `MACOS_KEYCHAIN_PASSWORD`
- `APPLE_NOTARY_API_KEY_P8_BASE64`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_KEY_ID`

The workflow in `.github/workflows/publish-main-build.yml` fails closed if any
of these are missing, so future release updates do not publish unsigned or
unnotarized DMGs by accident.
