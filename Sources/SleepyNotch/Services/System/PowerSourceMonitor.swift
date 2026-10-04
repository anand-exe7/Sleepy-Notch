import Foundation
import IOKit.ps

/// Watches the battery and power adapter, and reports the moments worth a
/// peek: plugging in, unplugging, reaching full, and dropping to low.
///
/// Event-driven: IOKit calls back when the power source changes (adapter
/// state, or the battery level moving by a percent). Nothing is polled.
@MainActor
final class PowerSourceMonitor {
    static let shared = PowerSourceMonitor()

    /// Percentage at or below which a low-battery peek is shown.
    static let lowThreshold = 20

    /// Called for each transition worth showing.
    var onEvent: ((PowerEvent) -> Void)?

    /// The last reading, or `nil` on a Mac with no internal battery.
    private(set) var snapshot: PowerSnapshot?

    private var runLoopSource: CFRunLoopSource?

    private init() {}

    var hasBattery: Bool { snapshot != nil }

    func start() {
        guard runLoopSource == nil else { return }
        snapshot = PowerSnapshot.read()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.powerSourcesChanged() }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    private func powerSourcesChanged() {
        guard let new = PowerSnapshot.read() else { return }
        let old = snapshot
        snapshot = new
        guard let old else { return }

        if new.isOnAC && !old.isOnAC {
            onEvent?(PowerEvent(kind: .pluggedIn, level: new.level, isCharging: new.isCharging))
        } else if !new.isOnAC && old.isOnAC {
            onEvent?(PowerEvent(kind: .unplugged, level: new.level, isCharging: false))
        } else if new.isOnAC && new.isCharged && !old.isCharged {
            onEvent?(PowerEvent(kind: .fullyCharged, level: new.level, isCharging: false))
        } else if !new.isOnAC && new.level <= Self.lowThreshold && old.level > Self.lowThreshold {
            onEvent?(PowerEvent(kind: .low, level: new.level, isCharging: false))
        }
    }
}

/// One reading of the internal battery.
struct PowerSnapshot: Equatable {
    /// 0–100.
    let level: Int
    let isOnAC: Bool
    let isCharging: Bool
    let isCharged: Bool

    /// `nil` when there's no internal battery (Mac mini, iMac, Studio).
    static func read() -> PowerSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let level = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current

            return PowerSnapshot(
                level: Swift.min(Swift.max(level, 0), 100),
                isOnAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false
            )
        }
        return nil
    }
}
