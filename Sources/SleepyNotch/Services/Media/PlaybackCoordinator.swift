import Foundation
import AppKit
import Combine

@MainActor
public final class PlaybackCoordinator: ObservableObject {
    public static let shared = PlaybackCoordinator()
    
    @Published public var currentTrack: TrackInfo = TrackInfo()
    @Published public var isHovered: Bool = false
    @Published public var isDemoMode: Bool = false
    @Published public var volume: Double = 0.75
    
    /// Last playback failure, surfaced in the expanded card. `nil` when the
    /// last command succeeded. Internal because `AppleScriptFailure` is, and
    /// same-module views can read it regardless.
    @Published private(set) var lastError: AppleScriptFailure?
    
    private var cancellables = Set<AnyCancellable>()
    private var artworkCache = NSCache<NSString, NSImage>()
    
    // Demo playlist for testing the UI. Only ever started by hand (menu or
    // `d`), and it starts paused, so it never animates on its own.
    private let demoTracks: [TrackInfo] = [
        TrackInfo(
            title: "Starboy",
            artist: "The Weeknd, Daft Punk",
            album: "Starboy",
            duration: 230,
            position: 45,
            isPlaying: false,
            source: .demo,
            artworkImage: DemoArtwork.cover(0)
        ),
        TrackInfo(
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            duration: 243,
            position: 80,
            isPlaying: false,
            source: .demo,
            artworkImage: DemoArtwork.cover(1)
        ),
        TrackInfo(
            title: "Get Lucky",
            artist: "Daft Punk ft. Pharrell Williams",
            album: "Random Access Memories",
            duration: 248,
            position: 112,
            isPlaying: false,
            source: .demo,
            artworkImage: DemoArtwork.cover(2)
        ),
        TrackInfo(
            title: "Electric Feel",
            artist: "MGMT",
            album: "Oracular Spectacular",
            duration: 229,
            position: 30,
            isPlaying: false,
            source: .demo,
            artworkImage: DemoArtwork.cover(3)
        )
    ]
    private var demoIndex = 0

    private init() {
        setupNotificationObservers()
        checkInitialPlayback()
    }
    
    // MARK: - Notifications Setup (Zero Polling Battery Optimization)
    
