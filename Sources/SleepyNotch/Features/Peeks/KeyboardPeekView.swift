import SwiftUI
import AppKit

/// Caps Lock or the keyboard layout changing, as one compact row under the
/// notch: a small Mac key, and beside it the name and the state. Only as big
/// as that, so it covers as little as it can.
///
/// The key rises in on the same fast-then-gentle curve as the others,
/// presses down once, and as it comes back up its green light switches to
/// the new state. Everything is a one-shot animation.
struct KeyboardPeekView: View {
    let event: KeyboardEvent
    /// Draws the settled state straight away, for previews.
    var startSettled = false

    @StateObject private var press = KeyPress()

    /// The height the peek drops below the notch.
    static let contentHeight: CGFloat = 56
    /// The key, scaled down from its full size to sit in the row.
    private static let keyScale: CGFloat = 0.6

    var body: some View {
        HStack(spacing: 13) {
            Keycap(symbol: symbol, label: keyLabel, led: ledState, isPressed: press.isDown)
                .scaleEffect(Self.keyScale * (press.risen ? 1 : 0.7))
                .frame(width: Keycap.size.width * Self.keyScale, height: Keycap.size.height * Self.keyScale)
                .opacity(press.risen ? 1 : 0)
                .offset(y: press.risen ? 0 : 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(subtitleColor)
                    .lineLimit(1)
                    .id(subtitle)
                    .transition(.opacity)
            }
            .opacity(press.text ? 1 : 0)
            .offset(x: press.text ? 0 : -6)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if startSettled { press.settle() } else { press.run() }
        }
        .onDisappear { press.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
    }

    /// The light: the old state until the press lands, then the new one.
    private var ledState: Keycap.LED {
        guard case .capsLock(let on) = event else { return .none }
        return press.hasLanded ? (on ? .on : .off) : (on ? .off : .on)
    }

    /// "On" reads in the light's green, so the state is clear at a glance.
    private var subtitleColor: Color {
        if case .capsLock(let on) = event, press.hasLanded, on { return Theme.Status.charging }
        return Theme.Text.secondary
    }

    private var symbol: String {
        switch event {
        case .capsLock: return "capslock"
        case .inputSource: return "globe"
        }
    }

    /// Printed under the glyph, like the real keys.
    private var keyLabel: String? {
        switch event {
        case .capsLock: return nil
        case .inputSource(let name): return name
        }
    }

    private var title: String {
        switch event {
        case .capsLock: return "Caps Lock"
        case .inputSource(let name): return name
        }
    }

    private var subtitle: String {
        switch event {
        case .capsLock(let on): return press.hasLanded ? (on ? "On" : "Off") : (on ? "Off" : "On")
        case .inputSource: return "Input Source"
        }
    }
}

/// A single key, drawn like the Mac's: a softly lit cap with a fine top
/// highlight and a darker lip below, the glyph in the middle, and an
/// optional light in its top-left corner.
struct Keycap: View {
    enum LED { case none, on, off }

    let symbol: String
    var label: String? = nil
    let led: LED
    let isPressed: Bool

    static let size = CGSize(width: 68, height: 60)
    private static let corner: CGFloat = 13

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The lip under the cap, which the press closes up.
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .offset(y: isPressed ? 0 : 3)

            // The cap.
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(isPressed ? 0.15 : 0.19), Color.white.opacity(isPressed ? 0.09 : 0.11)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )

            if led != .none {
                Capsule()
                    .fill(led == .on ? Theme.Status.charging : Color.white.opacity(0.16))
                    .frame(width: 10, height: 3.5)
                    .padding(.top, 9)
                    .padding(.leading, 10)
            }

            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                if let label {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                }
            }
            .foregroundColor(Theme.Text.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, led == .none ? 0 : 5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(isPressed ? 0.94 : 1)
        .offset(y: isPressed ? 2 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isPressed)
        .animation(.easeOut(duration: 0.2), value: led)
    }
}

/// The key's beats: rising in, the press, the light changing as it comes
/// back up. See `NotchInteractionState` for why this isn't `@State`.
private final class KeyPress: ObservableObject {
    @Published var risen = false
    @Published var text = false
    @Published var isDown = false
    @Published var hasLanded = false

    private var steps: [DispatchWorkItem] = []

    /// Almost all the way at once, then a gentle glide to a stop.
    private static let rise = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)

    func run() {
        cancel()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            settle()
            return
        }
        step(at: 0.05, Self.rise) { $0.risen = true }
        step(at: 0.22, .easeOut(duration: 0.35)) { $0.text = true }
        step(at: 0.45, nil) { $0.isDown = true }
        step(at: 0.6, .easeOut(duration: 0.2)) {
            $0.hasLanded = true
            $0.isDown = false
        }
    }

    func settle() {
        risen = true
        text = true
        hasLanded = true
    }

    func cancel() {
        steps.forEach { $0.cancel() }
        steps.removeAll()
    }

    private func step(at time: TimeInterval, _ animation: Animation?, _ change: @escaping (KeyPress) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let animation {
                withAnimation(animation) { change(self) }
            } else {
                change(self)
            }
        }
        steps.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: work)
    }
}
