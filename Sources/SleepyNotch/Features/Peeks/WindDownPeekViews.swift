import SwiftUI

/// Plays an entrance once, a moment after appearing. View state lives in a
/// small object, as elsewhere in the app.
private final class Entrance: ObservableObject {
    @Published var shown = false

    func play(after delay: TimeInterval = 0.12) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.shown = true }
    }
}

/// The bedtime reminder: the moon rises into place, then the words. It plays
/// once and rests; nothing moves after that.
struct WindDownPeekView: View {
    let bedtime: String

    static let contentHeight: CGFloat = 78

    @StateObject private var entrance = Entrance()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rise = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)

    var body: some View {
        let shown = entrance.shown || reduceMotion
        HStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(Theme.Text.primary)
                .offset(y: shown ? 0 : 14)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? nil : Self.rise, value: shown)
            VStack(alignment: .leading, spacing: 2) {
                Text("Time to wind down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text("Bedtime is \(bedtime)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
            }
            .offset(y: shown ? 0 : 10)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? nil : Self.rise.delay(0.18), value: shown)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 6)
        .onAppear { entrance.play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time to wind down. Bedtime is \(bedtime).")
    }
}

/// When the sleep timer ends: "Good night" written out by a pen, the way
/// the startup hello is.
struct GoodNightPeekView: View {
    static let contentHeight: CGFloat = 88

    /// A handwriting face that ships with macOS. If it's missing the system
    /// font stands in.
    private static let font: NSFont = NSFont(name: "SnellRoundhand-Bold", size: 38)
        ?? NSFont(name: "Snell Roundhand", size: 38)
        ?? NSFont.systemFont(ofSize: 30, weight: .light)

    var body: some View {
        WrittenCaption(
            text: "Good night",
            delay: 0.25,
            duration: 1.3,
            font: Self.font,
            color: NSColor.white.withAlphaComponent(0.9)
        )
        .frame(width: 240, height: 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Good night. Music paused.")
    }
}
