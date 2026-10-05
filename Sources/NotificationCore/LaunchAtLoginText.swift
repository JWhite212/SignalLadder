// Sources/NotificationCore/LaunchAtLoginText.swift
import Foundation

/// The words about the login item that more than one place says: its buttons, why
/// it is not offered, the menu's one line and what a failed request reports (M5
/// plan, Ruling 18, Ruling 15).
///
/// The Settings window's own labels and the sentence under its switch are in
/// `SettingsText`, which uses these. Each says no more than the app has read: it
/// reads the system's status, where the copy runs from and what the user chose,
/// and nothing about whether the app will start. No line speaks of an entry the
/// user added to Login Items by hand: one reads enabled on macOS 26.7.1 (measured
/// on 2026-10-05; not seen on macOS 14 or 15), so the status is what is shown for
/// it. No line says the login item is on unless the status is enabled.
public enum LaunchAtLoginText {
    // MARK: - The buttons

    /// The finding's button where the item can be registered.
    public static let turnOn = "Turn on Launch at login"
    /// Beside the Settings switch, and the finding's button where the system has
    /// the item switched off: it opens Login Items in System Settings.
    public static let openLoginItems = "Open Login Items…"
    /// Beside the Settings switch where the system has the item switched off.
    public static let switchOnAgain = "Switch on again"

    /// The words on a button. No default arm, so an action added later has to
    /// say its words.
    public static func label(for action: LaunchAtLogin.Action) -> String {
        switch action {
        case .turnOn: return turnOn
        case .switchOnAgain: return switchOnAgain
        case .openLoginItems: return openLoginItems
        }
    }

    // MARK: - Why it is not offered

    /// The fix, where a move is the fix, and the words the plan gives it.
    public static let moveToApplications = "Move SignalLadder to Applications, then open that copy."
    /// Said of a copy macOS runs from a path of its own.
    public static let translocatedReason = "macOS is running this copy of SignalLadder from a temporary location, so Launch at login is not offered."
    /// Said of a copy anywhere else that is not an Applications folder, which
    /// includes a program that is not in an app bundle.
    public static let elsewhereReason = "Launch at login is not offered from where this copy of SignalLadder is running."

    /// Why it is not offered, with the way to fix it. Settings says it under the
    /// switch, and the on-call finding says it where it has no button.
    public static func reason(for why: LaunchAtLogin.Unavailable) -> String {
        switch why {
        case .translocated: return "\(translocatedReason) \(moveToApplications)"
        case .elsewhere: return "\(elsewhereReason) \(moveToApplications)"
        }
    }

    // MARK: - The menu's one line

    /// Under the user's wish, when the system does not show the item enabled. It
    /// is one short line, ends in the title of the window it points to, and does
    /// not say the item is on: the user switched it on, and the system does not
    /// have it enabled. It changes no icon (O12). It is kept well under the width
    /// of the menu's widest line, whose mark is set from another font and which a
    /// release may set a little differently.
    public static let menuLine = "You switched on Launch at login; it is not enabled — see Settings"

    // MARK: - A request that failed

    /// For a registration the system wants approval for.
    public static let needsApproval = "macOS needs your approval before SignalLadder can start at login. You can give it in Login Items, in System Settings."
    /// For a registration the system turned away over the copy's signature.
    public static let unsignedCopy = "macOS did not accept this copy's signature, so Launch at login could not be switched on."
    /// For a registration the system did not refuse, after which the status read
    /// again still does not show the item enabled. It says what was read and no
    /// more: not why, and not that the item is on.
    public static let notEnabled = "macOS still does not report Launch at login as enabled. You can look in Login Items, in System Settings."

    /// What a request says, and nil for one that came to what was asked. An unknown
    /// failure carries the system's code, and no more of the error. Make the
    /// outcome with `LaunchAtLogin.outcomeAfterReading(_:ofRequest:statusAfter:)`, so
    /// that a registration that changed nothing is not silent.
    public static func message(for outcome: LaunchAtLogin.Outcome) -> String? {
        switch outcome {
        case .succeeded: return nil
        case .needsApproval: return needsApproval
        case .unsignedCopy: return unsignedCopy
        case .notEnabled: return notEnabled
        case .failed(.register, let code): return "Launch at login could not be switched on. macOS gave error \(code)."
        case .failed(.unregister, let code): return "Launch at login could not be switched off. macOS gave error \(code)."
        }
    }
}
