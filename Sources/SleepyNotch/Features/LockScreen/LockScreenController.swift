import AppKit
import SwiftUI
import Combine

/// Puts the Now Playing card above the lock screen while the Mac is locked,
/// and offers the same card in an ordinary window for checking it.
///
/// Event-driven: it listens for the system's lock and unlock notifications,
/// and only while the Settings switch is on. The card's window exists only
/// while the screen is locked, so unlocked it costs nothing.
@MainActor
final class LockScreenController {
    private let media: PlaybackCoordinator
    private let preferences: HUDPreferences
    private let state = LockScreenCardState()

    private var lockedPanel: NSPanel?
    private var space: SkyLightSpace?
    private var previewPanel: NSPanel?
    private var prototypePanel: NSPanel?
    private var prototypeSpace: SkyLightSpace?
    private var observers: [NSObjectProtocol] = []
    private var cancellable: AnyCancellable?

    private static let locked = Notification.Name("com.apple.screenIsLocked")
    private static let unlocked = Notification.Name("com.apple.screenIsUnlocked")

    init(media: PlaybackCoordinator, preferences: HUDPreferences) {
        self.media = media
        self.preferences = preferences
        cancellable = preferences.$lockScreenCard
            .removeDuplicates()
            .sink { [weak self] on in
                if on { self?.startObserving() } else { self?.stopObserving() }
            }
    }

    // MARK: - Lock and unlock

    private func startObserving() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: Self.locked, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenLocked() }
            },
            center.addObserver(forName: Self.unlocked, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenUnlocked() }
            },
        ]
    }

    private func stopObserving() {
        let center = DistributedNotificationCenter.default()
        observers.forEach(center.removeObserver)
        observers = []
        screenUnlocked()
    }

    private func screenLocked() {
        // Media only, and only when there's something to show.
        guard lockedPanel == nil, !media.currentTrack.isPlaceholder,
              let space = SkyLightSpace() else { return }
        state.isCoverLarge = false
        let panel = makePanel(level: .statusBar)
        place(panel, onBottomOf: NSScreen.main)
        panel.orderFrontRegardless()
        space.add(panel)
        self.space = space
        lockedPanel = panel
    }

    private func screenUnlocked() {
        space?.hide()
        lockedPanel?.orderOut(nil)
        lockedPanel = nil
        space = nil
    }

    // MARK: - Checking it

    /// The card in an ordinary window, since a locked screen blanks captures.
    func showPreview() {
        previewPanel?.orderOut(nil)
        state.isCoverLarge = false
        let panel = makePanel(level: .floating)
        panel.isMovableByWindowBackground = true
        place(panel, onBottomOf: NSScreen.main)
        panel.makeKeyAndOrderFront(nil)
        previewPanel = panel
    }

    func closePreview() {
        previewPanel?.orderOut(nil)
        previewPanel = nil
    }

    /// A small window with one button, moved above the lock screen. Lock the
    /// Mac by hand to see whether it shows there and takes clicks.
    func showPrototype() {
        closePrototype()
        guard let space = SkyLightSpace() else { return }
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = FirstClickHostingView(rootView: PrototypeView())
        place(panel, onBottomOf: NSScreen.main)
        panel.orderFrontRegardless()
        space.add(panel)
        prototypePanel = panel
        prototypeSpace = space
    }

    func closePrototype() {
        prototypeSpace?.hide()
        prototypePanel?.orderOut(nil)
        prototypePanel = nil
        prototypeSpace = nil
    }

    // MARK: - Windows

    private func makePanel(level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: LockScreenCardView.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = FirstClickHostingView(rootView: LockScreenCardView(media: media, state: state))
        return panel
    }

    /// Centred, near the bottom of the screen, clear of the clock above.
    private func place(_ panel: NSPanel, onBottomOf screen: NSScreen?) {
        guard let frame = screen?.frame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: frame.midX - size.width / 2, y: frame.minY + 40))
    }
}

private final class PrototypeCount: ObservableObject {
    @Published var clicks = 0
}

private struct PrototypeView: View {
    @StateObject private var count = PrototypeCount()

    var body: some View {
        VStack(spacing: 10) {
            Text("Prototype window")
                .font(.system(size: 14, weight: .semibold))
            Button("Clicked \(count.clicks) times") { count.clicks += 1 }
        }
        .foregroundColor(.white)
        .frame(width: 260, height: 110)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.7)))
    }
}

/// A hosting view that acts on the very first click. These panels never
/// become the active window, and without this a click would only be
/// swallowed as "activate the window".
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
