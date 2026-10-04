import AppKit

/// Real product renders of Apple headphones — cut out on transparent
/// backgrounds — read at runtime from the system frameworks that System
/// Settings uses for its AirPods pages. Nothing is bundled with this app.
///
/// These are private frameworks, so names can change between macOS versions.
/// Every lookup is optional, and callers fall back to SF Symbols.
@MainActor
enum ProductImages {
    struct EarbudSet {
        let left: NSImage
        let right: NSImage
        let chargingCase: NSImage
    }

    private static let frameworks = "/System/Library/PrivateFrameworks/"
    private static var cache: [String: NSImage] = [:]

    static func earbuds(for model: HeadphoneModel) -> EarbudSet? {
        let names: (left: Asset, right: Asset, chargingCase: Asset)
        switch model {
        case .airPods:
            names = (
                Asset("HeadphoneCommonUIKit", "B768-Left"),
                Asset("HeadphoneCommonUIKit", "B768-Right"),
                Asset("HeadphoneCommonUIKit", "B768-Case")
            )
        case .airPodsPro:
            names = (
                Asset("HeadphoneSettingsUI", "B788_Left"),
                Asset("HeadphoneSettingsUI", "B788_Right"),
                Asset("HeadphoneSettingsUI", "B788_case-closed-charged")
            )
        case .airPodsMax, .beats, .headphones:
            return nil
        }
        guard let left = image(names.left),
              let right = image(names.right),
              let chargingCase = image(names.chargingCase)
        else { return nil }
        return EarbudSet(left: left, right: right, chargingCase: chargingCase)
    }

    /// A single over-ear render.
    static func overEar(for model: HeadphoneModel) -> NSImage? {
        switch model {
        case .airPodsMax: return image(Asset("HeadphoneAssets", "B515d-Default"))
        case .beats: return image(Asset("HeadphoneAssets", "B518-Default"))
        case .airPods, .airPodsPro, .headphones: return nil
        }
    }

    private struct Asset {
        let framework: String
        let name: String

        init(_ framework: String, _ name: String) {
            self.framework = framework
            self.name = name
        }
    }

    private static func image(_ asset: Asset) -> NSImage? {
        let key = asset.framework + "/" + asset.name
        if let cached = cache[key] { return cached }
        guard let bundle = Bundle(path: frameworks + asset.framework + ".framework"),
              let image = bundle.image(forResource: asset.name)
        else { return nil }
        cache[key] = image
        return image
    }
}
