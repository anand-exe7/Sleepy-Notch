import SwiftUI
import Combine

/// Something going on that the closed notch keeps showing, like a Live
/// Activity on iPhone.
enum ActivityKind: CaseIterable, Equatable {
    case privacy
    case charging
    case music
    case timer
    case download
    case agent
    case stayAwake
    /// Not an activity: the "+N" that stands for the ones with no room (see
    /// `ActivityManager.allocate`).
    case overflow

    /// Lower comes first when bubbles are handed out: the camera and mic are
    /// about privacy, so they're never the one left out; then the charge.
    var priority: Int {
        switch self {
        case .privacy: return 0
        case .charging: return 1
        case .music: return 2
        case .timer: return 3
        case .download: return 4
        case .agent: return 5
        case .stayAwake: return 6
        case .overflow: return 99
        }
    }

    /// The name a Settings choice is kept under.
    var storageKey: String {
        switch self {
        case .privacy: return "privacy"
        case .charging: return "charging"
        case .music: return "music"
        case .timer: return "timer"
        case .download: return "download"
        case .agent: return "agent"
        case .stayAwake: return "stayAwake"
        case .overflow: return "overflow"
        }
    }

    /// What Settings → Indicators lets the user place, with its title.
    static let placeable: [(kind: ActivityKind, title: String)] = [
        (.charging, "Charging"),
        (.privacy, "Camera and microphone"),
        (.timer, "Timers"),
        (.download, "Downloads"),
        (.agent, "Agent status"),
        (.stayAwake, "Stay Awake"),
    ]
}

/// Where an activity is shown around the notch.
enum ActivitySlot: Hashable {
    /// In the notch's own wings (the main activity).
    case notch
    case leading
    case trailing
    /// The camera and mic while charging: no bubble of their own, just a
    /// small dot riding on the charge (its bubble, or the notch's wing).
    case attached
    /// More activities than there are bubbles: this one waits, unseen,
    /// until a side frees up.
    case hidden

    var isBubble: Bool { self == .leading || self == .trailing }
}

/// The camera and mic as a small dot on the charge (see `ActivitySlot.attached`).
struct PrivacyBadge: Equatable {
    var mic: Bool
    var camera: Bool
}

/// What a bubble draws.
enum BubbleFace: Equatable {
    /// The ring, with the camera and mic's dot on it while they're on.
    case charging(level: Int, badge: PrivacyBadge? = nil)
    case privacy(mic: Bool, camera: Bool)
    /// A ring that runs down to the end of the countdown.
    case timer(start: Date, end: Date)
    /// A ring around an arrow. How far along it is isn't part of the face:
    /// the ring reads it from the `DownloadsMonitor` itself, so a progress
    /// step redraws the ring and not the whole notch.
    case download
    /// The agent's state, as one glyph.
    case agent(AgentState)
    /// The cup: Stay Awake is on.
    case stayAwake
    /// "+N": that many more activities are in the tray.
    case overflow(Int)
}

/// One live activity. The manager owns its lifecycle; the notch only draws
/// it, so opening, closing or moving a bubble never touches the activity
/// itself (music keeps playing, monitoring keeps running).
struct LiveActivity: Identifiable, Equatable {
    enum Status: Equatable {
        /// Its notification is showing (or waiting to): the bubble holds
        /// back, so the notification can shrink into it.
        case announcing
        /// Resting in its place: the notch's wings or a bubble.
        case compact
        /// Opened into the notch by a click on its bubble.
        case expanded
    }

    let id = UUID()
    let kind: ActivityKind
    var status: Status
    var slot: ActivitySlot
    var level: Int?
    var micInUse = false
    var cameraInUse = false
    var timer: TimerSession?
    var download: DownloadSummary?
    var agent: AgentSummary?
    /// For the overflow chip: how many are in the tray.
    var overflowCount = 0
    let createdAt = Date()
    var lastInteraction = Date()

    var priority: Int { kind.priority }

    /// A state rather than an event: nothing to react to, so when room is
    /// short these give way first (Stay Awake; the agent while it works or
    /// has finished, but not while it needs the user).
    var isPassive: Bool {
        switch kind {
        case .stayAwake: return true
        case .agent: return agent?.state != .needsInput
        default: return false
        }
    }

