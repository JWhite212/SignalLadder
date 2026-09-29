import Foundation
@testable import NotificationCore

/// A scheduler whose clocks move only when a test moves them, so ladder timing
/// is proven in well under a second however many minutes it covers (M4 plan,
/// ruling 4).
///
/// Timers fall due by awake time. `advance(by:)` moves both clocks and fires
/// what falls due, in due order, earliest scheduled first on a tie, with the
/// clocks at each one's due time. `sleep(for:)` moves only the wall clock and
/// fires nothing: the Mac asleep.
@MainActor
final class ManualScheduler: EscalationScheduler {
    private(set) var wall: Date
    private(set) var awake: TimeInterval = 0

    private struct Pending {
        let token: EscalationTimerToken
        let due: TimeInterval
        let sequence: Int
        let work: @MainActor () -> Void
    }
    private var pending: [Pending] = []
    private var cancelled: [Pending] = []
    private var lastFired: Pending?
    private var scheduled = 0

    init(start: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        wall = start
    }

    func now() -> Date { wall }
    func awakeTime() -> TimeInterval { awake }

    func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> EscalationTimerToken {
        scheduled += 1
        let token = EscalationTimerToken()
        pending.append(Pending(token: token, due: awake + seconds, sequence: scheduled, work: work))
        return token
    }

    func cancel(_ token: EscalationTimerToken) {
        guard let index = pending.firstIndex(where: { $0.token == token }) else { return }
        cancelled.append(pending.remove(at: index))
    }

    var pendingCount: Int { pending.count }

    func advance(by seconds: TimeInterval) {
        let target = awake + seconds
        while let next = pending.filter({ $0.due <= target })
            .min(by: { ($0.due, $0.sequence) < ($1.due, $1.sequence) }) {
            pending.removeAll { $0.token == next.token }
            move(to: next.due)
            lastFired = next
            next.work()
        }
        move(to: target)
    }

    func sleep(for seconds: TimeInterval) {
        wall += seconds
    }

    /// Runs every cancelled timer's work, standing in for one that was already
    /// on its way when it was cancelled — what a hop to the main actor would
    /// allow, and ruling 2 rejects.
    func runCancelled() {
        let late = cancelled
        cancelled = []
        for timer in late { timer.work() }
    }

    /// Delivers the last timer that fired a second time, as a timer
    /// delivered twice would.
    func refireLast() {
        lastFired?.work()
    }

    private func move(to due: TimeInterval) {
        wall += due - awake
        awake = due
    }
}
