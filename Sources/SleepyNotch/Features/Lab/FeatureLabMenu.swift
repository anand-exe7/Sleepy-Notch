#if DEBUG
import AppKit

/// The "🧪 Feature Lab" submenu: pick a style for each trial feature and
/// trigger it on demand. Rebuilt each time it opens so checkmarks are current.
@MainActor
final class FeatureLabMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "Feature Lab")

    private var lab: LabSettings { LabSettings.shared }

    override init() {
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
                LabSettings.shared.artworkStyle = style
            }
        }
        add("Song-change peek", checked: lab.songChangePeek) {
            LabSettings.shared.songChangePeek.toggle()
        }
        add("Album colour glow", checked: lab.albumGlow) {
            LabSettings.shared.albumGlow.toggle()
        }
        add("Next demo song (turns on Demo Mode)") {
            FeatureLab.simulateSongChange()
        }

        menu.addItem(.separator())
        header(PowerSourceMonitor.shared.hasBattery
               ? "Charging"
               : "Charging (no battery on this Mac — simulate only)")
        for style in ChargingPeekStyle.allCases {
            add(style.title, checked: lab.chargingStyle == style, indent: true) {
                LabSettings.shared.chargingStyle = style
            }
        }
        add("Simulate plug in") { FeatureLab.simulatePower(.pluggedIn) }
        add("Simulate unplug") { FeatureLab.simulatePower(.unplugged) }
        add("Simulate fully charged") { FeatureLab.simulatePower(.fullyCharged) }
        add("Simulate low battery") { FeatureLab.simulatePower(.low) }

        menu.addItem(.separator())
        header("AirPods")
        add("Simulate AirPods Pro connecting") { FeatureLab.simulateHeadphones(.airPodsPro, connected: true) }
        add("Simulate AirPods connecting") { FeatureLab.simulateHeadphones(.airPods, connected: true) }
        add("Simulate AirPods Max connecting") { FeatureLab.simulateHeadphones(.airPodsMax, connected: true) }
        add("Simulate disconnecting") { FeatureLab.simulateHeadphones(.airPodsPro, connected: false) }

        menu.addItem(.separator())
        let count = ShelfStore.shared.items.count
        header(count == 0 ? "File shelf (drag a file onto the notch)" : "File shelf (\(count) on it)")
        add("Add sample files") { FeatureLab.addSampleFiles() }
        add("Clear shelf", enabled: count > 0) { ShelfStore.shared.clear() }
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
