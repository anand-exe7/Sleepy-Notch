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
        case .glass: "Black at the top, a soft blur along the bottom."
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
    /// fractions of the shape's height: solid black behind the notch and the
    /// title, then a long, slow fade into the glass, so the blur grows in
    /// gradually down the card instead of starting at a band. (At 0.7 the
    /// whole change happened in a short strip behind the play controls and
    /// read as a grey stripe.)
    static let blendStart: CGFloat = 0.5
    private static let blendEnd: CGFloat = 1
    /// How much black stays over the glass even at the very bottom. At 0.2
    /// the lower third turned pale grey over a light window: words behind
    /// the card read through it and the white controls lost their contrast.
    /// Kept this dark, the glass is a smoked edge (its blur and sheen still
    /// show) and nothing behind it can be read.
    ///
    /// The bottom is a plain blur now (no Liquid Glass sheen), over the
    /// last 30% only, solid under the fade; half black over it keeps it
    /// dark and smoky, so white controls read and what's behind is only a
    /// soft smear of colour.
    ///
    /// With Liquid Glass (macOS 26) little black stays over the glass, so
    /// its lit rim and lensing show at full strength; the darkness comes
    /// from the smoke layer under the glass instead (see `GlassHostView`).
    private static let blackFloor: CGFloat = {
        if #available(macOS 26, *) { return 0.12 }
        return 0.4
    }()

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
        // Smoothstep (3t² − 2t³) sampled finely: zero slope at both ends,
        // so neither end of the blend shows a line, but the change is spread
        // over the whole blend. (Smootherstep packed it into the middle,
        // which read as a band.)
        let steps = 32
        var stops: [(CGFloat, CGFloat)] = [(0, 1)]
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let amount = t * t * (3 - 2 * t)
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

/// Layers, back to front:
/// - the blur, cut to the shape and faded out above the blend by its own
///   mask image, so it's only there along the bottom;
/// - the black fade: solid black down to the blend, then dissolving;
/// - the cover: solid black over everything while closed.
///
/// The blur must have no masked layer above it: a behind-window blur under
/// a layer mask stops blurring (the window server drops the backdrop and
/// what's behind shows through plainly, only dimmed). So the blur is a
/// direct child of this view, shaped by `NSVisualEffectView.maskImage`,
/// and only the black layers sit in the masked overlay.
///
/// Battery: the blur is a backdrop, which the window server blurs afresh
/// on every frame the window changes, over its whole area. While the notch
/// is closed it's hidden outright (the black cover is opaque anyway), and
/// when it shows, its frame is just the band where it can appear: below
/// the blend, inside the shape's height. Its mask image is redrawn only
/// when the shape changes, so only while the notch moves.
private final class GlassHostView: NSView {
    private let blur = GlassHostView.makeBlur()
    /// Liquid Glass over the blur on macOS 26: its refraction, sheen and
    /// lit rim along the card's bottom edge. The blur under it keeps what's
    /// behind unreadable (the glass alone blurs only lightly).
    private let glass = GlassHostView.makeLiquidGlass()
    /// Smoke between the blur and the glass. The frosted blur lifts a dark
    /// screen to a pale grey fog; darkened here first, the glass bends a
    /// dark, smoky backdrop, like the Dock's glass over a dark window.
    private let smoke = PassiveLayerView()
    private let smokeMask = CAShapeLayer()
    private static let smokeOpacity: CGFloat = 0.55
    private let overlay = PassiveLayerView()
    private let cutout = CAShapeLayer()
    /// Black at the top dissolving into the blur, sized to the shape.
    private let fade = CAGradientLayer()
    /// Solid black over everything while closed.
    private let cover = CALayer()

