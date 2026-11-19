import SwiftUI

/// Page five: the lock screen. A sample lock screen steps through the three
/// looks (pill, player, full-screen art) and the list names everything the
/// lock screen can do, with the two switches that matter.
struct OnboardingLockStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var preferences: HUDPreferences
    let shown: Bool

    private static let cover = DemoArtwork.cover(0)
    private static let sampleSize = CGSize(width: 292, height: 200)
    private static let nextCovers: [NSImage] = (1..<4).map { DemoArtwork.cover($0) }
    private static let nextTitles = ["Slow Light", "Paper Moons", "Low Tide"]

    private struct Feature: Identifiable {
        var id: String { title }
        let symbol: String
        let title: String
        let detail: String
        let stage: LockSampleStage
    }

    private static let features: [Feature] = [
        Feature(symbol: "capsule.fill", title: "Glass pill", detail: "Above the lock screen clock", stage: .pill),
        Feature(symbol: "rectangle.expand.vertical", title: "Player", detail: "Scrub, skip and pause", stage: .card),
        Feature(symbol: "photo.fill", title: "Full-screen art", detail: "The cover, large and slowly drifting", stage: .art),
        Feature(symbol: "list.bullet", title: "Playing Next", detail: "Apple Music's queue", stage: .art),
        Feature(symbol: "play.rectangle.fill", title: "Animated covers", detail: "With your MusicKit token, in Settings", stage: .art),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                step: .lockScreen,
                title: "Your music, on the lock screen",
                subtitle: "Control what's playing without unlocking. Pick a look to preview it.",
                shown: shown
            )
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 12) {
                    sample
                    stagePicker
                    Text(caption)
                        .font(OnboardingStyle.small)
                        .foregroundColor(OnboardingStyle.tertiaryText)
                        .multilineTextAlignment(.center)
                        .frame(width: 292, height: 16, alignment: .top)
                        .rise(4, shown)
                }
                .rise(2, shown)
                features
                    .frame(width: 280, alignment: .leading)
            }
        }
    }

    private var caption: String {
        switch model.lockStage {
        case .pill: return "There while music plays. Click it to open the player."
        case .card: return "Play, skip and scrub without unlocking."
        case .art: return "Click the cover: the art fills the screen."
        }
    }

    // MARK: - Sample

    private var sample: some View {
        let stage = model.lockStage
        return ZStack(alignment: .top) {
            Wallpaper()
            if stage == .art {
                art.transition(.opacity)
            } else {
                VStack(spacing: 5) {
                    Text("Tuesday 17 November")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                    Text("9:41")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer(minLength: 0)
                }
                .padding(.top, 26)
                .transition(.opacity)
                VStack {
                    Spacer().frame(height: stage == .pill ? 118 : 92)
                    glass { stage == .pill ? AnyView(pill) : AnyView(playerCard) }
                        .frame(width: stage == .pill ? 190 : 240, height: stage == .pill ? 38 : 96)
                    Spacer(minLength: 0)
                }
            }
        }
        .overlay(alignment: .top) {
            NotchShape(bottomRadius: 7, topFlare: 4).fill(Color.black).frame(width: 84, height: 15)
        }
        .frame(width: Self.sampleSize.width, height: Self.sampleSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OnboardingStyle.stroke, lineWidth: 1))
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: stage)
    }

    private func glass<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: model.lockStage == .pill ? 19 : 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.25))
            )
            .clipShape(RoundedRectangle(cornerRadius: model.lockStage == .pill ? 19 : 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: model.lockStage == .pill ? 19 : 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
            )
    }

    private var pill: some View {
        HStack(spacing: 8) {
            Image(nsImage: Self.cover).resizable().scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("Night Drive")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
            Spacer(minLength: 0)
            Image(systemName: "pause.fill").font(.system(size: 10)).foregroundColor(.white)
        }
        .padding(.horizontal, 10)
    }

    private var playerCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(nsImage: Self.cover).resizable().scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Night Drive").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    Text("Sample Artist").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white).frame(width: proxy.size.width * 0.38)
                }
            }
            .frame(height: 3)
            HStack(spacing: 26) {
                Image(systemName: "backward.fill")
                Image(systemName: "pause.fill").font(.system(size: 14))
                Image(systemName: "forward.fill")
            }
            .font(.system(size: 11))
            .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
    }

    /// The full-screen look: the cover large behind, the song along the
    /// bottom and the Playing Next panel at the right.
    private var art: some View {
        ZStack {
            Image(nsImage: Self.cover).resizable().scaledToFill()
                .frame(width: Self.sampleSize.width, height: Self.sampleSize.height)
                .scaleEffect(1.25)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack {
                HStack {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.ultraThinMaterial))
                    Spacer()
                    Text("9:41").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white)
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Night Drive").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        HStack(spacing: 14) {
                            Image(systemName: "backward.fill")
                            Image(systemName: "pause.fill")
                            Image(systemName: "forward.fill")
                        }
                        .font(.system(size: 9)).foregroundColor(.white)
                    }
                    Spacer()
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 8)).foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(10)
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 5) {
                    Text("Playing Next").font(.system(size: 8, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 5) {
                            Image(nsImage: Self.nextCovers[i]).resizable().scaledToFill()
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            Text(Self.nextTitles[i]).font(.system(size: 8.5)).foregroundColor(.white)
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial).overlay(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
                .padding(.trailing, 10)
            }
        }
    }

    private var stagePicker: some View {
        HStack(spacing: 8) {
            ForEach(LockSampleStage.allCases, id: \.self) { stage in
                ChoiceChip(title: stage.title, selected: model.lockStage == stage) {
                    model.lockStage = stage
                }
            }
        }
        .rise(3, shown)
    }

    // MARK: - Features

    private var features: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What it can do")
                .font(OnboardingStyle.label)
                .foregroundColor(OnboardingStyle.secondaryText)
                .padding(.bottom, 1)
                .rise(2, shown)
            ForEach(Array(Self.features.enumerated()), id: \.element.id) { index, feature in
                HoverReader { hovering in row(feature, hovering: hovering) }
                    .rise(2 + index / 2, shown)
            }
        }
    }

    private func toggle(for feature: Feature) -> Binding<Bool>? {
        switch feature.title {
        case "Glass pill": return $preferences.lockScreenCard
        case "Playing Next": return $preferences.playingNext
        default: return nil
        }
    }

    private func row(_ feature: Feature, hovering: Bool) -> some View {
        let active = model.lockStage == feature.stage
        return Button {
            model.lockStage = feature.stage
        } label: {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: feature.symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(active ? .black : .white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(active ? Color.white : Color.white.opacity(0.08))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title)
                        .font(OnboardingStyle.heading)
                        .foregroundColor(.white.opacity(active ? 1 : 0.85))
                    Text(feature.detail)
                        .font(OnboardingStyle.small)
                        .foregroundColor(active ? OnboardingStyle.secondaryText : OnboardingStyle.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let isOn = toggle(for: feature) {
                    Toggle(feature.title, isOn: isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .focusable(false)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(active || hovering ? OnboardingStyle.surfaceHover : OnboardingStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(active ? 0.4 : hovering ? 0.2 : 0.08), lineWidth: 1)
            )
            .lifted(hovering)
            .animation(OnboardingStyle.select, value: active)
        }
        .buttonStyle(OnboardingPressStyle())
        .accessibilityLabel(feature.title)
    }
}
