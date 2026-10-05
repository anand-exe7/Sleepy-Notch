import Foundation
import AppKit
import Combine

/// The one source of truth for what's playing, and the single way to control
/// it. It routes commands to the right `PlaybackSource`, shows their effect
/// immediately (rolling back if the command fails), picks a source at
/// launch, and attaches album art.
///
/// Zero polling: everything here reacts to notifications from the sources
/// or to the user. Nothing runs between events.
@MainActor
final class PlaybackCoordinator: ObservableObject {
    static let shared = PlaybackCoordinator(
        appleMusic: AppleMusicSource(),
        spotify: SpotifySource(),
        demo: DemoSource()
    )

    @Published var currentTrack: TrackInfo = TrackInfo()
    @Published var isDemoMode: Bool = false

    /// Last playback failure, surfaced in the expanded card. `nil` when the
    /// last command succeeded.
    @Published private(set) var lastError: AppleScriptFailure?

    private let appleMusic: PlaybackSource
    private let spotify: PlaybackSource
    private let demo: DemoSource
    private let artworkCache = ArtworkCache()

    /// - Parameter checksOnLaunch: asks the running music apps what they're
    ///   playing. Off for tests, which drive the sources directly.
    init(
        appleMusic: PlaybackSource,
        spotify: PlaybackSource,
        demo: DemoSource,
        checksOnLaunch: Bool = true
    ) {
        self.appleMusic = appleMusic
        self.spotify = spotify
        self.demo = demo

        appleMusic.onUpdate = { [weak self] track in self?.liveSourceDidUpdate(track) }
        spotify.onUpdate = { [weak self] track in self?.liveSourceDidUpdate(track) }
        demo.onUpdate = { [weak self] track in self?.demoDidUpdate(track) }

        if checksOnLaunch {
            checkInitialPlayback()
        }
    }

    private func liveSource(for kind: MusicSource) -> PlaybackSource? {
        switch kind {
        case .appleMusic: return appleMusic
        case .spotify: return spotify
        case .demo: return nil
        }
    }

    /// Where commands go: the demo in demo mode, otherwise the app the current
    /// track came from — or Music when nothing has played yet, which is what
    /// the media keys do too.
    private var commandTarget: PlaybackSource {
        if isDemoMode { return demo }
        return liveSource(for: currentTrack.source) ?? appleMusic
    }

    // MARK: - Updates from sources

    private func liveSourceDidUpdate(_ track: TrackInfo) {
        // Demo mode deliberately ignores the real apps until it's turned off.
        guard !isDemoMode else { return }
        show(track)
    }

    private func demoDidUpdate(_ track: TrackInfo) {
        guard isDemoMode else { return }
        currentTrack = track
    }

    /// Shows a live track, with cached artwork if there is any, and fetches
    /// it otherwise.
    private func show(_ track: TrackInfo) {
        var track = track
        track.artworkImage = artworkCache.image(for: track)
        currentTrack = track
        if track.artworkImage == nil {
            loadArtwork(for: track)
        }
    }

    private func loadArtwork(for track: TrackInfo) {
        guard let source = liveSource(for: track.source) else { return }
        Task { [weak self] in
            guard let image = await source.artwork() else { return }
            self?.artworkDidLoad(image, for: track)
        }
    }

    private func artworkDidLoad(_ image: NSImage, for track: TrackInfo) {
        artworkCache.store(image, for: track)
        // The song may have changed while it loaded.
        if currentTrack.title == track.title {
            currentTrack.artworkImage = image
        }
    }

    // MARK: - Launch

    private func checkInitialPlayback() {
        Task { [weak self] in
            guard let self else { return }

            let running = await Task.detached(priority: .userInitiated) {
                RunningAppProbe.runningMusicApps()
            }.value
            let sources = running.compactMap { self.liveSource(for: $0) }

            guard !sources.isEmpty else {
                self.showIdle()
                return
            }

            // Ask every running app at once, then prefer whichever is actually
            // playing. Picking purely on "is it running" left a running-but-
            // paused app's HUD blank on "No Track Playing".
            let statuses = await withTaskGroup(
                of: SourceStatus?.self,
                returning: [SourceStatus].self
            ) { group in
                for source in sources {
                    group.addTask { await source.currentStatus() }
                }
                var collected: [SourceStatus] = []
                for await status in group {
                    if let status { collected.append(status) }
                }
                return collected
            }

            let best = statuses.first(where: { $0.isPlaying && $0.hasTrack })
                ?? statuses.first(where: { $0.hasTrack })

            guard let track = best?.track else {
                // Running, but stopped or not answering: no track to show.
                self.showIdle()
                return
            }
            self.isDemoMode = false
            self.show(track)
        }
    }

