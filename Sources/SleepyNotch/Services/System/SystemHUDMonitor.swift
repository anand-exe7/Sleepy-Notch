import Foundation
import CoreAudio
import CoreGraphics
import ObjectiveC

/// Tells the notch when the volume, the screen brightness or the keyboard
/// backlight changes, so it can show them the way macOS's own HUDs do.
///
/// Every source calls back on a change; nothing is polled.
/// - Volume: CoreAudio property listeners on the default output device (and
///   on the default device changing).
/// - Brightness: `DisplayServices`, a private framework, loaded with `dlsym`.
/// - Keyboard backlight: `CoreBrightness`'s `KeyboardBrightnessClient`, also
///   private and loaded at run time.
/// A private piece that isn't there on this macOS simply stays off.
///
/// Levels also change by themselves: the light sensor and the dimming
/// before sleep move the brightness, AirPods and other apps move the
/// volume. Like macOS's own pop-ups, only key presses are shown: a key
/// moves a level by exactly a sixteenth (a sixty-fourth with Shift-Option),
/// or to the end of the range, so any other change is ignored.
@MainActor
final class SystemHUDMonitor {
    /// Called with each reading worth showing.
    var onReading: ((HUDReading) -> Void)?

    private(set) var isRunning = false

    /// Smaller steps than this are the sensor's, not a key's (a key moves
    /// the level by a sixteenth, about 0.06).
    private static let keyStep = 0.04
    /// Quiet after starting and after switching devices, so initial values
    /// aren't announced.
    private var quietUntil = Date.distantPast

    // Volume
    private var outputDevice = AudioDeviceID(kAudioObjectUnknown)
    private var lastVolume: (level: Double, muted: Bool)?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    // Brightness
    private var lastBrightness: Double?
    private var brightnessRegistered = false

    // Keyboard backlight
    private var keyboardClient: NSObject?
    private var keyboardID: UInt64?
    private var lastKeyboard: Double?

    func setRunning(_ on: Bool) {
        guard on != isRunning else { return }
        isRunning = on
        if on { start() } else { stop() }
    }

    // MARK: - Start and stop

    private func start() {
        quietUntil = Date().addingTimeInterval(1.5)
        watchDefaultOutputDevice()
        bindOutputDevice()
        startBrightness()
        startKeyboard()
    }

