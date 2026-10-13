import AppKit
import SwiftUI

/// Owns the floating panel the HUD lives in: places it over the notch,
/// keeps it there across display changes, limits where it takes clicks, and
/// reports when it can't be seen. It hosts whatever view it's given — the
/// app decides what that is (see `AppEnvironment`).
@MainActor
final class NotchWindowController: NSObject, ObservableObject {
    /// Published so `NotchView` re-renders on display changes. Previously the
    /// screen-change handler replaced the entire `NSHostingView`, which tore
    /// down the `@StateObject` holding the hover state and reset the card.
    @Published private(set) var geometry: DisplayGeometry = .fallback
    /// Whether the menu bar is drawn dark, which decides where the open
    /// notch's top corners flare (see `NotchShape.shoulder`).
    @Published private(set) var menuBarIsDark = true

    private var window: NSPanel?
    private var hitView: NotchHitView?
    private var screenChangeObserver: Any?
    private var occlusionObserver: Any?
    private let power: PowerStateMonitor

    /// - Parameter content: the HUD's root view. Handed the controller so it
    ///   can read geometry and keep the hit area in step with what's drawn.
    init<Content: View>(power: PowerStateMonitor, content: (NotchWindowController) -> Content) {
        self.power = power
        super.init()
        geometry = NotchGeometryProvider.current()
        setupWindow(rootView: content(self))
        observeScreenChanges()
        observeOcclusion()
    }

    // MARK: - Window Setup

    private func setupWindow<Content: View>(rootView: Content) {
        let size = geometry.panelSize

        let panel = NSPanel(
            contentRect: geometry.panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        // `.stationary` keeps the HUD fixed while you swipe between desktops
        // or open Mission Control, instead of sliding away with the old
        // desktop and popping back in on the new one.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
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
        let hostingView = NSHostingView(rootView: rootView)
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
        power.setWindowVisible(visible)
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

    func setMenuBarIsDark(_ dark: Bool) {
        if dark != menuBarIsDark { menuBarIsDark = dark }
    }

    /// Tells the hit-test layer which region is interactive. Driven by the same
    /// expansion state the SwiftUI layer uses, so hit testing and the visible
    /// card can never disagree.
    func setCollapsed(_ collapsed: Bool) {
        hitView?.isNotchCollapsed = collapsed
    }


    /// Whether the cursor is over the panel right now. Used once after a file
    /// drag ends, since hover events don't arrive during a drag.
    func isCursorOverPanel() -> Bool {
        guard let window, window.isVisible else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    func toggleVisibility() {
        guard let window = self.window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}
