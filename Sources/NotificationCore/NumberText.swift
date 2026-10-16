// Sources/NotificationCore/NumberText.swift
import Foundation

/// A number as someone writing the rules file by hand would write it.
enum NumberText {
    /// "12", "2.5", "1e+300". A whole number is written without a decimal
    /// point only below 1e15, past which `Int` would trap: a hand-written file
    /// can hold any number, and the editor shows a rule even when the loader
    /// has refused the number in it.
    static func plain(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
