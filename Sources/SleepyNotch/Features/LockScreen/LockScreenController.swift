import AppKit
import SwiftUI
import Combine

/// Puts the Now Playing card above the lock screen while the Mac is locked,
/// and offers the same card in an ordinary window for previewing it.
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

    // MARK: - Preview

    /// The card in an ordinary window, for seeing it without locking.
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

    /// How far the card's bottom edge sits above the bottom of the screen:
    /// clear of the user's name and the password prompt.
    private static let bottomClearance: CGFloat = 170

    /// Centred, above the name and password prompt, so it grows upward
    /// toward the clock without covering them.
    private func place(_ panel: NSPanel, onBottomOf screen: NSScreen?) {
        guard let frame = screen?.frame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + Self.bottomClearance - LockScreenCardView.margin
        ))
    }
}

/// A hosting view that acts on the very first click. These panels never
/// become the active window, and without this a click would only be
/// swallowed as "activate the window".
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
