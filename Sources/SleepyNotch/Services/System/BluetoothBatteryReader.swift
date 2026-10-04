import Foundation

/// Best-effort battery levels for a connected Bluetooth device.
///
/// macOS has no public API for AirPods battery levels, but `system_profiler`
/// reports them for connected devices. It's one short process launch (~0.2s),
/// run once per connection, off the main thread. AirPods often report their
/// levels a few seconds after connecting, so `nil` is a normal answer.
enum BluetoothBatteryReader {
    static func battery(forDeviceNamed name: String) async -> HeadphoneBattery? {
        await Task.detached(priority: .utility) {
            guard let data = runSystemProfiler() else { return nil }
            return parse(data, deviceName: name)
        }.value
    }

    private static func runSystemProfiler() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    /// Shape: `{"SPBluetoothDataType": [{"device_connected": [{"<name>": {...}}]}]}`
    /// with levels like `"device_batteryLevelLeft": "80%"`.
    static func parse(_ data: Data, deviceName: String) -> HeadphoneBattery? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }

        for controller in controllers {
            let connected = controller["device_connected"] as? [[String: Any]] ?? []
            for entry in connected {
                guard let properties = entry[deviceName] as? [String: Any] else { continue }
                let battery = HeadphoneBattery(
                    left: percent(properties["device_batteryLevelLeft"]),
                    right: percent(properties["device_batteryLevelRight"]),
                    caseLevel: percent(properties["device_batteryLevelCase"]),
                    main: percent(properties["device_batteryLevelMain"])
                )
                return battery.isEmpty ? nil : battery
            }
        }
        return nil
    }

    private static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }
}
