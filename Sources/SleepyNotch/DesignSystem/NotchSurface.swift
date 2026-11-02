import SwiftUI
import AppKit

/// What the notch's body is made of.
enum NotchFinish: String, CaseIterable {
    /// Black where it meets the hardware notch, melting into frosted glass
    /// along the bottom, with the desktop softly blurred around the card.
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
        case .glass: "Black at the top, frosted glass along the bottom, and a soft blur around the open card."
        case .black: "Solid black, like the notch itself."
        }
    }

    /// The frosted material works on every supported macOS.
    var isAvailable: Bool { true }
}

/// The notch's body, drawn in the chosen finish.
///
/// With glass, only the open card gets it, and only along the bottom: the
/// top stays pure black, then dissolves into a real frosted blur of whatever
/// is behind it. The camera sits in a display cutout, so anything lighter
/// than black near it shows the cutout as a black block; keeping the top
/// black lets the card and the hardware notch read as one piece. Around the
/// open card the desktop is blurred too, fading out a little way from its
/// edge. Peeks and the closed notch are solid black.
///
/// All of it is Core Animation and AppKit's own blur, cut to the moving
/// shape each frame (see `FrostedHostView`), so nothing is redrawn on the
/// processor while the notch moves.
struct NotchSurface: View {
    /// The shape and size right now, animated by the caller.
    let shape: NotchShape
    let size: CGSize
    /// The open card's size, which the black fade is drawn at.
    let cardSize: CGSize
    /// The panel's size: room for the card, the widest peek and the blur
    /// around them.
    let panelSize: CGSize
    let finish: NotchFinish
    /// True unless the card is open. Peeks reach down into the glass area
    /// and stay solid black, and on the way closed the cover darkens the
    /// glass as the shape shrinks over it.
    let coversGlass: Bool

    /// Where black starts giving way to glass, and where it's all glass, as
    /// fractions of the card's height: black over the cover and title, glass
    /// along the timeline and controls.
    private static let blendStart: CGFloat = 0.42
    private static let blendEnd: CGFloat = 0.86

    var body: some View {
        if finish == .glass {
            FrostedBackdrop(shape: shape, size: size, cardSize: cardSize, covered: coversGlass)
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
    let cardSize: CGSize
    var covered: Bool

    var animatableData: AnimatablePair<NotchShape.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shape.animatableData, AnimatablePair(size.width, size.height)) }
        set {
            shape.animatableData = newValue.first
            size = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    var body: some View {
        FrostedRepresentable(shape: shape, size: size, cardSize: cardSize, covered: covered)
    }
}

private struct FrostedRepresentable: NSViewRepresentable {
    let shape: NotchShape
    let size: CGSize
    let cardSize: CGSize
    let covered: Bool

    func makeNSView(context: Context) -> FrostedHostView {
        FrostedHostView()
    }

    func updateNSView(_ view: FrostedHostView, context: Context) {
        view.cut(to: shape, size: size, cardSize: cardSize)
        view.setCovered(covered)
    }
}

/// Layers, back to front:
/// - the halo: a blur of the desktop around the card, its edge feathered
///   by a soft mask that follows the shape;
/// - the card: a frosted blur under a black fade and a black cover, all cut
///   to the shape.
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
    private let blur = NSVisualEffectView()
    private let overlay = PassiveLayerView()
    private let cutout = CAShapeLayer()
    /// Black at the top dissolving into the glass, at the card's size.
    private let fade = CAGradientLayer()
    /// Solid black over everything while closed or peeking.
    private let cover = CALayer()

    private var isCovered = true
    private var shape = NotchShape(bottomRadius: 0)
    private var size: CGSize = .zero
    private var cardSize: CGSize = .zero

    /// How far the halo's blur reaches past the card's edge.
    private static let haloSpread: CGFloat = 16

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        for effect in [halo, blur] {
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.appearance = NSAppearance(named: .darkAqua)
        }

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

    /// Opening, the cover lifts quickly so the glass is there from the start
    /// of the motion, and the blur around the card fades in; closing, both
    /// settle back as the shape shrinks.
    func setCovered(_ covered: Bool) {
        guard covered != isCovered else { return }
        isCovered = covered
        fadeOpacity(of: cover, to: covered ? 1 : 0, duration: covered ? 0.2 : 0.12)
        if let haloLayer = haloBox.layer {
            fadeOpacity(of: haloLayer, to: covered ? 0 : 1, duration: covered ? 0.18 : 0.3)
        }
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

    func cut(to shape: NotchShape, size: CGSize, cardSize: CGSize) {
        self.shape = shape
        self.size = size
        self.cardSize = cardSize
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
        fade.frame = CGRect(x: (bounds.width - cardSize.width) / 2, y: 0, width: cardSize.width, height: cardSize.height)
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
