import SwiftUI
import Combine

/// Something going on that the closed notch keeps showing, like a Live
/// Activity on iPhone.
enum ActivityKind: CaseIterable, Equatable {
    case privacy
    case charging
    case music

    /// Lower comes first when bubbles are handed out: the camera and mic are
    /// about privacy, so they're never the one left out; then the charge.
    var priority: Int {
        switch self {
        case .privacy: return 0
        case .charging: return 1
        case .music: return 2
        }
    }
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
    let createdAt = Date()
    var lastInteraction = Date()

    var priority: Int { kind.priority }
    var isExpanded: Bool { status == .expanded }

    var face: BubbleFace? {
        switch kind {
        case .charging: return .charging(level: level ?? 0)
        case .privacy: return .privacy(mic: micInUse, camera: cameraInUse)
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
    private var cancellables = Set<AnyCancellable>()
    private var rebalanceWork: DispatchWorkItem?
    private var lastPeek: Peek?

    init(peeks: PeekCenter) {
        self.peeks = peeks
    }

    /// Follows the live sources: the song, the charge, the camera and mic,
    /// with the Settings switches applied.
    func start(playback: PlaybackCoordinator, status: NotchStatus, preferences: HUDPreferences) {
        // First, so the activities already going at launch are placed in
        // the chosen style.
        preferences.$statusStyle
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

        music.combineLatest(charging, privacy)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
            .receive(on: RunLoop.main)
            .sink { [weak self] music, level, privacy in
                self?.sync(music: music, level: level, mic: privacy.mic, camera: privacy.camera)
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
            case .notch, .attached: break
            }
        }
        return result
    }

    // MARK: - Lifecycle

    private func sync(music: Bool, level: Int?, mic: Bool, camera: Bool) {
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
            let announces = kind != .music && style == .bubbles
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

    /// Hands out places. The main activity takes the notch; the others keep
    /// the side they have, and newcomers take the right, then the left.
    /// Returns whether a side was given up, so a lone left bubble may move
    /// over once the leaving one has melted away.
    @discardableResult
    private func allocate(_ list: inout [LiveActivity]) -> Bool {
        let sidesBefore = Set(activities.map(\.slot).filter(\.isBubble))
        let primary = [ActivityKind.music, .charging, .privacy]
            .first { kind in list.contains { $0.kind == kind } }
        // The charge comes first: while charging, the camera and mic get no
        // bubble of their own, only a dot on the charge.
        let attachesPrivacy = style == .bubbles
            && list.contains { $0.kind == .charging }
            && list.contains { $0.kind == .privacy }
        func attached(_ activity: LiveActivity) -> Bool {
            attachesPrivacy && activity.kind == .privacy
        }
        // Bubbles keep their side…
        var taken = Set(list.filter { $0.kind != primary && !attached($0) }.map(\.slot).filter(\.isBubble))
        for index in list.indices {
            if list[index].kind == primary {
                list[index].slot = .notch
                continue
            }
            if attached(list[index]) {
                list[index].slot = .attached
                continue
            }
            // …and newcomers (or the old main activity, handing over the
            // notch) take the right, then the left. The list is in priority
            // order, so two arriving together are placed the same way every
            // time.
            guard !list[index].slot.isBubble else { continue }
            list[index].slot = taken.contains(.trailing) ? .leading : .trailing
            taken.insert(list[index].slot)
        }
        let sidesAfter = Set(list.map(\.slot).filter(\.isBubble))
        return !sidesBefore.subtracting(sidesAfter).isEmpty
    }

    /// A lone bubble on the left moves to the right, once whatever was there
    /// has had time to melt away: it melts into the notch's left side and
    /// splits out of its right.
    private func scheduleRebalance() {
        rebalanceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let bubbles = self.activities.filter { $0.slot.isBubble }
            guard bubbles.count == 1,
                  let index = self.activities.firstIndex(where: { $0.slot == .leading })
            else { return }
            var next = self.activities
            next[index].slot = .trailing
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

    /// The pointer is on an opened activity.
    func noteInteraction(_ kind: ActivityKind) {
        guard let index = activities.firstIndex(where: { $0.kind == kind }) else { return }
        activities[index].lastInteraction = Date()
    }
}
