#!/usr/bin/env bash
#
# launch_icodex.sh - Launch the iCodex backend server
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR"
VENV_DIR="$BACKEND_DIR/venv"
REQUIREMENTS="$BACKEND_DIR/requirements.txt"
PORT=8642

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[iCodex]${NC} $*"; }
ok()    { echo -e "${GREEN}[iCodex]${NC} $*"; }
warn()  { echo -e "${YELLOW}[iCodex]${NC} $*"; }
error() { echo -e "${RED}[iCodex]${NC} $*"; }

# ── Check Python 3 ──────────────────────────────────────────────────────────
info "Checking for Python 3..."
if command -v python3 &>/dev/null; then
    PYTHON="python3"
    PYTHON_VERSION=$($PYTHON --version 2>&1)
    ok "Found $PYTHON_VERSION"
elif command -v python &>/dev/null; then
    PY_VER=$(python --version 2>&1)
    if echo "$PY_VER" | grep -q "Python 3"; then
        PYTHON="python"
        PYTHON_VERSION="$PY_VER"
        ok "Found $PYTHON_VERSION"
    else
        error "Python 3 is required but only found: $PY_VER"
        error "Install Python 3: https://www.python.org/downloads/"
        exit 1
    fi
else
    error "Python 3 is not installed."
    error "Install it from: https://www.python.org/downloads/"
    exit 1
fi

# ── Create venv if needed ───────────────────────────────────────────────────
if [ ! -d "$VENV_DIR" ]; then
    info "Creating virtual environment..."
    $PYTHON -m venv "$VENV_DIR"
    ok "Virtual environment created at $VENV_DIR"
fi

# ── Activate venv and install/update deps ────────────────────────────────────
source "$VENV_DIR/bin/activate"

if [ -f "$REQUIREMENTS" ]; then
    info "Installing/updating dependencies..."
    pip install -q --upgrade pip
    pip install -q -r "$REQUIREMENTS"
    ok "Dependencies installed."
fi

# ── Detect local IP ─────────────────────────────────────────────────────────
LOCAL_IP=$(python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(('8.8.8.8', 80))
    print(s.getsockname()[0])
except Exception:
    print('127.0.0.1')
finally:
    s.close()
")

# ── Kill any existing process on port ────────────────────────────────────────
EXISTING_PID=$(lsof -ti:$PORT 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
    warn "Killing existing process on port $PORT (PID: $EXISTING_PID)..."
    echo "$EXISTING_PID" | xargs kill -9 2>/dev/null || true
    sleep 1
    ok "Port $PORT freed."
fi

# ── Check Codex data ────────────────────────────────────────────────────────
if [ ! -d "$HOME/.codex" ]; then
    warn "~/.codex/ not found. Codex app may not be installed."
    warn "The server will start but some features may not work."
fi

# ── Start server ─────────────────────────────────────────────────────────────
echo ""
echo "=================================================="
echo "  iCodex Backend Server"
echo "  Local:   http://127.0.0.1:$PORT"
echo "  Network: http://$LOCAL_IP:$PORT"
echo "=================================================="
echo ""

ok "Starting iCodex menu bar app (manages server automatically)..."

# Send macOS notification
osascript -e "display notification \"iCodex menu bar app starting at http://$LOCAL_IP:$PORT\" with title \"iCodex\" subtitle \"Menu Bar App Starting\"" 2>/dev/null || true

cd "$BACKEND_DIR"
exec python menubar_app.py
