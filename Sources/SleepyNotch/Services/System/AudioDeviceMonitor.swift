import CoreAudio
import Foundation

/// Reports Bluetooth headphones connecting and disconnecting.
///
/// Watches CoreAudio's device list rather than Bluetooth itself, which needs
/// no Bluetooth permission: a connected pair of AirPods shows up as an audio
/// output device. CoreAudio calls back on changes; nothing is polled.
///
/// Two things make the raw device list unreliable, and both are handled:
/// - Headphones join the list a moment before they're ready to play (no
///   output streams, sometimes no transport type yet), and nothing calls
///   back when they become ready. So each change is checked again a few
///   times over the next few seconds (`recheckDelays`).
/// - When an app starts using their mic, AirPods switch to call mode: they
///   leave the list and come back a moment later. A disconnect only counts
///   once they've stayed away for `disconnectGrace`.
@MainActor
final class AudioDeviceMonitor {
    var onEvent: ((HeadphoneEvent) -> Void)?

    /// Connected Bluetooth outputs, by device UID.
    private var known: [String: String] = [:]
    private var isStarted = false
    /// Outputs that left the list, waiting to see if they come right back.
    private var leaving: [String: DispatchWorkItem] = [:]
    private var rechecks: [DispatchWorkItem] = []

    private static let recheckDelays: [TimeInterval] = [0.4, 1.2, 2.5, 4.5]
    private static let disconnectGrace: TimeInterval = 2.5

    init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        // Devices already connected at launch aren't news.
        known = Self.bluetoothOutputs()

        // The device list, and the default output (macOS switching to the
        // headphones once they're ready is often the first sign they are).
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                .main
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.devicesChanged()
                }
            }
        }
    }

    /// Checks now, then a few more times as the new device gets ready.
    /// One-shot timers, only after a change; nothing runs otherwise.
    private func devicesChanged() {
        check()
        for work in rechecks { work.cancel() }
        rechecks = Self.recheckDelays.map { delay in
            let work = DispatchWorkItem { [weak self] in self?.check() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    private func check() {
        let current = Self.bluetoothOutputs()
        for (uid, name) in current where known[uid] == nil {
            // Back within the grace (call mode switching): it never left.
            if let pending = leaving.removeValue(forKey: uid) {
                pending.cancel()
                continue
            }
            onEvent?(HeadphoneEvent(name: name, model: HeadphoneModel(deviceName: name), isConnected: true))
        }
        for (uid, name) in known where current[uid] == nil && leaving[uid] == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.leaving.removeValue(forKey: uid) != nil else { return }
                self.onEvent?(HeadphoneEvent(name: name, model: HeadphoneModel(deviceName: name), isConnected: false))
            }
            leaving[uid] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.disconnectGrace, execute: work)
        }
        known = current
    }

    // MARK: - CoreAudio queries

    /// Bluetooth devices that can play audio, as UID → name.
    private static func bluetoothOutputs() -> [String: String] {
        var result: [String: String] = [:]
        for device in deviceIDs() where isBluetooth(device) && hasOutput(device) {
            guard let uid = string(device, kAudioDevicePropertyDeviceUID),
                  let name = string(device, kAudioObjectPropertyName)
            else { continue }
            result[uid] = name
        }
        return result
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func hasOutput(_ device: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func string(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
