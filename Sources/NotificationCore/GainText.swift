// Sources/NotificationCore/GainText.swift
import Foundation

/// How a gain in decibels is written, wherever one is shown: beside the
/// editor's slider and on an Inspector row. One place, so the two cannot
/// disagree about the same number.
enum GainText {
    /// "+6 dB", "−3.5 dB", with a true minus sign, for a gain that is not 0.
    ///
    /// The number is written as it is, never truncated: a rules file edited by
    /// hand can hold 3.5, and the editor showed it as "+3". A whole number is
    /// written without a decimal point only below 1e15, past which `Int` would
    /// trap; such a gain is already refused by the loader ("gainDB … is outside
    /// -40…+12 dB"), but the editor still shows the rule that holds it, and
    /// showing it crashed the app (found on 2026-10-16).
    static func signed(_ gainDB: Double) -> String {
        let magnitude = abs(gainDB)
        let digits = magnitude == magnitude.rounded() && magnitude < 1e15 ? String(Int(magnitude)) : String(magnitude)
        return "\(gainDB > 0 ? "+" : "−")\(digits) dB"
    }
}
