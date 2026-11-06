import AppKit
import ApplicationServices

/// Tells the notch whether the menu bar is crowded right beside it, so the
/// activities can go inside the notch instead of covering a menu bar icon.
///
/// macOS draws the whole menu bar as one window, so the only way to know
/// where the icons are is Accessibility: each app's menu bar extras and the
/// front app's menus report their frames. That is read, on a background
/// queue, only when something that can change it happens (an app opening,
/// closing or coming to the front, a screen or Space change, wake, or the
/// permission arriving). Nothing is polled.
@MainActor
final class MenuBarCrowding: ObservableObject {
    @Published private(set) var isCrowded = false

    private var isRunning = false
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.anandexe7.sleepy-notch.menubar", qos: .utility)

    /// How much room a bubble and its gap need beside the notch, in points.
    static let clearance: CGFloat = 64

    func setRunning(_ on: Bool) {
        guard on != isRunning else { return }
        isRunning = on
        if on {
            observe()
            schedule()
        } else {
            for observer in observers {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
            pending?.cancel()
            if isCrowded { isCrowded = false }
        }
    }

    /// The same check, for a person to look at: where the nearest icons are.
    func describe() async -> String {
        guard let area = Self.areas() else { return "no notch" }
        let frames = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Self.readFrames()) }
        }
        let (left, right) = Self.nearest(frames: frames, notchLeft: area.left, notchRight: area.right)
        return "notch \(Int(area.left))-\(Int(area.right)); nearest icon on the left ends at \(left.map { String(Int($0)) } ?? "none"), on the right starts at \(right.map { String(Int($0)) } ?? "none"); crowded=\(Self.crowded(left: left, right: right, notchLeft: area.left, notchRight: area.right))"
    }

    // MARK: - When to look

    private func observe() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let again: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.schedule() }
        }
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didWakeNotification,
        ] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main, using: again))
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: again
        ))
    }

    /// One look shortly after the last event: apps open in bursts, and a new
    /// app's menu bar icon takes a moment to appear.
    func schedule() {
        guard isRunning else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, let area = Self.areas() else { return }
            self.queue.async {
                let frames = Self.readFrames()
                let (left, right) = Self.nearest(frames: frames, notchLeft: area.left, notchRight: area.right)
                let crowded = Self.crowded(left: left, right: right, notchLeft: area.left, notchRight: area.right)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if self.isRunning, crowded != self.isCrowded { self.isCrowded = crowded }
                    }
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Geometry

    /// The notch's left and right edge, in points from the screen's left, on
    /// the main screen; nil when it has no notch.
    private static func areas() -> (left: CGFloat, right: CGFloat)? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        return (screen.frame.minX + left.width, screen.frame.minX + right.minX - screen.frame.minX)
    }

    /// Icon frames the menu bar has near the notch.
    struct Frames {
        /// Right edges of the front app's menus.
        var menuEnds: [CGFloat] = []
        /// Left edges of menu bar extras.
        var extraStarts: [CGFloat] = []
    }

    /// The nearest icon on each side of the notch: where the app menus end
    /// (left) and where the extras begin (right).
    static func nearest(frames: Frames, notchLeft: CGFloat, notchRight: CGFloat) -> (left: CGFloat?, right: CGFloat?) {
        let left = frames.menuEnds.filter { $0 <= notchLeft + 1 }.max()
        let right = frames.extraStarts.filter { $0 >= notchRight - 1 }.min()
        return (left, right)
    }

    /// Crowded when an icon is closer to the notch than a bubble needs.
    static func crowded(left: CGFloat?, right: CGFloat?, notchLeft: CGFloat, notchRight: CGFloat) -> Bool {
        if let left, notchLeft - left < clearance { return true }
        if let right, right - notchRight < clearance { return true }
        return false
    }

    // MARK: - Reading the menu bar (Accessibility)

    /// Frames of the front app's menu titles and everyone's menu bar extras.
    /// Runs off the main thread; each call to another app has a short limit
    /// so one that doesn't answer can't hold it up.
    private static func readFrames() -> Frames {
        guard AXIsProcessTrusted() else { return Frames() }
        var frames = Frames()
        if let front = NSWorkspace.shared.frontmostApplication {
            let app = AXUIElementCreateApplication(front.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.25)
            if let bar = element(app, "AXMenuBar") {
                for item in children(of: bar) {
                    if let f = frame(of: item) { frames.menuEnds.append(f.maxX) }
                }
            }
        }
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy != .prohibited {
            let app = AXUIElementCreateApplication(running.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.25)
            guard let extras = element(app, "AXExtrasMenuBar") else { continue }
            for item in children(of: extras) {
                if let f = frame(of: item), f.width > 0 { frames.extraStarts.append(f.minX) }
            }
        }
        return frames
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
