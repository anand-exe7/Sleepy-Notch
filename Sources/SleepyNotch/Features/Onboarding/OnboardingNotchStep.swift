import SwiftUI

/// Page five: what shows beside the closed notch. How the camera, mic and
/// charge look (bubbles or inside the notch), then which notices and live
/// things are wanted.
struct OnboardingNotchStep: View {
    @ObservedObject var preferences: HUDPreferences
    let shown: Bool

    private struct Item: Identifiable {
        var id: String { title }
        let symbol: String
        let title: String
        let detail: String
        let isOn: Binding<Bool>
    }

    private var items: [Item] {
        [
            Item(symbol: "bolt.fill", title: "Charging", detail: "Plugging in, low battery", isOn: Binding(
                get: { preferences.chargingPeek },
                set: { preferences.chargingPeek = $0; preferences.chargingWing = $0 }
            )),
            Item(symbol: "airpodspro", title: "Headphones", detail: "When they connect", isOn: $preferences.headphonePeek),
            Item(symbol: "speaker.wave.2.fill", title: "Volume & brightness", detail: "Levels in the notch", isOn: $preferences.systemHUDs),
            Item(symbol: "capslock.fill", title: "Keyboard", detail: "Caps Lock and input", isOn: $preferences.keyboardPeek),
            Item(symbol: "waveform", title: "Voice waves", detail: "Mic bubble follows you", isOn: $preferences.voiceWaves),
            Item(symbol: "video.fill", title: "Meeting reminders", detail: "Five minutes before", isOn: $preferences.meetingReminders),
            Item(symbol: "timer", title: "Timers", detail: "From the menu bar", isOn: $preferences.timers),
            Item(symbol: "arrow.down.circle.fill", title: "Downloads", detail: "What's downloading", isOn: $preferences.downloads),
            Item(symbol: "record.circle", title: "Screen recording", detail: "Time while recording", isOn: $preferences.recordingTimer),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeader(
                step: .notch,
                title: "What shows around the notch",
                subtitle: "Charging, the mic and other live things show beside the notch.",
                shown: shown
            )
            HStack(spacing: 16) {
                styleCard(.bubbles)
                    .rise(2, shown)
                styleCard(.inNotch)
                    .rise(3, shown)
            }
            Text("Show me")
                .font(OnboardingStyle.label)
                .foregroundColor(OnboardingStyle.secondaryText)
                .padding(.bottom, -10)
                .rise(4, shown)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HoverReader { hovering in chip(item, hovering: hovering) }
                        .rise(4 + index / 3, shown)
                }
            }
        }
    }

    // MARK: - Style

    private func styleCard(_ style: StatusStyle) -> some View {
        OptionCard(
            title: style.title,
            detail: style == .bubbles ? "Each live thing gets its own bubble" : "Everything stays inside the notch",
            selected: preferences.statusStyle == style,
            action: { preferences.statusStyle = style }
        ) {
            ZStack(alignment: .top) {
                Wallpaper()
                StatusSample(style: style)
                    .padding(.top, 0)
            }
            .frame(width: 272, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(width: 292)
    }

    // MARK: - Chips

    private func chip(_ item: Item, hovering: Bool) -> some View {
        let on = item.isOn.wrappedValue
        return Button {
            item.isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(on ? .black : .white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(on ? Color.white : Color.white.opacity(0.08))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(on ? 1 : 0.7))
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.system(size: 10.5))
                        .foregroundColor(on ? OnboardingStyle.secondaryText : OnboardingStyle.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on || hovering ? OnboardingStyle.surfaceHover : OnboardingStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(on ? 0.35 : hovering ? 0.2 : 0.08), lineWidth: 1)
            )
            .lifted(hovering)
            .animation(OnboardingStyle.select, value: on)
        }
        .buttonStyle(OnboardingPressStyle())
        .accessibilityLabel("\(item.title), \(on ? "on" : "off")")
    }
}

/// A drawing of the closed notch while a song plays, the mic is in use and
/// the Mac is charging, in one status style: with Bubbles the song keeps
/// both wings and the others get bubbles; In the notch, the charge takes
/// the bars' place.
private struct StatusSample: View {
    let style: StatusStyle

    var body: some View {
        HStack(spacing: 6) {
            if style == .bubbles {
                bubble { Image(systemName: "mic.fill").foregroundColor(Color(nsColor: .systemOrange)) }
            }
            ZStack {
                NotchShape(bottomRadius: 10, topFlare: 5)
                    .fill(Color.black)
                HStack(spacing: 0) {
                    cover
                    Spacer(minLength: 0)
                    if style == .bubbles {
                        bars
                    } else {
                        charge
                    }
                }
                .padding(.leading, 13)
                .padding(.trailing, 12)
                .padding(.bottom, 2)
            }
            .frame(width: 168, height: 30)
            if style == .bubbles {
                bubble { Image(systemName: "battery.75percent").foregroundColor(Color(nsColor: .systemGreen)) }
            }
        }
    }

    /// The song's cover in the left wing.
    private var cover: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.95, green: 0.42, blue: 0.36), Color(red: 0.36, green: 0.16, blue: 0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: 15, height: 15)
    }

    /// The playing bars in the right wing (still: a drawing, not a dance).
    private var bars: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array([6.0, 11.0, 8.0, 10.0].enumerated()), id: \.offset) { _, height in
                Capsule().fill(Color.white.opacity(0.9)).frame(width: 2.2, height: height)
            }
        }
        .frame(height: 15)
    }

    /// The charge, in the bars' place.
    private var charge: some View {
        HStack(spacing: 2) {
            Image(systemName: "bolt.fill").font(.system(size: 7.5, weight: .bold))
            Text("63%").font(.system(size: 9.5, weight: .semibold).monospacedDigit())
        }
        .foregroundColor(Color(nsColor: .systemGreen))
    }

    private func bubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.black))
            .padding(.top, 3)
    }
}
