import AppKit
import SwiftUI

/// How big the floating player is.
enum FloatingPlayerSize: String, CaseIterable, Identifiable {
    case mini
    case player
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mini: return "Mini"
        case .player: return "Player"
        case .expanded: return "Expanded"
        }
    }

    var windowSize: CGSize {
        switch self {
        case .mini: return CGSize(width: 310, height: 66)
        case .player: return CGSize(width: 350, height: 166)
        case .expanded: return CGSize(width: 390, height: 488)
        }
    }

    var next: FloatingPlayerSize {
        switch self {
        case .mini: return .player
        case .player: return .expanded
        case .expanded: return .mini
        }
    }
}

/// A small player window that floats above everything: what's playing, the
/// controls, and, expanded, a large cover and what plays next.
///
/// The window and its view exist only while it is shown; hidden, it is
/// gone and costs nothing. Shown, it only moves as the song does (the
/// scrubber's once-a-second times), and with the music
/// paused nothing in it moves.
@MainActor
final class FloatingPlayerController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false
    @Published var size: FloatingPlayerSize {
        didSet {
            defaults.set(size.rawValue, forKey: Self.sizeKey)
            resizeWindow()
        }
    }

    private let media: PlaybackCoordinator
    private let power: PowerStateMonitor
    private let upNext: UpNextService
    private let preferences: HUDPreferences
    private let defaults = UserDefaults.standard
    private var panel: NSPanel?

    private static let sizeKey = "floatingPlayer.size"
    private static let originKey = "floatingPlayer.topLeft"

    init(
        media: PlaybackCoordinator,
        power: PowerStateMonitor,
        upNext: UpNextService,
        preferences: HUDPreferences
    ) {
        self.media = media
        self.power = power
        self.upNext = upNext
        self.preferences = preferences
        size = defaults.string(forKey: Self.sizeKey).flatMap(FloatingPlayerSize.init(rawValue:)) ?? .player
        super.init()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard panel == nil else { return }
        let content = FloatingPlayerView(
            controller: self, media: media, power: power,
            upNext: upNext, preferences: preferences
        )
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = FirstClickHostingView(rootView: content)
        place(panel)
        panel.orderFrontRegardless()
        self.panel = panel
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        // The view goes with the window: nothing of it is left running.
        panel?.contentView = nil
        panel = nil
        isVisible = false
    }

    // MARK: - Place and size

    /// Where the window's top-left was left, or the top right of the screen.
    private func place(_ panel: NSPanel) {
        let frame = panel.frame
        let screen = NSScreen.main?.visibleFrame ?? .zero
        var topLeft = CGPoint(x: screen.maxX - frame.width - 24, y: screen.maxY - 24)
        if let saved = defaults.array(forKey: Self.originKey) as? [Double], saved.count == 2 {
            let candidate = CGPoint(x: saved[0], y: saved[1])
            // Only if that spot is still on a screen.
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(candidate) }) {
                topLeft = candidate
            }
        }
        panel.setFrameTopLeftPoint(topLeft)
    }

    private func resizeWindow() {
        guard let panel else { return }
        let top = panel.frame.maxY
        let origin = CGPoint(x: panel.frame.minX, y: top - size.windowSize.height)
        panel.setFrame(CGRect(origin: origin, size: size.windowSize), display: true, animate: true)
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        defaults.set([Double(panel.frame.minX), Double(panel.frame.maxY)], forKey: Self.originKey)
    }
}
