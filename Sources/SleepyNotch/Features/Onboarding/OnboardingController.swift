import AppKit
import SwiftUI

/// The first-launch setup window. It shows once: from the moment it first
/// appears that is remembered, and every later launch (restarts and
/// shutdowns included) goes straight to the hello. Settings -> General -> Show Setup Again and the Feature
/// Lab bring it back by hand.
///
/// For a demo that changes nothing, launch with `SLEEPY_ONBOARDING=demo`:
/// it shows whatever happened before, and ending it isn't remembered.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let doneKey = "onboarding.completed"

    private let preferences: HUDPreferences
    private let permissions: OnboardingPermissions
    private let defaults: UserDefaults
    private var window: NSWindow?
    private var model: OnboardingModel?
    private var finishing = false
    /// Runs when the setup ends: the hello, and what waited for it.
    var onFinish: () -> Void = {}

    init(
        preferences: HUDPreferences,
        glance: CalendarGlance,
        accessibility: AccessibilityAccess,
        defaults: UserDefaults = .standard
    ) {
        self.preferences = preferences
        self.permissions = OnboardingPermissions(glance: glance, access: accessibility)
        self.defaults = defaults
    }

    private static var demoMode: Bool {
        ProcessInfo.processInfo.environment["SLEEPY_ONBOARDING"] == "demo"
    }

    /// Whether this launch opens with the setup.
    var isNeeded: Bool {
        Self.demoMode || !defaults.bool(forKey: Self.doneKey)
    }

    var isShowing: Bool { window != nil }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        finishing = false
        // Remembered the moment it first shows, not when it ends: quitting
        // with the window open, the Mac shutting down or restarting (which
        // quits apps without closing their windows), or a crash never reach
        // `windowWillClose`, and the setup came back on every launch after.
        // Its choices are saved as they're made, and Settings -> General ->
        // Show Setup brings it back by hand.
        markDone()
        let model = OnboardingModel(preferences: preferences, permissions: permissions)
        model.onFinish = { [weak self] in self?.finish() }
        self.model = model

        let hosting = NSHostingView(rootView: OnboardingView(model: model))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The desktop shows through, frosted, under a dark tint (the
        // view's own background), like a Mac's setup screens.
        let frost = NSVisualEffectView(frame: NSRect(origin: .zero, size: OnboardingView.size))
        frost.material = .hudWindow
        frost.blendingMode = .behindWindow
        frost.state = .active
        frost.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = frost.bounds
        hosting.autoresizingMask = [.width, .height]
        frost.addSubview(hosting)
        window.contentView = frost
        window.title = "Welcome to Sleepy Notch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            window.animator().alphaValue = 1
        }
        Bench.onboarding(window: window, model: model)
    }

    // MARK: - Ending

    /// Start was clicked: the window fades, then the notch says hello.
    private func finish() {
        guard !finishing, let window else { return }
        finishing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.window?.close() }
        })
    }

    func windowWillClose(_ notification: Notification) {
        model?.saveName()
        markDone()
        window?.delegate = nil
        window = nil
        model = nil
        // Back to the menu bar, a turn later so the window finishes closing.
        DispatchQueue.main.async { [onFinish] in
            NSApp.setActivationPolicy(.accessory)
            onFinish()
        }
    }

    /// The setup has been seen: later launches go straight to the hello.
    /// A demo run (`SLEEPY_ONBOARDING=demo`) changes nothing.
    private func markDone() {
        guard !Self.demoMode, !defaults.bool(forKey: Self.doneKey) else { return }
        defaults.set(true, forKey: Self.doneKey)
    }

    /// Forgets that the setup was done, so the next launch shows it.
    func forget() {
        defaults.removeObject(forKey: Self.doneKey)
    }
}
