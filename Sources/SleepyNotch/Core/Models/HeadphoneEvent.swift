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
    /// Other in-ear buds: Galaxy Buds, Pixel Buds, Jabra, Sony WF…, Beats
    /// Studio Buds and the like.
    case earbuds
    /// Other headphones, usually over-ear.
    case headphones

    /// Best guess from the device name, which is all CoreAudio gives us.
    /// A renamed device falls back to generic headphones.
    init(deviceName: String) {
        let name = deviceName.lowercased()
        if name.contains("airpods max") {
            self = .airPodsMax
        } else if name.contains("airpods pro") {
            self = .airPodsPro
        } else if name.contains("airpods") {
            self = .airPods
        } else if Self.earbudWords.contains(where: name.contains) {
            self = .earbuds
        } else if name.contains("beats") {
            self = .beats
        } else {
            self = .headphones
        }
    }

    /// Words in the names of in-ear buds (Beats' buds included, which would
    /// otherwise get the over-ear Beats picture).
    private static let earbudWords = [
        "buds", "earbud", "earphone", "in-ear", "fit pro", "powerbeats", "beats flex",
        "wf-", "elite", "nothing ear", "ear (", "tws", "pods",
    ]
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
        case .airPods, .airPodsPro, .earbuds:
            return (left != nil && right != nil && caseLevel != nil) || (main != nil && left == nil && right == nil)
        case .airPodsMax, .beats, .headphones:
            return main != nil
        }
    }
}
