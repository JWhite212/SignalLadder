// Sources/NotificationCore/WindowTitles.swift
import Foundation

/// The title of each window the app opens, in one place (M5 plan, Ruling 18).
///
/// The app's window controllers show these, and `Scripts/verify-live.sh` reads
/// them out of this file's text, so a title cannot change in the app and be
/// left behind in the harness. Each is declared on one line, as
/// `public static let NAME = "TEXT"`: that is the shape the harness's helper
/// reads, and `HarnessConstantsTests` holds every declaration here to it. Every
/// title begins with the app's name, and no two are alike.
public enum WindowTitles {
    public static let inspector = "SignalLadder Inspector"
    public static let ruleEditor = "SignalLadder Rules"
    public static let onCallCheck = "SignalLadder On-Call Check"
}
