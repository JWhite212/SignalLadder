// Sources/NotificationCore/QuitPolicy.swift
import Foundation

/// What quitting asks, and when it does not (M5 plan, Ruling 10, O6).
///
/// Quitting ends all capture and every alarm, so it is asked about while that
/// would cost something: while an alert is listed, as it always has been, and
/// now while the user is on call, since on-call state never expires and a
/// stray ⌘Q would otherwise end on-call alerting without a word. The prompt is
/// an ordinary alert with capture running behind it (Ruling 22), so a stray ⌘Q
/// costs an answer and not an outage.
///
/// **A log out, a restart and a shut down are never met by a prompt of the
/// app's own.** `applicationShouldTerminate` is what each of them calls, and an
/// alert there blocks them until it is answered, while cancelling aborts them,
/// which the system blames on the app. On-call state never expires, so the
/// prompt would meet every shutdown. The app reads two signals and this decides
/// from both:
///
/// - the quit's own reason, a four-character code the system sends with the
///   quit event (`kAEQuitReason`), which the app passes as a number since the
///   core imports none of the frameworks that name it; and
/// - the age of the last notice the system gave that a log out, a restart or a
///   shut down was requested (`NSWorkspace.willPowerOffNotification`), counted
///   in awake time from the moment it arrived.
///
/// Either excuses the prompt. A quit that neither classifies, a ⌘Q, the menu's
/// Quit or one another app sends, carries neither signal and is asked about,
/// and so is one
/// whose code is absent or not one of the six, which is the safe direction.
///
/// **A prompt that is already showing when a log out begins is ended only by
/// the notice.** AppKit swallows a quit that arrives while another is being
/// answered: it is answered as handled and `applicationShouldTerminate` is not
/// called again, so the quit's reason never reaches the app a second time, and
/// the alert would hold the log out until it is answered. The notice is the one
/// signal that can still arrive then: the main queue runs while an alert is up,
/// and a scratch program saw AppKit post the notice itself for a quit event that
/// carries a reason, the swallowed one included. So a notice that arrives while
/// a prompt is showing answers it as Quit (`noticeAnswersShowingPrompt`) and
/// `mayQuit` goes ahead without asking again. That a real log out's event
/// carries a reason, or that the system sends the notice, has not been seen:
/// where neither arrives, the prompt still holds the log out until it is
/// answered. The unsaved-draft sheet that follows holds one the same way, and
/// the notice does not answer it.
///
/// **The notice has a lifetime, because nothing else would end it.** A log out
/// that is aborted, by Cancel on the unsaved-draft sheet that still holds one
/// or by another app refusing, would leave the notice standing for the rest of
/// the session, and every later quit would skip the prompt. So a notice counts
/// for two minutes and no longer. A cancel made in the system's own dialog
/// reaches the app as nothing, so for those two minutes a quit is excused after
/// one (O6 states that cost), and a prompt that was showing when a notice
/// arrived has been answered as Quit, so a user whose prompt went that way and
/// who then cancels the system's dialog has quit.
public enum QuitPolicy {
    // MARK: - The quit's own reason

    public enum Reason: Equatable, Sendable {
        /// The user: ⌘Q or the menu's Quit (the app has no Dock icon). Also any quit whose code is
        /// absent or not one of the six below, since asking is the safe answer.
        case user
        case logOut
        case restart
        case shutDown
    }

    /// The reason a quit's four-character code gives. The codes are the SDK's
    /// own, as printed on 2026-09-30, and are given as numbers because the core
    /// names none of the frameworks that define them. An absent code is `.user`.
    public static func reason(fromCode code: UInt32?) -> Reason {
        switch code {
        case 1819240303?, 1919706991?:   // 'logo' kAELogOut, 'rlgo' kAEReallyLogOut
            return .logOut
        case 1920103284?, 1919251316?:   // 'rrst' kAEShowRestartDialog, 'rest' kAERestart
            return .restart
        case 1920164974?, 1936225652?:   // 'rsdn' kAEShowShutdownDialog, 'shut' kAEShutDown
            return .shutDown
        default:
            return .user
        }
    }

    // MARK: - The system's notice

    /// How long a power-off notice excuses the prompt: two minutes of awake
    /// time. Long enough for a slow log out to reach the app after the notice,
    /// and short enough that one that was aborted stops excusing quits soon.
    public static let noticeLifetime: TimeInterval = 120

    /// How old the last notice is, from the awake time it arrived at and the
    /// awake time now. nil when none has arrived.
    public static func noticeAge(arrivedAt: TimeInterval?, now: TimeInterval) -> TimeInterval? {
        arrivedAt.map { now - $0 }
    }

    /// Whether a notice that old still excuses the prompt: from the moment it
    /// arrived up to `noticeLifetime`, both ends included. A negative age, which
    /// no clock should give, is no notice, and neither is one that is not a
    /// number.
    public static func noticeExcuses(age: TimeInterval?) -> Bool {
        guard let age else { return false }
        return age >= 0 && age <= noticeLifetime
    }

