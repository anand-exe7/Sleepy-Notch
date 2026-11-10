import Foundation
import CoreAudio
import CoreGraphics
import ObjectiveC

/// Reads and sets the system volume, the screen brightness and the keyboard
/// backlight: what the volume and brightness keys change. Brightness and the
/// backlight go through private frameworks loaded at run time; a missing piece
/// just makes that one report that it can't.
enum SystemLevels {
    // MARK: - Volume

    private static let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663) // 'vmvc'

    private static func address(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func outputDevice() -> AudioDeviceID? {
        var a = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// Volume 0...1, or nil when the output has no main volume (some HDMI and
    /// USB devices).
    static func volume() -> Double? {
        guard let device = outputDevice() else { return nil }
        var a = address(virtualMainVolume)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &a),
              AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    @discardableResult
    static func setVolume(_ level: Double) -> Bool {
        guard let device = outputDevice() else { return false }
        var a = address(virtualMainVolume)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &a),
              AudioObjectIsPropertySettable(device, &a, &settable) == noErr, settable.boolValue else { return false }
        var value = Float32(min(1, max(0, level)))
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    static func isMuted() -> Bool? {
        guard let device = outputDevice() else { return nil }
        var a = address(kAudioDevicePropertyMute)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &a),
              AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = outputDevice() else { return false }
        var a = address(kAudioDevicePropertyMute)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &a),
              AudioObjectIsPropertySettable(device, &a, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    // MARK: - Brightness (DisplayServices)

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let displayServices: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
    )

    static func brightness() -> Double? {
        guard let symbol = displayServices.flatMap({ dlsym($0, "DisplayServicesGetBrightness") }) else { return nil }
        let get = unsafeBitCast(symbol, to: GetBrightness.self)
        var value: Float = 0
        return get(CGMainDisplayID(), &value) == 0 ? Double(value) : nil
    }

    @discardableResult
    static func setBrightness(_ level: Double) -> Bool {
        guard let symbol = displayServices.flatMap({ dlsym($0, "DisplayServicesSetBrightness") }) else { return false }
        let set = unsafeBitCast(symbol, to: SetBrightness.self)
        return set(CGMainDisplayID(), Float(min(1, max(0, level)))) == 0
    }

    // MARK: - Keyboard backlight (CoreBrightness)

    private typealias KeyboardGet = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KeyboardSet = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private static let keyboard: (client: NSObject, id: UInt64)? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let client = cls.init()
        let selector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: selector),
              let ids = client.perform(selector)?.takeRetainedValue() as? [NSNumber],
              let id = ids.first?.uint64Value else { return nil }
        return (client, id)
    }()

    static func keyboardBacklight() -> Double? {
        guard let keyboard else { return nil }
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard keyboard.client.responds(to: selector) else { return nil }
        let get = unsafeBitCast(keyboard.client.method(for: selector), to: KeyboardGet.self)
        return Double(get(keyboard.client, selector, keyboard.id))
    }

    @discardableResult
    static func setKeyboardBacklight(_ level: Double) -> Bool {
        guard let keyboard else { return false }
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard keyboard.client.responds(to: selector) else { return false }
        let set = unsafeBitCast(keyboard.client.method(for: selector), to: KeyboardSet.self)
        return set(keyboard.client, selector, Float(min(1, max(0, level))), keyboard.id)
    }
}
