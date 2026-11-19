# Releasing Sleepy Notch

## A normal release (what we do today)

The app is signed ad hoc, so people need **Open Anyway** the first time (the README explains it).

1. Make sure `main` has everything and is pushed:

   ```bash
   git switch main
   git pull
   ```

2. Build the universal app and the DMG, with the new version number:

   ```bash
   VERSION=0.1.2 scripts/make-app.sh --dmg
   ```

   It prints `Architectures: x86_64 arm64`. The DMG is `build/SleepyNotch.dmg`.

3. Write the release notes (what's new, the install steps, known limits) in a file, say `build/notes.md`, then publish:

   ```bash
   gh release create v0.1.2 build/SleepyNotch.dmg --target main --title "Sleepy Notch 0.1.2" --notes-file build/notes.md
   ```

   Add `--prerelease` for a test version that shouldn't show as "Latest".

## Notarizing (removes the "Open Anyway" step)

Apple only trusts apps signed with a **Developer ID** and checked by its notary service. This needs the Apple Developer Program ($99 a year) and Xcode installed (for `notarytool` and `stapler`).

### Once

1. Join the [Apple Developer Program](https://developer.apple.com/programs/).
2. Create a **Developer ID Application** certificate: Xcode → Settings → Accounts → your team → Manage Certificates → + → Developer ID Application. Check it's in your keychain:

   ```bash
   security find-identity -v -p codesigning
   ```

   You should see `Developer ID Application: Your Name (TEAMID)`.

3. Create an app-specific password at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords, and save it for `notarytool` (it asks for the password; it's stored in your keychain, never in the repo):

   ```bash
   xcrun notarytool store-credentials sleepy-notch --apple-id "you@example.com" --team-id TEAMID
   ```

### Each release

1. Build signed with your Developer ID. The script switches on the hardened runtime and the entitlements in `Support/SleepyNotch.entitlements` when it sees a Developer ID:

   ```bash
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" VERSION=0.2.0 scripts/make-app.sh --dmg
   ```

2. Sign the DMG too, send it to Apple and wait for the answer (usually a few minutes):

   ```bash
   codesign --sign "Developer ID Application: Your Name (TEAMID)" --timestamp build/SleepyNotch.dmg
   ```

   ```bash
   xcrun notarytool submit build/SleepyNotch.dmg --keychain-profile sleepy-notch --wait
   ```

   If it says **Invalid**, see why:

   ```bash
   xcrun notarytool log <submission-id> --keychain-profile sleepy-notch
   ```

3. Attach Apple's ticket to the DMG, so it opens even offline, and check it:

   ```bash
   xcrun stapler staple build/SleepyNotch.dmg
   ```

   ```bash
   spctl -a -t open --context context:primary-signature -vv build/SleepyNotch.dmg
   ```

   It should say `accepted` and `source=Notarized Developer ID`.

4. Publish as above. Then remove the "Open Anyway" step from the README and the release notes.

### Things to check after the first notarized build

The hardened runtime is stricter than ad hoc signing. Try each of these once on the notarized build: Music and Spotify control, the Calendar page, voice waves (microphone), Capture Text, dictation, and the brightness and keyboard-backlight notices (they use private frameworks loaded at run time). If one stops working, it usually needs one more entitlement in `Support/SleepyNotch.entitlements`.

## Homebrew (after notarizing)

With a notarized DMG, a Homebrew cask lets people install with one command. Make a repo named `homebrew-tap`, add `Casks/sleepy-notch.rb` pointing at the release's DMG and its SHA-256 (`shasum -a 256 build/SleepyNotch.dmg`), and people can run:

```bash
brew install --cask anand-exe7/tap/sleepy-notch
```
