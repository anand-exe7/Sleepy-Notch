import AppKit
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

/// An activity opened from its bubble (or from the notch): the charge, or
/// the camera and mic, in full. Sized to what it shows (`size(for:)`), so
/// the notch opens only as far as it needs. Its pieces arrive one after
/// another on a spring as it opens; after that only the voice waves move.
struct ActivityDetailView: View {
    let kind: ActivityKind
    @ObservedObject var activities: ActivityManager

    @StateObject private var reveal = DetailReveal()
    @StateObject private var micApps = MicApps()

    /// Fallback height; the notch normally uses `size(for:activity:)`.
    static let contentHeight: CGFloat = 76

    /// The body's width and the height below the notch for what's showing:
    /// one row per device that's on, or the charge — with the camera and
    /// mic's rows under it when they ride on the charge.
    static func size(for kind: ActivityKind, activity: LiveActivity?, riding: LiveActivity? = nil) -> CGSize {
        switch kind {
        case .charging:
            guard let riding else { return CGSize(width: 292, height: 76) }
            let rows = privacyRows(riding)
            return CGSize(
                width: riding.micInUse ? 318 : 292,
                height: 20 + chargeRowHeight + rows * (44 + rowSpacing)
            )
        case .timer, .download:
            return CGSize(width: 292, height: 76)
        case .privacy, .music:
            let rows = activity.map(privacyRows) ?? 1
            return CGSize(width: (activity?.micInUse ?? false) ? 318 : 262, height: 30 + rows * 44 + (rows - 1) * rowSpacing)
        }
    }

    private static func privacyRows(_ activity: LiveActivity) -> CGFloat {
        CGFloat(max(1, (activity.micInUse ? 1 : 0) + (activity.cameraInUse ? 1 : 0)))
    }

    /// The camera and mic riding on the charge, shown under it.
    static func riding(on kind: ActivityKind, in activities: ActivityManager) -> LiveActivity? {
        guard kind == .charging, let privacy = activities.activity(.privacy), privacy.slot == .attached else { return nil }
        return privacy
    }

    private static let chargeRowHeight: CGFloat = 52

    private static let rowSpacing: CGFloat = 8

    var body: some View {
        let activity = activities.activity(kind)
        let riding = Self.riding(on: kind, in: activities)
        Group {
            switch kind {
            case .charging:
                if let riding {
                    // The charge first, the camera and mic under it.
                    VStack(spacing: Self.rowSpacing) {
                        charging(level: activity?.level ?? 0, compact: true)
                            .frame(height: Self.chargeRowHeight)
                        privacyRows(mic: riding.micInUse, camera: riding.cameraInUse, first: 1)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                } else {
                    charging(level: activity?.level ?? 0)
                }
            case .privacy:
                privacy(mic: activity?.micInUse ?? false, camera: activity?.cameraInUse ?? false)
            case .timer:
                TimerDetail(session: activity?.timer) { activities.cancelTimer() }
            case .download:
                DownloadDetail()
            case .music:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            micApps.refresh()
            reveal.play(level: activity?.level ?? 0)
        }
        .onChange(of: activity?.micInUse) { _ in micApps.refresh() }
        .onChange(of: riding?.micInUse) { _ in micApps.refresh() }
        .onChange(of: activity?.level) { level in reveal.fill(to: level ?? 0) }
    }

    // MARK: - Charging

    /// `compact`: a row above the camera and mic, lined up with them on
    /// the left, with a smaller battery.
    private func charging(level: Int, compact: Bool = false) -> some View {
        let tint = ChargeTint.color(forLevel: level)
        return HStack(spacing: compact ? 14 : 18) {
            BatteryGlyph(fraction: reveal.fill, tint: tint)
                .scaleEffect(compact ? 0.62 : 1, anchor: .leading)
                .frame(width: compact ? 52 : nil, height: compact ? 24 : nil, alignment: .leading)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1.5)
                        .offset(x: -2.5)
                        .scaleEffect(reveal.shown ? 1 : 0.4)
                        .opacity(reveal.shown ? 1 : 0)
                        .animation(.spring(response: 0.42, dampingFraction: 0.6).delay(0.35), value: reveal.shown)
                }
                .modifier(Arrive(shown: reveal.shown, index: 0))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(level)%")
                    .font(.system(size: compact ? 20 : 28, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.Text.primary)
                Text(level >= 100 ? "Fully charged" : "Charging")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(tint)
            }
            .modifier(Arrive(shown: reveal.shown, index: 1))
            if compact { Spacer(minLength: 0) }
        }
        .padding(.bottom, compact ? 0 : 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Charging, \(level) percent")
    }

    // MARK: - Camera and mic

    private func privacy(mic: Bool, camera: Bool) -> some View {
        VStack(spacing: Self.rowSpacing) {
            privacyRows(mic: mic, camera: camera, first: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    /// One row per device that's on; `first` is the entrance order of the
    /// first one.
    @ViewBuilder
    private func privacyRows(mic: Bool, camera: Bool, first: Int) -> some View {
            if mic {
                row(
                    symbol: "mic.fill",
                    title: "Microphone",
                    color: Theme.Status.warning,
                    index: first,
                    app: micApps.apps.first
                ) {
                    MicWaveView(barCount: 9, barWidth: 3, spacing: 2.5, height: 26, animates: true)
                }
            }
            if camera {
                row(symbol: "video.fill", title: "Camera", color: Theme.Status.charging, index: first + (mic ? 1 : 0), app: nil) {
                    Circle()
                        .fill(Theme.Status.charging)
                        .frame(width: 7, height: 7)
                }
            }
    }

    private func row<Trailing: View>(
        symbol: String,
        title: String,
        color: Color,
        index: Int,
        app: NSRunningApplication?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color.opacity(0.18)))
                .scaleEffect(reveal.shown ? 1 : 0.5)
                .animation(.spring(response: 0.45, dampingFraction: 0.62).delay(0.06 + Double(index) * 0.08), value: reveal.shown)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                HStack(spacing: 5) {
                    if let app, let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text(app?.localizedName ?? "In use")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .frame(height: 44)
        .modifier(Arrive(shown: reveal.shown, index: index))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.map { "\(title) in use by \($0.localizedName ?? "an app")" } ?? "\(title) in use")
    }
}

/// Each piece rises into place and fades in, a beat after the one before.
private struct Arrive: ViewModifier {
    let shown: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.05 + Double(index) * 0.08), value: shown)
    }
}

/// Plays the detail's entrance once, and fills the battery up to the level.
private final class DetailReveal: ObservableObject {
    @Published var shown = false
    @Published var fill: Double = 0

    func play(level: Int) {
        DispatchQueue.main.async {
            self.shown = true
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) {
                self.fill = Self.fraction(level)
            }
        }
    }

    func fill(to level: Int) {
        withAnimation(.easeInOut(duration: 0.6)) { fill = Self.fraction(level) }
    }

    private static func fraction(_ level: Int) -> Double {
        max(0.04, min(1, Double(level) / 100))
    }
}

/// The apps using the mic, read when the detail opens or the mic changes.
@MainActor
private final class MicApps: ObservableObject {
    @Published var apps: [NSRunningApplication] = []

    func refresh() {
        apps = PrivacyIndicatorMonitor.appsUsingMic()
    }
}
