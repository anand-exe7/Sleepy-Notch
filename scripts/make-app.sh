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

# Universal: Apple Silicon and Intel in one app. Older Swift toolchains
# can't build several architectures at once without Xcode; then it's this
# Mac's own architecture only.
if swift build -c release --arch arm64 --arch x86_64; then
    binary="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/SleepyNotch"
else
    echo "Universal build not available here; building for $(uname -m) only." >&2
    swift build -c release
    binary="$(swift build -c release --show-bin-path)/SleepyNotch"
fi
echo "Architectures: $(lipo -archs "$binary")"

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
#
# For everyday builds: an ad-hoc signature changes with every build, and
# macOS ties privacy grants (Calendar, Microphone, Accessibility) to the
# signature, so each rebuild silently lost them. A self-signed certificate
# named "Sleepy Notch Dev" (Keychain Access -> Certificate Assistant ->
# Create a Certificate, type Code Signing) keeps them across builds; it is
# used when present, or set SIGN_IDENTITY to another one.
identity="${SIGN_IDENTITY:-}"
if [ -z "$identity" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Sleepy Notch Dev"; then
    identity="Sleepy Notch Dev"
fi
if [[ "$identity" == "Developer ID Application"* ]]; then
    # For notarization: the hardened runtime, the entitlements it needs for
    # what the app already asks permission for, and a secure timestamp.
    # See docs/RELEASING.md.
    codesign --force --deep --options runtime --timestamp \
        --entitlements Support/SleepyNotch.entitlements --sign "$identity" "$app"
else
    codesign --force --deep --sign "${identity:--}" "$app"
fi
[ -n "$identity" ] && echo "Signed with $identity" || echo "Signed ad hoc (privacy grants reset with each build)"
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
