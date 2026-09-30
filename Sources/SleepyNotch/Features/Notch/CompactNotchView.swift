import SwiftUI
import AppKit

public struct CompactNotchView: View {
    @ObservedObject var media: PlaybackCoordinator
    let notchWidth: CGFloat
    let isPhysicalNotch: Bool
    
    public var body: some View {
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
                                    .foregroundColor(.white.opacity(0.9))
                            )
                    }
                }
                
                // Scrolling track title
                if media.currentTrack.isPlaying {
                    MarqueeText(
                        "\(media.currentTrack.title)  ·  \(media.currentTrack.artist)",
                        font: .system(size: 10, weight: .medium, design: .rounded),
                        color: .white.opacity(0.85),
                        speed: 22
                    )
                    .frame(height: 14)
                } else {
                    Text(media.currentTrack.title)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            
            // ── Center gap (camera area, ~24pt clear) ──
            Color.clear
                .frame(width: 24)
            
            // ── Right Ear: waveform + progress dot ──
            HStack(spacing: 5) {
                // Tiny progress ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: media.currentTrack.progressRatio)
                        .stroke(accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 10, height: 10)
                
                WaveformVisualizer(
                    isPlaying: media.currentTrack.isPlaying,
                    tintColor: accentColor,
                    barCount: 3,
                    height: 12
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(width: notchWidth, height: 32)
    }
    
    private var accentColor: Color {
        switch media.currentTrack.source {
        case .appleMusic: return Color(red: 1.0, green: 0.27, blue: 0.42)  // richer pink
        case .spotify:    return Color(red: 0.11, green: 0.84, blue: 0.42) // spotify green
        case .demo:       return Color(red: 0.33, green: 0.58, blue: 1.0)  // electric blue
        }
    }
}