    private var isCovered = true
    private var hideBlur: DispatchWorkItem?
    private var glassFrom = NotchSurface.blendStart
    private var shape = NotchShape(bottomRadius: 0)
    private var size: CGSize = .zero
    private var maskedFor: (shape: NotchShape.AnimatableData, size: CGSize, box: CGRect, from: CGFloat)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        addSubview(blur)
        if let glass {
            smoke.layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.smokeOpacity).cgColor
            // A plain shape mask is fine here: the smoke isn't a backdrop.
            smoke.layer?.mask = smokeMask
            smoke.isHidden = true
            addSubview(smoke)
            glass.isHidden = true
            addSubview(glass)
        }
        addSubview(overlay)

        let stops = NotchSurface.blackFade(from: glassFrom)
        fade.colors = stops.map { NSColor.black.withAlphaComponent($0.opacity).cgColor }
        fade.locations = stops.map { NSNumber(value: Double($0.location)) }
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        // Rendered with more than 8 bits per channel: half a step of black
        // over a few dozen points otherwise shows as visible stripes.
        fade.contentsFormat = .RGBA16Float
        // Closed at first: nothing behind the cover is rendered.
        blur.isHidden = true
        cover.backgroundColor = NSColor.black.cgColor
        overlay.layer?.addSublayer(fade)
        overlay.layer?.addSublayer(cover)
        overlay.layer?.mask = cutout
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// Purely visual: clicks go to the card above it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A plain dark blur (the user asked for a blur, not Liquid Glass,
    /// whose sheen and lit rim read as a pale panel over light windows).
    private static func makeBlur() -> NSVisualEffectView {
        let frosted = NSVisualEffectView()
        frosted.material = .hudWindow
        frosted.blendingMode = .behindWindow
        frosted.state = .active
        frosted.appearance = NSAppearance(named: .darkAqua)
        return frosted
    }

    private static func makeLiquidGlass() -> NSView? {
        guard #available(macOS 26, *) else { return nil }
        let glass = NSGlassEffectView()
        // Clear, like the Dock: it bends and lights what's under it rather
        // than frosting it. The regular style frosted the bottom into a pale
        // grey fog over dark windows.
        glass.style = .clear
        glass.tintColor = NSColor.black.withAlphaComponent(0.18)
        glass.appearance = NSAppearance(named: .darkAqua)
        return glass
    }

    private func setBackdropHidden(_ hidden: Bool) {
        blur.isHidden = hidden
        smoke.isHidden = hidden || glass == nil
        glass?.isHidden = hidden
    }

    /// Opening, the cover lifts quickly so the blur is there from the start
    /// of the motion; closing, it settles back as the shape shrinks.
    func setCovered(_ covered: Bool) {
        guard covered != isCovered else { return }
        isCovered = covered
        hideBlur?.cancel()
        hideBlur = nil
        let target: Float = covered ? 1 : 0
        let from = cover.presentation()?.opacity ?? cover.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !covered { setBackdropHidden(false) }
        cover.opacity = target
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = target
        animation.duration = covered ? 0.18 : 0.12
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        cover.add(animation, forKey: "opacity")
        // Once the cover is solid, the blur under it is taken out of the
        // picture altogether, so a closed notch costs nothing for it.
        guard covered else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isCovered else { return }
            self.setBackdropHidden(true)
        }
        hideBlur = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Moves where the blur begins: the black glides there, the blur's
    /// mask follows on the next shape change or at once.
    func setGlassFrom(_ start: CGFloat) {
        guard start != glassFrom else { return }
        glassFrom = start
        let locations = NotchSurface.blackFade(from: start).map { NSNumber(value: Double($0.location)) }
        let from = fade.presentation()?.locations ?? fade.locations
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.locations = locations
        CATransaction.commit()
        let glide = CABasicAnimation(keyPath: "locations")
        glide.fromValue = from
        glide.toValue = locations
        glide.duration = 0.45
        glide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fade.add(glide, forKey: "locations")
        updateMasks()
    }

    func cut(to shape: NotchShape, size: CGSize) {
        self.shape = shape
        self.size = size
        updateMasks()
    }

    override func layout() {
        super.layout()
        overlay.frame = bounds
        updateMasks()
    }

    /// A little above where the blur begins, so its edge never shows
    /// through the start of the blend.
    private static let bandMargin: CGFloat = 12

    private func updateMasks() {
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cutout.frame = bounds
        cutout.path = shape.path(in: rect).cgPath
        // The fade only runs top to bottom, so it spans the whole width:
        // the bubbles beside the notch stay black while the card opens.
        fade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: size.height)
        cover.frame = bounds
        CATransaction.commit()

        // The blur covers just the rows where the blend lets it show,
        // across the shape's width.
        let top = max(0, size.height * glassFrom - Self.bandMargin)
        let box = CGRect(x: rect.minX, y: top, width: rect.width, height: max(0, size.height - top)).integral
        guard box.width > 0, box.height > 0 else { return }
        if let last = maskedFor, last.shape == shape.animatableData, last.size == size, last.box == box, last.from == glassFrom { return }
        maskedFor = (shape.animatableData, size, box, glassFrom)
        blur.frame = box
        blur.maskImage = Self.maskImage(shape: shape, shapeRect: rect, box: box, from: glassFrom)
        layoutGlass(shapeRect: rect, box: box)
    }

    /// The glass can't take a mask image (or a masked parent: it would stop
    /// refracting), so it's a rounded rectangle laid over the body's bottom:
    /// as wide as the body between the flares, its corners matching the
    /// shape's. Its top corners sit where the black is still solid.
    private func layoutGlass(shapeRect: CGRect, box: CGRect) {
        guard #available(macOS 26, *), let glass = glass as? NSGlassEffectView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        smoke.frame = box
        smokeMask.frame = smoke.bounds
        smokeMask.path = shape.path(in: shapeRect.offsetBy(dx: -box.minX, dy: -box.minY)).cgPath
        CATransaction.commit()
        let body = shape.bottomBody(in: shapeRect)
        glass.frame = CGRect(x: body.left, y: box.minY, width: max(0, body.right - body.left), height: box.height)
        // A Core Animation continuous corner reaches about 1.53 × its radius
        // along each edge; match the shape's reach.
        glass.cornerRadius = min(body.cornerReach / 1.53, glass.frame.height / 2, glass.frame.width / 2)
    }

    /// The shape, solid, in the box's own coordinates. The blur must be
    /// fully opaque wherever it shows: faded out by its mask (as it once
    /// was), part of the sharp background showed through the blur itself
    /// and text behind the card stayed readable. The black fade above it
    /// does all the fading, and also hides the band's top edge.
    private static func maskImage(shape: NotchShape, shapeRect: CGRect, box: CGRect, from start: CGFloat) -> NSImage {
        let path = shape.path(in: shapeRect).cgPath
        return NSImage(size: box.size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: -box.minX, y: -box.minY)
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
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
