// Sources/NotificationCore/MenuRebuildGate.swift
import Foundation

/// When the status menu's items may be rebuilt (M5 plan, Ruling 22).
///
/// Capture runs while the menu is open, and so does every timer the app owns,
/// and each change they make ends in a rebuild that empties the one `NSMenu`
/// and fills it again. A banner that arrives as the user reaches for Snooze,
/// On Call or Quit could put an Acknowledge section above them and move every
/// row under the pointer, so that the click lands on Acknowledge All, which
/// silences a page the user has not seen, or on Quit. So the items are not
/// rebuilt while the menu is open: that is owed, and made once when it closes.
///
/// What is held is the items and nothing else. The Inspector's sync, the
/// pulse of the status icon and the icon itself are not under the pointer, and
/// a page that arrives mid-menu must show on the icon and the panel at once, so
/// every request answers with those three, whether the menu is open or not.
///
/// A value with no clock and no menu, so that every state is tested. The app
/// asks it before each rebuild and carries out what it answers, in order, and
/// tells it when the menu opens and closes.
public struct MenuRebuildGate: Equatable, Sendable {
    /// One thing to do when the menu changes, in the order to do it.
    public enum Step: Equatable, Sendable {
        case syncInspector
        case updatePulse
        case refreshGlyph
        /// Empty the menu and fill it again.
        case rebuildItems
    }

    /// What every change does, whether the menu is open or not: none of the
    /// three is under the pointer.
    public static let everyChange: [Step] = [.syncInspector, .updatePulse, .refreshGlyph]

    /// Whether the menu is open, as the app last told the gate.
    public private(set) var isOpen = false

    /// Set by a request made while the menu was open and cleared by the close
    /// that answers it, so that however many were asked for, one is made.
    private var rebuildOwed = false

    public init() {}

    /// Asked before each rebuild of the menu: what to do now. The three that
    /// run on every change come first, then the items if the menu is closed.
    /// While it is open the items are left out and one is owed.
    public mutating func request() -> [Step] {
        guard isOpen else { return Self.everyChange + [.rebuildItems] }
        rebuildOwed = true
        return Self.everyChange
    }

    /// The menu is open. Telling the gate again changes nothing.
    public mutating func menuOpened() {
        isOpen = true
    }

    /// The menu is closed: the items to rebuild if any request was held while
    /// it was open, once however many there were, and nothing otherwise. The
    /// three that run on every change already ran at each request.
    ///
    /// The app also says so when the menu is about to open, so that the
    /// rebuild it makes then goes ahead, and the rebuild owed from a menu whose
    /// close was never reported is the one it makes: the answer is not needed.
    @discardableResult
    public mutating func menuClosed() -> [Step] {
        isOpen = false
        guard rebuildOwed else { return [] }
        rebuildOwed = false
        return [.rebuildItems]
    }
}
