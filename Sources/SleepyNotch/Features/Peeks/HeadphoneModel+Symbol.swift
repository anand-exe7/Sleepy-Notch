import AppKit

extension HeadphoneModel {
    /// SF Symbol stand-in when the product renders aren't available.
    var symbolName: String {
        let preferred: String
        switch self {
        case .airPods: preferred = "airpods.gen3"
        case .airPodsPro: preferred = "airpodspro"
        case .airPodsMax: preferred = "airpodsmax"
        case .beats: preferred = "beats.headphones"
        case .headphones: preferred = "headphones"
        }
        return NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil
            ? preferred
            : "headphones"
    }
}
