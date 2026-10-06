// Sources/NotificationCore/SetupProgress.swift
import Foundation

/// The steps of the first run, in the order the guide shows them (M5 plan, Ruling 16,
/// O13, Task 7). `allCases` is that order.
///
/// A step's state is read from facts wherever a fact can show it, and what is stored is
/// only what no fact can (`SetupProgress`). A step that was skipped is such a thing, so
/// its raw string is saved, inside a token (`SetupProgress.recordSkipped(_:)`). **The raw
/// strings are written out, so that they do not follow the case names.** They are equal
/// to the names today, and a string that looks redundant is what keeps it so: renaming a
/// case in the code must not change what an earlier build saved, which would read as
/// every skip forgotten. A test holds the eight to the words typed in it. A string is
/// only ever added for a step that is added, and one that is gone is left to be read as
/// unknown.
///
/// Which of them may be skipped is the plan's to say (`SetupPlan`), and not this type's:
/// the progress records what it is told.
public enum SetupStep: String, CaseIterable, Equatable, Sendable {
    /// Step 0. How it works: the replacement model and the three limits said plainly.
    /// What was seen of it is stored as `SetupProgress.hasSeenIntroduction`.
    case howItWorks = "howItWorks"
    /// Step 1. Accessibility, which a fact shows (`AXIsProcessTrusted()`).
    case accessibility = "accessibility"
    /// Step 2. Notifications, which a fact shows (`NotificationPermission` and whether a
    /// banner would be drawn).
    case notifications = "notifications"
    /// Step 3. Prove it can read: done when health is verified, and a soft gate that may
    /// be passed without verifying (O13).
    case proveItCanRead = "proveItCanRead"
    /// Step 4. The first rule, which a fact shows (the rules, and whether one alerts
    /// aloud).
    case firstRule = "firstRule"
    /// Step 5. Mute the source app, which the mute checklist shows, as the user's word.
    case muteSourceApp = "muteSourceApp"
    /// Step 6. Do Not Disturb and Focus. No fact can show it, since a Focus cannot be
    /// read, so it is done when the user attests it (`SetupProgress.focusIsAttested`).
    case focus = "focus"
    /// Step 7. Keep it running: Launch at login, done when the login item is enabled, or
    /// skipped.
    case keepItRunning = "keepItRunning"
}

/// What the first run has to remember because nothing it can read would show it (M5
/// plan, Ruling 16, O13, Task 7): one list of tokens, as the mute checklist is one list
/// of digests.
///
/// **Only these are stored.** That the guide was started, that it was dismissed, that it
/// was finished, that a named step was skipped, that the user attests the Focus step,
/// and that they have seen the introduction. Everything else the guide shows (whether
/// Accessibility is granted, what the notification permission is, what health reads,
/// which rules there are, whether an app is muted, what the login item says) is read
/// afresh each time, so that a permission taken away afterwards is not hidden by
/// something saved. A token is a short fixed word and never holds what a notification
/// said, an app's name or a rule's name, so nothing a banner carried reaches the
/// preferences by this route.
///
/// **Dismissed is one token, and one method records it.** "Not now" and closing the
/// guide's window are the same act (O13): each leaves the guide closed, so that it does
/// not open again by itself, and each leaves its one menu line while a required step is
/// outstanding. They call `recordDismissed()` and there is no second way to write it, so
/// they cannot come to differ.
///
/// **Reading and writing a list.** `init(stored:)` takes the list the app target read from
/// the preferences and `stored` is what it writes back, in the shape
/// `MuteChecklist.stored` has. An empty list is a fresh install's progress, and so is
/// none at all.
///
/// - A token this build does not know is ignored when read: it is no fact, it makes
///   nothing read as started, dismissed, finished or skipped, and a list that holds
///   only such tokens is a fresh install's. A "skipped:" token whose step is not one
///   of `SetupStep`'s, or is empty, is such a token; so is one with different
///   spelling, case or spaces. Tokens are matched exactly.
/// - It is **kept** when the list is written back, after the ones this build knows, and
///   not dropped. A newer build may add a token, and an older build that read the list
///   and wrote it back without it would take away what the newer build saved: a user
///   who moves between two builds would see the guide's answer change with nothing
///   done. Keeping costs a few short words in a list that holds no more than a handful,
///   and a token this build does not know comes from a newer build or from a preferences
///   file edited by hand.
/// - A token read twice, or recorded twice, is one token. The order the list was read
///   in is not kept: known tokens are written in the one order below, and unknown ones
///   after them in sorted order, so what is saved is the same whatever order things
///   were recorded in, and two progresses that hold the same facts are equal. The one
///   exception is a dismissal recorded after the guide was finished, which is not written
///   (`recordDismissed()`): dismissed and then finished is saved as both, and finished
///   and then dismissed as `finished` alone, so for that pair the order is what is saved.
///
/// **What is written**, and so what is read, each one exactly (a test holds these to
/// the words typed in it, since they are saved):
///
/// | what | token |
/// | --- | --- |
/// | the guide was started | `started` |
/// | the introduction was seen | `introductionSeen` |
/// | a step was skipped | `skipped:` and the step's raw string (`SetupStep`) |
/// | the Focus step is attested | `focusAttested` |
/// | the guide was dismissed | `dismissed` |
/// | the guide was finished | `finished` |
public struct SetupProgress: Equatable, Sendable {
    /// The preferences key the app target keeps `stored` under, as a list of strings.
    /// The one value Tasks 7 and 8 add (M5 plan, Global Constraints), and nothing but
    /// tokens is in it.
    public static let storageKey = "setupProgress"

