#!/bin/bash
# Builds MCP Manager and packages it into a double-clickable macOS .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MCP Manager"
BIN_NAME="MCPManager"
BUNDLE_ID="com.kyle.mcpmanager"
VERSION="1.0.0"

echo "▶ Building release binary…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$BIN_NAME"

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
    <key>CFBundleVersion</key>         <string>$VERSION</string>
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
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✅ Built: $APP_DIR"
echo "   Run with:  open \"$APP_DIR\""
