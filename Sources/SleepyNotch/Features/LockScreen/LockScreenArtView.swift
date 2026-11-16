import SwiftUI

/// The album art filling the lock screen, opened by clicking the cover on
/// the lock screen card. The art fills the screen sharp and drifts slowly;
/// with a MusicKit token saved, Apple Music's animated cover plays over it
/// instead. The clock sits small at the top; the song, scrubber, controls
/// and volume sit along the bottom over a dark fade; Playing Next opens in
/// a glass panel on the right. Clicking the art itself goes back.
struct LockScreenArtView: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject var power: PowerStateMonitor
    @ObservedObject var state: LockScreenCardState
    @ObservedObject var preferences: HUDPreferences
    @ObservedObject var model: LockScreenArtModel
    @ObservedObject var upNext: UpNextService
    let screenSize: CGSize

    private var track: TrackInfo { media.currentTrack }
    private var shown: Bool { model.isShown }
    private static let rise = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)
    private static let controlsWidth: CGFloat = 520

    var body: some View {
        ZStack {
            artwork
            // Anywhere on the art itself goes back to the lock screen.
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 0) {
                clock
                    .padding(.top, 36)
                Spacer(minLength: 0)
                controls
                    .padding(.bottom, screenSize.height * 0.09)
            }

            corners
            queuePanel
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .environment(\.colorScheme, .dark)
        .environment(\.notchCardActive, true)
        .onAppear { model.load(for: track, upNext: upNext) }
        .onChange(of: track.identityKey) { _ in model.load(for: track, upNext: upNext) }
    }

    // MARK: - Art

    private var artwork: some View {
        ZStack {
            DriftingArtworkView(image: model.largeArtwork ?? track.artworkImage, blurred: false)
            LoopingVideoView(url: model.motionURL)
            // Shade for the clock and the controls; the middle stays clear.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.2),
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.78), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 1.04)
        .animation(.easeOut(duration: 0.6), value: shown)
    }

    // MARK: - Clock

    /// The art covers the system's clock, so it shows its own, in one line.
    private var clock: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(context.date, style: .time)
                    .foregroundColor(.white)
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .foregroundColor(.white.opacity(0.6))
            }
            .font(.system(size: 30, weight: .bold))
            .monospacedDigit()
        }
        .shadow(color: .black.opacity(0.3), radius: 10, y: 2)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : -10)
        .animation(Self.rise.delay(0.1), value: shown)
        .allowsHitTesting(false)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                roundButton(model.showsQueue ? "list.bullet.circle.fill" : "list.bullet", label: "Playing Next") {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { model.showsQueue.toggle() }
                }
            }
            PlayerScrubber(media: media, power: power, accentColor: .white, onLockScreen: true)
                .frame(height: 18)
            TransportControls(media: media)
                .frame(width: 300, height: 44)
                .scaleEffect(1.3)
                .padding(.vertical, 8)
            volume
            Text("Press Esc or click the art to go back")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .padding(.top, 4)
        }
        .frame(width: Self.controlsWidth)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 24)
        .animation(Self.rise.delay(0.18), value: shown)
    }

    private var volume: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
            VolumeBar(value: model.volume) { model.setVolume($0) }
                .frame(height: 16)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 2)
    }

    /// Ways back to the lock screen: Done at the top right, the close button
    /// at the bottom left (and Esc, any key, or a click on the art).
    private var corners: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: close) {
                    Text("Done")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(GlassPanelBackground(cornerRadius: 17, tint: 0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(PressScaleButtonStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Back to the lock screen")
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            Spacer()
            HStack {
                roundButton("xmark", label: "Back to the lock screen", size: 44) { close() }
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .opacity(shown ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.3), value: shown)
    }

    private func roundButton(_ symbol: String, label: String, size: CGFloat = 38, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(GlassPanelBackground(cornerRadius: size / 2, tint: 0.15))
                .clipShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Playing Next

    private var queuePanel: some View {
        HStack {
            Spacer()
            if model.showsQueue {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playing Next")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.bottom, 8)
                    if track.source != .appleMusic {
                        note("Playing Next is only available for Apple Music.")
                    } else if upNext.items.isEmpty {
                        note("Nothing queued, or shuffle is on.")
                    } else {
                        ForEach(upNext.items) { item in
                            Button { upNext.play(item) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(item.artist)
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 10)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                            }
                            .buttonStyle(PressScaleButtonStyle())
                        }
                    }
                }
                .padding(20)
                .frame(width: 300, alignment: .topLeading)
                .background(GlassPanelBackground(cornerRadius: 26, tint: 0.3))
                .padding(.trailing, 40)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundColor(.white.opacity(0.6))
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.3)) { state.showsArt = false }
    }
}

/// A thin white bar to drag, for the system volume.
private struct VolumeBar: View {
    let value: Double
    let set: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22)).frame(height: 5)
                Capsule().fill(Color.white).frame(width: max(5, proxy.size.width * value), height: 5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                set(min(1, max(0, drag.location.x / max(1, proxy.size.width))))
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