    /// Nothing is playing anywhere: show a still "No Track Playing" card.
    ///
    /// This used to switch to demo mode, whose tracks were marked as playing,
    /// so the HUD animated all day with no music at all — and, because demo
    /// mode ignores real notifications, it stayed stuck on fake tracks even
    /// after you opened Music or Spotify.
    private func showIdle() {
        isDemoMode = false
        // A real notification may have landed while the startup probe ran;
        // don't overwrite it.
        guard currentTrack.source == .demo else { return }
        currentTrack = TrackInfo()
    }

    // MARK: - Playback controls

    func togglePlayPause() {
        let target = commandTarget
        // Optimistic: show the change now. If the command fails it's rolled
        // back, so the HUD never sits there confidently claiming the wrong thing.
        let previous = currentTrack
        currentTrack.position = currentTrack.currentPosition
        currentTrack.lastUpdated = Date()
        currentTrack.isPlaying.toggle()
        perform(revertingTo: previous, optimisticStamp: currentTrack.lastUpdated) {
            try await target.togglePlayPause()
        }
    }

    func nextTrack() {
        let target = commandTarget
        perform { try await target.nextTrack() }
    }

    func previousTrack() {
        let target = commandTarget
        perform { try await target.previousTrack() }
    }

    func seek(to progressRatio: Double) {
        let target = commandTarget
        let newPosition = max(0, min(currentTrack.duration * progressRatio, currentTrack.duration))
        let previous = currentTrack
        let stamp = Date()
        currentTrack.position = newPosition
        currentTrack.lastUpdated = stamp
        perform(revertingTo: previous, optimisticStamp: stamp) {
            try await target.seek(toSeconds: newPosition)
        }
    }

    /// Runs a command without blocking the UI, and surfaces failures.
    ///
    /// `revertingTo` / `optimisticStamp` exist because play/pause and seek
    /// update the HUD *before* the command resolves. If it then fails — most
    /// often because Automation access was denied — the previous state is put
    /// back. The stamp guards the rollback, so a real notification that
    /// arrived in the meantime isn't clobbered.
    private func perform(
        revertingTo snapshot: TrackInfo? = nil,
        optimisticStamp: Date? = nil,
        _ command: @escaping () async throws -> Void
    ) {
        Task { [weak self] in
            do {
                try await command()
                self?.lastError = nil
            } catch let failure as AppleScriptFailure {
                self?.handle(failure, revertingTo: snapshot, optimisticStamp: optimisticStamp)
            } catch {
                self?.handle(.scriptError(number: -1, message: error.localizedDescription),
                             revertingTo: snapshot,
                             optimisticStamp: optimisticStamp)
            }
        }
    }

    /// Records a failure and, when the optimistic update was never superseded
    /// by a real notification, rolls the HUD back to its last truthful state.
    private func handle(
        _ failure: AppleScriptFailure,
        revertingTo snapshot: TrackInfo?,
        optimisticStamp: Date?
    ) {
        lastError = failure
        guard let snapshot, let optimisticStamp else { return }
        // A notification that landed after our optimistic write means the real
        // state is already newer — leave it alone.
        guard currentTrack.lastUpdated == optimisticStamp else { return }
        currentTrack = snapshot
    }

    // MARK: - Demo mode

    func toggleDemoMode() {
        if isDemoMode {
            isDemoMode = false
            checkInitialPlayback()
        } else {
            isDemoMode = true
            demo.start(advancing: false)
        }
    }

    /// Feature Lab: jump to the next demo song so artwork transitions can be
    /// tried on demand. Turns demo mode on (paused) if it was off.
    func advanceDemoSong() {
        if isDemoMode {
            demo.showNext()
        } else {
            isDemoMode = true
            demo.start(advancing: true)
        }
    }
}
