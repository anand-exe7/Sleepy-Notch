import AppKit
import ApplicationServices
import Carbon

/// Reports Caps Lock turning on or off, and the keyboard layout changing.
///
/// The layout comes from a system broadcast and needs no permission.
/// Caps Lock is a modifier-key event from other apps, which macOS only
/// delivers once the app is allowed Accessibility access (`canSeeCapsLock`);
/// until then the monitor is simply silent. Nothing is polled.
@MainActor
final class KeyboardMonitor: ObservableObject {
    var onEvent: ((KeyboardEvent) -> Void)?

    /// Whether macOS lets the app see Caps Lock in other apps. Kept up to
    /// date, so the Settings window can offer to fix it.
    @Published private(set) var canSeeCapsLock = AXIsProcessTrusted()

    private var capsLockOn = NSEvent.modifierFlags.contains(.capsLock)
    private var inputSource = KeyboardMonitor.currentInputSourceName()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isStarted = false

    init() {}

    /// Shows macOS's own prompt to allow Accessibility access. The person
    /// decides in System Settings.
    static func requestCapsLockAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        installGlobalMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.capsLockChanged(event.modifierFlags.contains(.capsLock))
            return event
        }

        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.inputSourceChanged() }
        }

        // Broadcast when any app's Accessibility access changes. The new
        // answer can lag the broadcast slightly, hence the short wait.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.accessibilityAccessChanged()
            }
        }
    }

    /// A monitor added before access was granted stays deaf, so it's
    /// replaced once access arrives.
    private func installGlobalMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let on = event.modifierFlags.contains(.capsLock)
            Task { @MainActor [weak self] in self?.capsLockChanged(on) }
        }
    }

    private func accessibilityAccessChanged() {
        let trusted = AXIsProcessTrusted()
        guard trusted != canSeeCapsLock else { return }
        canSeeCapsLock = trusted
        if trusted, isStarted { installGlobalMonitor() }
    }

    private func capsLockChanged(_ on: Bool) {
        guard on != capsLockOn else { return }
        capsLockOn = on
        onEvent?(.capsLock(isOn: on))
    }

    private func inputSourceChanged() {
        guard let name = Self.currentInputSourceName(), name != inputSource else { return }
        inputSource = name
        onEvent?(.inputSource(name: name))
    }

    private static func currentInputSourceName() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