    // MARK: - What stands

    /// What quitting would end, as the prompt names it: how many escalations are
    /// still escalating, how many were missed while the Mac slept and not yet
    /// seen, how many matches those stand for between them, and whether on-call
    /// mode is on.
    ///
    /// The matches are a count of their own because a match can join an
    /// escalation already listed (M5 plan, Ruling 14), and then neither of the
    /// other two counts moves while something the user was not shown has been
    /// added to it: a silent join has sounded nothing for it, and it may be owed
    /// a page. A whole number and no word a notification said (M4 Ruling 17).
    public struct Standing: Equatable, Sendable {
        public var escalating: Int
        public var missed: Int
        /// The matches the escalating and the unseen missed ones stand for
        /// between them, an escalation that no match joined counting as 1.
        public var matches: Int
        public var onCall: Bool

        public init(escalating: Int, missed: Int, matches: Int, onCall: Bool) {
            self.escalating = escalating
            self.missed = missed
            self.matches = matches
            self.onCall = onCall
        }

        /// From the escalations the coordinator lists. It takes the summaries
        /// and not their statuses alone, so that the matches cannot be left out
        /// of what is read, and it is the one way the app makes a `Standing`.
        public init(listed: [EscalationSummary], onCall: Bool) {
            let escalating = listed.filter { $0.status.isEscalating }
            let missed = listed.filter { $0.status.isUnseenMiss }
            self.init(escalating: escalating.count,
                      missed: missed.count,
                      matches: (escalating + missed).reduce(0) { $0 + $1.matchCount },
                      onCall: onCall)
        }
    }

    // MARK: - The words

    /// What the alert says: its bold line, and the lines beneath it.
    public struct Prompt: Equatable, Sendable {
        public let message: String
        public let detail: String

        public init(message: String, detail: String) {
            self.message = message
            self.detail = detail
        }
    }

    public static let cancelTitle = "Cancel"
    public static let quitTitle = "Quit"

    /// The alert's two buttons, in the order they are added. Cancel is first, so
    /// it is the default and a stray Return leaves everything running; Quit is
    /// the second, which is the answer the app reads as yes.
    public static let buttonTitles = [cancelTitle, quitTitle]

    /// The prompt's bold line when on-call mode is all there is to say.
    public static let onCallMessage = "You are on call. Quit anyway?"

    /// What quitting does to on-call mode, said beside the escalation prompt
    /// when there is one and alone when there is not. It does not say that a
    /// saved date keeps anyone covered, since none does while the app is not
    /// running (Ruling 7).
    public static let onCallLine = "On-call mode is on: quitting ends on-call alerting and the faster self-test, and nothing is captured until SignalLadder is running again."

    /// Asked before quitting while anything is listed: quitting ends every
    /// escalation, and a Shortcut not yet run is never run. With only missed
    /// ones listed nothing is left to sound or run, and the detail says what
    /// quitting does lose instead.
    ///
    /// The bold line says how many matches the alerts stand for, as the menu's
    /// line does and in its words (`BurstText.matches`), only when they outnumber
    /// the alerts: "1 alert (3 matches) is still waiting to be acknowledged.
    /// Quit anyway?" A prompt asked again because a match joined an alert it had
    /// already named would otherwise read as the one before it, and with no
    /// match joined it reads as it always did (M5 plan, Ruling 14).
    ///
    /// - Parameters:
    ///   - escalating: listed and still escalating, capped or not.
    ///   - missed: missed while asleep and not yet seen.
    ///   - matches: what those stand for between them, as `Standing.matches`.
    public static func escalationPrompt(escalating: Int, missed: Int, matches: Int) -> Prompt {
        let listed = escalating + missed
        let alerts = listed == 1 ? "1 alert" : "\(listed) alerts"
        let stood = matches > listed ? BurstText.matches(matches).map { " (\($0))" } ?? "" : ""
        let detail = escalating > 0
            ? "Quitting stops every alert still escalating. Nothing more will sound or show, and a Shortcut not yet run will not run."
            : "Nothing is escalating now. Quitting forgets the \(missed == 1 ? "alert" : "alerts") missed while the Mac was asleep, and the menu will not list \(missed == 1 ? "it" : "them") again."
        return Prompt(message: "\(alerts)\(stood) \(listed == 1 ? "is" : "are") still waiting to be acknowledged. Quit anyway?",
                      detail: detail)
    }

    // MARK: - Whether to ask

