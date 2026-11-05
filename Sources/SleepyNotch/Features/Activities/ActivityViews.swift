import SwiftUI

/// Which devices just switched on, for the notice.
struct PrivacyNotice: Equatable {
    var mic: Bool
    var camera: Bool
}

/// The camera or mic just switched on: one short row under the notch, then
/// it shrinks into its bubble. Orange for the mic and green for the camera,
/// the colours macOS's own indicators use.
struct PrivacyNoticeView: View {
    let notice: PrivacyNotice

    static let contentHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -4) {
                if notice.camera {
                    badge("video.fill", Theme.Status.charging)
                }
                if notice.mic {
                    badge("mic.fill", Theme.Status.warning)
                }
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var title: String {
        switch (notice.camera, notice.mic) {
        case (true, true): return "Camera and microphone on"
        case (true, false): return "Camera on"
        default: return "Microphone on"
        }
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 24, height: 24)
            .background(Circle().fill(color.opacity(0.2)))
            .background(Circle().fill(Color.black).padding(-1.5))
    }
}

/// An activity opened from its bubble: the charge, or the camera and mic,
/// in full. Reads the activity live, so the level ticks while it's open.
struct ActivityDetailView: View {
    let kind: ActivityKind
    @ObservedObject var activities: ActivityManager

    /// The same height as the charging card, so the notch keeps its size
    /// when one gives way to the other.
    static let contentHeight: CGFloat = ChargingPeekView.contentHeight

    var body: some View {
        let activity = activities.activity(kind)
        VStack(spacing: 0) {
            switch kind {
            case .charging:
                charging(level: activity?.level ?? 0)
            case .privacy:
                privacy(mic: activity?.micInUse ?? false, camera: activity?.cameraInUse ?? false)
            case .music:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Charging

    private func charging(level: Int) -> some View {
        VStack(spacing: 0) {
            header(title: "Charging", subtitle: level >= 100 ? "Fully charged" : "Power adapter connected")
                .padding(.top, 16)
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                BatteryGlyph(fraction: Double(level) / 100, tint: Theme.Status.charging)
                    .overlay {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1.5)
                            .offset(x: -2.5)
                    }
                Text("\(level)%")
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.Text.primary)
            }
            .padding(.bottom, 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Charging, \(level) percent")
    }

    // MARK: - Camera and mic

    private func privacy(mic: Bool, camera: Bool) -> some View {
        VStack(spacing: 0) {
            header(
                title: camera && mic ? "Camera and microphone" : camera ? "Camera" : "Microphone",
                subtitle: "In use"
            )
            .padding(.top, 16)
            Spacer(minLength: 0)
            HStack(spacing: 28) {
                device("video.fill", "Camera", on: camera, color: Theme.Status.charging)
                HStack(spacing: 14) {
                    device("mic.fill", "Microphone", on: mic, color: Theme.Status.warning)
                    if mic {
                        MicWaveView(barCount: 6, barWidth: 3, spacing: 3, height: 24, animates: true)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .accessibilityElement(children: .combine)
    }

    private func device(_ symbol: String, _ name: String, on: Bool, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(on ? color : Theme.Text.tertiary)
                .frame(width: 38, height: 38)
                .background(Circle().fill((on ? color : Color.white).opacity(on ? 0.2 : 0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(on ? Theme.Text.primary : Theme.Text.tertiary)
                Text(on ? "On" : "Off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(on ? color : Theme.Text.tertiary)
            }
        }
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
                .fixedSize()
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
    }
}
