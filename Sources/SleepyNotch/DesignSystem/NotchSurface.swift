import SwiftUI
import AppKit

/// What the notch's body is made of.
enum NotchFinish: String, CaseIterable {
    /// Black where it meets the hardware notch, melting into Liquid Glass
    /// below it.
    case glass
    /// Solid black all the way down, like the hardware cutout.
    case black

    var title: String {
        switch self {
        case .glass: "Liquid Glass"
        case .black: "Black"
        }
    }

    var summary: String {
        switch self {
        case .glass: "Black at the top, melting into glass along the bottom."
        case .black: "Solid black, like the notch itself."
        }
    }

    /// Glass needs macOS 26. Older systems always get black.
    var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return self == .black
    }
}

/// The notch's body, drawn in the chosen finish.
///
/// With glass, only the open card gets it, and only along the bottom: the
/// top stays pure black, then dissolves into glass. The camera sits in a
/// display cutout, so anything lighter than black near it shows the cutout
/// as a black block; keeping the top black lets the card and the hardware
/// notch read as one piece. Peeks and the closed notch are solid black.
///
/// The glass is macOS's own Liquid Glass view, resized on every frame of the
/// notch's spring to the card's body (see `GlassBackdrop`). SwiftUI's glass
/// couldn't be made to follow the motion: masked, it redrew as it was
/// uncovered and arrived after the card had opened; clipped, it jumped to
/// the final size, so the bottom of a closing card went see-through. The
/// black fade over it is drawn once at the open card's size and cut out by
/// the moving shape.
struct NotchSurface: View {
    /// The shape and size right now, animated by the caller.
    let shape: NotchShape
    let size: CGSize
    /// The open card's size, which the black fade is drawn at.
    let cardSize: CGSize
    let finish: NotchFinish
    /// True unless the card is open. Peeks reach down into the glass area
    /// and stay solid black, and on the way closed the cover darkens the
    /// glass as the shape shrinks over it.
    let coversGlass: Bool

    /// Where black starts giving way to glass, and where it's all glass, as
    /// fractions of the shape's height. A tall blend, so the black
    /// dissolves into the glass gradually rather than meeting it at a seam.
    private static let blendStart: CGFloat = 0.3
    private static let blendEnd: CGFloat = 0.76

    var body: some View {
        if #available(macOS 26, *), finish == .glass {
            // Glass, the black fade over it and the black cover all live in
            // one stack of Core Animation layers under one cut-out (see
            // `GlassHostView`). Drawn as SwiftUI shapes, the fade was
            // repainted pixel by pixel on the processor every frame.
            GlassBackdrop(shape: shape, size: size, covered: coversGlass)
                .frame(width: cardSize.width, height: cardSize.height)
                .frame(width: cardSize.width, height: cardSize.height, alignment: .top)
        } else {
            shape
                .fill(Theme.notchFill)
                .frame(width: size.width, height: size.height)
        }
    }

    /// Black on top dissolving to clear, as (location, opacity) pairs down
    /// the shape, along an S-curve so the seam has no visible edge.
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

// MARK: - Native glass

/// macOS's Liquid Glass view, cut to the notch's shape as it moves.
///
/// The glass itself is never resized: it's laid out once at the open card's
/// size, and each frame only the cut-out over it changes — a single path on
/// its container's mask. Resizing it every frame re-ran its own layout and
/// cost the app about 15% CPU while the notch moved. An `Animatable` view, so
/// SwiftUI hands it the spring's in-between shape on every frame. (Marking
/// the representable itself `Animatable` isn't enough: it only ever got the
/// final shape.)
@available(macOS 26, *)
private struct GlassBackdrop: View, Animatable {
    var shape: NotchShape
    var size: CGSize
    var covered: Bool

    var animatableData: AnimatablePair<NotchShape.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shape.animatableData, AnimatablePair(size.width, size.height)) }
        set {
            shape.animatableData = newValue.first
            size = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    var body: some View {
        NativeGlass(shape: shape, size: size, covered: covered)
    }
}

@available(macOS 26, *)
private struct NativeGlass: NSViewRepresentable {
    let shape: NotchShape
    let size: CGSize
    let covered: Bool

    func makeNSView(context: Context) -> GlassHostView {
        GlassHostView()
    }

    func updateNSView(_ view: GlassHostView, context: Context) {
        view.cut(to: shape, size: size)
        view.setCovered(covered)
    }
}

@available(macOS 26, *)
private final class GlassHostView: NSView {
    private let glass = NSGlassEffectView()
    private let cutout = CAShapeLayer()
    /// Black at the top dissolving into the glass, sized to the shape.
    private let fade = CAGradientLayer()
    /// Solid black over everything while closed or peeking.
    private let cover = CALayer()
    private var isCovered = true
    private var shape = NotchShape(bottomRadius: 0)
    private var size: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.style = .regular
        // A light tint: glassy, while still dark enough for white text and
        // controls over a bright desktop.
        glass.tintColor = NSColor.black.withAlphaComponent(0.16)
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
        fade.colors = NotchSurface.blackFade.map { NSColor.black.withAlphaComponent($0.opacity).cgColor }
        fade.locations = NotchSurface.blackFade.map { NSNumber(value: Double($0.location)) }
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        cover.backgroundColor = NSColor.black.cgColor
        layer?.mask = cutout
    }

    /// The fade and cover sit above the glass view's own layer.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let layer, fade.superlayer == nil else { return }
        layer.addSublayer(fade)
        layer.addSublayer(cover)
    }

    /// Opening, the cover lifts quickly so the glass is there from the start
    /// of the motion; closing, it settles back more gently as the shape
    /// shrinks over the glass.
    func setCovered(_ covered: Bool) {
        guard covered != isCovered else { return }
        isCovered = covered
        let from = cover.presentation()?.opacity ?? cover.opacity
        let to: Float = covered ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cover.opacity = to
        CATransaction.commit()
        let fadeAnimation = CABasicAnimation(keyPath: "opacity")
        fadeAnimation.fromValue = from
        fadeAnimation.toValue = to
        fadeAnimation.duration = covered ? 0.24 : 0.1
        fadeAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        cover.add(fadeAnimation, forKey: "cover")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// Purely visual: clicks go to the card above it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func cut(to shape: NotchShape, size: CGSize) {
        self.shape = shape
        self.size = size
        updateCutout()
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        updateCutout()
    }

    private func updateCutout() {
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cutout.frame = bounds
        cutout.path = shape.path(in: rect).cgPath
        fade.frame = rect
        cover.frame = bounds
        CATransaction.commit()
    }
}
