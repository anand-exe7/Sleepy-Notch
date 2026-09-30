import AppKit
import SwiftUI

@MainActor
public final class NotchWindowController: NSObject, ObservableObject {
    public static let shared = NotchWindowController()

    private var window: NSPanel?
    private var hitView: NotchHitView?
    private var screenChangeObserver: Any?

    private var metrics: NotchMetrics = .fallback
    private var notchCenterX: CGFloat = 735.5
    private var screenMaxY: CGFloat = 956

    public override init() {
        super.init()
        detectNotchGeometry()
        setupWindow()
        observeScreenChanges()
    }

    // MARK: - Notch Geometry Detection

    private func detectNotchGeometry() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           left.width > 0, right.width > 0 {
            let width = right.minX - left.maxX
            let height = screen.frame.maxY - left.minY
            metrics = NotchMetrics(notchWidth: width, notchHeight: height)
            notchCenterX = left.maxX + width / 2
        } else {
            // No physical notch on this display. Keep the 13" defaults; Phase D
            // adds a proper floating-pill fallback for this case.
            metrics = .fallback
            notchCenterX = screen.frame.width / 2
        }
        screenMaxY = screen.frame.maxY
    }

    // MARK: - Window Setup

    private func setupWindow() {
        // The panel is allocated its full expanded size once and never resized.
        // It's borderless and clear, and NotchView clips its content to the
        // notch shape, so the surplus area is invisible — and leaving it alone
        // means the SwiftUI spring is the only animation in play.
        let width = metrics.panelWidth
        let height = metrics.panelHeight

        let panel = NSPanel(
            contentRect: NSRect(
                x: notchCenterX - width / 2,
                y: screenMaxY - height,
                width: width,
                height: height
            ),
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
        // the visible notch silhouette, so the surplus transparent area never
        // shadows the menu bar underneath.
        let host = NotchHitView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        host.metrics = metrics
        let hostingView = NSHostingView(rootView: NotchView(metrics: metrics))
        hostingView.frame = host.bounds
        hostingView.autoresizingMask = [.width, .height]
        host.addSubview(hostingView)

        panel.contentView = host

        panel.orderFrontRegardless()
        self.window = panel
        self.hitView = host
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
        detectNotchGeometry()

        guard let panel = window, let host = hitView else { return }
        panel.setFrame(frameForPanel(), display: true)
        host.metrics = metrics
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        host.subviews.first?.frame = host.bounds
        panel.orderFrontRegardless()
    }

    private func frameForPanel() -> NSRect {
        NSRect(
            x: notchCenterX - metrics.panelWidth / 2,
            y: screenMaxY - metrics.panelHeight,
            width: metrics.panelWidth,
            height: metrics.panelHeight
        )
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
