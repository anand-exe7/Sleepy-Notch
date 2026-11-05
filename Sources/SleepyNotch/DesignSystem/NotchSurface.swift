import SwiftUI
import AppKit

/// What the notch's body is made of.
enum NotchFinish: String, CaseIterable {
    /// Black where it meets the hardware notch, melting into glass along the
    /// bottom.
    case glass
    /// Solid black all the way down, like the hardware cutout.
    case black

    var title: String {
        switch self {
        case .glass: "Glass"
        case .black: "Black"
        }
    }

    var summary: String {
        switch self {
        case .glass: "Black at the top, Liquid Glass along the bottom."
        case .black: "Solid black, like the notch itself."
        }
    }

    /// Liquid Glass on macOS 26, frosted glass before it.
    var isAvailable: Bool { true }
}

/// The notch's body, drawn in the chosen finish.
///
/// With glass, the open card and peeks are solid black at the top,
/// dissolving into glass along the bottom: Liquid Glass on macOS 26,
/// blurring what's behind it, frosted glass before it. The camera sits in a
/// display cutout, so anything lighter than black near it shows the cutout
/// as a black block; keeping the top black lets the card and the hardware
/// notch read as one piece. The closed notch is solid black.
///
/// The glass itself only exists along the bottom: it's faded out with a
/// mask above the blend, and the black is drawn over it as well, so nothing
/// behind the card can show through the black part, at any brightness.
/// All of it is Core Animation and AppKit's own glass, cut to the moving
/// shape each frame (see `GlassHostView`), so nothing is redrawn on the
/// processor while the notch moves.
struct NotchSurface: View {
    /// The shape and size right now, animated by the caller.
    let shape: NotchShape
    let size: CGSize
    /// The shape never draws shorter than this (see `NotchClip.minHeight`).
    var minHeight: CGFloat = 0
    /// The panel's size: room for the card and the widest peek.
    let panelSize: CGSize
    let finish: NotchFinish
    /// True while closed: the notch is solid black. On the way closed the
    /// cover darkens the glass as the shape shrinks over it.
    let coversGlass: Bool
    /// Where the black starts giving way to glass, as a fraction of the
    /// shape's height. The welcome lets the glass rise higher.
    var glassFrom: CGFloat = NotchSurface.blendStart
    /// Glass even with the Black finish (the welcome). Comes on while the
    /// notch is still closed and goes off once it has closed again, when
    /// both finishes are the same solid black, so the switch never shows.
    var forcesGlass = false

    /// Where black starts giving way to glass, and where it's all glass, as
    /// fractions of the shape's height: solid black over the cover, title
    /// and timeline, glass only behind the bottom row.
    static let blendStart: CGFloat = 0.66
    private static let blendEnd: CGFloat = 1
    /// How much black stays over the glass even at the very bottom. Fully
    /// clear there, the glass showed as a pale strip along the bottom edge —
    /// almost white over a light window.
    private static let blackFloor: CGFloat = 0.3

    var body: some View {
        if finish == .glass || forcesGlass {
            GlassBackdrop(shape: shape, size: size, minHeight: minHeight, covered: coversGlass, glassFrom: glassFrom)
                .frame(width: panelSize.width, height: panelSize.height)
        } else {
            NotchClip(shape: shape, size: size, minHeight: minHeight)
                .fill(Theme.notchFill)
                .frame(width: panelSize.width, height: panelSize.height)
        }
    }

    /// Black on top dissolving to clear, as (location, opacity) pairs down
    /// the shape, along an S-curve so the seam has no visible edge.
    /// The same number of stops whatever `start` is, with the same
    /// opacities, so moving the blend only moves the locations.
    fileprivate static func blackFade(from start: CGFloat) -> [(location: CGFloat, opacity: CGFloat)] {
        // Smootherstep (6t⁵ − 15t⁴ + 10t³) sampled finely: it starts and
        // ends with zero slope *and* zero curvature, so neither end of the
        // blend shows a line where it begins or finishes.
        let steps = 16
        var stops: [(CGFloat, CGFloat)] = [(0, 1)]
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let amount = t * t * t * (t * (t * 6 - 15) + 10)
            stops.append((start + (blendEnd - start) * t, 1 - amount * (1 - blackFloor)))
        }
        stops.append((1, blackFloor))
        return stops
    }
}

// MARK: - Glass

/// The glass and black, cut to the notch's shape as it moves. An
/// `Animatable` view, so SwiftUI hands it the spring's in-between shape on
/// every frame. (Marking the representable itself `Animatable` isn't
/// enough: it only ever got the final shape.)
private struct GlassBackdrop: View, Animatable {
    var shape: NotchShape
    var size: CGSize
    var minHeight: CGFloat = 0
    var covered: Bool
    var glassFrom: CGFloat

    var animatableData: AnimatablePair<NotchShape.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shape.animatableData, AnimatablePair(size.width, size.height)) }
        set {
            shape.animatableData = newValue.first
            size = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    var body: some View {
        GlassRepresentable(shape: shape, size: CGSize(width: size.width, height: max(size.height, minHeight)), covered: covered, glassFrom: glassFrom)
    }
}

private struct GlassRepresentable: NSViewRepresentable {
    let shape: NotchShape
    let size: CGSize
    let covered: Bool
    let glassFrom: CGFloat

    func makeNSView(context: Context) -> GlassHostView {
        GlassHostView()
    }

