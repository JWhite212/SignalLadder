// Sources/NotificationCore/ShortcutTest.swift
import Foundation

/// What the editor's Test Shortcut button decides and says, as pure
/// functions, so the view only shows it.
///
/// The button really runs the Shortcut, so it is not offered when it could
/// run one that was not meant, and its result is never shown beside a name
/// it was not for (M5 plan, ruling 5 and ruling 6).
public enum ShortcutTest {
    /// How a test ended, with the name it was for.
    public struct Report: Equatable, Sendable {
        public enum Outcome: Equatable, Sendable {
            /// The Shortcut was started. Never "worked": one that fails after
            /// it starts is still one that started.
            case started
            /// It did not start, for the runner's own reason.
            case failed(String)
        }

        /// The name the test ran, exactly as it was given.
        public let name: String
        public let outcome: Outcome

        public init(name: String, outcome: Outcome) {
            self.name = name
            self.outcome = outcome
        }

        /// Whether the Shortcut started, which is when a held "Shortcut did
        /// not run" of the same name can go.
        public var started: Bool { outcome == .started }

        /// The result as it reads beside the button: what started, or the
        /// runner's own reason as it is.
        public var text: String {
            switch outcome {
            case .started: return EditorText.shortcutTestStarted(name)
            case .failed(let reason): return reason
            }
        }
    }

    /// Whether the button can be pressed: not while a test is pending, so a
    /// double click cannot page twice, and not while the name is blank, since
    /// nothing can be run by no name.
    public static func canRun(name: String, pending: Bool) -> Bool {
        !pending && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The result to show beside a name field: only one that was for exactly
    /// the name the field holds now. A different capital or a stray space is
    /// another name, as it is to the Shortcuts app, so a result for one is no
    /// word about the other.
    public static func shown(_ report: Report?, forField name: String) -> Report? {
        guard let report, report.name == name else { return nil }
        return report
    }
}
