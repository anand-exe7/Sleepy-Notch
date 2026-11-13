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
    private let power: PowerStateMonitor
    private let preferences: HUDPreferences
    private let state = LockScreenCardState()

    private var lockedPanel: NSPanel?
    private var space: SkyLightSpace?
    private var previewPanel: NSPanel?
    private let artModel = LockScreenArtModel()
    private let upNext: UpNextService
    private var observers: [NSObjectProtocol] = []
    private var cancellable: AnyCancellable?
    private var artCancellable: AnyCancellable?

    private static let locked = Notification.Name("com.apple.screenIsLocked")
    private static let unlocked = Notification.Name("com.apple.screenIsUnlocked")

    init(media: PlaybackCoordinator, power: PowerStateMonitor, preferences: HUDPreferences, upNext: UpNextService) {
        self.upNext = upNext
        self.media = media
        self.power = power
        self.preferences = preferences
        cancellable = preferences.$lockScreenCard
            .removeDuplicates()
            .sink { [weak self] on in
                if on { self?.startObserving() } else { self?.stopObserving() }
            }
        artCancellable = state.$showsArt
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] shows in
                if shows { self?.showArt() } else { self?.hideArt() }
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
        state.isExpanded = false
        state.showsArt = false
        let panel = makePanel(level: .statusBar)
        place(panel, onBottomOf: NSScreen.main)
        panel.orderFrontRegardless()
        space.add(panel)
        self.space = space
        lockedPanel = panel
    }

    private func screenUnlocked() {
        state.showsArt = false
        removeArtPanel()
        space?.hide()
        lockedPanel?.orderOut(nil)
        lockedPanel = nil
        space = nil
    }

    // MARK: - Preview

    /// The card in an ordinary window, for seeing it without locking.
    func showPreview() {
        previewPanel?.orderOut(nil)
        state.isExpanded = false
        state.showsArt = false
        let panel = makePanel(level: .floating)
        panel.isMovableByWindowBackground = true
        place(panel, onBottomOf: NSScreen.main)
        panel.makeKeyAndOrderFront(nil)
        previewPanel = panel
    }

    func closePreview() {
        state.showsArt = false
        removeArtPanel()
        previewPanel?.orderOut(nil)
        previewPanel = nil
    }

    // MARK: - Full-screen art

    /// The window the card lives in: on the lock screen, or the preview.
    private var cardPanel: LockScreenPanel? { (lockedPanel ?? previewPanel) as? LockScreenPanel }
    /// The card's view and frame while the art borrows its window.
    private var savedCard: (view: NSView?, frame: CGRect)?

    /// Fills the screen with the art. It reuses the card's own window rather
    /// than opening another: on the lock screen a second window didn't get
    /// the clicks, so there was no way back. The window also takes the
    /// keyboard while the art shows, so Esc (or any key) goes back.
    private func showArt() {
        guard savedCard == nil, let panel = cardPanel, let screen = panel.screen ?? NSScreen.main else { return }
        savedCard = (panel.contentView, panel.frame)
        artModel.reset()
        panel.contentView = FirstClickHostingView(rootView: LockScreenArtView(
            media: media, power: power, state: state, preferences: preferences,
            model: artModel, upNext: upNext, screenSize: screen.frame.size
        ))
        panel.setFrame(screen.frame, display: true)
        panel.takesKeyboard = true
        panel.onCancel = { [weak self] in self?.state.showsArt = false }
        panel.orderFrontRegardless()
        panel.makeKey()
        DispatchQueue.main.async { [artModel] in artModel.isShown = true }
    }

    /// Its pieces fall away, then the card comes back in its window.
    private func hideArt() {
        guard savedCard != nil else { return }
        artModel.isShown = false
        artModel.showsQueue = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.state.showsArt else { return }
            self.removeArtPanel()
        }
    }

    /// Puts the card back (dropping the art's view also stops its video).
    private func removeArtPanel() {
        guard let saved = savedCard else { return }
        savedCard = nil
        artModel.reset()
        guard let panel = cardPanel else { return }
        panel.takesKeyboard = false
        panel.onCancel = nil
        panel.resignKey()
        panel.contentView = saved.view
        panel.setFrame(saved.frame, display: true)
    }

    // MARK: - Windows

    private func makePanel(level: NSWindow.Level) -> NSPanel {
        let panel = LockScreenPanel(
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
        panel.contentView = FirstClickHostingView(rootView: LockScreenCardView(media: media, power: power, state: state, preferences: preferences))
        return panel
    }

    /// How far the card's bottom edge sits above the bottom of the screen:
    /// clear of the user's name and the password prompt.
    private static let bottomClearance: CGFloat = 240

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
