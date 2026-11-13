import AppKit
import CoreImage
import QuartzCore
import SwiftUI

/// The album art filling a whole screen: blurred, darkened at the edges,
/// and drifting slowly (a long, gentle zoom and pan).
///
/// The blur is made once per cover, and the drift is one Core Animation
/// animation handed to the window server, so the app does no work per
/// frame. A new cover cross-fades in.
struct DriftingArtworkView: NSViewRepresentable {
    let image: NSImage?
    /// Softened into a glow, or shown sharp (with the shading left to the
    /// view in front).
    var blurred = true

    func makeNSView(context: Context) -> DriftingArtworkLayerView {
        let view = DriftingArtworkLayerView()
        view.isBlurred = blurred
        view.show(image)
        return view
    }

    func updateNSView(_ view: DriftingArtworkLayerView, context: Context) {
        view.show(image)
    }
}

final class DriftingArtworkLayerView: NSView {
    private let art = CALayer()
    private let shade = CAGradientLayer()
    private var shown: NSImage?
    var isBlurred = true {
        didSet { shade.isHidden = !isBlurred; art.opacity = isBlurred ? 0.9 : 1 }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        art.contentsGravity = .resizeAspectFill
        art.opacity = 0.9
        // Darker towards the edges and the bottom, so the cover and the
        // controls in front stand out.
        shade.type = .radial
        shade.colors = [NSColor.black.withAlphaComponent(0.15).cgColor, NSColor.black.withAlphaComponent(0.7).cgColor]
        shade.startPoint = CGPoint(x: 0.5, y: 0.55)
        shade.endPoint = CGPoint(x: 1.25, y: 1.25)
        layer?.addSublayer(art)
        layer?.addSublayer(shade)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Larger than the screen, so the drift never shows an edge.
        art.frame = bounds.insetBy(dx: -bounds.width * 0.12, dy: -bounds.height * 0.12)
        shade.frame = bounds
        CATransaction.commit()
        startDrift()
    }

    func show(_ image: NSImage?) {
        guard image !== shown else { return }
        shown = image
        let blurred = isBlurred
            ? image.flatMap(Self.blurred)
            : image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.8
        art.add(fade, forKey: "contents")
        art.contents = blurred
    }

    private func startDrift() {
        guard art.animation(forKey: "drift") == nil, bounds.width > 0 else { return }
        let zoom = CABasicAnimation(keyPath: "transform.scale")
        zoom.fromValue = 1.0
        zoom.toValue = isBlurred ? 1.1 : 1.06
        let pan = CABasicAnimation(keyPath: "position")
        pan.fromValue = NSValue(point: CGPoint(x: art.position.x - bounds.width * 0.04, y: art.position.y + bounds.height * 0.03))
        pan.toValue = NSValue(point: CGPoint(x: art.position.x + bounds.width * 0.04, y: art.position.y - bounds.height * 0.03))
        let drift = CAAnimationGroup()
        drift.animations = [zoom, pan]
        drift.duration = 26
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        art.add(drift, forKey: "drift")
    }

    /// The cover, softened into a glow of its own colours.
    private static func blurred(_ image: NSImage) -> CGImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg).clampedToExtent()
        let blur = input.applyingGaussianBlur(sigma: Double(max(cg.width, cg.height)) / 18)
        let tuned = blur.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.25,
            kCIInputBrightnessKey: -0.06,
        ])
        return CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(tuned, from: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    }
}