    /// Every token, the ones this build knows and the ones it does not.
    private var tokens: Set<String>

    /// Reads what the preferences gave for `storageKey`. An empty list is a fresh
    /// install's progress, and tokens this build does not know are ignored by every
    /// question and kept by `stored`.
    public init(stored: [String] = []) {
        tokens = Set(stored)
    }

    /// The list to save: the known tokens in one fixed order, then the unknown ones
    /// sorted. A progress that holds nothing saves the empty list, and a fresh one that
    /// holds only tokens this build does not know saves those (`isFresh`).
    public var stored: [String] {
        Self.vocabulary.filter(tokens.contains) + tokens.subtracting(Self.vocabulary).sorted()
    }

    // MARK: - What has been recorded

    /// Nothing this build knows has been recorded, which is what a fresh install reads
    /// as, and what a list of tokens only a newer build knows reads as. A progress whose
    /// only tokens are unknown ones is still fresh, and what it holds is kept (`stored`).
    public var isFresh: Bool { tokens.isDisjoint(with: Self.vocabulary) }

    /// The guide was started. Only `recordStarted()` writes it: recording the
    /// introduction, a skip, the Focus attestation, a dismissal or a finish does not say
    /// the guide was started, so a progress can hold any of those and be neither fresh
    /// nor started. What the guide makes of such a progress is `SetupPlan`'s to decide.
    public var hasStarted: Bool { tokens.contains(Token.started) }

    /// The guide was dismissed, by "Not now" or by closing its window, which are one
    /// act (O13).
    public var isDismissed: Bool { tokens.contains(Token.dismissed) }

    /// The guide was finished.
    public var isFinished: Bool { tokens.contains(Token.finished) }

    /// The user has seen the introduction (step 0).
    public var hasSeenIntroduction: Bool { tokens.contains(Token.introductionSeen) }

    /// The user has said they have attended to Do Not Disturb and Focus (step 6): their
    /// word, since the app cannot read a Focus.
    public var focusIsAttested: Bool { tokens.contains(Token.focusAttested) }

    /// Whether the user skipped a step. Only a token for a step that `SetupStep` has,
    /// spelt exactly, says so. It answers for any of the eight as the list holds it:
    /// whether a skip stands in for a step is `SetupPlan`'s decision, and a skip stored
    /// for a step that the plan does not let be skipped is a stored word and not a step
    /// that is done.
    public func isSkipped(_ step: SetupStep) -> Bool { tokens.contains(Token.skipped(step)) }

    // MARK: - Recording

    /// The guide was started. Recording it twice changes nothing.
    public mutating func recordStarted() { tokens.insert(Token.started) }

    /// The guide was dismissed: the one way to write it, which "Not now" and closing the
    /// window both use (O13).
    ///
    /// **A guide that is finished is not dismissed.** Closing its window after the last
    /// step is not a "Not now", and a dismissal beside `finished` would say nothing a
    /// reader needs, so this records nothing then. The guard is deliberate, and it makes
    /// the order of this pair matter, which is so of no other two records: dismissed and
    /// then finished keeps both, and finished and then dismissed keeps `finished` alone.
    /// The window's close path calls it every time and need not ask whether the guide
    /// was finished, which would be a decision in the app target that nothing tests
    /// (Ruling 10).
    public mutating func recordDismissed() {
        guard !isFinished else { return }
        tokens.insert(Token.dismissed)
    }

    /// The guide was finished. A dismissal recorded earlier is kept: it was a fact when
    /// it was recorded, and finishing does not undo it. A dismissal recorded after is not
    /// written (`recordDismissed()`).
    public mutating func recordFinished() { tokens.insert(Token.finished) }

    /// The user has seen the introduction.
    public mutating func recordIntroductionSeen() { tokens.insert(Token.introductionSeen) }

    /// The user attests the Focus step.
    public mutating func recordFocusAttested() { tokens.insert(Token.focusAttested) }

    /// The user skipped a step. It records what it is told: which steps may be skipped
    /// is `SetupPlan`'s decision. Skipping one step says nothing of another, and
    /// skipping one twice is once.
    public mutating func recordSkipped(_ step: SetupStep) { tokens.insert(Token.skipped(step)) }

    // MARK: - The tokens

    /// The words written, each exactly.
    private enum Token {
        static let started = "started"
        static let introductionSeen = "introductionSeen"
        static let focusAttested = "focusAttested"
        static let dismissed = "dismissed"
        static let finished = "finished"

        /// What is written for a skipped step: the word, a colon and the step's raw
        /// string, which is never a name, an app or a rule.
        static func skipped(_ step: SetupStep) -> String { "skipped:" + step.rawValue }
    }

    /// Every token this build knows, in the order `stored` writes them.
    private static let vocabulary: [String] = {
        var tokens: [String] = [Token.started, Token.introductionSeen]
        tokens += SetupStep.allCases.map(Token.skipped)
        tokens += [Token.focusAttested, Token.dismissed, Token.finished]
        return tokens
    }()
}
