import SwiftUI
import AppKit

struct CompactNotchView: View {
    @ObservedObject var media: PlaybackCoordinator
    let collapsedSize: CGSize
    /// On a real notch the centre gap reserves room for the camera housing. A
    /// floating pill has no camera to avoid, so the space is reclaimed.
    let isPhysicalNotch: Bool

    init(media: PlaybackCoordinator, collapsedSize: CGSize, isPhysicalNotch: Bool) {
        self.media = media
        self.collapsedSize = collapsedSize
        self.isPhysicalNotch = isPhysicalNotch
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // ── Left Ear: mini artwork + track title ──
            HStack(spacing: 5) {
                // Tiny glowing album art
                Group {
                    if let art = media.currentTrack.artworkImage {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3.5))
                            .shadow(color: accentColor.opacity(0.5), radius: 3, y: 0)
                    } else {
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(accentColor.opacity(0.4))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Image(systemName: media.currentTrack.isPlaying ? "play.fill" : "pause.fill")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(Theme.Text.primary)
                            )
                    }
                }
                
                // Track title. Collapsed, nothing moves: long titles are
                // truncated rather than scrolled, so the notch costs zero
                // frames while it sits there. Scrolling lives in the card.
                if media.currentTrack.isPlaying {
                    Text("\(media.currentTrack.title)  ·  \(media.currentTrack.artist)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: 14)
                } else {
                    Text(media.currentTrack.title)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Text.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            
            // ── Center gap (camera housing) — only on a real notch ──
            if isPhysicalNotch {
                Color.clear
                    .frame(width: 24)
            } else {
                Spacer().frame(width: 8)
            }
            
            // ── Right Ear: waveform + progress dot ──
            HStack(spacing: 5) {
                // Tiny progress ring
                ZStack {
                    Circle()
                        .stroke(Theme.hairline, lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: media.currentTrack.progressRatio)
                        .stroke(accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 10, height: 10)
                
                // Still bars: raised while playing, flat when paused.
                WaveformVisualizer(
                    isPlaying: media.currentTrack.isPlaying,
                    animates: false,
                    tintColor: accentColor,
                    barCount: 3,
                    height: 12
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(width: collapsedSize.width, height: collapsedSize.height)
    }
    
    private var accentColor: Color {
        Theme.accent(for: media.currentTrack.source)
    }
}