    func updateNSView(_ view: GlassHostView, context: Context) {
        view.cut(to: shape, size: size)
        view.setCovered(covered)
        view.setGlassFrom(glassFrom)
    }
}

/// Layers, back to front, all cut to the shape:
/// - the glass, faded out above the blend by a mask, so it's only there
///   along the bottom;
/// - the black fade: solid black down to the blend, then dissolving;
/// - the cover: solid black over everything while closed.
///
/// The glass is never resized: it's laid out once at the panel's size and
/// only the masks over it change each frame. Hand-made layers live in leaf
/// views (`PassiveLayerView`): added to a view with subviews, AppKit
/// reorders them under those subviews.
private final class GlassHostView: NSView {
    private let body = PassiveLayerView()
    private let glassBox = PassiveLayerView()
    private let glass = GlassHostView.makeGlass()
    /// The glass's own mask: clear at the top, opaque along the bottom.
    private let glassMask = CAGradientLayer()
    private let overlay = PassiveLayerView()
    private let cutout = CAShapeLayer()
    /// Black at the top dissolving into the glass, sized to the shape.
    private let fade = CAGradientLayer()
    /// Solid black over everything while closed.
    private let cover = CALayer()

    private var isCovered = true
    private var glassFrom = NotchSurface.blendStart
    private var shape = NotchShape(bottomRadius: 0)
    private var size: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        addSubview(body)
        body.addSubview(glassBox)
        glassBox.addSubview(glass)
        body.addSubview(overlay)

        let stops = NotchSurface.blackFade(from: glassFrom)
        let locations = stops.map { NSNumber(value: Double($0.location)) }
        fade.colors = stops.map { NSColor.black.withAlphaComponent($0.opacity).cgColor }
        fade.locations = locations
        // The glass shows exactly where the black gives way.
        glassMask.colors = stops.map { NSColor.black.withAlphaComponent(1 - $0.opacity).cgColor }
        glassMask.locations = locations
        for gradient in [fade, glassMask] {
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }
        glassBox.layer?.mask = glassMask
        // Let the glass overhang the panel (see `glassOverhang`); the masks
        // still cut it to the shape.
        if #available(macOS 14, *) {
            body.clipsToBounds = false
            glassBox.clipsToBounds = false
        }
        cover.backgroundColor = NSColor.black.cgColor
        overlay.layer?.addSublayer(fade)
        overlay.layer?.addSublayer(cover)
        body.layer?.mask = cutout
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// Purely visual: clicks go to the card above it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The glass along the bottom: Apple's regular Liquid Glass where there
    /// is one, with a heavy dark tint so it stays smoky dark over light
    /// windows too, meets the black above it without a visible step, and
    /// keeps white controls readable; frosted glass on older systems.
    private static func makeGlass() -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.tintColor = NSColor.black.withAlphaComponent(0.68)
            glass.appearance = NSAppearance(named: .darkAqua)
            return glass
        }
        let frosted = NSVisualEffectView()
        frosted.material = .hudWindow
        frosted.blendingMode = .behindWindow
        frosted.state = .active
        frosted.appearance = NSAppearance(named: .darkAqua)
        return frosted
    }

    /// Opening, the cover lifts quickly so the glass is there from the start
    /// of the motion; closing, it settles back as the shape shrinks.
    func setCovered(_ covered: Bool) {
        guard covered != isCovered else { return }
        isCovered = covered
        let target: Float = covered ? 1 : 0
        let from = cover.presentation()?.opacity ?? cover.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cover.opacity = target
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = target
        animation.duration = covered ? 0.18 : 0.12
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        cover.add(animation, forKey: "opacity")
    }

    /// Moves where the glass begins, gliding there rather than jumping.
    func setGlassFrom(_ start: CGFloat) {
        guard start != glassFrom else { return }
        glassFrom = start
        let locations = NotchSurface.blackFade(from: start).map { NSNumber(value: Double($0.location)) }
        for gradient in [fade, glassMask] {
            let from = gradient.presentation()?.locations ?? gradient.locations
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.locations = locations
            CATransaction.commit()
            let glide = CABasicAnimation(keyPath: "locations")
            glide.fromValue = from
            glide.toValue = locations
            glide.duration = 0.45
            glide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradient.add(glide, forKey: "locations")
        }
    }

    func cut(to shape: NotchShape, size: CGSize) {
        self.shape = shape
        self.size = size
        updateMasks()
    }

    /// How far the glass reaches past the panel on every side. Liquid Glass
    /// lights its own edges; laid out at the panel's size, its bottom rim
    /// sat just below the card and showed as a pale strip along the bottom.
    /// Out here, the window clips it away.
    private static let glassOverhang: CGFloat = 80

    override func layout() {
        super.layout()
        body.frame = bounds
        glassBox.frame = bounds
        glass.frame = bounds.insetBy(dx: -Self.glassOverhang, dy: -Self.glassOverhang)
        overlay.frame = bounds
        updateMasks()
    }

    private func updateMasks() {
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cutout.frame = bounds
        cutout.path = shape.path(in: rect).cgPath
        // The fades only run top to bottom, so they span the whole width:
        // the bubbles beside the notch stay black while the card opens.
        let band = CGRect(x: 0, y: 0, width: bounds.width, height: size.height)
        fade.frame = band
        glassMask.frame = band
        cover.frame = bounds
        CATransaction.commit()
    }
}

/// A flipped, click-through layer-backed view, for holding hand-made
/// sublayers (with no subviews of its own) or for carrying a mask.
private final class PassiveLayerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
