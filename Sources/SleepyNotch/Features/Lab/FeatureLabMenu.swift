#if DEBUG
import AppKit

/// The "🧪 Feature Lab" submenu: pick a style for each trial feature and
/// trigger it on demand. Rebuilt each time it opens so checkmarks are current.
@MainActor
final class FeatureLabMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "Feature Lab")

    private let featureLab: FeatureLab
    private var lab: LabSettings { featureLab.lab }

    init(featureLab: FeatureLab) {
        self.featureLab = featureLab
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
            add(style.title, checked: lab.artworkStyle == style, indent: true) {
                self.lab.artworkStyle = style
            }
        }
        add("Song-change peek", checked: lab.songChangePeek) {
            self.lab.songChangePeek.toggle()
        }
        add("Tint controls with album colour", checked: lab.albumTint) {
            self.lab.albumTint.toggle()
        }
        add("Next demo song (turns on Demo Mode)") {
            self.featureLab.simulateSongChange()
        }

        menu.addItem(.separator())
        header(featureLab.powerSource.hasBattery
               ? "Charging"
               : "Charging (no battery on this Mac — simulate only)")
        add("Simulate plug in") { self.featureLab.simulatePower(.pluggedIn) }
        add("Simulate unplug") { self.featureLab.simulatePower(.unplugged) }
        add("Simulate fully charged") { self.featureLab.simulatePower(.fullyCharged) }
        add("Simulate low battery") { self.featureLab.simulatePower(.low) }

        menu.addItem(.separator())
        header("Headphones")
        add("Simulate AirPods Pro connecting") { self.featureLab.simulateHeadphones(.airPodsPro, connected: true) }
        add("Simulate AirPods connecting") { self.featureLab.simulateHeadphones(.airPods, connected: true) }
        add("Simulate AirPods Max connecting") { self.featureLab.simulateHeadphones(.airPodsMax, connected: true) }
        add("Simulate Beats connecting") { self.featureLab.simulateHeadphones(.beats, connected: true) }
        add("Simulate other headphones connecting") { self.featureLab.simulateHeadphones(.headphones, connected: true) }
        add("Simulate disconnecting") { self.featureLab.simulateHeadphones(.airPodsPro, connected: false) }

        menu.addItem(.separator())
        header("Beside the notch")
        add("Camera & mic dots", checked: lab.privacyDots) { self.lab.privacyDots.toggle() }
        add("Simulate mic in use", indent: true) { self.featureLab.simulatePrivacy(mic: true, camera: false) }
        add("Simulate camera and mic in use", indent: true) { self.featureLab.simulatePrivacy(mic: true, camera: true) }
        add("Clear simulated dots", indent: true) { self.featureLab.simulatePrivacy(mic: false, camera: false) }
        add("Battery level while charging", checked: lab.chargingWing) { self.lab.chargingWing.toggle() }
        add("Simulate charging", indent: true) { self.featureLab.simulateCharging(true) }
        add("Clear simulated charging", indent: true) { self.featureLab.simulateCharging(false) }

        menu.addItem(.separator())
        header("Keyboard")
        add("Caps Lock & layout peek", checked: lab.keyboardPeek) { self.lab.keyboardPeek.toggle() }
        if !KeyboardMonitor.canSeeCapsLock {
            add("Allow Caps Lock detection (Accessibility)…", indent: true) { KeyboardMonitor.requestCapsLockAccess() }
        }
        add("Simulate Caps Lock on", indent: true) { self.featureLab.simulateKeyboard(.capsLock(isOn: true)) }
        add("Simulate layout change", indent: true) { self.featureLab.simulateKeyboard(.inputSource(name: "ABC")) }

        menu.addItem(.separator())
        header("Calendar")
        add("Meeting reminders", checked: lab.meetingReminders) { self.lab.meetingReminders.toggle() }
        add("Simulate meeting with Join link", indent: true) { self.featureLab.simulateMeeting(withLink: true) }
        add("Simulate meeting without link", indent: true) { self.featureLab.simulateMeeting(withLink: false) }

        menu.addItem(.separator())
        header("Clipboard")
        add("Copied peek", checked: lab.copyPeek) { self.lab.copyPeek.toggle() }
        add("Simulate copying text", indent: true) {
            self.featureLab.simulateCopy(.text("Let's move the review to Thursday afternoon"))
        }
        add("Simulate copying a link", indent: true) {
            self.featureLab.simulateCopy(.link(URL(string: "https://www.apple.com/airpods-pro/")!))
        }

        menu.addItem(.separator())
        let count = featureLab.shelf.items.count
        header(count == 0 ? "File shelf (drag a file onto the notch)" : "File shelf (\(count) on it)")
        add("Add sample files") { self.featureLab.addSampleFiles() }
        add("Clear shelf", enabled: count > 0) { self.featureLab.shelf.clear() }
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
