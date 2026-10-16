// Sources/NotificationCore/BlankText.swift
import Foundation

extension String {
    /// Empty once spaces, tabs and line breaks are taken off both ends: a name,
    /// voice or template with nothing in it. One test, so that what the loader
    /// refuses as blank and what the warnings leave to it cannot differ, as
    /// they once did over a line break (2026-10-16).
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
