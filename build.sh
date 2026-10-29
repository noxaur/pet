#!/bin/bash
# Builds build/Clawd.app. With --install it copies the app to ~/Applications and opens it.
set -euo pipefail
cd "$(dirname "$0")"
# The build number is the commit count on the current branch, so each commit on main gives a newer build.
BUILD=${CLAWD_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
VERSION=${CLAWD_VERSION:-1.0.$BUILD}
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/Clawd.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/Clawd" "$APP/Contents/MacOS/Clawd"
# Sparkle comes with the app. ditto keeps the symlinks and the signature of the framework.
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Clawd"
# The SwiftPM resource bundles, for example the PermissionFlow translations.
for bundle in "$BIN"/*.bundle; do
    [[ -e "$bundle" ]] && ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.noxaur.clawd</string>
    <key>CFBundleName</key><string>Clawd</string>
    <key>CFBundleExecutable</key><string>Clawd</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>https://github.com/noxaur/pet/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>Mr2lg5TSzrWr3y6y/5EFOlfUnPDr76IQaO6KTZ/GCW4=</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>
</dict>
</plist>
PLIST
# A designated requirement on the identifier only keeps the Accessibility permission across rebuilds.
codesign --force --sign - -r='designated => identifier "com.noxaur.clawd"' "$APP"
echo "Built $APP $VERSION ($BUILD)"
if [[ "${1:-}" == "--install" ]]; then
    pkill -x Clawd || true
    # Clawd gives back borrowed windows before he quits.
    for _ in $(seq 1 50); do pgrep -x Clawd >/dev/null || break; sleep 0.2; done
    rm -rf ~/Applications/Clawd.app
    mkdir -p ~/Applications
    cp -R "$APP" ~/Applications/
    open ~/Applications/Clawd.app
fi
