import CoreAudio
import Foundation

/// Reports Bluetooth headphones connecting and disconnecting.
///
/// Watches CoreAudio's device list rather than Bluetooth itself, which needs
/// no Bluetooth permission: a connected pair of AirPods shows up as an audio
/// output device. CoreAudio calls back on changes; nothing is polled.
@MainActor
final class AudioDeviceMonitor {
    static let shared = AudioDeviceMonitor()

    var onEvent: ((HeadphoneEvent) -> Void)?

    /// Connected Bluetooth outputs, by device UID.
    private var known: [String: String] = [:]
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        // Devices already connected at launch aren't news.
        known = Self.bluetoothOutputs()

        var address = Self.address(kAudioHardwarePropertyDevices)
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

    private func devicesChanged() {
        let current = Self.bluetoothOutputs()
        for (uid, name) in current where known[uid] == nil {
            onEvent?(HeadphoneEvent(name: name, model: HeadphoneModel(deviceName: name), isConnected: true))
        }
        for (uid, name) in known where current[uid] == nil {
            onEvent?(HeadphoneEvent(name: name, model: HeadphoneModel(deviceName: name), isConnected: false))
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
