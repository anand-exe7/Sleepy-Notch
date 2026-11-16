import SwiftUI

/// The Controls page: four fixed toggles, like Control Center's. A lit
/// circle is on. Turning one on, the white grows out from the middle with a
/// little give and the glyph swaps with a pop; turning it off, the white
/// shrinks back. Focus shows its countdown under it while a round runs.
struct ControlsView: View {
    @ObservedObject var controls: ControlsService
    @ObservedObject var stayAwake: StayAwakeService
    @ObservedObject var pomodoro: PomodoroService
    @ObservedObject var timers: TimerService
    @Environment(\.notchCardActive) private var cardActive
    let width: CGFloat

    /// The lit circle growing in and out.
    private static let fill = Animation.spring(response: 0.28, dampingFraction: 0.62)
    /// The glyph swapping: a beat after the circle starts, so a dark glyph
    /// never shows on the dark circle before the white has grown in.
    private static let glyph = Animation.spring(response: 0.3, dampingFraction: 0.7).delay(0.07)

    var body: some View {
        let focusRound = timers.session?.pomodoro
        HStack(spacing: 18) {
            tile(
                "Dark Mode",
                symbol: controls.darkMode ? "moon.fill" : "sun.max.fill",
                on: controls.darkMode
            ) { controls.toggleDarkMode() }
            tile(
                "Mute",
                symbol: controls.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                on: controls.muted
            ) { controls.toggleMute() }
            tile(
                "Stay Awake",
                symbol: stayAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                on: stayAwake.isOn
            ) { stayAwake.toggle() }
            tile(
                "Focus",
                symbol: focusRound == .rest ? "leaf.fill" : "target",
                on: focusRound != nil,
                caption: focusCaption
            ) {
                focusRound != nil ? pomodoro.stop() : pomodoro.startFocus()
            }
        }
        .frame(width: width, height: NotchMetrics.controlsBodyHeight - 6, alignment: .center)
        .onAppear { if cardActive { controls.refresh() } }
        .onChange(of: cardActive) { active in if active { controls.refresh() } }
    }

    /// While a round runs, the time left (counted by the system, so nothing
    /// ticks here).
    @ViewBuilder
    private var focusCaption: some View {
        if let session = timers.session, session.pomodoro != nil {
            Text(timerInterval: session.start...session.end, countsDown: true, showsHours: false)
                .monospacedDigit()
        } else {
            Text("Focus")
        }
    }

    private func tile(
        _ title: String,
        symbol: String,
        on: Bool,
        action: @escaping () -> Void
    ) -> some View {
        tile(title, symbol: symbol, on: on, caption: Text(title), action: action)
    }

    private func tile<Caption: View>(
        _ title: String,
        symbol: String,
        on: Bool,
        caption: Caption,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 7) {
            Button(action: action) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.13))
                    // The lit layer grows from the middle rather than the
                    // colour switching at once.
                    Circle()
                        .fill(Color.white)
                        .scaleEffect(on ? 1 : 0.3)
                        .opacity(on ? 1 : 0)
                        .animation(Self.fill, value: on)
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(on ? .black : Theme.Text.primary)
                        .id(symbol)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .scale(scale: 1.3).combined(with: .opacity)
                        ))
                        .animation(Self.glyph, value: symbol)
                        .animation(.easeOut(duration: 0.18).delay(0.07), value: on)
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
            }
            .buttonStyle(PressScaleButtonStyle())
            caption
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(on ? Theme.Text.primary : Theme.Text.secondary)
                .lineLimit(1)
                .animation(.easeOut(duration: 0.18), value: on)
        }
        .frame(width: 62)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(on ? "on" : "off")")
        .accessibilityAddTraits(.isButton)
    }
}
