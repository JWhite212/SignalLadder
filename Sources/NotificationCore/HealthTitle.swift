import Foundation

/// The health line at the top of the menu, as a pure function.
///
/// Moved out of AppDelegate when it had to start saying how old its evidence
/// is. "Working — verified" with no age read, on 2026-09-25, as a statement
/// about the present while capture had been blind since 80 seconds after the
/// self-test it rested on.
public enum HealthTitle {
    // The health line's wordings, each declared on one line as `public static let
    // NAME = "TEXT"`, the shape the harness reads (M5 plan, Ruling 18, Task 9). The
    // harness finds the health line among the menu's lines by what it says, so the
    // words it looks for are these, and `HarnessConstantsTests` holds the function
    // below to them.

    /// What a verified health line begins with, whatever follows: "Working —
    /// verified 3 min ago".
    public static let verifiedStem = "Working — verified"
    /// The whole line before any self-test has succeeded.
    public static let checkingLine = "Checking…"
    /// What a stale health line begins with, whatever follows: "Unverified — last
    /// verified 34 min ago".
    public static let unverifiedStem = "Unverified"
    /// The whole line of a health that is degraded.
    public static let cannotVerifyLine = "Cannot verify itself"
    /// The whole line of a health that is blind.
    public static let notCapturingLine = "NOT capturing notifications"

    /// - Parameter secondsSinceLastSuccessfulCanary: nil if no self-test has
    ///   ever succeeded.
    public static func text(for health: CaptureHealth,
                            secondsSinceLastSuccessfulCanary age: TimeInterval?) -> String {
        switch health {
        case .verified:
            guard let age else { return verifiedStem }
            return "\(verifiedStem) \(ago(age))"
        case .unknown:
            // Unknown after a success means the evidence went stale. Saying
            // "Checking…" there would suggest a check is under way; none is.
            guard let age else { return checkingLine }
            return "\(unverifiedStem) — last verified \(ago(age))"
        case .degraded:
            return cannotVerifyLine
        case .blind:
            return notCapturingLine
        }
    }

    /// "just now", "3 min ago", "1 hr 5 min ago", "2 hr ago".
    public static func ago(_ seconds: TimeInterval) -> String {
        // A clock set backwards must not produce "-3 min ago".
        let minutes = Int(max(0, seconds)) / 60
        if minutes == 0 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) hr ago" : "\(hours) hr \(rest) min ago"
    }
}
