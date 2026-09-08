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
APP_VERSION="${MULTICLIP_VERSION:-1.4.2}"
BUILD_NUMBER="${MULTICLIP_BUILD_NUMBER:-6}"

# A real signing identity gives TCC a stable designated requirement, allowing
# Accessibility permission to survive rebuilds. CI and developers can select a
# specific identity with MULTICLIP_SIGNING_IDENTITY. Otherwise use the first
# available code-signing identity, falling back to an ad-hoc signature only
# for local debug builds.
SIGNING_IDENTITY="${MULTICLIP_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null |
      sed -n 's/.*"\(.*\)"/\1/p' |
      head -n 1
  )"
fi

if [[ "$CONFIGURATION" == "release" && -z "$SIGNING_IDENTITY" ]]; then
  echo "Error: release builds require a stable code-signing identity." >&2
  echo "Install an Apple Development or Developer ID certificate, or set" >&2
  echo "MULTICLIP_SIGNING_IDENTITY to the identity that should sign the app." >&2
  exit 1
fi

swift build -c "$CONFIGURATION" --package-path "$REPO_ROOT"
BINARY="$(swift build -c "$CONFIGURATION" --package-path "$REPO_ROOT" --show-bin-path)/MenuBarClipboard"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
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
	<string>$APP_VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026 Ali Faraz</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

cp "$BINARY" "$APP/Contents/MacOS/MenuBarClipboard"

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP"
  echo "Signed with $SIGNING_IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Warning: no code-signing identity was found; Accessibility permission"
  echo "will need to be granted again after the app binary is rebuilt."
fi

echo "Built $APP"
