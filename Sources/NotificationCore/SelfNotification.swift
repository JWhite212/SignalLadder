// Sources/NotificationCore/SelfNotification.swift
import Foundation

/// The notifications this app posts about itself, and the test for recognising
/// one once it comes back through capture.
///
/// The app's own alarms travel the same pipeline as real traffic, so they must
/// be excluded from the capture count or the app inflates a number the user
/// reads as notifications they received.
///
/// The exclusion is deliberately narrow. Matching on app name alone would be a
/// silent-loss path: another app whose banner carries the same name would have
/// its genuine notifications dropped without trace, which is the exact failure
/// this product exists to prevent. Requiring the title too means a banner must
/// carry both our name and our wording to be discarded. An inflated count is
/// visible and correctable; a dropped notification is neither.
///
/// The titles live here, beside the test that matches them, so the code that
/// posts an alarm and the code that recognises one cannot drift apart.
///
/// The self-test title is included even though the canary is normally excluded
/// earlier by its per-run marker. That earlier exclusion is not guaranteed: the
/// marker is matched against captured text, and any failure of that match — a
/// missing description, a timed-out attribute read, a timeout that has already
/// cleared the pending marker — drops the canary's own banner straight into the
/// user-visible count. Relying on the marker alone assumed the marker always
/// matches, which is precisely the assumption a failing self-test violates.
public enum SelfNotification {
    public static let blindTitle = "SignalLadder is not capturing"
    public static let degradedTitle = "SignalLadder cannot verify itself"
    public static let selfTestTitle = "SignalLadder self-test"

    /// The health banner's body when its health has no cause to give one, as
    /// `.blind([])` has none. It says nothing about what the app read: no cause,
    /// no app name and nothing a notification said (M5 plan, Ruling 18).
    public static let fallbackBody = "Open the menu for details."

    private static let ownTitles: Set<String> = [blindTitle, degradedTitle, selfTestTitle]

    /// True when this banner is one the app posted about itself — an alarm or a
    /// self-test.
    ///
    /// `ownAppName` is nil when the bundle declares no name at all — an
    /// unbundled or malformed build. Excluding nothing is the safe failure.
    public static func isOwnNotification(_ notification: CapturedNotification,
                                         ownAppName: String?) -> Bool {
        guard let ownAppName, !ownAppName.isEmpty else { return false }
        guard notification.appNameGuess == ownAppName else { return false }
        return ownTitles.contains(notification.title)
    }
}
