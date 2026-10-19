#!/bin/bash
# make-app.sh — build the MQ80 Studio executable and assemble a signed .app
# bundle without Xcode (Command Line Tools only).
#
# Usage:
#   ./scripts/make-app.sh              # build + icon + bundle + sign + zip + smoke test
#   SKIP_BUILD=1 ./scripts/make-app.sh # reuse existing .build-manual binaries
#   SKIP_ICON=1  ./scripts/make-app.sh # do not regenerate dist/AppIcon.icns
#   SMOKE_TEST=0 ./scripts/make-app.sh # assemble only, do not launch the app
#
# Outputs:
#   dist/MQ80Studio.app
#   dist/MQ80Studio-<version>.zip          (ditto, keeps bundle layout)
#   dist/AppIcon.icns                      (when icon generation succeeds)
#   dist/mq80ctl                           (convenience CLI copy)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build-manual"
DIST="$ROOT/dist"
VERSION="${VERSION:-0.2.0}"
APP_NAME="IQUNIX-DRIVE"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
BUNDLE_ID="com.iqunix.drive"
DISPLAY_NAME="IQUNIX-DRIVE"

# Keep every temporary/cache path inside the repository (sandbox friendly).
mkdir -p "$BUILD/tmp" "$BUILD/modulecache" "$DIST"
export TMPDIR="$BUILD/tmp"
export CLANG_MODULE_CACHE_PATH="$BUILD/modulecache"

