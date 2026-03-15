#!/usr/bin/env bash
#
# install.sh - Developer tool: Install iCodex Backend as a macOS service + .app wrapper
# NOTE: End users should install via the DMG (build_dmg.sh). This script is for development.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR"
APP_NAME="iCodex Server"
APP_BUNDLE_ID="com.icodex.backend"
PLIST_NAME="$APP_BUNDLE_ID.plist"
INSTALL_DIR="$HOME/Library/iCodex"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
APPLICATIONS_DIR="/Applications"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[Install]${NC} $*"; }
ok()    { echo -e "${GREEN}[Install]${NC} $*"; }
warn()  { echo -e "${YELLOW}[Install]${NC} $*"; }
error() { echo -e "${RED}[Install]${NC} $*"; }

echo ""
echo "=================================================="
echo "  iCodex Backend Installer"
echo "=================================================="
echo ""

# ── Check Python 3 ──────────────────────────────────────────────────────────
info "Checking prerequisites..."
if ! command -v python3 &>/dev/null; then
    error "Python 3 is required. Install from https://www.python.org/downloads/"
    exit 1
fi
ok "Python 3 found: $(python3 --version)"

# ── Accessibility Permission ────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  IMPORTANT: Accessibility Permission Required   ║${NC}"
echo -e "${YELLOW}╠══════════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║                                                  ║${NC}"
echo -e "${YELLOW}║  iCodex controls the Codex GUI via AppleScript. ║${NC}"
echo -e "${YELLOW}║  This requires macOS Accessibility permission.   ║${NC}"
echo -e "${YELLOW}║                                                  ║${NC}"
echo -e "${YELLOW}║  After installation, you MUST:                   ║${NC}"
echo -e "${YELLOW}║                                                  ║${NC}"
echo -e "${YELLOW}║  1. Open System Settings                        ║${NC}"
echo -e "${YELLOW}║  2. Go to Privacy & Security > Accessibility    ║${NC}"
echo -e "${YELLOW}║  3. Click '+' and add 'iCodex Server.app'       ║${NC}"
echo -e "${YELLOW}║     (from /Applications)                        ║${NC}"
echo -e "${YELLOW}║                                                  ║${NC}"
echo -e "${YELLOW}║  Without this, sending messages, stop, and      ║${NC}"
echo -e "${YELLOW}║  interrupt commands to Codex will NOT work.      ║${NC}"
echo -e "${YELLOW}║                                                  ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
echo ""
read -p "Press Enter to continue with installation..."

# ── Copy backend to install directory ────────────────────────────────────────
info "Installing backend to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

# Copy all backend files (excluding venv, __pycache__)
rsync -a --delete \
    --exclude='venv/' \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    --exclude='.git/' \
    --exclude='*.dmg' \
    "$BACKEND_DIR/" "$INSTALL_DIR/MacBackend/"

ok "Backend files installed."

# ── Create venv and install deps ─────────────────────────────────────────────
info "Setting up Python virtual environment..."
VENV_DIR="$INSTALL_DIR/MacBackend/venv"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install -q --upgrade pip
pip install -q -r "$INSTALL_DIR/MacBackend/requirements.txt"
deactivate
ok "Virtual environment ready."

# ── Create launcher wrapper ──────────────────────────────────────────────────
LAUNCHER="$INSTALL_DIR/launch_icodex.sh"
cat > "$LAUNCHER" << 'LAUNCHER_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="$HOME/Library/iCodex"
BACKEND_DIR="$INSTALL_DIR/MacBackend"
VENV_DIR="$BACKEND_DIR/venv"

source "$VENV_DIR/bin/activate"

# Kill existing process on port 8642
lsof -ti:8642 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1

cd "$BACKEND_DIR"
exec python menubar_app.py
LAUNCHER_SCRIPT
chmod +x "$LAUNCHER"

# ── Create launchd plist ─────────────────────────────────────────────────────
info "Setting up auto-start on login..."
mkdir -p "$LAUNCH_AGENTS_DIR"

# Unload existing plist if present
if [ -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME" ]; then
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
fi

cat > "$LAUNCH_AGENTS_DIR/$PLIST_NAME" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$APP_BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/launch_icodex.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/logs/icodex.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/logs/icodex_error.log</string>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR/MacBackend</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
    </dict>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
PLIST

mkdir -p "$INSTALL_DIR/logs"

launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
ok "LaunchAgent installed. Server will auto-start on login."

# ── Create .app wrapper ─────────────────────────────────────────────────────
info "Creating iCodex Server.app..."
APP_DIR="$APPLICATIONS_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Info.plist
cat > "$CONTENTS_DIR/Info.plist" << INFOPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleExecutable</key>
    <string>icodex_launcher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
INFOPLIST

# Executable script
cat > "$MACOS_DIR/icodex_launcher" << 'APPSCRIPT'
#!/usr/bin/env bash
INSTALL_DIR="$HOME/Library/iCodex"
BACKEND_DIR="$INSTALL_DIR/MacBackend"
VENV_DIR="$BACKEND_DIR/venv"

# Get local IP
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
" 2>/dev/null || echo "127.0.0.1")

# Kill existing
lsof -ti:8642 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1

# Send notification
osascript -e "display notification \"Server starting at http://$LOCAL_IP:8642\" with title \"iCodex Server\"" 2>/dev/null || true

# Start menu bar app (it manages the server)
source "$VENV_DIR/bin/activate"
cd "$BACKEND_DIR"
exec python menubar_app.py >> "$INSTALL_DIR/logs/icodex.log" 2>&1
APPSCRIPT
chmod +x "$MACOS_DIR/icodex_launcher"

# Create a simple icon using system Python (optional, won't fail if it can't)
python3 - "$RESOURCES_DIR/AppIcon.icns" << 'ICONSCRIPT' 2>/dev/null || true
import sys, os
# Create a minimal valid .icns file with a 16x16 icon
# This is a valid minimal icns with a blank icon
icon_path = sys.argv[1]
# Use a system icon instead
src = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ExecutableBinaryIcon.icns"
if os.path.exists(src):
    import shutil
    shutil.copy2(src, icon_path)
ICONSCRIPT

ok "iCodex Server.app created in $APPLICATIONS_DIR"

# ── Start the server now ─────────────────────────────────────────────────────
info "Starting the server..."
launchctl start "$APP_BUNDLE_ID" 2>/dev/null || true

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

echo ""
echo "=================================================="
echo "  Installation Complete!"
echo ""
echo "  Server URL:    http://$LOCAL_IP:8642"
echo "  App Location:  $APP_DIR"
echo "  Logs:          $INSTALL_DIR/logs/"
echo ""
echo "  The server will auto-start on login."
echo "  Open iCodex Server.app to start manually."
echo ""
echo -e "  ${YELLOW}NEXT STEP: Grant Accessibility Permission${NC}"
echo "  System Settings > Privacy & Security > Accessibility"
echo "  Add 'iCodex Server' (from /Applications)"
echo ""
echo "  To uninstall:"
echo "    launchctl unload ~/Library/LaunchAgents/$PLIST_NAME"
echo "    rm -rf ~/Library/iCodex"
echo "    rm -rf \"$APP_DIR\""
echo "    rm ~/Library/LaunchAgents/$PLIST_NAME"
echo "=================================================="
echo ""
