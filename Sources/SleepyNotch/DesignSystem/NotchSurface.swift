import SwiftUI
import AppKit

/// What the notch's body is made of.
enum NotchFinish: String, CaseIterable {
    /// Black where it meets the hardware notch, melting into glass along the
    /// bottom, with the desktop softly blurred around the open card.
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
        case .glass: "Black at the top, Liquid Glass along the bottom, and a soft blur around the open card."
        case .black: "Solid black, like the notch itself."
        }
    }

    /// Liquid Glass on macOS 26, frosted glass before it.
    var isAvailable: Bool { true }
}

/// The notch's body, drawn in the chosen finish.
///
/// With glass, the open card and peeks are black at the top, dissolving
/// into glass along the bottom third: Liquid Glass on macOS 26, blurring
/// what's behind it, frosted glass before it. The camera sits in
/// a display cutout, so anything lighter than black near it shows the cutout
/// as a black block; keeping the top black lets the card and the hardware
/// notch read as one piece. Around the open card the desktop is blurred too,
/// fading out a little way from its edge. The closed notch is solid black.
///
/// All of it is Core Animation and AppKit's own blur, cut to the moving
/// shape each frame (see `FrostedHostView`), so nothing is redrawn on the
/// processor while the notch moves.
struct NotchSurface: View {
    /// The shape and size right now, animated by the caller.
    let shape: NotchShape
    let size: CGSize
    /// The panel's size: room for the card, the widest peek and the blur
    /// around them.
    let panelSize: CGSize
    let finish: NotchFinish
    /// True while closed: the notch is solid black. On the way closed the
    /// cover darkens the glass as the shape shrinks over it.
    let coversGlass: Bool
    /// The blur around the shape, only for the open card.
    let showsHalo: Bool

    /// Where black starts giving way to glass, and where it's all glass, as
    /// fractions of the shape's height: solid black over the cover, title
    /// and timeline, glass only behind the bottom row. A long, gentle blend
    /// into a dark glass, so there's no line where one meets the other.
    private static let blendStart: CGFloat = 0.6
    private static let blendEnd: CGFloat = 0.98

    var body: some View {
        if finish == .glass {
            FrostedBackdrop(shape: shape, size: size, covered: coversGlass, halo: showsHalo)
                .frame(width: panelSize.width, height: panelSize.height)
        } else {
            shape
                .fill(Theme.notchFill)
                .frame(width: size.width, height: size.height)
        }
    }

    /// Black on top dissolving to clear, as (location, opacity) pairs down
    /// the card, along an S-curve so the seam has no visible edge.
    fileprivate static let blackFade: [(location: CGFloat, opacity: CGFloat)] = {
        // Smootherstep (6t⁵ − 15t⁴ + 10t³) sampled finely: it starts and
        // ends with zero slope *and* zero curvature, so neither end of the
        // blend shows a line where it begins or finishes.
        let steps = 16
        var stops: [(CGFloat, CGFloat)] = [(0, 1)]
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let amount = t * t * t * (t * (t * 6 - 15) + 10)
            stops.append((blendStart + (blendEnd - blendStart) * t, 1 - amount))
        }
        stops.append((1, 0))
        return stops
    }()
}

// MARK: - Frosted glass

/// The frosted card and the blur around it, cut to the notch's shape as it
/// moves. An `Animatable` view, so SwiftUI hands it the spring's in-between
/// shape on every frame. (Marking the representable itself `Animatable`
/// isn't enough: it only ever got the final shape.)
private struct FrostedBackdrop: View, Animatable {
    var shape: NotchShape
    var size: CGSize
    var covered: Bool
    var halo: Bool

    var animatableData: AnimatablePair<NotchShape.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shape.animatableData, AnimatablePair(size.width, size.height)) }
        set {
            shape.animatableData = newValue.first
            size = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    var body: some View {
        FrostedRepresentable(shape: shape, size: size, covered: covered, halo: halo)
    }
}

private struct FrostedRepresentable: NSViewRepresentable {
    let shape: NotchShape
    let size: CGSize
    let covered: Bool
    let halo: Bool

    func makeNSView(context: Context) -> FrostedHostView {
        FrostedHostView()
    }

