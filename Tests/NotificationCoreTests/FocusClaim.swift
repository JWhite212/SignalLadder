import Foundation

/// What a line that says a Focus is on, or was on, looks like (M5 plan, Ruling 9). A Focus
/// cannot be read, so no line the app says may claim one: the on-call check's lines and the
/// first run's are each held to this pattern, which is written here once so that the two
/// cannot come to differ.
///
/// The pattern is itself tested to match what it forbids (`OnCallCheckTests` and
/// `SetupTextTests`), so that a test built on it can fail, and to let pass the mute
/// walkthrough's sentence "so nothing can be captured while one is on", which is
/// conditional and says no Focus is on.
enum FocusClaim {
    static let pattern = #"(focus|do not disturb)( mode)? (is|was|has been) (currently |now )?(on|active|enabled|switched on|turned on)"#

    private static let expression = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)

    /// Whether `line` claims that a Focus is on or was on.
    static func isMade(by line: String) -> Bool {
        expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }
}
