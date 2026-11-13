import AVFoundation
import AppKit
import SwiftUI

/// A muted video looping to fill its frame, faded in once its first frame
/// is ready (so the still underneath shows until then), and stopped as
/// soon as it leaves the screen. For Apple Music's animated covers.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> LoopingVideoLayerView {
        let view = LoopingVideoLayerView()
        view.play(url)
        return view
    }

    func updateNSView(_ view: LoopingVideoLayerView, context: Context) {
        view.play(url)
    }

    static func dismantleNSView(_ view: LoopingVideoLayerView, coordinator: ()) {
        view.stop()
    }
}

final class LoopingVideoLayerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private var current: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.opacity = 0
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func play(_ url: URL?) {
        guard url != current else { return }
        stop()
        current = url
        guard let url else { return }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = 0.8
                self?.playerLayer.add(fade, forKey: "fade")
                self?.playerLayer.opacity = 1
            }
        }
        player.play()
        self.player = player
    }

    func stop() {
        readyObservation = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        playerLayer.player = nil
        playerLayer.opacity = 0
        current = nil
    }
}
