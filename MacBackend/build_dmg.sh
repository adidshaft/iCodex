#!/usr/bin/env bash
#
# build_dmg.sh - Package iCodex-Connect into a distributable .dmg
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="iCodex-Connect"
DMG_VERSION="2.1.0"
DMG_FILENAME="${APP_NAME}-${DMG_VERSION}.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"
APP_DIR="$STAGING_DIR/${APP_NAME}.app"
STANDALONE_APP_DIR="$BUILD_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BACKEND_BUNDLE="$RESOURCES_DIR/MacBackend"
LOGO_PNG="$SCRIPT_DIR/../logo.png"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
SIGN_APP="${SIGN_APP:-0}"
NOTARIZE_DMG="${NOTARIZE_DMG:-0}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[Build]${NC} $*"; }
ok()    { echo -e "${GREEN}[Build]${NC} $*"; }
warn()  { echo -e "${YELLOW}[Build]${NC} $*"; }
error() { echo -e "${RED}[Build]${NC} $*"; }

sign_app_bundle() {
    if [ "$SIGN_APP" != "1" ] && [ -z "$CODE_SIGN_IDENTITY" ]; then
        warn "Signing skipped. Set SIGN_APP=1 and CODE_SIGN_IDENTITY='Developer ID Application: ...' to sign the app."
        return
    fi

    if [ -z "$CODE_SIGN_IDENTITY" ]; then
        error "SIGN_APP=1 requires CODE_SIGN_IDENTITY to be set."
        exit 1
    fi

    info "Signing app bundle with identity: $CODE_SIGN_IDENTITY"
    codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp --options runtime "$MACOS_DIR/icodex_keystroke"
    codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp --options runtime --deep "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
    ok "App bundle signed."
}

notarize_dmg_if_configured() {
    if [ "$NOTARIZE_DMG" != "1" ]; then
        if [ -z "$NOTARYTOOL_PROFILE" ]; then
            warn "Notarization skipped. Set NOTARIZE_DMG=1 and NOTARYTOOL_PROFILE=<keychain-profile> to notarize the DMG."
        fi
        return
    fi

    if [ -z "$CODE_SIGN_IDENTITY" ]; then
        error "NOTARIZE_DMG=1 requires CODE_SIGN_IDENTITY to be set."
        exit 1
    fi

    if [ -z "$NOTARYTOOL_PROFILE" ]; then
        error "NOTARIZE_DMG=1 requires NOTARYTOOL_PROFILE to be set."
        exit 1
    fi

    info "Submitting DMG for notarization with profile: $NOTARYTOOL_PROFILE"
    xcrun notarytool submit "$BUILD_DIR/$DMG_FILENAME" --keychain-profile "$NOTARYTOOL_PROFILE" --wait

    info "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$BUILD_DIR/$DMG_FILENAME"
    ok "DMG notarized and stapled."
}

echo ""
echo "=================================================="
echo "  iCodex-Connect DMG Builder v${DMG_VERSION}"
echo "=================================================="
echo ""

# ── Clean ────────────────────────────────────────────────────────────────
info "Cleaning previous build..."
mkdir -p "$BUILD_DIR"
find "$BUILD_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BACKEND_BUNDLE"

# ── Bundle backend ───────────────────────────────────────────────────────
info "Bundling backend..."
rsync -a \
    --exclude='venv/' \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    --exclude='.git/' \
    --exclude='build/' \
    --exclude='*.dmg' \
    --exclude='.DS_Store' \
    "$SCRIPT_DIR/" "$BACKEND_BUNDLE/"
ok "Backend bundled."

# ── App icon ─────────────────────────────────────────────────────────────
ICON_FILE=""
if [ -f "$LOGO_PNG" ]; then
    info "Creating app icon from logo.png..."
    # logo.png is actually JPEG — convert to real PNG first
    REAL_PNG="$BUILD_DIR/logo_real.png"
    sips -s format png "$LOGO_PNG" --out "$REAL_PNG" >/dev/null 2>&1

    ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"

    # iconutil requires exactly these filenames
    sips -z 16 16 "$REAL_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32 "$REAL_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32 "$REAL_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64 "$REAL_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128 "$REAL_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256 "$REAL_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256 "$REAL_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512 "$REAL_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512 "$REAL_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1
    sips -z 1024 1024 "$REAL_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1

    if iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null; then
        ICON_FILE="AppIcon"
        ok "App icon created."
    else
        warn "iconutil failed — app will use default icon."
    fi
    rm -rf "$ICONSET_DIR" "$REAL_PNG"
else
    warn "logo.png not found at $LOGO_PNG — using system icon."
fi