    /// What a quit is asked, or nil when it is not asked.
    ///
    /// Nil for a log out, a restart or a shut down, however much is listed and
    /// on call or not, and whenever a power-off notice is no older than
    /// `noticeLifetime`, whatever the quit's own reason says. Otherwise the
    /// escalation prompt while anything is listed, one line longer while on
    /// call; the on-call words alone when on call with nothing listed; and nil
    /// when nothing stands that quitting would end.
    public static func prompt(reason: Reason, noticeAge: TimeInterval?,
                              escalating: Int, missed: Int, matches: Int, onCall: Bool) -> Prompt? {
        guard reason == .user, !noticeExcuses(age: noticeAge) else { return nil }
        let anyListed = escalating + missed > 0
        switch (anyListed, onCall) {
        case (false, false):
            return nil
        case (true, false):
            return escalationPrompt(escalating: escalating, missed: missed, matches: matches)
        case (true, true):
            let escalation = escalationPrompt(escalating: escalating, missed: missed, matches: matches)
            return Prompt(message: escalation.message, detail: "\(escalation.detail) \(onCallLine)")
        case (false, true):
            return Prompt(message: onCallMessage, detail: onCallLine)
        }
    }

    /// Whether to ask again after the user answered Quit, because what stands has
    /// grown beyond what the prompt named: more escalating, more missed, more
    /// matches, or on-call mode on where the prompt did not say so. Capture runs
    /// behind the alert (Ruling 22), so an escalation can begin while it is up,
    /// and a match can join one that is listed (Ruling 14), which raises neither
    /// count and has sounded nothing if it joined silently; answering Quit to a
    /// prompt that named fewer would quit either away unseen. An on-call-only
    /// prompt names none, so one escalation is more.
    ///
    /// Fewer, or the same, is not asked again: the user has said what they meant
    /// about everything they were told of. The matches are a total, as the two
    /// counts beside them are, so what was acknowledged while the prompt was up
    /// is taken from what stood and a match that joined another escalation is
    /// added to it, and the two can offset one another.
    public static func askAgain(asked: Standing, now: Standing) -> Bool {
        now.escalating > asked.escalating
            || now.missed > asked.missed
            || now.matches > asked.matches
            || (now.onCall && !asked.onCall)
    }

    /// The whole question, from the first prompt to the answer that settles it:
    /// whether the quit may go ahead.
    ///
    /// It asks what `prompt` says to, shows it through `ask`, which answers true
    /// for Quit, and reads what stands again once the answer is in, as `ask`
    /// returns after the alert has been up for as long as the user took. While
    /// `askAgain` says so it asks again, naming what stands now. Cancel ends it
    /// at once. The notice's age is read afresh each time a prompt is made, so a
    /// log out that begins while the alert is up is not held up by a second one.
    ///
    /// - Parameters:
    ///   - standing: what stands now. Read before the first prompt, and once
    ///     after each answer of Quit; never carried over.
    ///   - noticeAge: the age of the last power-off notice, nil for none, read
    ///     whenever a prompt is made.
    ///   - ask: shows the prompt and says whether the user answered Quit.
    public static func mayQuit(reason: Reason,
                               standing: () -> Standing,
                               noticeAge: () -> TimeInterval?,
                               ask: (Prompt) -> Bool) -> Bool {
        var named = standing()
        while let question = Self.prompt(reason: reason, noticeAge: noticeAge(), escalating: named.escalating,
                                         missed: named.missed, matches: named.matches, onCall: named.onCall) {
            guard ask(question) else { return false }
            let now = standing()
            guard askAgain(asked: named, now: now) else { return true }
            named = now
        }
        return true
    }

    // MARK: - A prompt that is already showing

    /// Whether a prompt that is already on screen is answered, as Quit, because
    /// the system's notice of a power-off has arrived, `age` being how old it is
    /// by the app's clock (zero when it has just arrived). It is when that notice
    /// excuses a prompt, which is when a prompt about to be shown would not be.
    ///
    /// Only a notice answers a prompt. What stands growing, shrinking or ending
    /// while the alert is up does not: `mayQuit` reads that after the user has
    /// answered, and a quit is never made for the user because an alert was
    /// acknowledged behind the prompt. And only the prompt of a quit that is
    /// being asked is answered: the app stops its own alert's session and no
    /// other.
    ///
    /// The answer is Quit and not Cancel because Cancel would leave the app
    /// running, with a log out that AppKit swallowed and nothing was seen to send
    /// again. `mayQuit` reads the notice's age afresh when it would ask again, so
    /// the quit goes ahead with no second prompt, however much more stands by
    /// then. The unsaved-draft sheet that follows is not answered.
    public static func noticeAnswersShowingPrompt(age: TimeInterval?) -> Bool {
        noticeExcuses(age: age)
    }

    // MARK: - What the log says

    /// The one line the app logs for each quit it is asked about: the code it
    /// read, or none, and how old any power-off notice was, or none, and nothing
    /// else. It is how the live check of a real log out and a real restart learns
    /// which signal arrives, and it holds nothing a notification said.
    public static func logLine(code: UInt32?, noticeAge: TimeInterval?) -> String {
        let codeText = code.map { "\(characters(of: $0)) (\($0))" } ?? "none"
        let ageText = noticeAge.map { String(format: "%.1f s old", $0) } ?? "none"
        return "quit reason code: \(codeText); power-off notice: \(ageText)"
    }

    /// A four-character code as the four characters, in quotes, when each is
    /// printable ASCII, and as hexadecimal when not.
    static func characters(of code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return String(format: "0x%08X", code) }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
}
