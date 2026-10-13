import AppKit

/// Real product renders of Apple headphones — cut out on transparent
/// backgrounds — read at runtime from the system frameworks that System
/// Settings uses for its AirPods pages. Nothing is bundled with this app.
///
/// These are private frameworks, so names can change between macOS versions.
/// Every lookup is optional, and callers fall back to SF Symbols.
@MainActor
enum ProductImages {
    struct Earbuds {
        let left: NSImage
        let right: NSImage
        /// The closed case. Optional: the earbuds still show without it.
        let chargingCase: NSImage?
    }

    private static let frameworks = "/System/Library/PrivateFrameworks/"
    private static var cache: [String: NSImage] = [:]

    /// Front-facing left and right earbuds, and the case. The first set
    /// that loads wins, so a renamed asset in a future macOS falls through
    /// to the next.
    static func earbuds(for model: HeadphoneModel) -> Earbuds? {
        let candidates: [(left: Asset, right: Asset, chargingCase: Asset)]
        switch model {
        case .airPodsPro:
            candidates = [
                (Asset("HeadphoneCommonUIKit", "B698-Left"), Asset("HeadphoneCommonUIKit", "B698-Right"), Asset("HeadphoneCommonUIKit", "B698-Case")),
                (Asset("HeadphoneSettingsUI", "B788_Left"), Asset("HeadphoneSettingsUI", "B788_Right"), Asset("HeadphoneSettingsUI", "B788_case-closed-charged")),
            ]
        case .airPods:
            candidates = [
                (Asset("HeadphoneCommonUIKit", "B768-Left"), Asset("HeadphoneCommonUIKit", "B768-Right"), Asset("HeadphoneCommonUIKit", "B768-Case")),
            ]
        case .airPodsMax, .beats, .headphones:
            return nil
        }
        for set in candidates {
            if let left = image(set.left), let right = image(set.right) {
                return Earbuds(left: left, right: right, chargingCase: image(set.chargingCase))
            }
        }
        return nil
    }

    /// A single over-ear render. Beats uses a light colourway: the black
    /// one disappears against the notch.
    static func overEar(for model: HeadphoneModel) -> NSImage? {
        switch model {
        case .airPodsMax: return image(Asset("HeadphoneAssets", "B515d-Default"))
        case .beats: return image(Asset("HeadphoneAssets", "B518-2"))
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
