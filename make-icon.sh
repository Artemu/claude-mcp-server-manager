#!/bin/bash
# Generates Resources/AppIcon.icns from make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p Resources build/icon
PNG="build/icon/icon_1024.png"

echo "▶ Rendering icon…"
swift make-icon.swift "$PNG"

ICONSET="build/icon/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"

# Standard macOS icon sizes (1x and 2x).
gen() { sips -z "$1" "$1" "$PNG" --out "$ICONSET/$2" >/dev/null; }
gen 16    icon_16x16.png
gen 32    icon_16x16@2x.png
gen 32    icon_32x32.png
gen 64    icon_32x32@2x.png
gen 128   icon_128x128.png
gen 256   icon_128x128@2x.png
gen 256   icon_256x256.png
gen 512   icon_256x256@2x.png
gen 512   icon_512x512.png
cp "$PNG" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "✅ Wrote Resources/AppIcon.icns"
