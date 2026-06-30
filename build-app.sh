#!/bin/bash
# Builds MCP Manager and packages it into a double-clickable macOS .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MCP Manager"
BIN_NAME="MCPManager"
BUNDLE_ID="com.kyle.mcpmanager"

# Version (CFBundleShortVersionString): override with VERSION=... or derive from
# the latest git tag (e.g. v1.2.3 -> 1.2.3). Falls back to 0.0.0 for dev builds.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
# Build number (CFBundleVersion): total commit count, monotonically increasing.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# Build a universal binary so the app runs on both Apple Silicon and Intel Macs.
ARCH_FLAGS="--arch arm64 --arch x86_64"

echo "▶ Building universal release binary (arm64 + x86_64, v$VERSION, build $BUILD)…"
swift build -c release $ARCH_FLAGS

BIN_PATH="$(swift build -c release $ARCH_FLAGS --show-bin-path)/$BIN_NAME"

APP_DIR="build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "▶ Assembling $APP_DIR …"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH" "$CONTENTS/MacOS/$BIN_NAME"

if [ ! -f Resources/AppIcon.icns ]; then
    echo "▶ Icon missing — generating…"
    ./make-icon.sh
fi
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>      <string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>$BUILD</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleIconName</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

echo "▶ Ad-hoc code signing…"
codesign --force --deep --sign - "$CONTENTS/MacOS/$BIN_NAME"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR" && echo "  signature OK"

ARCHS="$(lipo -archs "$CONTENTS/MacOS/$BIN_NAME")"
echo "▶ Architectures: $ARCHS"
case "$ARCHS" in
    *arm64*x86_64* | *x86_64*arm64*) echo "  universal ✓" ;;
    *) echo "  WARNING: expected a universal (arm64 + x86_64) binary, got: $ARCHS" ;;
esac

echo "✅ Built: $APP_DIR"
echo "   Run with:  open \"$APP_DIR\""
