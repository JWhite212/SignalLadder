// Sources/SignalLadder/QuitSignals.swift
import AppKit
import NotificationCore

/// The two signals that say a quit is a log out, a restart or a shut down, read
/// for `QuitPolicy`, which decides from them (M5 plan, Ruling 10).
///
/// This reads, remembers, and says when a notice arrives. What a code means,
/// how long a notice counts, whether to ask and whether a prompt that is
/// showing is answered are `QuitPolicy`'s, in the core, where they are tested.
///
/// - The quit's own reason, a four-character code the system sends with the
///   quit event, read from the event being answered while
///   `applicationShouldTerminate` runs.
/// - The system's notice that a log out, a restart or a shut down was
///   requested, remembered as the awake time it arrived at, so that its age is
///   counted in awake time as an escalation's timers are.
///
/// That either arrives on a real log out is what developers report and has not
/// been seen in this app: the log line `QuitPolicy.logLine` is what the live
/// check reads it from. The two are not independent: a scratch program saw
/// AppKit post the notice itself for a quit event that carries a reason, and
/// none for one that carries none.
@MainActor
final class QuitSignals {
    private let awakeTime: () -> TimeInterval
    private var noticeArrivedAt: TimeInterval?
    private let center: NotificationCenter
    private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - awakeTime: the clock a notice's age is counted on, which stops while
    ///     the Mac sleeps: the escalations' own.
    ///   - center: where the system posts the notice, the workspace's.
    init(awakeTime: @escaping () -> TimeInterval,
         center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.awakeTime = awakeTime
        self.center = center
    }

    /// Starts listening for the system's notice. Called once, at launch, beside
    /// the wake observer; calling it again changes nothing.
    ///
    /// - Parameter onNotice: called on the main queue each time a notice
    ///   arrives, after it is remembered, so that `noticeAge()` is then about zero. It
    ///   is how a quit prompt that is already showing hears of one: that prompt
    ///   holds a log out, which AppKit does not send to the app a second time.
    func observe(onNotice: @escaping @MainActor () -> Void = {}) {
        guard observer == nil else { return }
        observer = center.addObserver(forName: NSWorkspace.willPowerOffNotification,
                                      object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.noticeArrivedAt = self.awakeTime()
                onNotice()
            }
        }
    }

    /// How old the last notice is, in awake time; nil when none has arrived or it
    /// was forgotten.
    func noticeAge() -> TimeInterval? {
        QuitPolicy.noticeAge(arrivedAt: noticeArrivedAt, now: awakeTime())
    }

    /// Forgets the notice, as every quit that is answered with cancel does: a log
    /// out that was aborted must not go on excusing the quits after it.
    func forgetNotice() {
        noticeArrivedAt = nil
    }

    /// The reason the quit being answered now carries, or nil when it carries
    /// none, as a user's does.
    func reasonCode() -> UInt32? {
        Self.reasonCode(in: NSAppleEventManager.shared().currentAppleEvent)
    }

    /// The reason a quit event carries. The SDK's header calls it a parameter of
    /// the event and developers report it as an attribute, so both are read, the
    /// attribute first, and the first that gives a code is the answer. The code is
    /// read as an enumeration code, which a descriptor holding it as a type code
    /// gives as well. Nothing is read from anywhere else, and a code of zero,
    /// which is what a descriptor that cannot be coerced gives, is none.
    static func reasonCode(in event: NSAppleEventDescriptor?) -> UInt32? {
        guard let event else { return nil }
        let keyword = AEKeyword(kAEQuitReason)
        for descriptor in [event.attributeDescriptor(forKeyword: keyword), event.paramDescriptor(forKeyword: keyword)] {
            if let code = descriptor?.enumCodeValue, code != 0 { return code }
        }
        return nil
    }
}