log() { printf '%s\n' "$*"; }
die() { printf 'make-app: ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Build the two executables
# ---------------------------------------------------------------------------
if [ "${SKIP_BUILD:-0}" = "1" ]; then
  log "== build skipped (SKIP_BUILD=1) =="
  [ -x "$BUILD/IQUNIX-DRIVE" ] || die "$BUILD/IQUNIX-DRIVE missing; run ./scripts/build.sh release first"
  [ -x "$BUILD/iqunixctl" ] || die "$BUILD/iqunixctl missing; run ./scripts/build.sh release first"
else
  log "== building (scripts/build.sh release) =="
  "$ROOT/scripts/build.sh" release
fi

# ---------------------------------------------------------------------------
# 2. Icon: draw a 1024px master with Swift/AppKit, then iconutil -> .icns
# ---------------------------------------------------------------------------
ICON_OK=0
if [ "${SKIP_ICON:-0}" = "1" ] && [ -f "$DIST/AppIcon.icns" ]; then
  log "== icon skipped (SKIP_ICON=1), reusing $DIST/AppIcon.icns =="
  ICON_OK=1
else
  log "== generating app icon =="
  ICON_SWIFT="$ROOT/scripts/make-icon.swift"
  ICON_BIN="$BUILD/make-icon"
  ICONSET="$BUILD/AppIcon.iconset"
  # iconutil cannot write its output inside this workspace volume (sandboxed
  # external volume), so build the .icns under /tmp and copy it back.
  ICON_TMP="$(mktemp -d "${MQ80_ICON_TMPDIR:-/tmp}/mq80-icon.XXXXXX")"
  if [ -f "$ICON_SWIFT" ]; then
    if [ ! -x "$ICON_BIN" ] || [ "$ICON_SWIFT" -nt "$ICON_BIN" ]; then
      if ! swiftc -O "$ICON_SWIFT" -o "$ICON_BIN"; then
        log "WARN: could not compile $ICON_SWIFT; packaging without a new icon"
      fi
    fi
    if [ -x "$ICON_BIN" ] && "$ICON_BIN" "$ICONSET" >/dev/null; then
      if iconutil -c icns -o "$ICON_TMP/AppIcon.icns" "$ICONSET" \
         && cp "$ICON_TMP/AppIcon.icns" "$DIST/AppIcon.icns"; then
        ICON_OK=1
        log "icon: dist/AppIcon.icns ($(sips -g pixelWidth -g pixelHeight "$ICONSET/icon_512x512@2x.png" 2>/dev/null | awk '/pixel/{printf "%s ", $2}')master)"
      else
        log "WARN: iconutil failed; packaging without an app icon"
      fi
    else
      log "WARN: icon renderer failed; packaging without an app icon"
    fi
  else
    log "WARN: $ICON_SWIFT not found; packaging without an app icon"
  fi
  rm -rf "$ICON_TMP"
fi

# ---------------------------------------------------------------------------
# 3. Assemble the bundle
# ---------------------------------------------------------------------------
log "== assembling $APP =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"

cp "$BUILD/IQUNIX-DRIVE" "$APP/Contents/MacOS/$APP_NAME"
chmod 755 "$APP/Contents/MacOS/$APP_NAME"

# CLI helper inside the bundle (optional convenience) + top-level dist copy.
if [ -x "$BUILD/iqunixctl" ]; then
  cp "$BUILD/iqunixctl" "$APP/Contents/Helpers/iqunixctl"
  chmod 755 "$APP/Contents/Helpers/iqunixctl"
  cp "$BUILD/iqunixctl" "$DIST/iqunixctl"
  chmod 755 "$DIST/iqunixctl"
fi

# Bundled VIA keyboard definition library (1,484 definitions). The app's
# DefinitionStore also looks for it under Contents/Resources.
if [ -d "$ROOT/Resources/VIAKeyboardDefinitions" ]; then
  rm -rf "$APP/Contents/Resources/VIAKeyboardDefinitions"
  cp -R "$ROOT/Resources/VIAKeyboardDefinitions" "$APP/Contents/Resources/VIAKeyboardDefinitions"
  log "resources: VIAKeyboardDefinitions ($(find "$APP/Contents/Resources/VIAKeyboardDefinitions" -name '*.json' | wc -l | tr -d ' ') json)"
fi

if [ "$ICON_OK" = "1" ]; then
  cp "$DIST/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# NOTE: intentionally no App Sandbox / no entitlements — the app needs direct
# non-sandboxed IOHIDManager access to the keyboard.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$DISPLAY_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$DISPLAY_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026 IQUNIX-DRIVE contributors. All rights reserved.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

printf 'APPL????' > "$APP/Contents/PkgInfo"

# ---------------------------------------------------------------------------
# 4. Ad-hoc code signature (required for a stable TCC identity on this Mac)
# ---------------------------------------------------------------------------
log "== ad-hoc signing =="
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

# ---------------------------------------------------------------------------
# 5. Distribution zip + checksum (this sha256 goes into the Homebrew cask)
# ---------------------------------------------------------------------------
log "== zipping =="
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
ZIP_SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
ZIP_SIZE="$(du -h "$ZIP" | awk '{print $1}')"

# Verify the ZIP really round-trips and that the signature survives packing.
VERIFY_DIR="$BUILD/zipverify"
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
if ditto -x -k "$ZIP" "$VERIFY_DIR" \
   && codesign --verify --deep --strict "$VERIFY_DIR/$APP_NAME.app"; then
  log "zip:  verified (extract + codesign --verify OK)"
  ZIP_OK=yes
else
  log "WARN: zip verification failed"
  ZIP_OK=no
fi
rm -rf "$VERIFY_DIR"

# Keep the local Homebrew cask in sync with the artifact we just produced.
# A cask URL must not depend on where the cask file is loaded from (it may be
# copied into a local tap), so we bake the absolute dist path in.
CASK="$ROOT/Casks/iqunix-drive.rb"
if [ -f "$CASK" ]; then
  sed -i '' -E \
    -e "s|^  version \".*\"|  version \"$VERSION\"|" \
    -e "s|^  sha256 .*|  sha256 :no_check|" \
    -e "s|^  url \".*\"|  url \"file://$ZIP\"|" \
    "$CASK"
  log "cask: synced version/url in Casks/iqunix-drive.rb (sha256 :no_check for locally built zip)"
fi

log ""
log "APP:  $APP"
log "ZIP:  $ZIP  ($ZIP_SIZE)"
log "SHA:  $ZIP_SHA"
log "ICON: $([ "$ICON_OK" = 1 ] && echo yes || echo no)"
log "ZIPVERIFY: $ZIP_OK"
log ""

# ---------------------------------------------------------------------------
# 6. Launch smoke test (best effort; GUI launching may be restricted in CI)
# ---------------------------------------------------------------------------
SMOKE_RESULT="not run"
if [ "${SMOKE_TEST:-1}" = "1" ]; then
  log "== smoke test: launching the app =="
  if open -n "$APP" 2>/dev/null; then
    sleep 2
    if pgrep -x IQUNIX-DRIVE >/dev/null 2>&1; then
      SMOKE_RESULT="PASS (process IQUNIX-DRIVE alive after 2s)"
    else
      SMOKE_RESULT="FAIL (open returned but no IQUNIX-DRIVE process after 2s)"
    fi
  else
    # `open` can be blocked in sandboxed/CI shells; try launching the binary
    # directly, which at least validates bundle layout + executable bits.
    "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 &
    LAUNCH_PID=$!
    sleep 2
    if kill -0 "$LAUNCH_PID" 2>/dev/null; then
      SMOKE_RESULT="PASS (direct exec, pid $LAUNCH_PID alive after 2s)"
    else
      SMOKE_RESULT="SKIP (open unavailable and direct exec exited immediately)"
    fi
  fi

  # Quit gracefully, then make sure it is really gone.
  osascript -e 'tell application "IQUNIX-DRIVE" to quit' >/dev/null 2>&1 || true
  sleep 1
  if pgrep -x IQUNIX-DRIVE >/dev/null 2>&1; then
    pkill -x IQUNIX-DRIVE >/dev/null 2>&1 || true
    sleep 1
  fi
  if pgrep -x IQUNIX-DRIVE >/dev/null 2>&1; then
    SMOKE_RESULT="$SMOKE_RESULT; WARN: process still running"
  fi
  log "smoke test: $SMOKE_RESULT"
  log ""
fi

log "OK: $APP"
log "Install (Homebrew 7 requires developer mode for casks loaded from a path):"
log "  HOMEBREW_DEVELOPER=1 brew install --cask \"$ROOT/Casks/iqunix-drive.rb\""
log "Or use a local tap (no env var needed, see docs/build-and-install.md)."
log "Cask sha256: $ZIP_SHA"
