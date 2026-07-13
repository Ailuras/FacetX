import AppKit
import FacetXCore
import Foundation
import UserNotifications

enum FocusTargetKind: String {
    case task, event
}

/// What is being focused on. `id` is the stable focus key: the item's facetID
/// when present (survives reminder/event conversion), otherwise the EventKit
/// identifier.
struct FocusTarget: Equatable {
    let id: String
    let title: String
    let kind: FocusTargetKind
    /// Shown next to the countdown in the menu bar and widget — the project
    /// name for the work item.
    let projectLabel: String
    /// Recorded with the session for future per-project statistics.
    let projectPrefix: String
}

/// One running pomodoro-style countdown. Wall-clock based with a pause bank,
/// so elapsed time stays correct across UI reloads.
struct FocusSession {
    let target: FocusTarget
    let plannedSeconds: Int
    let startedAt: Date
    var segmentStart: Date
    var banked: TimeInterval
    var isPaused: Bool

    func elapsed(now: Date) -> TimeInterval {
        banked + (isPaused ? 0 : max(0, now.timeIntervalSince(segmentStart)))
    }

    func remaining(now: Date) -> TimeInterval {
        max(0, TimeInterval(plannedSeconds) - elapsed(now: now))
    }
}

/// App-wide focus timer: one session at a time, ticking on a 1s timer while
/// active. Finished sessions accrue to the target in ItemStore; `totalsByTarget`
/// feeds the row badges and `todaySeconds` the widget stat.
@MainActor
final class FocusService: ObservableObject {
    @Published private(set) var session: FocusSession?
    @Published private(set) var now = Date()
    @Published private(set) var totalsByTarget: [String: ItemStore.FocusTotals] = [:]
    @Published private(set) var todaySeconds = 0

    private var timer: Timer?
    private var notificationsRequested = false

    init() {
        reloadTotals()
    }

    var isFocusing: Bool { session != nil }

    func isFocusing(_ targetID: String) -> Bool {
        session?.target.id == targetID
    }

    var remainingSeconds: Int {
        guard let session else { return 0 }
        return Int(session.remaining(now: now).rounded(.up))
    }

    var progress: Double {
        guard let session, session.plannedSeconds > 0 else { return 0 }
        return min(1, session.elapsed(now: now) / Double(session.plannedSeconds))
    }

    // ── Controls ─────────────────────────────────────────────────────────────

    /// Start focusing on a target. A running session is finished (and recorded)
    /// first, so switching focus never silently drops time.
    func start(target: FocusTarget, minutes: Int) {
        if session != nil { finish() }
        let start = Date()
        session = FocusSession(target: target,
                               plannedSeconds: max(60, minutes * 60),
                               startedAt: start,
                               segmentStart: start,
                               banked: 0,
                               isPaused: false)
        now = start
        startTimer()
        requestNotificationAuthorizationIfNeeded()
    }

    func pause() {
        guard var s = session, !s.isPaused else { return }
        s.banked = s.elapsed(now: Date())
        s.isPaused = true
        session = s
    }

    func resume() {
        guard var s = session, s.isPaused else { return }
        s.segmentStart = Date()
        s.isPaused = false
        session = s
        now = Date()
    }

    /// End the session early. Records the elapsed time when at least a minute
    /// was spent; shorter fragments are discarded as noise.
    func finish() {
        guard let s = session else { return }
        let elapsed = Int(s.elapsed(now: Date()))
        session = nil
        stopTimer()
        if elapsed >= 60 {
            record(session: s, seconds: elapsed)
        }
    }

    /// Timer ran out: record the full planned duration and celebrate.
    private func complete() {
        guard let s = session else { return }
        session = nil
        stopTimer()
        record(session: s, seconds: s.plannedSeconds)
        notifyCompletion(s)
    }

    private func record(session s: FocusSession, seconds: Int) {
        ItemStore.shared.recordFocusSession(
            targetID: s.target.id,
            projectPrefix: s.target.projectPrefix,
            title: s.target.title,
            kind: s.target.kind.rawValue,
            startedAt: s.startedAt,
            seconds: seconds
        )
        reloadTotals()
    }

    func reloadTotals() {
        totalsByTarget = ItemStore.shared.focusTotalsByTarget()
        todaySeconds = ItemStore.shared.focusSecondsToday()
    }

    // ── Timer ────────────────────────────────────────────────────────────────

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let session else {
            stopTimer()
            return
        }
        now = Date()
        if !session.isPaused, session.remaining(now: now) <= 0 {
            complete()
        }
    }

    // ── Completion feedback ──────────────────────────────────────────────────

    private func requestNotificationAuthorizationIfNeeded() {
        guard !notificationsRequested else { return }
        notificationsRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyCompletion(_ s: FocusSession) {
        NSSound(named: "Glass")?.play()
        let content = UNMutableNotificationContent()
        content.title = L10n.pick("Focus complete", "专注完成")
        content.body = "\(s.target.title) · \(Self.format(seconds: s.plannedSeconds))"
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // ── Formatting ───────────────────────────────────────────────────────────

    /// Compact duration for badges: "45m", "1h20m", "3h".
    nonisolated static func format(seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h\(String(format: "%02d", rest))m"
    }

    /// Countdown clock: "24:59".
    nonisolated static func clock(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension ProjectItem {
    /// The stable key focus time accrues to for this item.
    var focusTargetID: String { facetID ?? id }

    func focusTarget(projectName: String) -> FocusTarget {
        let kind: FocusTargetKind = self.kind == .reminder ? .task : .event
        return FocusTarget(id: focusTargetID,
                           title: content,
                           kind: kind,
                           projectLabel: projectName,
                           projectPrefix: projectPrefix)
    }
}
