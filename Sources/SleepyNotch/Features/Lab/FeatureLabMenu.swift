#if DEBUG
import AppKit

/// The "🧪 Feature Lab" submenu: pick a style for each trial feature and
/// trigger it on demand. Rebuilt each time it opens so checkmarks are current.
@MainActor
final class FeatureLabMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "Feature Lab")

    private let wiring: AppWiring
    private var preferences: HUDPreferences { wiring.preferences }

    init(wiring: AppWiring) {
        self.wiring = wiring
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        rebuild()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        header("Album animation")
        for style in ArtworkTransitionStyle.allCases {
            add(style.title, checked: preferences.artworkStyle == style, indent: true) {
                self.preferences.artworkStyle = style
            }
        }
        add("Song-change peek", checked: preferences.songChangePeek) {
            self.preferences.songChangePeek.toggle()
        }
        add("Tint controls with album colour", checked: preferences.albumTint) {
            self.preferences.albumTint.toggle()
        }
        add("Next demo song (turns on Demo Mode)") {
            self.wiring.simulateSongChange()
        }

        menu.addItem(.separator())
        header(wiring.powerSource.hasBattery
               ? "Charging"
               : "Charging (no battery on this Mac — simulate only)")
        add("Simulate plug in") { self.wiring.simulatePower(.pluggedIn) }
        add("Simulate unplug") { self.wiring.simulatePower(.unplugged) }
        add("Simulate fully charged") { self.wiring.simulatePower(.fullyCharged) }
        add("Simulate low battery") { self.wiring.simulatePower(.low) }

        menu.addItem(.separator())
        header("Headphones")
        add("Simulate AirPods Pro connecting") { self.wiring.simulateHeadphones(.airPodsPro, connected: true) }
        add("Simulate AirPods connecting") { self.wiring.simulateHeadphones(.airPods, connected: true) }
        add("Simulate AirPods Max connecting") { self.wiring.simulateHeadphones(.airPodsMax, connected: true) }
        add("Simulate Beats connecting") { self.wiring.simulateHeadphones(.beats, connected: true) }
        add("Simulate other headphones connecting") { self.wiring.simulateHeadphones(.headphones, connected: true) }
        add("Simulate disconnecting") { self.wiring.simulateHeadphones(.airPodsPro, connected: false) }

        menu.addItem(.separator())
        header("Beside the notch")
        add("Camera & mic dots", checked: preferences.privacyDots) { self.preferences.privacyDots.toggle() }
        add("Simulate mic in use", indent: true) { self.wiring.simulatePrivacy(mic: true, camera: false) }
        add("Simulate camera and mic in use", indent: true) { self.wiring.simulatePrivacy(mic: true, camera: true) }
        add("Clear simulated dots", indent: true) { self.wiring.simulatePrivacy(mic: false, camera: false) }
        add("Battery level while charging", checked: preferences.chargingWing) { self.preferences.chargingWing.toggle() }
        add("Simulate charging", indent: true) { self.wiring.simulateCharging(true) }
        add("Clear simulated charging", indent: true) { self.wiring.simulateCharging(false) }

        menu.addItem(.separator())
        header("Keyboard")
        add("Caps Lock & layout peek", checked: preferences.keyboardPeek) { self.preferences.keyboardPeek.toggle() }
        if !KeyboardMonitor.canSeeCapsLock {
            add("Allow Caps Lock detection (Accessibility)…", indent: true) { KeyboardMonitor.requestCapsLockAccess() }
        }
        add("Simulate Caps Lock on", indent: true) { self.wiring.simulateKeyboard(.capsLock(isOn: true)) }
        add("Simulate layout change", indent: true) { self.wiring.simulateKeyboard(.inputSource(name: "ABC")) }

        menu.addItem(.separator())
        header("Calendar")
        add("Meeting reminders", checked: preferences.meetingReminders) { self.preferences.meetingReminders.toggle() }
        add("Simulate meeting with Join link", indent: true) { self.wiring.simulateMeeting(withLink: true) }
        add("Simulate meeting without link", indent: true) { self.wiring.simulateMeeting(withLink: false) }

        menu.addItem(.separator())
        header("Clipboard")
        add("Copied peek", checked: preferences.copyPeek) { self.preferences.copyPeek.toggle() }
        add("Simulate copying text", indent: true) {
            self.wiring.simulateCopy(.text("Let's move the review to Thursday afternoon"))
        }
        add("Simulate copying a link", indent: true) {
            self.wiring.simulateCopy(.link(URL(string: "https://www.apple.com/airpods-pro/")!))
        }

        menu.addItem(.separator())
        let count = wiring.shelf.items.count
        header(count == 0 ? "File shelf (drag a file onto the notch)" : "File shelf (\(count) on it)")
        add("Add sample files") { self.wiring.addSampleFiles() }
        add("Clear shelf", enabled: count > 0) { self.wiring.shelf.clear() }
    }

    // MARK: - Helpers

    private func header(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func add(
        _ title: String,
        checked: Bool = false,
        indent: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        let item = ClosureMenuItem(title: title, action: action)
        item.state = checked ? .on : .off
        item.indentationLevel = indent ? 1 : 0
        item.isEnabled = enabled
        menu.addItem(item)
    }
}

/// An `NSMenuItem` that runs a closure, so the menu doesn't need a selector
/// per action.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func fire() {
        handler()
    }
}
#endif