    private func setupNotificationObservers() {
        let center = DistributedNotificationCenter.default()
        
        // Apple Music notification
        center.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAppleMusicNotification(notification)
            }
        }
        
        // Spotify notification
        center.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleSpotifyNotification(notification)
            }
        }
    }
    
    // MARK: - Initial Check
    
    private func checkInitialPlayback() {
        Task { [weak self] in
            guard let self else { return }
            
            let running = await Task.detached(priority: .userInitiated) {
                RunningAppProbe.runningMusicApps()
            }.value
            
            guard !running.isEmpty else {
                self.showIdle()
                return
            }
            
            // Ask every running app at once, then prefer whichever is actually
            // playing. Previously we picked purely on "is it running", but the
            // old script only returned data when `player state is playing`, so
            // a running-but-paused app left the HUD blank on "No Track Playing".
            let statuses = await withTaskGroup(
                of: SourceStatus?.self,
                returning: [SourceStatus].self
            ) { group in
                for source in running {
                    group.addTask { await self.status(of: source) }
                }
                var collected: [SourceStatus] = []
                for await status in group {
                    if let status { collected.append(status) }
                }
                return collected
            }
            
            let best = statuses.first(where: { $0.isPlaying && $0.hasTrack })
                ?? statuses.first(where: { $0.hasTrack })
            
            guard let best else {
                // Running, but stopped or not answering: no track to show.
                self.showIdle()
                return
            }
            self.apply(best)
        }
    }
    
    // MARK: - Notification Handlers
    
    private func handleAppleMusicNotification(_ notification: Notification) {
        guard !isDemoMode else { return }
        guard let userInfo = notification.userInfo else { return }
        
        let stateStr = userInfo["Player State"] as? String ?? ""
        let isPlaying = (stateStr == "Playing")
        let title = userInfo["Name"] as? String ?? "Unknown Title"
        let artist = userInfo["Artist"] as? String ?? "Unknown Artist"
        let album = userInfo["Album"] as? String ?? ""
        
        // Apple Music total time is sometimes in milliseconds or seconds
        var totalSec: Double = 180
        if let total = userInfo["Total Time"] as? NSNumber {
            let val = total.doubleValue
            totalSec = val > 1000 ? val / 1000.0 : val
        }
        
        var posSec: Double = 0
        // Position isn't always in userInfo, can be extracted or estimated
        if let loc = userInfo["Location"] as? NSNumber {
            posSec = loc.doubleValue
        }
        
        let track = TrackInfo(
            title: title,
            artist: artist,
            album: album,
            duration: totalSec > 0 ? totalSec : 180,
            position: posSec,
            isPlaying: isPlaying,
            source: .appleMusic,
            artworkImage: artworkCache.object(forKey: "\(artist)-\(title)" as NSString),
            lastUpdated: Date()
        )
        
        self.currentTrack = track
        
        if track.artworkImage == nil {
            fetchAppleMusicArtwork(title: title, artist: artist)
        }
    }
    
    private func handleSpotifyNotification(_ notification: Notification) {
        guard !isDemoMode else { return }
        guard let userInfo = notification.userInfo else { return }
        
        let stateStr = userInfo["Player State"] as? String ?? ""
        let isPlaying = (stateStr == "Playing" || stateStr == "kPSP")
        let title = userInfo["Name"] as? String ?? "Unknown Title"
        let artist = userInfo["Artist"] as? String ?? "Unknown Artist"
        let album = userInfo["Album"] as? String ?? ""
        
        // Spotify reports BOTH duration and position in milliseconds. Reading
        // duration as ms but position as seconds inflated the position by 1000x,
        // which clamped the scrubber to the end of every track.
        var totalSec: Double = 180
        if let dur = userInfo["Duration"] as? NSNumber {
            totalSec = MusicSource.spotify.normalizedTime(dur.doubleValue)
        }
        
        var posSec: Double = 0
        if let pos = userInfo["Playback Position"] as? NSNumber {
            posSec = MusicSource.spotify.normalizedTime(pos.doubleValue)
        }
        
        let track = TrackInfo(
            title: title,
            artist: artist,
            album: album,
            duration: totalSec > 0 ? totalSec : 180,
            position: posSec,
            isPlaying: isPlaying,
            source: .spotify,
            artworkImage: artworkCache.object(forKey: "\(artist)-\(title)" as NSString),
            lastUpdated: Date()
        )
        
        self.currentTrack = track
        
        if track.artworkImage == nil {
            fetchSpotifyArtwork(title: title, artist: artist)
        }
    }
    
    // MARK: - Playback Controls (via AppleScript, Background Async)
    
    public func togglePlayPause() {
        if isDemoMode {
            currentTrack.position = currentTrack.currentPosition
            currentTrack.lastUpdated = Date()
            currentTrack.isPlaying.toggle()
            return
        }
        
        let appName = RunningAppProbe.applicationName(for: currentTrack.source)
        
        // Optimistic UI update. If the script fails we roll this back, so the
        // HUD never sits there confidently claiming the wrong thing.
        let previous = currentTrack
        currentTrack.position = currentTrack.currentPosition
        currentTrack.lastUpdated = Date()
        currentTrack.isPlaying.toggle()
        let optimisticStamp = currentTrack.lastUpdated
        
        performTransport("tell application \"\(appName)\" to playpause",
                         revertingTo: previous,
                         optimisticStamp: optimisticStamp)
    }
    
    public func nextTrack() {
        if isDemoMode {
            demoIndex = (demoIndex + 1) % demoTracks.count
            loadDemoTrack(index: demoIndex, isPlaying: currentTrack.isPlaying)
            return
        }
        
        let appName = RunningAppProbe.applicationName(for: currentTrack.source)
        performTransport("tell application \"\(appName)\" to next track")
    }
    
    public func previousTrack() {
        if isDemoMode {
            demoIndex = (demoIndex - 1 + demoTracks.count) % demoTracks.count
            loadDemoTrack(index: demoIndex, isPlaying: currentTrack.isPlaying)
            return
        }
        
        let appName = RunningAppProbe.applicationName(for: currentTrack.source)
        performTransport("tell application \"\(appName)\" to previous track")
    }
    
    public func seek(to progressRatio: Double) {
        let newPos = max(0, min(currentTrack.duration * progressRatio, currentTrack.duration))
        let previous = currentTrack
        let optimisticStamp = Date()
        currentTrack.position = newPos
        currentTrack.lastUpdated = optimisticStamp
        
        guard !isDemoMode else { return }
        
        let appName = RunningAppProbe.applicationName(for: currentTrack.source)
        // `player position` is in the same unit the source reports time in, so
        // a Spotify seek has to be scaled back up to milliseconds or the track
        // jumps to the wrong offset.
        let rawPosition = currentTrack.source.usesMillisecondTime
            ? newPos * 1000.0
            : newPos
        
        performTransport("tell application \"\(appName)\" to set player position to \(Int(rawPosition))",
                         revertingTo: previous,
                         optimisticStamp: optimisticStamp)
    }
    
    // MARK: - AppleScript Execution Helpers
    
    /// Fires a transport command without blocking the UI, and surfaces failures.
    ///
    /// `revertingTo` / `optimisticStamp` exist because the transport buttons
    /// update the HUD *before* the script resolves. If the script then fails —
    /// most often because automation access was denied — we put the previous
    /// track state back. The stamp guards the rollback so that a real
    /// notification arriving in the meantime isn't clobbered.
    private func performTransport(
        _ scriptText: String,
        revertingTo snapshot: TrackInfo? = nil,
        optimisticStamp: Date? = nil
    ) {
        Task { [weak self] in
            do {
                _ = try await AppleScriptRunner.shared.run(scriptText)
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
    
    /// Clears the surfaced error. Called when a command succeeds.
    public func clearError() {
        lastError = nil
    }
    
    // MARK: - Artwork Helpers
    
    public func cacheArtwork(_ image: NSImage, for key: String, title: String) {
        artworkCache.setObject(image, forKey: key as NSString)
        if currentTrack.title == title {
            currentTrack.artworkImage = image
        }
    }
    
    private func fetchAppleMusicArtwork(title: String, artist: String) {
        let script = """
        tell application "Music"
            if (exists current track) and (count of artworks of current track > 0) then
                return raw data of artwork 1 of current track
            end if
        end tell
        """
        Task { [weak self] in
            guard let data = try? await AppleScriptRunner.shared.run(script).data,
                  let image = NSImage(data: data) else { return }
            self?.cacheArtwork(image, for: "\(artist)-\(title)", title: title)
        }
    }
    
    private func fetchSpotifyArtwork(title: String, artist: String) {
        let script = "tell application \"Spotify\" to get artwork url of current track"
        Task { [weak self] in
            guard let urlString = try? await AppleScriptRunner.shared.run(script).text,
                  let url = URL(string: urlString),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            self?.cacheArtwork(image, for: "\(artist)-\(title)", title: title)
        }
    }
    
    // MARK: - Startup Status Queries
    
    /// What a single music app reports about itself at launch.
    struct SourceStatus {
        let source: MusicSource
        /// "playing", "paused" or "stopped", lowercased.
        let state: String
        let track: TrackInfo?

        var isPlaying: Bool { state == "playing" }
        var hasTrack: Bool { track != nil }
    }
    
    /// `state|||title|||artist|||album|||duration|||position`
    private static let statusSeparator = "|||"
    
    private static func statusScript(for appName: String) -> String {
        """
        tell application "\(appName)"
            set playerState to (player state as string)
            if playerState is "stopped" then return "stopped"
            return playerState & "\(statusSeparator)" & (get name of current track) & "\(statusSeparator)" & (get artist of current track) & "\(statusSeparator)" & (get album of current track) & "\(statusSeparator)" & (get duration of current track) & "\(statusSeparator)" & (get player position)
        end tell
        """
    }
    
    private static func parseStatus(
        _ result: AppleScriptResult,
        source: MusicSource
    ) -> SourceStatus? {
        guard let text = result.text else { return nil }
        let parts = text.components(separatedBy: statusSeparator)
        guard parts.count >= 6 else { return nil }
        
        let state = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard state != "stopped" else {
            return SourceStatus(source: source, state: state, track: nil)
        }
        
        // Duration and position arrive in the same unit, so both go through
        // the same normalisation.
        let rawDuration = Double(parts[4]) ?? 0
        let rawPosition = Double(parts[5]) ?? 0
        let duration = source.normalizedTime(rawDuration)
        
        let track = TrackInfo(
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: duration > 0 ? duration : 180,
            position: min(source.normalizedTime(rawPosition), duration > 0 ? duration : .greatestFiniteMagnitude),
            isPlaying: state == "playing",
            source: source,
            lastUpdated: Date()
        )
        return SourceStatus(source: source, state: state, track: track)
    }
    
    /// Queries one app. Never touches the main thread, and a failure here is
    /// not fatal — it just means that app can't be the active source.
    private func status(of source: MusicSource) async -> SourceStatus? {
        let appName = RunningAppProbe.applicationName(for: source)
        guard let result = try? await AppleScriptRunner.shared.run(
            Self.statusScript(for: appName)
        ) else { return nil }
        return Self.parseStatus(result, source: source)
    }
    
    private func apply(_ status: SourceStatus) {
        isDemoMode = false
        guard let track = status.track else { return }
        currentTrack = track
        switch status.source {
        case .appleMusic: fetchAppleMusicArtwork(title: track.title, artist: track.artist)
        case .spotify: fetchSpotifyArtwork(title: track.title, artist: track.artist)
        case .demo: break
        }
    }
    
    // MARK: - Demo Mode Helpers
    
    public func toggleDemoMode() {
        isDemoMode.toggle()
        if isDemoMode {
            loadDemoTrack(index: demoIndex, isPlaying: false)
        } else {
            checkInitialPlayback()
        }
    }
    
    /// Feature Lab: jump to the next demo song so artwork transitions can be
    /// tried on demand. Turns demo mode on if it was off.
    func advanceDemoSong() {
        let wasPlaying = isDemoMode && currentTrack.isPlaying
        isDemoMode = true
        demoIndex = (demoIndex + 1) % demoTracks.count
        loadDemoTrack(index: demoIndex, isPlaying: wasPlaying)
    }
    
    private func loadDemoTrack(index: Int, isPlaying: Bool) {
        var track = demoTracks[index]
        track.isPlaying = isPlaying
        track.lastUpdated = Date()
        self.currentTrack = track
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
}
