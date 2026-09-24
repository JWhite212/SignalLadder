// Sources/NotificationCore/CaptureRingBuffer.swift
import Foundation

/// The last N captures, in memory and nowhere else.
///
/// This is the first place in the project that retains notification content at
/// all — every earlier stage read it, used it, and dropped it. The spec permits
/// exactly this and no more: in-memory, bounded, dying with the process (§6).
/// There is deliberately no persistence, no export, and no logging path out of
/// this type. Adding one would need a decision about content leaving the
/// machine, which the project has already made in the negative.
///
/// Not thread-safe by design. Callers are main-actor isolated, and adding a
/// lock would suggest otherwise.
public final class CaptureRingBuffer {
    private var storage: [InspectorEntry] = []
    private let capacity: Int
    private let recentWindow: TimeInterval

    /// - Parameters:
    ///   - capacity: rows retained. ~50 per §6.
    ///   - recentWindow: how far back `recentCountForApp` looks.
    public init(capacity: Int = 50, recentWindow: TimeInterval = 3600) {
        self.capacity = max(1, capacity)
        self.recentWindow = recentWindow
    }

    /// Newest first, as the Inspector displays them (§7.2).
    public var entries: [InspectorEntry] { storage.reversed() }

    public var count: Int { storage.count }

    public var isEmpty: Bool { storage.isEmpty }

    /// Records a capture and returns the entry created for it.
    ///
    /// - Parameter suppressedRepeatCount: copies dedupe collapsed into this
    ///   one. Carried through rather than discarded so the Inspector can show
    ///   that suppression happened at all.
    @discardableResult
    public func record(_ notification: CapturedNotification,
                       suppressedRepeatCount: Int) -> InspectorEntry {
        let context = makeContext(for: notification)
        let entry = InspectorEntry(captured: notification,
                                   context: context,
                                   suppressedRepeatCount: suppressedRepeatCount)
        storage.append(entry)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
        return entry
    }

    /// Attaches an evaluation result to a row that already exists.
    ///
    /// Silently does nothing when the row has aged out — a slow evaluator
    /// returning after eviction is expected, and dropping its result is the
    /// correct outcome. Matching on identity rather than position is what makes
    /// that safe: positions shift on every eviction.
    public func annotate(id: UUID, with annotation: MatchAnnotation) {
        guard let index = storage.firstIndex(where: { $0.id == id }) else { return }
        storage[index].annotation = annotation
    }

    /// Records that dedupe suppressed a further copy of something already here,
    /// on the row it actually duplicates. Returns false when no such row is
    /// present, leaving the caller to decide what to do with the fact.
    ///
    /// The alternative — holding the count aside and attaching it to whatever
    /// arrives next — puts the number on a different notification, possibly
    /// from a different app entirely, and loses it outright if nothing else
    /// ever arrives. Both are misreporting in the one window built so the user
    /// can trust what they are seeing.
    ///
    /// Matches on `rawText` because that is the key dedupe itself used; any
    /// other key could disagree with the decision being recorded.
    @discardableResult
    public func noteSuppressedRepeat(matching rawText: String) -> Bool {
        guard let index = storage.lastIndex(where: { $0.captured.rawText == rawText }) else {
            return false
        }
        storage[index].suppressedRepeatCount += 1
        return true
    }

    /// Counts recent notifications from the same app, including the one being
    /// recorded, and reports whether that count is a total or a floor.
    private func makeContext(for notification: CapturedNotification) -> ContextSnapshot {
        let cutoff = notification.timestamp.addingTimeInterval(-recentWindow)

        let priorFromSameApp = storage.filter {
            $0.captured.appNameGuess == notification.appNameGuess && $0.captured.timestamp >= cutoff
        }.count

        // The count can only be short if the buffer was already full AND the
        // entry about to fall off was inside the window AND it belonged to the
        // app being counted. All three, not two.
        //
        // Dropping the last condition looks harmless and is not. On a full
        // buffer, some app's oldest entry is almost always inside the window,
        // so the flag would fire for every app on every record — and a hedge
        // that is always on carries no information. It would turn the one
        // number that measures the user's actual problem, how hard a single
        // channel is drowning them, into a permanent shrug.
        let willEvict = storage.count >= capacity
        let losingACountedEntry = storage.first.map {
            $0.captured.timestamp >= cutoff && $0.captured.appNameGuess == notification.appNameGuess
        } ?? false

        return ContextSnapshot(date: notification.timestamp,
                               recentCountForApp: priorFromSameApp + 1,
                               recentCountIsUnderCounted: willEvict && losingACountedEntry)
    }
}
