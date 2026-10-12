// Sources/SignalLadder/ShortcutFields.swift
import NotificationCore
import ShortcutRunner

extension ShortcutRunner.Fields {
    /// What a Shortcut is given of a notification: its app, title, subtitle and
    /// body, and never its raw text, its time or its subrole.
    ///
    /// The one place those four are chosen, so that a run set off by an
    /// escalation and a run the editor tests are given the same fields and
    /// cannot drift apart.
    init(_ notification: CapturedNotification) {
        self.init(appNameGuess: notification.appNameGuess, title: notification.title,
                  subtitle: notification.subtitle, body: notification.body)
    }
}
