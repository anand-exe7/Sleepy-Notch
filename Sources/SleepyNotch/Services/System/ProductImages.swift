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
        case .airPodsMax, .beats, .earbuds, .headphones:
            return nil
        }
        for set in candidates {
            if let left = image(set.left), let right = image(set.right) {
                return Earbuds(left: left, right: right, chargingCase: image(set.chargingCase))
            }
        }
        return nil
    }

    /// Apple's own 3D-rendered AirPods Pro clip, with a transparent
    /// background: the closed case, its lid swinging open, the buds inside
    /// (then, later on, the buds lifting out). System Settings plays it for
    /// the hearing test. Only AirPods Pro have one: its buds have ear tips,
    /// so regular AirPods open their own case instead (see
    /// `RegularAirPodsCase`).
    static func caseOpeningVideo(for model: HeadphoneModel) -> URL? {
        model == .airPodsPro ? proCaseClip : nil
    }

    /// Looked up once: the card asks on every frame it draws.
    private static let proCaseClip: URL? = [
        "HeadphoneSettingsUI.framework/Versions/A/Resources/B788_HearingFittestAirpods.mov",
        "HeadphoneAssets.framework/Versions/A/Resources/B788_HearingFittestAirpods.mov",
    ]
    .map { URL(fileURLWithPath: frameworks + $0) }
    .first { FileManager.default.fileExists(atPath: $0.path) }

    /// Apple's own 3D clip of the regular AirPods case turning a full circle,
    /// closed, with a transparent background: the one macOS's Bluetooth
    /// service shows when AirPods connect. Six seconds, starting and ending
    /// face on. Newest case first (AirPods 4, then 3, then 2), named by
    /// Apple's Bluetooth product ID.
    static func caseSpinVideo(for model: HeadphoneModel) -> URL? {
        model == .airPods ? airPodsCaseSpin : nil
    }

    /// Looked up once, like `proCaseClip`.
    private static let airPodsCaseSpin: URL? = {
        let folder = "/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources/"
        return ["8217", "8211", "8207"]
            .map { URL(fileURLWithPath: folder + "Banner-PID-\($0)-Case-mov/Banner-PID-\($0)-Case-Loop.mov") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }()

    /// A single over-ear render, in a light colourway: the dark ones
    /// disappear against the notch.
    static func overEar(for model: HeadphoneModel) -> NSImage? {
        switch model {
        case .airPodsMax:
            return image(Asset("HeadphoneAssets", "B515d-19")) ?? image(Asset("HeadphoneAssets", "B515d-Default"))
        case .beats: return image(Asset("HeadphoneAssets", "B518-2"))
        case .airPods, .airPodsPro, .earbuds, .headphones: return nil
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
