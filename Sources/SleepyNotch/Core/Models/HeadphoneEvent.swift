import Foundation

/// A pair of headphones connecting or disconnecting.
struct HeadphoneEvent: Equatable {
    let name: String
    let model: HeadphoneModel
    let isConnected: Bool
    /// Filled in after the fact, when macOS reports it. Often unavailable.
    var battery: HeadphoneBattery?
}

enum HeadphoneModel: Equatable {
    case airPods
    case airPodsPro
    case airPodsMax
    case beats
    case headphones

    /// Best guess from the device name, which is all CoreAudio gives us.
    /// A renamed device ("Studio Buds") falls back to generic headphones.
    init(deviceName: String) {
        let name = deviceName.lowercased()
        if name.contains("airpods max") {
            self = .airPodsMax
        } else if name.contains("airpods pro") {
            self = .airPodsPro
        } else if name.contains("airpods") {
            self = .airPods
        } else if name.contains("beats") {
            self = .beats
        } else {
            self = .headphones
        }
    }
}

/// Battery levels, 0–100. AirPods report left, right and case; over-ear
/// headphones report a single `main` level.
struct HeadphoneBattery: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var main: Int?

    var isEmpty: Bool {
        left == nil && right == nil && caseLevel == nil && main == nil
    }

    /// Whether every part this model has reported a level, so there's
    /// nothing more worth waiting for.
    func isComplete(for model: HeadphoneModel) -> Bool {
        switch model {
        case .airPods, .airPodsPro:
            return (left != nil && right != nil && caseLevel != nil) || (main != nil && left == nil && right == nil)
        case .airPodsMax, .beats, .headphones:
            return main != nil
        }
    }
}
