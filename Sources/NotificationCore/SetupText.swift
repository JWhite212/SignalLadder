// Sources/NotificationCore/SetupText.swift
import Foundation

/// The words of the first run (M5 plan, Ruling 18, Task 7).
///
/// This holds only the menu's nudge line so far. Every step's title, reason and
/// button, and the summary, are the next commit's, and are added here.
///
/// Each line says no more than the app has established, and none holds what a
/// notification said or a rule's name. The nudge names a step, and never an app.
public enum SetupText {
    // MARK: - The menu's nudge

    /// How the menu's setup line begins, and what the harness looks for to know
    /// that a Mac's menu carries none (Task 9). It stays on one line as
    /// `public static let NAME = "TEXT"`, the shape the harness reads (Ruling 18).
    public static let nudgeStem = "Setup is not finished"

    /// What the nudge calls a step that is still to do. Only the three steps the
    /// nudge counts have a word (`SetupPlan.requiredSteps`), so another step is
    /// said as nothing. The words are nouns, so that a list of them reads on one
    /// line, and none says why the step is outstanding, since the nudge has read no
    /// more than that it is.
    static func nudgeWord(for step: SetupStep) -> String? {
        switch step {
        case .accessibility: return "Accessibility"
        case .notifications: return "Notifications"
        case .firstRule: return "a first rule"
        case .howItWorks, .proveItCanRead, .muteSourceApp, .focus, .keepItRunning: return nil
        }
    }

    /// The menu's one line while setup is not finished, or nil when none of the
    /// steps it counts is outstanding.
    ///
    /// `outstanding` is what the plan has read to be so: a step whose state is not
    /// known yet is not in it (`SetupPlan.nudgeLine(_:guideIsOpen:)`), so the line
    /// says which step is outstanding only as far as that was read. The steps are
    /// said in the plan's order whatever order they come in, once each, and a step
    /// the nudge does not count is left out. The line never mentions health: the
    /// health line, the alarm and the icon say that, and a nudge that did would show
    /// at every launch, when health reads "Checking…" (Ruling 16).
    public static func nudgeLine(outstanding: [SetupStep]) -> String? {
        let words = SetupStep.allCases.filter { outstanding.contains($0) }.compactMap { nudgeWord(for: $0) }
        guard !words.isEmpty else { return nil }
        return "\(nudgeStem) — still to do: \(MuteWalkthroughText.list(words))"
    }
}