# ── Info.plist ───────────────────────────────────────────────────────────
info "Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << INFOPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.icodex.connect</string>
    <key>CFBundleVersion</key>
    <string>${DMG_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${DMG_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>icodex_keystroke</string>
    <key>CFBundleIconFile</key>
    <string>${ICON_FILE}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>iCodex-Connect needs to control the Codex app to send messages and manage threads from your iPhone.</string>
</dict>
</plist>
INFOPLIST

# ── Launcher executable ──────────────────────────────────────────────────
info "Creating launcher..."
cat > "$MACOS_DIR/icodex_launcher_impl" << 'LAUNCHER'
#!/usr/bin/env bash
#
# iCodex-Connect launcher — runs inside the .app bundle.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTENTS_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BACKEND_DIR="$RESOURCES_DIR/MacBackend"
DATA_DIR="$HOME/Library/Application Support/iCodex-Connect"
VENV_DIR="$DATA_DIR/venv"
LOG_DIR="$DATA_DIR/logs"

mkdir -p "$DATA_DIR" "$LOG_DIR"

# ── Find Python 3 ────────────────────────────────────────────────────────
PYTHON=""
for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [ -x "$candidate" ]; then
        PYTHON="$candidate"
        break
    fi
done

if [ -z "$PYTHON" ]; then
    osascript -e 'display alert "Python 3 Required" message "iCodex-Connect requires Python 3.\n\nInstall via: brew install python3\nor from python.org" as critical buttons {"OK"} default button "OK"' 2>/dev/null || true
    exit 1
fi

# ── Create venv + install deps if needed ─────────────────────────────────
if [ ! -f "$VENV_DIR/bin/python" ]; then
    osascript -e 'display notification "Setting up for first launch (this may take a minute)..." with title "iCodex-Connect"' 2>/dev/null || true

    "$PYTHON" -m venv "$VENV_DIR" >>"$LOG_DIR/setup.log" 2>&1 || {
        osascript -e 'display alert "Setup Failed" message "Could not create Python environment.\n\nCheck: ~/Library/Application Support/iCodex-Connect/logs/setup.log" as critical buttons {"OK"} default button "OK"' 2>/dev/null || true
        exit 1
    }

    "$VENV_DIR/bin/pip" install -q --upgrade pip >>"$LOG_DIR/setup.log" 2>&1
    "$VENV_DIR/bin/pip" install -q -r "$BACKEND_DIR/requirements.txt" >>"$LOG_DIR/setup.log" 2>&1 || {
        osascript -e 'display alert "Setup Failed" message "Could not install dependencies.\n\nCheck: ~/Library/Application Support/iCodex-Connect/logs/setup.log" as critical buttons {"OK"} default button "OK"' 2>/dev/null || true
        exit 1
    }

    osascript -e 'display notification "Setup complete!" with title "iCodex-Connect"' 2>/dev/null || true
fi

# ── Kill stale process on port 8642 ──────────────────────────────────────
lsof -ti:8642 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 0.5

# ── Launch the menu bar app ──────────────────────────────────────────────
cd "$BACKEND_DIR"
exec "$VENV_DIR/bin/python" menubar_app.py >>"$LOG_DIR/icodex.log" 2>&1
LAUNCHER
chmod +x "$MACOS_DIR/icodex_launcher_impl"

# ── Compile native keystroke helper ───────────────────────────────────
info "Compiling native keystroke helper..."
SWIFT_SRC="$SCRIPT_DIR/icodex_keystroke.swift"
if [ -f "$SWIFT_SRC" ]; then
    swiftc -O \
        -o "$MACOS_DIR/icodex_keystroke" \
        "$SWIFT_SRC" \
        -framework Cocoa -framework CoreGraphics 2>&1 || {
        error "Failed to compile icodex_keystroke.swift"
        exit 1
    }
    chmod +x "$MACOS_DIR/icodex_keystroke"
    ok "Native keystroke helper compiled."
else
    error "icodex_keystroke.swift not found!"
    exit 1
fi

ok "App bundle created."

# ── Remove quarantine from the built app ─────────────────────────────────
xattr -cr "$APP_DIR" 2>/dev/null || true

# ── Optional signing ──────────────────────────────────────────────────────
sign_app_bundle

# ── Applications symlink for drag-to-install ─────────────────────────────
ln -s /Applications "$STAGING_DIR/Applications"

# ── Installer note for the DMG window ─────────────────────────────────────
cat > "$STAGING_DIR/Install iCodex-Connect.txt" << 'INSTALLNOTE'
1. Drag iCodex-Connect.app into Applications.
2. Open iCodex-Connect from Applications, or open it here and choose "Install and Open".
3. When macOS opens Accessibility settings, add iCodex-Connect and toggle it ON.
4. The installer volume should eject automatically after the app relaunches.
INSTALLNOTE

# ── Standalone app bundle for local testing ───────────────────────────────
info "Creating standalone app bundle..."
ditto "$APP_DIR" "$STANDALONE_APP_DIR"
xattr -cr "$STANDALONE_APP_DIR" 2>/dev/null || true
if [ -n "$CODE_SIGN_IDENTITY" ]; then
    codesign --verify --deep --strict --verbose=2 "$STANDALONE_APP_DIR"
fi
ok "Standalone app created: $STANDALONE_APP_DIR"

# ── Build DMG ────────────────────────────────────────────────────────────
info "Building DMG..."
rm -f "$BUILD_DIR/$DMG_FILENAME"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$BUILD_DIR/$DMG_FILENAME"

ok "DMG created: $BUILD_DIR/$DMG_FILENAME"

# ── Optional notarization ────────────────────────────────────────────────
notarize_dmg_if_configured

# ── Summary ──────────────────────────────────────────────────────────────
DMG_SIZE=$(du -sh "$BUILD_DIR/$DMG_FILENAME" | cut -f1)
echo ""
echo "=================================================="
echo "  Build Complete!"
echo ""
echo "  DMG:  $BUILD_DIR/$DMG_FILENAME ($DMG_SIZE)"
echo "  App:  $STANDALONE_APP_DIR"
if [ -n "$CODE_SIGN_IDENTITY" ]; then
echo "  Sign: $CODE_SIGN_IDENTITY"
fi
if [ "$NOTARIZE_DMG" = "1" ]; then
echo "  Note: notarized with profile $NOTARYTOOL_PROFILE"
fi
echo ""
echo "  Install flow: open the DMG and drag ${APP_NAME}.app into Applications"
echo "  Quick test:    open \"$STANDALONE_APP_DIR\""
echo "=================================================="
echo ""
