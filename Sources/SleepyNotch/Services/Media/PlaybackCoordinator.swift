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

        // The app the song came from quit: there's no song any more. Music
        // and Spotify usually say "Stopped" as they go, but not always.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let quit = RunningAppProbe.source(forBundleIdentifier: app?.bundleIdentifier)
            Task { @MainActor [weak self] in
                guard let self, let quit, !self.isDemoMode, self.currentTrack.source == quit else { return }
                self.currentTrack = TrackInfo()
            }
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
        // The app is talking to us again, so an old failure no longer applies.
        lastError = nil
        // The player stopped (see the sources): clear the song, after a
        // moment. Skipping reports "Stopped" between two songs, and clearing
        // at once flashed the empty card and sent the next press to the
        // wrong app. A new song cancels the wait.
        if track.isPlaceholder {
            pendingClear?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isDemoMode else { return }
                self.endToggleSettle(applyingHeldBack: false)
                self.currentTrack = TrackInfo()
            }
            pendingClear = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.clearDelay, execute: work)
            return
        }
        pendingClear?.cancel()
        pendingClear = nil
        if holdsBack(track) { return }
        show(track)
    }

    private var pendingClear: DispatchWorkItem?
    /// Longer than the gap between two songs, short enough that a player
    /// that really stopped clears the card promptly.
    private static let clearDelay: TimeInterval = 1.5

    // MARK: - Settling a play/pause press

    /// Right after play/pause is pressed, the button shows the new state at
    /// once. But Music fades the sound out when pausing, and while it fades
    /// it can still report "Playing" — so the button flipped to pause, back
    /// to play, then to pause again when the real "Paused" came in.
    ///
    /// So for a moment after a press, a report about the same song that
    /// disagrees with it is held back. Once the app confirms the press, late
    /// disagreeing reports are dropped; if it never does, the held report is
    /// the truth after all and is shown when the moment is up. One one-shot
    /// timer per press; nothing polls.
    private struct ToggleSettle {
        let expectsPlaying: Bool
        let identity: String
        var confirmed = false
        var heldBack: TrackInfo?
        let end: DispatchWorkItem
    }

    private var toggleSettle: ToggleSettle?
    /// Long enough for Music's fade-out and its "Paused" report.
    private static let toggleSettleTime: TimeInterval = 1.2

    private func beginToggleSettle(expectsPlaying: Bool) {
        toggleSettle?.end.cancel()
        let end = DispatchWorkItem { [weak self] in
            self?.endToggleSettle(applyingHeldBack: true)
        }
        toggleSettle = ToggleSettle(
            expectsPlaying: expectsPlaying,
            identity: currentTrack.identityKey,
            end: end
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.toggleSettleTime, execute: end)
    }

    /// Whether `track` is a stale report to hold back (or drop) while a
    /// press settles.
    private func holdsBack(_ track: TrackInfo) -> Bool {
        guard var settle = toggleSettle else { return false }
        // Another song: the press is old news.
        guard track.identityKey == settle.identity else {
            endToggleSettle(applyingHeldBack: false)
            return false
        }
        if track.isPlaying == settle.expectsPlaying {
            settle.confirmed = true
            settle.heldBack = nil
            toggleSettle = settle
            return false
        }
        if !settle.confirmed {
            settle.heldBack = track
            toggleSettle = settle
        }
        return true
    }

    private func endToggleSettle(applyingHeldBack: Bool) {
        guard let settle = toggleSettle else { return }
        settle.end.cancel()
        toggleSettle = nil
        if applyingHeldBack, let track = settle.heldBack, !isDemoMode,
           currentTrack.identityKey == track.identityKey {
            show(track)
        }
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
        // The song may have changed while it loaded. Matched on the whole
        // identity, so two songs that share a title ("Intro") don't swap art.
        if currentTrack.identityKey == track.identityKey {
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

            // Demo mode was turned (back) on while this ran: leave it be.
            guard !self.isDemoMode else { return }
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

            guard !self.isDemoMode else { return }
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
    /// Not demo mode: that would animate all day with no music, and since
    /// demo mode ignores real notifications it would stay on fake tracks
    /// after Music or Spotify opened.
    private func showIdle() {
        isDemoMode = false
        // A real notification may have landed while the startup probe ran;
        // don't overwrite it.
        guard currentTrack.source == .demo else { return }
        currentTrack = TrackInfo()
    }

    // MARK: - Position

    /// Corrects the timeline against the app's real position. Called when
    /// the card opens — the moment someone looks — because seeking inside
    /// Music itself, from Control Center or from another device sends no
    /// notification, and a streamed song can start later than reported.
    /// One question per opening; nothing polls.
    private var lastResync = Date.distantPast

    /// Asks the player where it really is, to correct drift when the card
    /// opens. It's an AppleScript round trip, so at most every few seconds:
    /// opening and closing the card quickly asked Spotify every time.
    func resyncPosition() {
        guard !isDemoMode, let source = liveSource(for: currentTrack.source) else { return }
        guard Date().timeIntervalSince(lastResync) > 5 else { return }
        lastResync = Date()
        let identity = currentTrack.identityKey
        Task { [weak self] in
            guard let raw = await source.currentPosition(),
                  let self,
                  self.currentTrack.identityKey == identity
            else { return }
            let track = self.currentTrack
            let position = min(max(track.source.normalizedPosition(raw, duration: track.duration), 0), track.duration)
            // Already in step: leave it, so the clock doesn't restart for nothing.
            guard abs(position - track.currentPosition) > 0.25 else { return }
            self.currentTrack.position = position
            self.currentTrack.lastUpdated = Date()
        }
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
        beginToggleSettle(expectsPlaying: currentTrack.isPlaying)
        perform(revertingTo: previous, optimisticStamp: currentTrack.lastUpdated) {
            try await target.togglePlayPause()
        }
    }

    func nextTrack() {
        let target = commandTarget
        perform(then: { [weak self] in self?.confirmAfterSkip() }) {
            try await target.nextTrack()
        }
    }

    func previousTrack() {
        let target = commandTarget
        // More than a few seconds in, Back restarts the song, in Music and
        // Spotify alike, and neither says a word about it: the timeline
        // carried on from the old spot until the card was reopened. Show
        // the restart now; the player's own answer confirms it.
        if !isDemoMode, !currentTrack.isPlaceholder, currentTrack.currentPosition > Self.restartThreshold {
            currentTrack.position = 0
            currentTrack.lastUpdated = Date()
        }
        perform(then: { [weak self] in self?.confirmAfterSkip() }) {
            try await target.previousTrack()
        }
    }

    /// How far into a song Back restarts it rather than going to the one
    /// before (Music and Spotify both use about three seconds).
    private static let restartThreshold: TimeInterval = 3

    /// After a skip, one question to the player, a moment after the command
    /// lands: which song, where, playing or not. A restart sends no
    /// notification at all, and a new song's can trail the press. One
    /// question per press; nothing polls.
    private var skipConfirm: DispatchWorkItem?
    private static let skipConfirmDelay: TimeInterval = 0.35

    private func confirmAfterSkip() {
        guard !isDemoMode, let source = liveSource(for: currentTrack.source) else { return }
        skipConfirm?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let status = await source.currentStatus(),
                      let track = status.track,
                      let self, !self.isDemoMode
                else { return }
                self.applyConfirmed(track)
            }
        }
        skipConfirm = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.skipConfirmDelay, execute: work)
    }

    private func applyConfirmed(_ track: TrackInfo) {
        guard track.identityKey == currentTrack.identityKey else {
            // A new song whose notification hasn't arrived yet.
            show(track)
            return
        }
        // The same song: correct where it is, if it's off.
        let drift = abs(track.position - currentTrack.currentPosition)
        guard drift > 0.5 || track.isPlaying != currentTrack.isPlaying else { return }
        currentTrack.position = min(max(track.position, 0), currentTrack.duration)
        currentTrack.isPlaying = track.isPlaying
        currentTrack.lastUpdated = Date()
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
        then succeeded: (() -> Void)? = nil,
        _ command: @escaping () async throws -> Void
    ) {
        Task { [weak self] in
            do {
                try await command()
                self?.lastError = nil
                succeeded?()
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
        // The press didn't go through: nothing to settle.
        endToggleSettle(applyingHeldBack: false)
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
