import SwiftUI

/// Caps Lock or the keyboard layout changing, shown as the key itself: a
/// keycap that presses down and, for Caps Lock, lights its green LED like
/// the real key — then the name and state beside it.
struct KeyboardPeekView: View {
    let event: KeyboardEvent
    /// Draws the settled state straight away, for previews.
    var startSettled = false

    @StateObject private var press = KeyPress()

    var body: some View {
        HStack(spacing: 16) {
            Keycap(
                symbol: symbol,
                led: ledState,
                isPressed: press.isDown
            )

            VStack(alignment: .leading, spacing: 3) {
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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .onAppear {
            if startSettled { press.settle() } else { press.run() }
        }
    }

    /// The LED: off until the press lands, then the new state.
    private var ledState: Keycap.LED {
        guard case .capsLock(let on) = event else { return .none }
        return press.hasLanded ? (on ? .on : .off) : (on ? .off : .on)
    }

    /// "On" reads in the LED's green, so the state is clear at a glance.
    private var subtitleColor: Color {
        if case .capsLock(let on) = event, press.hasLanded, on { return Theme.Status.charging }
        return Theme.Text.secondary
    }

    private var symbol: String {
        switch event {
        case .capsLock: return "capslock.fill"
        case .inputSource: return "globe"
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

/// A single key, drawn like the Mac's: a rounded cap with the glyph, and
/// an optional LED in its top-left corner.
struct Keycap: View {
    enum LED { case none, on, off }

    let symbol: String
    let led: LED
    let isPressed: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isPressed ? 0.16 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                )
            // The key's lower lip, which the press closes up.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(height: 3)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(isPressed ? 0 : 1)

            if led != .none {
                Capsule()
                    .fill(led == .on ? Theme.Status.charging : Color.white.opacity(0.18))
                    .frame(width: 8, height: 3)
                    .padding(.top, 6)
                    .padding(.leading, 7)
            }

            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, led == .none ? 0 : 4)
        }
        .frame(width: 44, height: 40)
        .scaleEffect(isPressed ? 0.92 : 1)
        .offset(y: isPressed ? 1.5 : 0)
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: isPressed)
        .animation(.easeOut(duration: 0.12), value: led)
    }
}

/// The press: down as the peek opens, then up, with the state flipping as
/// it lands. See `NotchInteractionState` for why this isn't `@State`.
private final class KeyPress: ObservableObject {
    @Published var isDown = false
    @Published var hasLanded = false

    func run() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            self.isDown = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.easeOut(duration: 0.15)) { self.hasLanded = true }
            self.isDown = false
        }
    }

    func settle() {
        hasLanded = true
    }
}
