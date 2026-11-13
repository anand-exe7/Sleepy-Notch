import AppKit
import SwiftUI

/// Owns the floating panel the HUD lives in: places it over the notch,
/// keeps it there across display changes, limits where it takes clicks, and
/// reports when it can't be seen. It hosts whatever view it's given — the
/// app decides what that is (see `AppEnvironment`).
@MainActor
final class NotchWindowController: NSObject, ObservableObject {
    /// Published so `NotchView` re-renders on display changes. The hosting
    /// view is kept rather than replaced, which would tear down the hover
    /// state and reset the card.
    @Published private(set) var geometry: DisplayGeometry = .fallback
    /// The pointer is over what the HUD is drawing (see `NotchHitView`).
    @Published private(set) var isPointerInside = false

    private var window: NSPanel?
    private var hitView: NotchHitView?
    private var screenChangeObserver: Any?
    private var occlusionObserver: Any?
    private var mouseMonitors: [Any] = []
    /// Called for every pointer event anywhere (move, drag, click, scroll), so
    /// other services can tell the user is around without a monitor of their own.
    var onPointerActivity: (() -> Void)?
    private var hiddenForMissionControl = false
    private var lastMissionControlCheck = Date.distantPast
    private var missionControlRecheck: DispatchWorkItem?
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
        observeMouse()
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
        // or open Mission Control. (`.transient` hid it from Mission Control
        // by parking it at the bottom of the screen, where a strip of it
        // showed.) The closed notch is pure black over the hardware notch,
        // so it's invisible there; hover is kept from opening the card over
        // Mission Control instead (see `updateMousePassThrough`).
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Starts click-through; `updateMousePassThrough` turns events on
        // only while the pointer is over what's drawn.
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        // The hit-test container clips where the panel accepts mouse events to
        // the visible notch or pill, so the surplus transparent area never
        // shadows the menu bar underneath.
        let host = NotchHitView(frame: NSRect(origin: .zero, size: size))
        host.interactiveSize = geometry.collapsedSize
        host.onPointerInsideChange = { [weak self] inside in
            self?.isPointerInside = inside
        }
        // Takes the first click even while another app is active; a plain
        // hosting view sometimes swallowed it, so a tab button "didn't work".
        let hostingView = FirstClickHostingView(rootView: rootView)
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

    /// Swiping between desktops or into a full-screen app hides the panel
    /// for a moment. Reporting that at once tucked the wings into the notch
    /// and stopped and restarted everything (the mic listener among them),
    /// so the notch came back slowly after every switch. Visible is reported
    /// at once; hidden only once it has lasted. Locking and display sleep
    /// have their own notifications and still stop everything immediately.
    private static let hiddenGrace: TimeInterval = 1.0
    private var pendingHidden: DispatchWorkItem?

