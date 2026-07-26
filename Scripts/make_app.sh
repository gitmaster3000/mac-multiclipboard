#!/bin/bash
# Packages the SwiftPM executable into a Multiclipboard.app bundle.
#
# A bare `swift run` binary has no bundle identifier, so the window server
# never delivers Carbon hot-key events to it and the ⌘⇧V picker shortcut
# silently does nothing. Running the app from a bundle fixes that.

set -euo pipefail

CONFIGURATION="${1:-debug}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/Multiclipboard.app"

swift build -c "$CONFIGURATION" --package-path "$REPO_ROOT"
BINARY="$(swift build -c "$CONFIGURATION" --package-path "$REPO_ROOT" --show-bin-path)/MenuBarClipboard"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>MenuBarClipboard</string>
	<key>CFBundleIdentifier</key>
	<string>com.multiclipboard.MenuBarClipboard</string>
	<key>CFBundleName</key>
	<string>Multiclipboard</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

cp "$BINARY" "$APP/Contents/MacOS/MenuBarClipboard"
codesign --force --sign - "$APP"

echo "Built $APP"
