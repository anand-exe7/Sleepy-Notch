import SwiftUI

/// Page four: the music card's look. A sample card on the left changes as
/// each option is picked: the cover change plays, the finish swaps, the
/// colour moves into the bars and the progress line.
struct OnboardingPlayerStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var preferences: HUDPreferences
    let shown: Bool

    /// Made-up songs for the sample card.
    private static let songs = ["Night Drive", "Slow Light", "Paper Moons", "Low Tide"]
    private static let covers: [NSImage] = (0..<4).map { DemoArtwork.cover($0) }
    /// Roughly each sample cover's own colour, for "Match the album's colour".
    private static let albumColours: [Color] = [
        Color(red: 0.91, green: 0.87, blue: 0.79),
        Color(red: 0.9, green: 0.85, blue: 0.74),
        Color(red: 0.92, green: 0.5, blue: 0.36),
        Color(red: 0.66, green: 0.8, blue: 0.6),
    ]

    private var tint: Color {
        if preferences.albumTint { return Self.albumColours[model.coverIndex] }
        if preferences.highlight == .multicolour {
            return HighlightColour.rolled[model.coverIndex % HighlightColour.rolled.count].color
        }
        return preferences.highlight.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                step: .player,
                title: "Make the player yours",
                subtitle: "Pick how the music card looks. The sample changes as you choose.",
                shown: shown
            )
            HStack(alignment: .top, spacing: 28) {
                sample
                    .rise(2, shown)
                options
                    .frame(width: 280, alignment: .leading)
            }
        }
    }

    // MARK: - Sample

    private var sample: some View {
        VStack(spacing: 10) {
            ScreenPreview(notchWidth: 254, notchHeight: 150, glass: preferences.finish == .glass) {
                card.padding(.top, 34)
            }
            .frame(width: 292, height: 204)
            .animation(.easeInOut(duration: 0.35), value: preferences.finish)
            Button {
                model.playCoverChange()
            } label: {
                Label("Play the next song", systemImage: "forward.fill")
                    .font(OnboardingStyle.small.weight(.medium))
                    .foregroundColor(OnboardingStyle.secondaryText)
            }
            .buttonStyle(OnboardingPressStyle())
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                ArtworkTransitionContainer(
                    key: "\(model.coverIndex)",
                    style: preferences.artworkStyle,
                    size: 50,
                    cornerRadius: 10
                ) {
                    CoverArtView(image: Self.covers[model.coverIndex], size: 50, cornerRadius: 10)
                }
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.songs[model.coverIndex])
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Sample Artist")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.6))
                }
                .id(model.coverIndex)
                .transition(.opacity)
                Spacer(minLength: 0)
                EqualizerBars(isPlaying: true, animates: shown, color: tint)
                    .frame(width: 18, height: 14)
            }
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(tint).frame(width: proxy.size.width * 0.38)
                    }
                }
                .frame(height: 3)
                HStack {
                    Text("1:12")
                    Spacer()
                    Text("\u{2212}2:04")
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.45))
            }
            HStack(spacing: 30) {
                Image(systemName: "backward.fill")
                Image(systemName: "pause.fill").font(.system(size: 17))
                Image(systemName: "forward.fill")
            }
            .font(.system(size: 13))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.3), value: model.coverIndex)
        .animation(.easeInOut(duration: 0.3), value: tint)
    }

    // MARK: - Options

    private var options: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Cover change", order: 3) {
                HStack(spacing: 8) {
                    ForEach(ArtworkTransitionStyle.allCases, id: \.self) { style in
                        ChoiceChip(title: style.title, selected: preferences.artworkStyle == style) {
                            model.chooseCoverChange(style)
                        }
                    }
                }
            } note: { preferences.artworkStyle.summary }

            section("Finish", order: 4) {
                HStack(spacing: 8) {
                    ForEach(NotchFinish.allCases.filter(\.isAvailable), id: \.self) { finish in
                        ChoiceChip(title: finish.title, selected: preferences.finish == finish) {
                            preferences.finish = finish
                        }
                    }
                }
            } note: { preferences.finish.summary }

            section("Colour", order: 5) {
                HStack(spacing: 3) {
                    ForEach(HighlightColour.allCases) { colour in
                        swatch(colour)
                    }
                }
                .opacity(preferences.albumTint ? 0.35 : 1)
                .disabled(preferences.albumTint)
            } note: { nil }

            VStack(alignment: .leading, spacing: 10) {
                OnboardingToggle(title: "Match the album's colour", isOn: $preferences.albumTint)
                OnboardingToggle(title: "Cover beside the closed notch", isOn: $preferences.nowPlayingWings)
                OnboardingToggle(title: "Notice when the song changes", isOn: $preferences.songChangePeek)
            }
            .padding(.top, 2)
            .rise(6, shown)
        }
    }

    private func section<Content: View>(
        _ title: String,
        order: Int,
        @ViewBuilder content: () -> Content,
        note: () -> String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(OnboardingStyle.label)
                .foregroundColor(OnboardingStyle.secondaryText)
            content()
            if let note = note() {
                Text(note)
                    .font(OnboardingStyle.small)
                    .foregroundColor(OnboardingStyle.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        }
        .rise(order, shown)
    }

    private func swatch(_ colour: HighlightColour) -> some View {
        let selected = preferences.highlight == colour
        return Button {
            preferences.highlight = colour
        } label: {
            ZStack {
                if colour == .multicolour {
                    Circle().fill(AngularGradient(colors: HighlightColour.rolled.map(\.color) + [HighlightColour.rolled[0].color], center: .center))
                } else {
                    Circle().fill(colour.color)
                }
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .padding(-4)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.7)
            }
            .frame(width: 18, height: 18)
            .padding(5)
            .animation(OnboardingStyle.select, value: selected)
        }
        .buttonStyle(OnboardingPressStyle())
        .help(colour.title)
        .accessibilityLabel(colour.title)
    }
}