    private func stop() {
        unbindOutputDevice()
        if let deviceListener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
        }
        deviceListener = nil
        stopBrightness()
        stopKeyboard()
        lastVolume = nil
        lastBrightness = nil
        lastKeyboard = nil
    }

    /// Whether going from `old` to `new` looks like volume or brightness
    /// keys: whole steps of 1/16 or 1/64 (up to four held-key repeats
    /// merged into one callback), or a short last step to 0 or 1.
    static func looksLikeKeyPress(from old: Double, to new: Double) -> Bool {
        let change = abs(new - old)
        guard change > 0.001 else { return false }
        for step in [1.0 / 16, 1.0 / 64] {
            let steps = (change / step).rounded()
            if steps >= 1, steps <= 4, abs(change - steps * step) < 0.004 { return true }
        }
        let atEnd = new < 0.001 || new > 0.999
        return atEnd && change <= 1.0 / 16 + 0.004
    }

    private func emit(_ reading: HUDReading) {
        guard isRunning, Date() >= quietUntil else { return }
        onReading?(reading)
    }

    // MARK: - Volume

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// 'vmvc': the device's virtual main volume, the one the volume keys move.
    private static let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663)

    private func watchDefaultOutputDevice() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                // A different output: its volume isn't news.
                self.quietUntil = Date().addingTimeInterval(1)
                self.unbindOutputDevice()
                self.bindOutputDevice()
            }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    }

    private func bindOutputDevice() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return }
        outputDevice = device
        lastVolume = readVolume()

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.volumeChanged() }
        }
        volumeListener = block
        for selector in [Self.virtualMainVolume, kAudioDevicePropertyMute] {
            var property = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            if AudioObjectHasProperty(device, &property) {
                AudioObjectAddPropertyListenerBlock(device, &property, .main, block)
            }
        }
    }

    private func unbindOutputDevice() {
        if let volumeListener, outputDevice != kAudioObjectUnknown {
            for selector in [Self.virtualMainVolume, kAudioDevicePropertyMute] {
                var property = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
                AudioObjectRemovePropertyListenerBlock(outputDevice, &property, .main, volumeListener)
            }
        }
        volumeListener = nil
        outputDevice = AudioDeviceID(kAudioObjectUnknown)
    }

    private func readVolume() -> (level: Double, muted: Bool)? {
        guard outputDevice != kAudioObjectUnknown else { return nil }
        var volumeAddress = Self.address(Self.virtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(outputDevice, &volumeAddress, 0, nil, &size, &level) == noErr else { return nil }
        var muteAddress = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var mute: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(outputDevice, &muteAddress) {
            _ = AudioObjectGetPropertyData(outputDevice, &muteAddress, 0, nil, &muteSize, &mute)
        }
        return (Double(level), mute != 0)
    }

    private func volumeChanged() {
        guard isRunning, let now = readVolume() else { return }
        defer { lastVolume = now }
        guard let last = lastVolume else { return }
        // Mute pressed (the level stays put), or a volume key's step.
        let mutePressed = last.muted != now.muted && abs(last.level - now.level) < 0.001
        guard mutePressed || Self.looksLikeKeyPress(from: last.level, to: now.level) else { return }
        emit(HUDReading(kind: .volume, level: now.level, muted: now.muted))
    }

    // MARK: - Brightness (DisplayServices, private)

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias BrightnessCallback = @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void
    private typealias RegisterBrightness = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, BrightnessCallback) -> Int32
    private typealias UnregisterBrightness = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?) -> Int32

    private static let displayServices: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
    )

    private static func displayFunction<T>(_ name: String, as type: T.Type) -> T? {
        displayServices.flatMap { dlsym($0, name) }.map { unsafeBitCast($0, to: type) }
    }

    /// Whether this Mac exposes its screen brightness at all.
    static var canReadBrightness: Bool {
        guard let get = displayFunction("DisplayServicesGetBrightness", as: GetBrightness.self) else { return false }
        var value: Float = 0
        return get(CGMainDisplayID(), &value) == 0
    }

    private static func readBrightness() -> Double? {
        guard let get = displayFunction("DisplayServicesGetBrightness", as: GetBrightness.self) else { return nil }
        var value: Float = 0
        return get(CGMainDisplayID(), &value) == 0 ? Double(value) : nil
    }

    private func startBrightness() {
        guard let register = Self.displayFunction("DisplayServicesRegisterForBrightnessChangeNotifications", as: RegisterBrightness.self),
              Self.canReadBrightness else { return }
        lastBrightness = Self.readBrightness()
        let result = register(CGMainDisplayID(), nil) { _, _, _, _, _ in
            Task { @MainActor in SystemHUDMonitor.activeMonitor?.brightnessChanged() }
        }
        brightnessRegistered = result == 0
        Self.activeMonitor = self
    }

    private func stopBrightness() {
        if brightnessRegistered,
           let unregister = Self.displayFunction("DisplayServicesUnregisterForBrightnessChangeNotifications", as: UnregisterBrightness.self) {
            _ = unregister(CGMainDisplayID(), nil)
        }
        brightnessRegistered = false
        if Self.activeMonitor === self { Self.activeMonitor = nil }
    }

    /// The C callback has no context to carry, so it reaches the running
    /// monitor through this.
    private static weak var activeMonitor: SystemHUDMonitor?

    private func brightnessChanged() {
        guard isRunning, let now = Self.readBrightness() else { return }
        defer { lastBrightness = now }
        guard let last = lastBrightness, abs(now - last) >= Self.keyStep,
              Self.looksLikeKeyPress(from: last, to: now) else { return }
        emit(HUDReading(kind: .brightness, level: now))
    }

    // MARK: - Keyboard backlight (CoreBrightness, private)

    private static let coreBrightness: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY
    )

    private typealias KeyboardLevel = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KeyboardRegister = @convention(c) (AnyObject, Selector, NSArray, UInt64, @escaping @convention(block) (NSString?, AnyObject?) -> Void) -> Void

    private func startKeyboard() {
        guard Self.coreBrightness != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return }
        let client = cls.init()
        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: idsSelector),
              let ids = client.perform(idsSelector)?.takeRetainedValue() as? [NSNumber],
              let id = ids.first?.uint64Value else { return }

        let levelSelector = NSSelectorFromString("brightnessForKeyboard:")
        let registerSelector = NSSelectorFromString("registerNotificationForKeys:keyboardID:block:")
        guard client.responds(to: levelSelector), client.responds(to: registerSelector) else { return }
        let level = unsafeBitCast(client.method(for: levelSelector), to: KeyboardLevel.self)
        let register = unsafeBitCast(client.method(for: registerSelector), to: KeyboardRegister.self)

        keyboardClient = client
        keyboardID = id
        lastKeyboard = Double(level(client, levelSelector, id))
        register(client, registerSelector, ["KeyboardBacklightBrightness"] as NSArray, id) { _, value in
            let reading = (value as? NSNumber)?.doubleValue
            Task { @MainActor in SystemHUDMonitor.activeMonitor?.keyboardChanged(to: reading) }
        }
        Self.activeMonitor = self
    }

    private func stopKeyboard() {
        if let client = keyboardClient {
            let selector = NSSelectorFromString("unregisterKeyboardNotificationBlock")
            if client.responds(to: selector) { _ = client.perform(selector) }
        }
        keyboardClient = nil
        keyboardID = nil
    }

    private func keyboardChanged(to value: Double?) {
        guard isRunning, let now = value else { return }
        defer { lastKeyboard = now }
        guard let last = lastKeyboard, abs(now - last) >= Self.keyStep,
              Self.looksLikeKeyPress(from: last, to: now) else { return }
        emit(HUDReading(kind: .keyboardBacklight, level: now))
    }
}
