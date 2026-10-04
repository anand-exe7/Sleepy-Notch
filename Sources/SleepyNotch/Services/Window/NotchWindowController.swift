import AppKit
import SwiftUI

@MainActor
public final class NotchWindowController: NSObject, ObservableObject {
    public static let shared = NotchWindowController()

    /// Published so `NotchView` re-renders on display changes. This is what
    /// keeps a pinned HUD pinned: previously the screen-change handler replaced
    /// the entire `NSHostingView`, which tore down the `@StateObject` holding
    /// the hover/pin state and silently unpinned the card.
    @Published private(set) var geometry: DisplayGeometry = .fallback

    private var window: NSPanel?
    private var hitView: NotchHitView?
    private var screenChangeObserver: Any?
    private var occlusionObserver: Any?

    public override init() {
        super.init()
        geometry = NotchGeometryProvider.current()
        setupWindow()
        observeScreenChanges()
        observeOcclusion()
    }

    // MARK: - Window Setup

    private func setupWindow() {
        let size = geometry.panelSize

        let panel = NSPanel(
            contentRect: geometry.panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        // The hit-test container clips where the panel accepts mouse events to
        // the visible notch or pill, so the surplus transparent area never
        // shadows the menu bar underneath.
        let host = NotchHitView(frame: NSRect(origin: .zero, size: size))
        host.geometry = geometry
        let hostingView = NSHostingView(rootView: NotchView(windowController: self))
        hostingView.frame = host.bounds
        hostingView.autoresizingMask = [.width, .height]
        host.addSubview(hostingView)

        panel.contentView = host

        panel.orderFrontRegardless()
        self.window = panel
        self.hitView = host
    }

    // MARK: - Visibility

    /// Occlusion covers every way the HUD stops being seen — hidden from the
    /// menu, covered, or on a display that went to sleep — so animations and
    /// timers can stop rather than drawing frames nobody sees.
    private func observeOcclusion() {
        guard let panel = window else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reportVisibility()
            }
        }
        // No initial read: right after `orderFrontRegardless` the window server
        // may not have computed occlusion yet, and a premature "not visible"
        // would freeze the HUD. The monitor defaults to visible, and the first
        // real change arrives as a notification.
    }

    private func reportVisibility() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        PowerStateMonitor.shared.setWindowVisible(visible)
    }

    // MARK: - Screen Changes

    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenChange()
            }
        }
    }

    private func handleScreenChange() {
        let updated = NotchGeometryProvider.current()
        guard updated != geometry else { return }

        geometry = updated

        guard let panel = window, let host = hitView else { return }
        panel.setFrame(updated.panelFrame, display: true)
        host.geometry = updated
        host.frame = NSRect(origin: .zero, size: updated.panelSize)
        host.subviews.first?.frame = host.bounds
        panel.orderFrontRegardless()
    }

    /// Tells the hit-test layer which region is interactive. Driven by the same
    /// expansion state the SwiftUI layer uses, so hit testing and the visible
    /// card can never disagree.
    public func setCollapsed(_ collapsed: Bool) {
        hitView?.isNotchCollapsed = collapsed
    }

    public func toggleVisibility() {
        guard let window = self.window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}
