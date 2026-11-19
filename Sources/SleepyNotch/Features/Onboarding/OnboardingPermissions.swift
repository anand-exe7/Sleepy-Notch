import AppKit
import AVFoundation
import Carbon
import EventKit

/// Where one permission stands, for the setup's last page.
enum PermissionState: Equatable {
    case notAsked
    case asking
    case allowed
    /// Turned down: only System Settings can change it now.
    case denied
    /// Music control with no music app open: macOS asks the first time a
    /// song is read.
    case later
}

/// The permissions the setup asks for at its end, in one place: Calendar,
/// the microphone, control of Music (Automation) and Accessibility. Each is
/// read when the last page opens and again when the app comes back to the
/// front (after System Settings); nothing is watched in between.
@MainActor
final class OnboardingPermissions: ObservableObject {
    @Published private(set) var calendar: PermissionState = .notAsked
    @Published private(set) var microphone: PermissionState = .notAsked
    @Published private(set) var music: PermissionState = .notAsked
    @Published private(set) var accessibility: PermissionState = .notAsked

    private let glance: CalendarGlance
    private let access: AccessibilityAccess
    private var observer: NSObjectProtocol?

    init(glance: CalendarGlance, access: AccessibilityAccess) {
        self.glance = glance
        self.access = access
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        calendar = Self.calendarState()
        microphone = Self.microphoneState()
        access.refresh()
        accessibility = access.isTrusted ? .allowed : (accessibility == .asking ? .asking : .notAsked)
        if music != .asking { readMusic(asking: false) }
    }

    // MARK: - Calendar

    private static func calendarState() -> PermissionState {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        default:
            if #available(macOS 14, *) { return status == .fullAccess ? .allowed : .denied }
            return status == .authorized ? .allowed : .denied
        }
    }

    func askCalendar() {
        guard calendar == .notAsked else { return SystemSettings.openCalendars() }
        calendar = .asking
        Task {
            await glance.requestAccess()
            let state = Self.calendarState()
            // Still undecided: macOS didn't show its prompt (an old answer
            // for a differently signed copy). System Settings it is.
            calendar = state == .notAsked ? .denied : state
        }
    }

    // MARK: - Microphone

    private static func microphoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .allowed
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    func askMicrophone() {
        guard microphone == .notAsked else { return Self.openPrivacy("Privacy_Microphone") }
        microphone = .asking
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { [weak self] in
                self?.microphone = Self.microphoneState()
            }
        }
    }

    // MARK: - Music (Automation)

    /// The music apps the card can control, by bundle id.
    private static let players = ["com.apple.Music", "com.spotify.client"]

    func askMusic() {
        switch music {
        case .denied: SystemSettings.openAutomation()
        case .notAsked: readMusic(asking: true)
        default: break
        }
    }

    /// Asks macOS whether this app may send Apple events to an open music
    /// app (and, when `asking`, lets macOS show its prompt). Off the main
    /// thread: the call waits for the user's answer.
    private func readMusic(asking: Bool) {
        let open = Self.players.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        guard !open.isEmpty else {
            music = .later
            return
        }
        if asking { music = .asking }
        DispatchQueue.global(qos: .userInitiated).async {
            let results = open.map { Self.automationStatus(bundle: $0, ask: asking) }
            let state: PermissionState
            if results.contains(noErr) {
                state = .allowed
            } else if results.contains(OSStatus(errAEEventNotPermitted)) {
                state = .denied
            } else {
                state = .notAsked
            }
            DispatchQueue.main.async { [weak self] in self?.music = state }
        }
    }

    private nonisolated static func automationStatus(bundle: String, ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let id = Array(bundle.utf8)
        let created = id.withUnsafeBufferPointer { buffer in
            AECreateDesc(typeApplicationBundleID, buffer.baseAddress, buffer.count, &target)
        }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
    }

    // MARK: - Accessibility

    func askAccessibility() {
        if accessibility == .asking {
            access.openSettings()
            return
        }
        accessibility = .asking
        access.request()
        if access.isTrusted { accessibility = .allowed }
    }

    private static func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
