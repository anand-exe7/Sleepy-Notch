import AppKit

/// The quick toggles on the Controls tab: Dark Mode, Mute and Wi-Fi (Stay
/// Awake is its own service). Each is read when the tab opens, and Dark Mode
/// also follows the system's own notification when it changes, so nothing is
/// polled.
@MainActor
final class ControlsService: ObservableObject {
    @Published private(set) var darkMode = false
    @Published private(set) var muted = false
    /// nil when this Mac has no Wi-Fi to switch.
    @Published private(set) var wifiOn: Bool?
    /// Says what went wrong, for the notice.
    var onProblem: ((String) -> Void)?

    private var wifiDevice: String?
    private var observer: NSObjectProtocol?

    init() {
        darkMode = Self.systemIsDark()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.darkMode = Self.systemIsDark() }
        }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    nonisolated static func systemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Reads the state that isn't pushed to us: called when the tab opens.
    func refresh() {
        muted = SystemLevels.isMuted() ?? false
        darkMode = Self.systemIsDark()
        Task { await readWifi() }
    }

    // MARK: - Dark Mode

    func toggleDarkMode() {
        let target = !darkMode
        darkMode = target
        Task {
            let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(target)"
            do { _ = try await AppleScriptRunner.shared.run(script) } catch {
                darkMode = !target
                onProblem?(error is AppleScriptFailure && (error as? AppleScriptFailure)?.isFixedInSystemSettings == true
                    ? "Allow Sleepy Notch to control System Events in Privacy & Security > Automation"
                    : "Couldn't change the appearance")
            }
        }
    }

    // MARK: - Mute

    func toggleMute() {
        guard SystemLevels.setMuted(!muted) else { return onProblem?("This output can't be muted") ?? () }
        muted.toggle()
    }

    // MARK: - Wi-Fi

    func toggleWifi() {
        guard let device = wifiDevice, let on = wifiOn else { return }
        wifiOn = !on
        Task {
            let ok = await Self.networksetup(["-setairportpower", device, on ? "off" : "on"]) != nil
            if !ok { wifiOn = on; onProblem?("Couldn't change Wi-Fi") }
            await readWifi()
        }
    }

    private func readWifi() async {
        if wifiDevice == nil { wifiDevice = await Self.findWifiDevice() }
        guard let device = wifiDevice else { wifiOn = nil; return }
        let text = await Self.networksetup(["-getairportpower", device]) ?? ""
        wifiOn = text.lowercased().contains(": on")
    }

    private static func findWifiDevice() async -> String? {
        guard let text = await networksetup(["-listallhardwareports"]) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        guard let port = lines.firstIndex(where: { $0.contains("Hardware Port: Wi-Fi") }) else { return nil }
        return lines.dropFirst(port + 1).prefix(3)
            .first { $0.hasPrefix("Device:") }
            .map { $0.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces) }
    }

    /// Runs `networksetup` off the main thread; nil if it failed.
    private nonisolated static func networksetup(_ arguments: [String]) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        }.value
    }
}