    var isExpanded: Bool { status == .expanded }

    var face: BubbleFace? {
        switch kind {
        case .charging: return .charging(level: level ?? 0)
        case .privacy: return .privacy(mic: micInUse, camera: cameraInUse)
        case .timer: return timer.map { .timer(start: $0.start, end: $0.end) }
        case .download: return download == nil ? nil : .download
        case .agent: return agent.map { .agent($0.state) }
        case .stayAwake: return .stayAwake
        case .overflow: return .overflow(overflowCount)
        case .music: return nil
        }
    }
}

/// A bubble as the notch draws it.
struct BubbleSlot: Equatable {
    let kind: ActivityKind
    let face: BubbleFace
    /// Split off and resting beside the notch, rather than tucked inside it
    /// (announcing, opened, or on its way somewhere else).
    let visible: Bool
}

/// What the closed notch shows: the main activity in its wings, and up to
/// one bubble either side.
struct IslandArrangement: Equatable {
    var primary: ActivityKind?
    var leading: BubbleSlot?
    var trailing: BubbleSlot?
    /// The "In the notch" style: the camera and mic take the left wing from
    /// the cover (or the battery), and the charge takes the right wing from
    /// the bars, instead of getting bubbles.
    var leadingStatus = false
    var trailingStatus = false
    /// The camera and mic's dot beside the charge in the notch's right wing
    /// (charging with no song).
    var notchBadge: PrivacyBadge?
    /// The running countdown, for the wings when it's the main activity.
    var timer: TimerSession?
    /// The downloads, for the wings when they're the main activity.
    var download: DownloadSummary?
    /// The agent's sessions, for the wings when it's the main activity.
    var agent: AgentSummary?

    static let empty = IslandArrangement()

    func bubble(_ side: NotchSide) -> BubbleSlot? {
        side == .leading ? leading : trailing
    }
}

/// Keeps track of every live activity — music, the charge, the camera and
/// mic — and decides where each one is shown.
///
/// - The main activity sits in the notch's wings: the song, else the charge,
///   else the camera and mic.
/// - The charge comes before the camera and mic: while charging, they get
///   no bubble, just a small dot on the charge, and open along with it.
/// - Anything else gets a bubble. The first takes the right side, a second
///   the left, and a bubble keeps its side while it lives. When the right one
///   ends, a lone left bubble moves over once the other has melted away. The
///   camera and mic share one bubble, so there are never more than two.
/// - A new activity first shows as a notification (the charging card, a
///   "Microphone in use" notice), which then shrinks into its bubble. While
///   something else is showing, the notification waits its turn in the
///   peek queue and the bubble waits with it.
/// - Clicking a bubble opens the activity into the notch. It closes on its
///   own after `autoCollapseDelay`, unless the pointer is on it, and shrinks
///   back into its bubble.
@MainActor
final class ActivityManager: ObservableObject {
    @Published private(set) var activities: [LiveActivity] = []
    /// Bubbles, or status inside the notch's wings (Settings).
    @Published private(set) var style: StatusStyle = .bubbles

    /// How long an opened activity stays open without the pointer on it.
    nonisolated static let autoCollapseDelay: TimeInterval = 5

    /// How long a new activity waits for its notification to show up before
    /// splitting off on its own.
    private static let announceGrace: TimeInterval = 1.2
    /// How long a bubble that's going away takes to melt into the notch,
    /// before another may take its side.
    private static let mergeDuration: TimeInterval = 0.45

    private let peeks: PeekCenter
    private weak var timers: TimerService?
    private weak var stayAwakeService: StayAwakeService?
    private weak var preferences: HUDPreferences?
    private var cancellables = Set<AnyCancellable>()
    private var rebalanceWork: DispatchWorkItem?
    private var lastPeek: Peek?

    init(peeks: PeekCenter) {
        self.peeks = peeks
    }

