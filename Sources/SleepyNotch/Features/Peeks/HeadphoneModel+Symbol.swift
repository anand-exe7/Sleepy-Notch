import AppKit

/// Whether this macOS has an SF Symbol, asked once per name: the headphone
/// card asks on every frame it draws.
enum SymbolAvailability {
    @MainActor private static var known: [String: Bool] = [:]

    @MainActor static func exists(_ name: String) -> Bool {
        if let answer = known[name] { return answer }
        let answer = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        known[name] = answer
        return answer
    }
}

@MainActor
extension HeadphoneModel {
    /// SF Symbol stand-in when the product renders aren't available.
    var symbolName: String {
        let preferred: String
        switch self {
        case .airPods: preferred = "airpods.gen3"
        case .airPodsPro: preferred = "airpodspro"
        case .airPodsMax: preferred = "airpodsmax"
        case .beats: preferred = "beats.headphones"
        case .earbuds: preferred = "earbuds"
        case .headphones: preferred = "headphones"
        }
        return SymbolAvailability.exists(preferred)
            ? preferred
            : "headphones"
    }
}
