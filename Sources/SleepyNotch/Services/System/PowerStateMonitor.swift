import AppKit
import Foundation

/// Answers "is anything we draw actually being seen, and is motion welcome?"
///
/// Every signal here is a system notification — nothing is polled. Views use
/// the two published flags to decide whether their timers and animations may
/// run at all:
///
/// - `isNotchVisible` is false while the display sleeps, the screen is locked,
///   another user session is active, or the notch window is off screen. Nobody
///   can see the HUD, so *everything* stops, including the progress clock.
/// - `allowsDecorativeMotion` additionally drops to false under Low Power Mode
///   or Reduce Motion. Purely decorative animation (waveform, marquee) stops;
///   information the user is looking at, like elapsed time, keeps updating.
@MainActor
final class PowerStateMonitor: ObservableObject {
    static let shared = PowerStateMonitor()

    @Published private(set) var isNotchVisible = true
    @Published private(set) var allowsDecorativeMotion = true

    private var displayAsleep = false
    private var screenLocked = false
    private var sessionInactive = false
    private var windowVisible = true
    private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private init() {
        observe()
        recompute()
    }

    /// Reported by the window controller from the panel's occlusion state, which
    /// covers the notch window being hidden, covered, or on a sleeping display.
    func setWindowVisible(_ visible: Bool) {
        windowVisible = visible
        recompute()
    }

    // MARK: - Observation

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        on(workspace, NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true }
        on(workspace, NSWorkspace.screensDidWakeNotification) { $0.displayAsleep = false }
        on(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        on(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        on(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) {
            $0.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        // Undocumented but long-stable: loginwindow broadcasts these on lock.
        let distributed = DistributedNotificationCenter.default()
        on(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        on(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }

        // Posted on an arbitrary thread; `on` hops back to the main actor.
        on(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) {
            $0.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func on(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        update: @escaping @MainActor (PowerStateMonitor) -> Void
    ) {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                update(self)
                self.recompute()
            }
        }
    }

    // MARK: - State

    private func recompute() {
        let visible = !displayAsleep && !screenLocked && !sessionInactive && windowVisible
        let motion = visible && !lowPowerMode && !reduceMotion
        // @Published fires on every assignment, so only assign on a real change
        // to avoid re-rendering the HUD for no reason.
        if visible != isNotchVisible { isNotchVisible = visible }
        if motion != allowsDecorativeMotion { allowsDecorativeMotion = motion }
    }
}
