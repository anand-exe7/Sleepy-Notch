import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac (and its display) from sleeping on its own while it is on,
/// with a power assertion, shown beside the notch as an activity.
///
/// No timer: the assertion is held until it is switched off, and the system
/// releases it by itself if the app quits. It is not remembered across
/// launches: a Mac left awake silently would be a surprise.
@MainActor
final class StayAwakeService: ObservableObject {
    @Published private(set) var isOn = false

    private var assertion: IOPMAssertionID = 0

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Sleepy Notch: Stay Awake" as CFString,
                &id
            )
            guard result == kIOReturnSuccess else { return }
            assertion = id
            isOn = true
        } else {
            release()
        }
    }

    func toggle() {
        setOn(!isOn)
    }

    private func release() {
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
        isOn = false
    }
}
