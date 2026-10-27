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
final class KeyboardMonitor {
    var onEvent: ((KeyboardEvent) -> Void)?

    private var capsLockOn = NSEvent.modifierFlags.contains(.capsLock)
    private var inputSource = KeyboardMonitor.currentInputSourceName()
    private var monitors: [Any] = []
    private var isStarted = false

    init() {}

    /// Whether macOS lets the app see Caps Lock in other apps.
    static var canSeeCapsLock: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt to allow Accessibility access. The person
    /// decides in System Settings.
    static func requestCapsLockAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            let on = event.modifierFlags.contains(.capsLock)
            Task { @MainActor [weak self] in self?.capsLockChanged(on) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.capsLockChanged(event.modifierFlags.contains(.capsLock))
            return event
        }) {
            monitors.append(local)
        }

        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.inputSourceChanged() }
        }
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