    func updateNSView(_ view: FrostedHostView, context: Context) {
        view.cut(to: shape, size: size)
        view.setCovered(covered)
        view.setHalo(halo)
    }
}

/// Layers, back to front:
/// - the halo: a blur of the desktop around the card, its edge feathered
///   by a soft mask that follows the shape;
/// - the body: glass under a black fade and a black cover, all cut to the
///   shape. The fade follows the shape's height, so a short peek gets the
///   same black top and glass bottom as the card.
///
/// The blurs are never resized: they're laid out once at the panel's size
/// and only the masks over them change each frame. Hand-made layers live in
/// leaf views (`PassiveLayerView`): added to a view with subviews, AppKit
/// reorders them under those subviews.
private final class FrostedHostView: NSView {
    private let haloBox = PassiveLayerView()
    private let halo = NSVisualEffectView()
    private let haloMask = CAShapeLayer()

    private let cardBox = PassiveLayerView()
    private let blur = FrostedHostView.makeGlass()
    private let overlay = PassiveLayerView()
    private let cutout = CAShapeLayer()
    /// Black at the top dissolving into the glass, sized to the shape.
    private let fade = CAGradientLayer()
    /// Solid black over everything while closed or peeking.
    private let cover = CALayer()

    private var isCovered = true
    private var isHaloShown = false
    private var shape = NotchShape(bottomRadius: 0)
    private var size: CGSize = .zero

    /// How far the halo's blur reaches past the card's edge.
    private static let haloSpread: CGFloat = 16

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        halo.material = .hudWindow
        halo.blendingMode = .behindWindow
        halo.state = .active
        halo.appearance = NSAppearance(named: .darkAqua)

        addSubview(haloBox)
        haloBox.addSubview(halo)
        haloMask.fillColor = NSColor.black.cgColor
        haloMask.shadowColor = NSColor.black.cgColor
        haloMask.shadowOpacity = 1
        haloMask.shadowOffset = .zero
        haloMask.shadowRadius = Self.haloSpread
        haloBox.layer?.mask = haloMask
        haloBox.layer?.opacity = 0

        addSubview(cardBox)
        cardBox.addSubview(blur)
        cardBox.addSubview(overlay)
        fade.colors = NotchSurface.blackFade.map { NSColor.black.withAlphaComponent($0.opacity).cgColor }
        fade.locations = NotchSurface.blackFade.map { NSNumber(value: Double($0.location)) }
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        cover.backgroundColor = NSColor.black.cgColor
        overlay.layer?.addSublayer(fade)
        overlay.layer?.addSublayer(cover)
        cardBox.layer?.mask = cutout
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// Purely visual: clicks go to the card above it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The glass along the bottom: Apple's regular Liquid Glass where there
    /// is one — blurred, with the glass's own light and depth (the clear
    /// style barely blurred at all) — with a dark tint to keep white text
    /// readable; frosted glass on older systems.
    private static func makeGlass() -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            // Dark enough to meet the black above it without a visible step.
            glass.tintColor = NSColor.black.withAlphaComponent(0.5)
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
        fadeOpacity(of: cover, to: covered ? 1 : 0, duration: covered ? 0.22 : 0.12)
    }

    /// The blur around the open card fades in as it opens and out as it
    /// closes.
    func setHalo(_ shown: Bool) {
        guard shown != isHaloShown, let haloLayer = haloBox.layer else { return }
        isHaloShown = shown
        fadeOpacity(of: haloLayer, to: shown ? 0.9 : 0, duration: shown ? 0.35 : 0.2)
    }

    private func fadeOpacity(of layer: CALayer, to target: Float, duration: CFTimeInterval) {
        let from = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = target
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = target
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "opacity")
    }

    func cut(to shape: NotchShape, size: CGSize) {
        self.shape = shape
        self.size = size
        updateMasks()
    }

    override func layout() {
        super.layout()
        for view in [haloBox, halo, cardBox, blur, overlay] as [NSView] {
            view.frame = view.superview === self ? bounds : view.superview?.bounds ?? bounds
        }
        updateMasks()
    }

    private func updateMasks() {
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
        let path = shape.path(in: rect).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cutout.frame = bounds
        cutout.path = path
        haloMask.frame = bounds
        haloMask.path = path
        haloMask.shadowPath = path
        fade.frame = rect
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
