import SwiftUI

/// The percentage beside the notch when downloads are the main activity.
struct DownloadWingText: View {
    @EnvironmentObject private var downloads: DownloadsMonitor

    var body: some View {
        Group {
            if let fraction = downloads.summary?.fraction {
                Text("\(Int((fraction * 100).rounded()))%")
            } else {
                // The app doesn't say how far along it is.
                Text((downloads.summary?.count ?? 0) > 1 ? "\(downloads.summary?.count ?? 0)" : "")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .foregroundColor(Theme.Text.primary)
        .lineLimit(1)
        .accessibilityLabel("Downloading")
    }
}

/// The downloads as a bubble: a ring filled to how far along they are,
/// around an arrow. It only changes when the progress does.
struct DownloadRing: View {
    @EnvironmentObject private var downloads: DownloadsMonitor

    var body: some View {
        let fraction = downloads.summary?.fraction
        ZStack {
            if let fraction {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2.4)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, fraction)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.Text.primary)
        }
        .padding(5)
        .accessibilityLabel(fraction.map { "Downloading, \(Int(($0 * 100).rounded())) percent" } ?? "Downloading")
    }
}

/// Opened from its bubble: what's downloading and how far along.
struct DownloadDetail: View {
    @EnvironmentObject private var downloads: DownloadsMonitor
    private var summary: DownloadSummary? { downloads.summary }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundColor(Theme.Text.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary?.name ?? "Download")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.Text.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        guard let summary else { return "" }
        let more = summary.count > 1 ? " · \(summary.count) downloads" : ""
        if let fraction = summary.fraction {
            return "\(Int((fraction * 100).rounded()))%\(more)"
        }
        return "Downloading\(more)"
    }
}

/// A download finished: a short row under the notch.
struct DownloadDonePeekView: View {
    let name: String

    static let contentHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Downloaded \(name)")
    }
}