    private func reportVisibility() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        pendingHidden?.cancel()
        pendingHidden = nil
        if visible {
            power.setWindowVisible(true)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.window?.occlusionState.contains(.visible) == false else { return }
                self.power.setWindowVisible(false)
            }
        }
        pendingHidden = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hiddenGrace, execute: work)
    }

    // MARK: - Click-through

    /// The panel is always the size of the open card, and an invisible
    /// window still takes clicks anywhere a tracking area covers it — so a
    /// window parked under the notch couldn't be clicked. Instead the panel
    /// ignores the mouse entirely, letting clicks fall through to whatever
    /// is below, except while the pointer is over the drawn HUD.
    ///
    /// While it ignores the mouse it gets no events of its own, so a global
    /// monitor watches the pointer (mouse events need no permission). Each
    /// event is one rectangle test.
    private func observeMouse() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel]
        // Monitors call back on the main thread, so the work runs right
        // there: no task per mouse event, which while the pointer moves is
        // over a hundred a second. The event already carries where the
        // pointer is (in screen coordinates, as it belongs to no window of
        // ours); asking `NSEvent.mouseLocation` instead was a round trip to
        // the window server on every one of them.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let location = event.locationInWindow
                self.onPointerActivity?()
                self.checkMissionControl(pointerAt: location)
                self.updateMousePassThrough(pointerAt: location)
            }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            let location = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) }
                ?? event.locationInWindow
            self?.updateMousePassThrough(pointerAt: location)
            return event
        }) {
            mouseMonitors.append(local)
        }
        updateMousePassThrough()
    }

    /// - Parameter location: where the pointer is, in screen coordinates;
    ///   read from the window server when the caller has no event in hand.
    private func updateMousePassThrough(pointerAt location: NSPoint? = nil) {
        guard let panel = window, let hitView else { return }
        let point = hitView.convert(panel.convertPoint(fromScreen: location ?? NSEvent.mouseLocation), from: nil)
        var inside = panel.isVisible && !hiddenForMissionControl && hitView.acceptsMouse(at: point)
        guard panel.ignoresMouseEvents == inside else { return }
        // Reaching for the Spaces bar in Mission Control shouldn't open the
        // card over it. Checked only as the pointer arrives on the notch.
        if inside, MissionControl.isOpen(on: panel.screen) { inside = false }
        guard panel.ignoresMouseEvents == inside else { return }
        panel.ignoresMouseEvents = !inside
        // The pointer crossed the edge while the panel wasn't listening, so
        // no enter or exit event comes: settle hover from where it is.
        hitView.refreshPointer()
    }

    // MARK: - Mission Control

    /// Hides the HUD while Mission Control is open. macOS's own way —
    /// `.transient` — parks the window at the bottom of the screen, where a
    /// strip of it shows, and there's no notification for Mission Control
    /// opening. So it's checked here, as the pointer moves (at most a couple
    /// of times a second), and only while the HUD shows more than the bare
    /// notch: that's pure black over the hardware notch, invisible anyway.
    /// While hidden, a one-shot re-check runs until Mission Control closes.
    /// Reading the window list is a round trip to the window server that
    /// lists every window, so it's paced by where the pointer is: close to
    /// the top of the screen, where Mission Control's Spaces bar sits and
    /// the HUD could be reached, every 0.4 s; anywhere lower, where it
    /// would only hide the wings a moment later, every 1.5 s.
    private static let missionControlCheckNearTop: TimeInterval = 0.4
    private static let missionControlCheckElsewhere: TimeInterval = 1.5
    private static let topBand: CGFloat = 200

    private func checkMissionControl(force: Bool = false, pointerAt location: NSPoint? = nil) {
        guard let panel = window, let hitView else { return }
        if !hiddenForMissionControl {
            guard hitView.interactiveSize != geometry.collapsedSize else { return }
            let nearTop = location.map { $0.y >= (panel.screen?.frame.maxY ?? .infinity) - Self.topBand } ?? true
            let interval = nearTop ? Self.missionControlCheckNearTop : Self.missionControlCheckElsewhere
            guard force || Date().timeIntervalSince(lastMissionControlCheck) > interval else { return }
        }
        guard !missionControlCheckPending else { return }
        lastMissionControlCheck = Date()
        missionControlCheckPending = true
        // Off the main thread: a forced check comes as the card starts to
        // open, and waiting on the window server there held its first frame.
        let screen = panel.screen
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let open = MissionControl.isOpen(on: screen)
            DispatchQueue.main.async {
                guard let self else { return }
                self.missionControlCheckPending = false
                self.setHiddenForMissionControl(open)
            }
        }
    }

    private var missionControlCheckPending = false

    /// One look at whether Mission Control is open on the HUD's screen.
    func isMissionControlOpen() -> Bool {
        hiddenForMissionControl || MissionControl.isOpen(on: window?.screen)
    }

    private func setHiddenForMissionControl(_ hidden: Bool) {
        missionControlRecheck?.cancel()
        if hidden {
            let work = DispatchWorkItem { [weak self] in self?.checkMissionControl(force: true) }
            missionControlRecheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
        guard hidden != hiddenForMissionControl, let panel = window else { return }
        hiddenForMissionControl = hidden
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hidden ? 0.12 : 0.2
            panel.animator().alphaValue = hidden ? 0 : 1
        }
        updateMousePassThrough()
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
        host.frame = NSRect(origin: .zero, size: updated.panelSize)
        host.subviews.first?.frame = host.bounds
        panel.orderFrontRegardless()
    }

    /// Tells the hit-test and hover layer the size of what's drawn. Driven by
    /// the same layout the SwiftUI layer draws, so clicks, hover and the
    /// visible HUD can never disagree.
    func setInteractiveSize(_ size: CGSize) {
        guard let hitView else { return }
        let old = hitView.interactiveSize
        hitView.interactiveSize = size
        // Something more is about to show — a peek, the wings, the card —
        // perhaps over Mission Control. Only checked as it grows: reading
        // the window list is a round trip to the window server, too much to
        // repeat on every open and close.
        if size.width > old.width || size.height > old.height {
            checkMissionControl(force: true)
        }
        updateMousePassThrough()
    }

    /// Whether the cursor is over the drawn HUD right now. Used once after a
    /// file drag ends, since hover events don't arrive during a drag, and
    /// after switching desktops.
    /// Where the bubbles beside the notch rest, in the panel's top-left
    /// coordinates, so they take clicks.
    func setBubbleRects(_ rects: [CGRect]) {
        guard let hitView else { return }
        let flipped = rects.map {
            CGRect(x: $0.minX, y: hitView.bounds.height - $0.maxY, width: $0.width, height: $0.height)
        }
        guard flipped != hitView.bubbleRects else { return }
        hitView.bubbleRects = flipped
        updateMousePassThrough()
    }

    /// Development only (see `Bench`): pretends the pointer is on or off
    /// the HUD, so the card can be driven without Accessibility.
    func benchSetPointerInside(_ inside: Bool) {
        hitView?.pointerOverride = inside
        hitView?.refreshPointer()
    }

    /// Development only (see `Bench`): the panel's number and screen frame.
    func benchWindow() -> (number: Int, frame: CGRect)? {
        guard let window else { return nil }
        return (window.windowNumber, window.frame)
    }

    func isCursorOverHUD() -> Bool {
        guard let window, window.isVisible, let hitView else { return false }
        return hitView.refreshPointer()
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
