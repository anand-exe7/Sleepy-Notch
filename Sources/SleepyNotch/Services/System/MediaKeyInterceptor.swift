import AppKit
import CoreGraphics

/// Takes over the volume, brightness and keyboard backlight keys, so macOS's
/// own pop-ups never appear and the notch's HUD is the only one.
///
/// macOS has no switch for its pop-ups, and the helper that draws them is
/// protected, so the one clean way is to receive the keys first. A session
/// event tap (which needs Accessibility) sees each media key before the
/// system; for the keys it handles it makes the change itself, through
/// `SystemLevels`, and consumes the key. The change fires the same listeners
/// as before, so the HUD shows exactly as it did. The tap is event-driven:
/// it runs only when a key is pressed.
///
/// Safe by construction:
/// - a key is only consumed if the change was actually made, otherwise it is
///   passed on and macOS handles it as usual (an HDMI output with no volume
///   control, say);
/// - it is only installed while on, allowed and the notch is visible, so the
///   lock screen and a sleeping display always get their keys;
/// - if the app quits or crashes the tap goes with it and the keys are the
///   system's again at once.
@MainActor
final class MediaKeyInterceptor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var isRunning = false

    /// A key press changes a level by this much; Shift+Option changes it by
    /// a quarter of it, as the system does.
    static let step = 1.0 / 16
    static let fineStep = step / 4

    // NX_KEYTYPE_*
    private enum Key: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
        case illuminationUp = 21, illuminationDown = 22
    }

    func setRunning(_ on: Bool) {
        guard on != isRunning else { return }
        isRunning = on
        on ? install() : remove()
    }

    // MARK: - The tap

    private func install() {
        guard tap == nil else { return }
        let mask: CGEventMask = 1 << 14 // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated { interceptor.receive(type: type, event: event) }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // No Accessibility yet: stay off.
            isRunning = false
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func remove() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system turns a tap off if it's too slow or while something
        // secure is in front: switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let code = (ns.data1 & 0xFFFF_0000) >> 16
        let flags = ns.data1 & 0x0000_FFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0xA
        guard let key = Key(rawValue: code) else { return Unmanaged.passUnretained(event) }
        let fine = event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)
        // The release goes the same way as the press did: if the press was
        // handled, so is the release.
        if !isDown { return handled.contains(code) ? nil : Unmanaged.passUnretained(event) }
        if apply(key, fine: fine) {
            handled.insert(code)
            return nil
        }
        handled.remove(code)
        return Unmanaged.passUnretained(event)
    }

    private var handled = Set<Int>()

    // MARK: - The change

    /// Makes the change for `key`; false if it couldn't, so the key goes on
    /// to the system.
    private func apply(_ key: Key, fine: Bool) -> Bool {
        let step = fine ? Self.fineStep : Self.step
        switch key {
        case .soundUp, .soundDown:
            guard let current = SystemLevels.volume() else { return false }
            let target = current + (key == .soundUp ? step : -step)
            // Turning it up from mute un-mutes, like the system.
            if key == .soundUp, SystemLevels.isMuted() == true { SystemLevels.setMuted(false) }
            return SystemLevels.setVolume(target)
        case .mute:
            guard let muted = SystemLevels.isMuted() else { return false }
            return SystemLevels.setMuted(!muted)
        case .brightnessUp, .brightnessDown:
            guard let current = SystemLevels.brightness() else { return false }
            return SystemLevels.setBrightness(current + (key == .brightnessUp ? step : -step))
        case .illuminationUp, .illuminationDown:
            guard let current = SystemLevels.keyboardBacklight() else { return false }
            return SystemLevels.setKeyboardBacklight(current + (key == .illuminationUp ? step : -step))
        }
    }
}
