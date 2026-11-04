import SwiftUI
import AppKit
import AVFoundation

/// A stretch of one of Apple's product clips (see
/// `ProductImages.caseOpeningVideo`), played once and held on its last
/// frame. Without an end time it just shows the start frame.
///
/// The clip is HEVC with a transparent background, decoded by the Mac's
/// media engine, so playing it costs the app next to nothing; once it stops,
/// nothing runs. The player is let go as soon as the view goes away.
struct ProductVideo: NSViewRepresentable {
    let url: URL
    /// Where the clip starts, in seconds.
    let start: Double
    /// Where it stops and holds; nil holds the start frame.
    var end: Double?
    /// Seconds after appearing before it plays.
    var delay: TimeInterval = 0
    /// Playback speed: 2 plays it twice as fast.
    var rate: Float = 1

    func makeNSView(context: Context) -> ProductVideoView {
        ProductVideoView(url: url, start: start, end: end, delay: delay, rate: rate)
    }

    func updateNSView(_ view: ProductVideoView, context: Context) {}

    static func dismantleNSView(_ view: ProductVideoView, coordinator: ()) {
        view.stop()
    }
}

final class ProductVideoView: NSView {
    private let player: AVPlayer
    private let videoLayer: AVPlayerLayer
    private var playWork: DispatchWorkItem?

    init(url: URL, start: Double, end: Double?, delay: TimeInterval, rate: Float = 1) {
        let item = AVPlayerItem(url: url)
        if let end {
            item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        }
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        // A local file: no buffering to wait for.
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = false
        videoLayer = AVPlayerLayer(player: player)
        videoLayer.videoGravity = .resizeAspect
        videoLayer.backgroundColor = .clear
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(videoLayer)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Reduce Motion: straight to the last frame.
        let first = reduceMotion ? (end ?? start) : start
        player.seek(to: CMTime(seconds: first, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        guard end != nil, !reduceMotion else { return }
        let work = DispatchWorkItem { [weak self] in self?.player.playImmediately(atRate: rate) }
        playWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }

    /// Stops and lets everything go: the clip, its decoder and the last
    /// frame the layer was holding.
    func stop() {
        playWork?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        videoLayer.player = nil
    }
}
