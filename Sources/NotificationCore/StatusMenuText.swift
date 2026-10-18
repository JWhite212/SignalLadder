// Sources/NotificationCore/StatusMenuText.swift
import Foundation

/// The status menu's titles that no feature's text enum holds (M5 plan, Ruling 18,
/// Task 9): the capture count's line, and the items that open the Inspector and the rule
/// editor and reload the rules.
///
/// `Scripts/verify-live.sh` looks for the first and chooses the other three, so they
/// are read from this file by the harness's one helper and typed nowhere else. The app
/// target shows them and types no word of its own: `AppDelegate` builds each item from
/// the constant here, which changes no word the menu shows. Each is declared on one line
/// as `public static let NAME = "TEXT"`, the shape the helper reads, and
/// `HarnessConstantsTests` holds every declaration to it.
public enum StatusMenuText {
    /// What the capture count's line begins with, whatever follows: "Captured 212
    /// notifications". The harness reads the count out of the line that has it.
    public static let capturedStem = "Captured"

    /// The item that opens the Inspector.
    public static let showInspectorTitle = "Show Inspector…"

    /// The item that opens the rule editor.
    public static let editRulesTitle = "Edit Rules…"

    /// The item that reads the rules file again, which the app does not watch.
    public static let reloadRulesTitle = "Reload Rules"

    /// The capture count's line: "Captured 1 notification", "Captured 212 notifications".
    /// It counts what the pipeline has seen and says nothing of what any of it said.
    public static func capturedLine(count: Int) -> String {
        "\(capturedStem) \(count) notification\(count == 1 ? "" : "s")"
    }

    /// The line about how many of the captures kept the rules in effect now match:
    /// "Current rules match 2 of the last 50". nil with no rule in effect or nothing
    /// captured, where there is nothing to count. Typed in `AppDelegate` until #97.
    public static func ruleMatchLine(matched: Int, of captured: Int, rulesInEffect: Int) -> String? {
        guard rulesInEffect > 0, captured > 0 else { return nil }
        return "Current rules match \(matched) of the last \(captured)"
    }
}