    /// Follows the live sources: the song, the charge, the camera and mic,
    /// with the Settings switches applied.
    func start(
        playback: PlaybackCoordinator,
        status: NotchStatus,
        timers: TimerService,
        downloads: DownloadsMonitor,
        agents: AgentStatusService,
        stayAwake: StayAwakeService,
        crowding: MenuBarCrowding,
        power: PowerStateMonitor,
        preferences: HUDPreferences
    ) {
        self.timers = timers
        self.stayAwakeService = stayAwake
        self.preferences = preferences
        // Where the user keeps each activity is re-applied as soon as it
        // changes.
        preferences.$trayOnly
            .dropFirst()
            .sink { [weak self] _ in self?.reallocate() }
            .store(in: &cancellables)
        // The user pausing the music themselves ends a sleep timer: it has
        // nothing left to fade. (The timer's own pause comes after it has
        // finished, so it never lands here.)
        playback.$currentTrack
            .map { $0.isPlaying }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak timers] playing in if !playing { timers?.playbackPausedByUser() } }
            .store(in: &cancellables)
        // Listens for the agent's hooks only while the switch is on.
        preferences.$agentStatus
            .removeDuplicates()
            .sink { agents.setActive($0) }
            .store(in: &cancellables)
        agents.onNotice = { [weak self, weak preferences] notice in
            // The playful line has its own Settings switch.
            if notice.state == .working, preferences?.agentBanter != true { return }
            self?.peeks.post(.agentNotice(notice))
        }
        // Watches the Downloads folder only while the switch is on and the
        // notch can be seen.
        preferences.$downloads.combineLatest(power.$isNotchVisible)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { downloads.setActive($0) }
            .store(in: &cancellables)
        downloads.onFinish = { [weak self] name in
            self?.peeks.post(.downloadDone(name: name))
        }
        preferences.$timers
            .sink { timers.isEnabled = $0 }
            .store(in: &cancellables)
        timers.onFinish = { [weak self] duration, sleep in
            if sleep {
                self?.peeks.post(.goodNight)
            } else {
                self?.peeks.post(.timerDone(minutes: Int((duration / 60).rounded()), sleep: false))
            }
        }
        // First, so the activities already going at launch are placed in
        // the chosen style.
        // The chosen style, unless "adapt to a crowded menu bar" is on and
        // an icon sits where a bubble would go: then everything goes inside
        // the notch, so no icon is covered.
        preferences.$statusStyle
            .combineLatest(preferences.$adaptiveStyle, crowding.$isCrowded)
            .map { style, adaptive, crowded -> StatusStyle in adaptive && crowded ? .inNotch : style }
            .removeDuplicates()
            .sink { [weak self] style in self?.setStyle(style) }
            .store(in: &cancellables)
        let music = playback.$currentTrack
            .map { !$0.isPlaceholder }
            .removeDuplicates()
            .combineLatest(preferences.$nowPlayingWings)
            .map { $0 && $1 }
        let charging = status.$chargingLevel
            .combineLatest(preferences.$chargingWing)
            .map { $1 ? $0 : nil }
        let privacy = status.$micInUse
            .combineLatest(status.$cameraInUse, preferences.$privacyDots)
            .map { (mic: $0 && $2, camera: $1 && $2) }

        let status4 = music.combineLatest(charging, privacy)
        let extras = timers.$session.combineLatest(downloads.$summary, agents.$summary, stayAwake.$isOn)
        status4.combineLatest(extras)
            .removeDuplicates { old, new in
                old.0.0 == new.0.0 && old.0.1 == new.0.1 && old.0.2 == new.0.2
                    && old.1.0 == new.1.0 && old.1.1?.count == new.1.1?.count
                    && old.1.1?.name == new.1.1?.name && old.1.2 == new.1.2 && old.1.3 == new.1.3
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] base, extra in
                self?.sync(
                    music: base.0, level: base.1, mic: base.2.mic, camera: base.2.camera,
                    timer: extra.0, download: extra.1, agent: extra.2, stayAwake: extra.3
                )
            }
            .store(in: &cancellables)

        peeks.$current
            .removeDuplicates { $0?.id == $1?.id }
            .sink { [weak self] peek in self?.peekChanged(to: peek) }
            .store(in: &cancellables)
    }

    // MARK: - Reading

    func activity(_ kind: ActivityKind) -> LiveActivity? {
        activities.first { $0.kind == kind }
    }

    /// What the notch shows right now.
    var arrangement: IslandArrangement {
        var result = IslandArrangement()
        result.primary = activities.first { $0.slot == .notch }?.kind
        result.timer = activity(.timer)?.timer
        result.download = activity(.download)?.download
        result.agent = activity(.agent)?.agent
        if style == .inNotch {
            let has = { (kind: ActivityKind) in self.activities.contains { $0.kind == kind } }
            result.leadingStatus = has(.privacy) && result.primary != .privacy
            result.trailingStatus = has(.charging) && result.primary == .music
            return result
        }
        // The camera and mic riding on the charge show once their notice
        // has shrunk away.
        let badge: PrivacyBadge? = activity(.privacy).flatMap { privacy in
            privacy.slot == .attached && privacy.status == .compact
                ? PrivacyBadge(mic: privacy.micInUse, camera: privacy.cameraInUse)
                : nil
        }
        if result.primary == .charging { result.notchBadge = badge }
        for activity in activities {
            guard var face = activity.face else { continue }
            if activity.kind == .charging { face = .charging(level: activity.level ?? 0, badge: badge) }
            let slot = BubbleSlot(kind: activity.kind, face: face, visible: activity.status == .compact)
            switch activity.slot {
            case .leading: result.leading = slot
            case .trailing: result.trailing = slot
            case .notch, .attached, .hidden: break
            }
        }
        return result
    }

    // MARK: - Lifecycle

    private func sync(music: Bool, level: Int?, mic: Bool, camera: Bool, timer: TimerSession?, download: DownloadSummary?, agent: AgentSummary?, stayAwake: Bool) {
        var next = activities
        func upsert(_ kind: ActivityKind, present: Bool, update: (inout LiveActivity) -> Void) -> Bool {
            if let index = next.firstIndex(where: { $0.kind == kind }) {
                if present {
                    update(&next[index])
                } else {
                    next.remove(at: index)
                }
                return false
            }
            guard present else { return false }
            // Music is already on screen (it's the notch's own wings), so it
            // has nothing to announce.
            // Inside the notch there's no bubble to announce either.
            // A timer the user just started needs no announcing either.
            let announces = kind != .music && kind != .timer && kind != .download && kind != .agent && kind != .stayAwake && style == .bubbles
            var activity = LiveActivity(kind: kind, status: announces ? .announcing : .compact, slot: .notch)
            update(&activity)
            next.append(activity)
            return true
        }

        let previousPrivacy = activity(.privacy)
        _ = upsert(.music, present: music) { _ in }
        let newCharge = upsert(.charging, present: level != nil) { $0.level = level }
        let newPrivacy = upsert(.privacy, present: mic || camera) {
            $0.micInUse = mic
            $0.cameraInUse = camera
        }
        _ = upsert(.timer, present: timer != nil) { $0.timer = timer }
        _ = upsert(.download, present: download != nil) { $0.download = download }
        _ = upsert(.agent, present: agent != nil) { $0.agent = agent }
        _ = upsert(.stayAwake, present: stayAwake) { _ in }
        next.sort { $0.priority < $1.priority }

        // A device switching on (the mic, then the camera too) is news even
        // when the bubble is already there: say so, and let it shrink back.
        let micStarted = mic && previousPrivacy?.micInUse != true
        let cameraStarted = camera && previousPrivacy?.cameraInUse != true
        let announcePrivacy = style == .bubbles
            && (newPrivacy || (previousPrivacy != nil && (micStarted || cameraStarted)))
        if announcePrivacy, let index = next.firstIndex(where: { $0.kind == .privacy }), next[index].status != .expanded {
            next[index].status = .announcing
        }

        let freed = allocate(&next)
        withAnimation(NotchView.splitMotion) {
            activities = next
        }

        if announcePrivacy {
            peeks.post(.privacy(PrivacyNotice(mic: micStarted || (newPrivacy && mic), camera: cameraStarted || (newPrivacy && camera))))
            settleAnnouncement(.privacy, after: Self.announceGrace)
        }
        if newCharge && style == .bubbles {
            settleAnnouncement(.charging, after: Self.announceGrace)
        }
        if freed { scheduleRebalance() }
    }

    /// Hands out places. The main activity takes the notch. Beside it there
    /// are two bubble places; the others keep the side they have, and
    /// newcomers take the right, then the left.
    ///
    /// When there's more than the two places can show, or the user keeps
    /// something in the tray (Settings), the best one gets a bubble and a
    /// "+N" chip takes the other, standing for everything else: nothing is
    /// hidden without a sign, and clicking the chip opens the tray with all
    /// of it. "Best" is the ones that need attention before the passive
    /// states (Stay Awake, the agent while it works), then by priority.
    ///
    /// Returns whether a side was given up, so a lone left bubble may move
    /// over once the leaving one has melted away.
    @discardableResult
    private func allocate(_ list: inout [LiveActivity]) -> Bool {
        let sidesBefore = Set(activities.map(\.slot).filter(\.isBubble))
        let previousChip = list.first { $0.kind == .overflow }
        list.removeAll { $0.kind == .overflow }
        let primary = [ActivityKind.music, .charging, .privacy, .timer, .download, .agent, .stayAwake]
            .first { kind in list.contains { $0.kind == kind } }
        // The charge comes first: while charging, the camera and mic get no
        // bubble of their own, only a dot on the charge.
        let attachesPrivacy = style == .bubbles
            && list.contains { $0.kind == .charging }
            && list.contains { $0.kind == .privacy }
        func attached(_ activity: LiveActivity) -> Bool {
            attachesPrivacy && activity.kind == .privacy
        }

        // Who competes for a bubble, and who goes to the tray.
        let extras = list.filter { $0.kind != primary && !attached($0) }
        var inTray = extras.filter { preferences?.isTrayOnly($0.kind) == true }
        let pool = extras
            .filter { activity in !inTray.contains { $0.kind == activity.kind } }
            .sorted { ($0.isPassive ? 1 : 0, $0.priority) < ($1.isPassive ? 1 : 0, $1.priority) }
        let places = 2
        var shown = pool
        if !inTray.isEmpty || pool.count > places {
            // One place goes to the chip.
            shown = Array(pool.prefix(places - 1))
            inTray += pool.dropFirst(places - 1)
        }
        let shownKinds = Set(shown.map(\.kind))

        // Bubbles keep their side…
        var taken = Set(list.filter { shownKinds.contains($0.kind) }.map(\.slot).filter(\.isBubble))
        for index in list.indices {
            let kind = list[index].kind
            if kind == primary {
                list[index].slot = .notch
            } else if attached(list[index]) {
                list[index].slot = .attached
            } else if !shownKinds.contains(kind) {
                list[index].slot = .hidden
            } else if !list[index].slot.isBubble {
                // …and newcomers (or the old main activity, handing over the
                // notch) take the right, then the left. The list is in
                // priority order, so two arriving together are placed the
                // same way every time.
                list[index].slot = taken.contains(.trailing) ? .leading : .trailing
                taken.insert(list[index].slot)
            }
        }

        // The chip, on whichever side is free (keeping its own if it can).
        if !inTray.isEmpty {
            var chip = previousChip ?? LiveActivity(kind: .overflow, status: .compact, slot: .trailing)
            chip.overflowCount = inTray.count
            let free: [ActivitySlot] = [.trailing, .leading].filter { !taken.contains($0) }
            chip.slot = free.contains(chip.slot) ? chip.slot : (free.first ?? .hidden)
            chip.status = .compact
            list.append(chip)
        }

        let sidesAfter = Set(list.map(\.slot).filter(\.isBubble))
        return !sidesBefore.subtracting(sidesAfter).isEmpty
    }

    /// Re-places everything after a Settings change.
    private func reallocate() {
        var next = activities
        allocate(&next)
        guard next != activities else { return }
        withAnimation(NotchView.splitMotion) {
            activities = next
        }
    }

    /// Everything running that the tray lists: all but the music (which has
    /// its own card) and the chip itself.
    var trayEntries: [LiveActivity] {
        activities.filter { $0.kind != .music && $0.kind != .overflow }
    }

    /// Opens the tray: one card listing everything that's running.
    func expandTray() {
        guard !trayEntries.isEmpty else { return }
        for other in activities where other.status == .expanded {
            setStatus(other.kind, .compact)
        }
        peeks.postNow(.tray)
    }

    /// A lone bubble on the left moves to the right, once whatever was there
    /// has had time to melt away: it melts into the notch's left side and
    /// splits out of its right.
    private func scheduleRebalance() {
        rebalanceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var next = self.activities
            let bubbles = next.filter { $0.slot.isBubble }
            if bubbles.count == 1, let index = next.firstIndex(where: { $0.slot == .leading }) {
                next[index].slot = .trailing
            }
            // A side that freed up goes to an activity that was waiting.
            self.allocate(&next)
            guard next != self.activities else { return }
            withAnimation(NotchView.splitMotion) {
                self.activities = next
            }
        }
        rebalanceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.mergeDuration, execute: work)
    }

    // MARK: - Notifications

    /// Once the grace is up, an activity whose notification never showed
    /// (Settings turned it off, the screen was locked, it was dropped from
    /// the queue) splits off on its own.
    private func settleAnnouncement(_ kind: ActivityKind, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.activity(kind)?.status == .announcing else { return }
            let showing = self.peeks.current.map { $0.content.announces == kind } ?? false
            let waiting = self.peeks.hasPending { $0.announces == kind }
            if showing || waiting {
                // Still on its way: check again once it's had its turn.
                self.settleAnnouncement(kind, after: 1)
                return
            }
            self.setStatus(kind, .compact)
        }
    }

    /// A notification left the notch: the activity it was about shrinks
    /// into its bubble, on the same spring that closes the notification.
    private func peekChanged(to peek: Peek?) {
        if let previous = lastPeek, previous.id != peek?.id, let kind = previous.content.announces {
            let stillShown = peek?.content.announces == kind
            if !stillShown, let status = activity(kind)?.status, status != .compact {
                setStatus(kind, .compact)
            }
        }
        lastPeek = peek
    }

    private func setStatus(_ kind: ActivityKind, _ status: LiveActivity.Status) {
        guard let index = activities.firstIndex(where: { $0.kind == kind }),
              activities[index].status != status
        else { return }
        var next = activities
        next[index].status = status
        next[index].lastInteraction = Date()
        withAnimation(NotchView.splitMotion) {
            activities = next
        }
    }

    /// Switching style in Settings: everything settles in place, and an
    /// activity opened from its bubble folds away.
    private func setStyle(_ new: StatusStyle) {
        guard new != style else { return }
        if new == .inNotch, case .activity? = peeks.current?.content {
            peeks.dismissCurrent()
        }
        var next = activities
        for index in next.indices { next[index].status = .compact }
        withAnimation(NotchView.splitMotion) {
            style = new
            // Whether the camera and mic ride on the charge depends on it.
            allocate(&next)
            activities = next
        }
    }

    // MARK: - Interaction

    /// A click on a bubble — or on the notch while the charge or the mic is
    /// all it shows — opens the activity into the notch, replacing whatever
    /// notification is showing; any other bubble stays.
    func expand(_ kind: ActivityKind) {
        if kind == .overflow { return expandTray() }
        guard kind != .music,
              let current = activity(kind), current.status == .compact,
              // In the notch there are no bubbles to click; the notch's own
              // activity still opens.
              style == .bubbles || current.slot == .notch
        else { return }
        // Another activity that's open shrinks back first (the queue swaps
        // them in one motion).
        for other in activities where other.kind != kind && other.status == .expanded {
            setStatus(other.kind, .compact)
        }
        setStatus(kind, .expanded)
        peeks.postNow(.activity(kind))
    }

    /// The Stay Awake detail's Turn Off button.
    func turnOffStayAwake() {
        stayAwakeService?.setOn(false)
    }

    /// The timer's Cancel button.
    func cancelTimer() {
        timers?.cancel()
    }

    /// The pointer is on an opened activity.
    func noteInteraction(_ kind: ActivityKind) {
        guard let index = activities.firstIndex(where: { $0.kind == kind }) else { return }
        activities[index].lastInteraction = Date()
    }
}
