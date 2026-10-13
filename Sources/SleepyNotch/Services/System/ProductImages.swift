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
    }

    private static let frameworks = "/System/Library/PrivateFrameworks/"
    private static var cache: [String: NSImage] = [:]

    /// Front-facing left and right earbuds. The first set that loads wins,
    /// so a renamed asset in a future macOS falls through to the next.
    static func earbuds(for model: HeadphoneModel) -> Earbuds? {
        let candidates: [(Asset, Asset)]
        switch model {
        case .airPodsPro:
            candidates = [
                (Asset("HeadphoneCommonUIKit", "B698-Left"), Asset("HeadphoneCommonUIKit", "B698-Right")),
                (Asset("HeadphoneSettingsUI", "B788_Left"), Asset("HeadphoneSettingsUI", "B788_Right")),
            ]
        case .airPods:
            candidates = [
                (Asset("HeadphoneCommonUIKit", "B768-Left"), Asset("HeadphoneCommonUIKit", "B768-Right")),
            ]
        case .airPodsMax, .beats, .headphones:
            return nil
        }
        for (left, right) in candidates {
            if let l = image(left), let r = image(right) {
                return Earbuds(left: l, right: r)
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
