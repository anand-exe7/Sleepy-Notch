#!/bin/bash
# Builds "Sleepy Notch.app" from the SwiftPM release build.
#
#   scripts/make-app.sh              build, bundle and ad-hoc sign into build/
#   scripts/make-app.sh --dmg        also make build/SleepyNotch.dmg
#
# A bare SwiftPM executable can't claim a URL scheme or show up properly to
# macOS; inside an .app it can (sleepynotch:// links work), and the privacy
# prompts show the texts from Info.plist under the app's own name.
#
# The result is signed ad hoc, so it runs on this Mac. To give it to other
# people it has to be signed with a Developer ID and notarized: that needs an
# Apple Developer account and is left to the owner (see the SIGN lines).
set -euo pipefail

cd "$(dirname "$0")/.."
name="Sleepy Notch"
bundle_id="com.anandexe7.sleepy-notch"
version="${VERSION:-0.1.0}"
out="build"
app="$out/$name.app"

swift build -c release
binary=".build/release/SleepyNotch"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/SleepyNotch"

# Support/Info.plist holds the usage texts and the URL scheme; the bundle
# adds what only an .app needs.
cp Support/Info.plist "$app/Contents/Info.plist"
plist="$app/Contents/Info.plist"
set_key() { /usr/libexec/PlistBuddy -c "Set :$1 $2" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :$1 ${3:-string} $2" "$plist"; }
set_key CFBundleExecutable SleepyNotch
set_key CFBundleIdentifier "$bundle_id"
set_key CFBundlePackageType APPL
set_key CFBundleName "$name"
set_key CFBundleDisplayName "$name"
set_key CFBundleShortVersionString "$version"
set_key CFBundleVersion "$version"
set_key LSMinimumSystemVersion 13.0
# A menu bar app: no Dock icon.
set_key LSUIElement true bool
set_key NSHighResolutionCapable true bool
set_key NSAppleEventsUsageDescription "Sleepy Notch controls Music and Spotify: play, pause, skip, the volume for the sleep timer, and likes and playlists in Apple Music."

plutil -lint "$plist" >/dev/null

# SIGN: replace "-" with a "Developer ID Application: …" identity to sign for
# distribution, then notarize with `xcrun notarytool`.
codesign --force --deep --sign - "$app"
echo "Built $app"

if [ "${1:-}" = "--dmg" ]; then
    dmg="$out/SleepyNotch.dmg"
    stage="$out/dmg-stage"
    rm -rf "$stage" "$dmg"
    mkdir -p "$stage"
    cp -R "$app" "$stage/"
    ln -s /Applications "$stage/Applications"
    hdiutil create -quiet -volname "$name" -srcfolder "$stage" -ov -format UDZO "$dmg"
    rm -rf "$stage"
    echo "Built $dmg"
fi
