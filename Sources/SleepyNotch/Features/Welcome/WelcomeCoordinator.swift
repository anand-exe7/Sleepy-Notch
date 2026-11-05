import Foundation
import Combine

/// Says hello from the notch every time the app opens, once someone can see
/// the notch, before anything else: until it has played, the notch holds
/// everything else back (the wings, the bubbles, other peeks), and what
/// happened meanwhile follows it in order.
///
/// The welcome is a peek, so `PeekCenter` keeps it from overlapping the card
/// or another peek. Everything here is one-shot: a subscription that waits
/// for the notch to be visible, and a single delayed attempt. Once the
/// welcome has shown (or isn't due) nothing is left running.
@MainActor
final class WelcomeCoordinator {
    private let peeks: PeekCenter
    private let power: PowerStateMonitor
    private let preferences: HUDPreferences
    private let window: NotchWindowController
    private let defaults: UserDefaults
    private let bootSession: () -> String?

    private var boot: String?
    private var posted = false
    private var attempt: DispatchWorkItem?
    private var missionControlChecks = 0
    private var cancellables = Set<AnyCancellable>()

    static let defaultsKey = "welcome.lastBootSession"
    /// After login the desktop, menu bar and login items are still settling;
    /// waiting a moment lets the welcome arrive into a calm screen. Also the
    /// pause after unlocking, if the screen was locked at launch.
    private static let settleDelay: TimeInterval = 1.6
    /// Mission Control was open: look again this much later.
    private static let missionControlRecheck: TimeInterval = 1.0
    /// Gives up waiting on Mission Control after about a minute.
    private static let maxMissionControlChecks = 60

    init(
        peeks: PeekCenter,
        power: PowerStateMonitor,
        preferences: HUDPreferences,
        window: NotchWindowController,
        defaults: UserDefaults = .standard,
        bootSession: @escaping () -> String? = BootSession.current
    ) {
        self.peeks = peeks
        self.power = power
        self.preferences = preferences
        self.window = window
        self.defaults = defaults
        self.bootSession = bootSession
    }

    /// Called once, when the app has finished launching.
    func start() {
        guard preferences.welcomeAtStartup else { return }
        boot = bootSession()
        peeks.holdForWelcome()

        // Done as soon as the welcome is on screen.
        peeks.$current
            .sink { [weak self] peek in
                if peek?.content == .welcome { self?.didShow() }
            }
            .store(in: &cancellables)

        // Locked, asleep or another user: wait until the desktop is back.
        power.$isNotchVisible
            .removeDuplicates()
            .sink { [weak self] visible in self?.visibilityChanged(visible) }
            .store(in: &cancellables)
    }

    private func visibilityChanged(_ visible: Bool) {
        attempt?.cancel()
        guard visible, !posted else { return }
        schedule(after: Self.settleDelay)
    }

    private func schedule(after delay: TimeInterval) {
        attempt?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.present() }
        attempt = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func present() {
        guard !posted, power.isNotchVisible else { return }
        // The HUD hides in Mission Control, and there's no notification for
        // it closing: look again a moment later.
        if window.isMissionControlOpen() {
            missionControlChecks += 1
            if missionControlChecks < Self.maxMissionControlChecks {
                schedule(after: Self.missionControlRecheck)
            } else {
                peeks.releaseWelcomeHold()
            }
            return
        }
        posted = true
        peeks.post(.welcome)
    }

    /// Plays the welcome now, whatever the startup (Settings' Preview
    /// button). Doesn't count as this startup's welcome.
    func preview() {
        peeks.post(.welcome)
    }

    private func didShow() {
        if let boot { defaults.set(boot, forKey: Self.defaultsKey) }
        stop()
    }

    private func stop() {
        attempt?.cancel()
        attempt = nil
        cancellables.removeAll()
    }
}

extension WelcomeCoordinator {
    /// Forgets that this startup was welcomed, so the next launch shows it.
    func forgetThisStartup() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
