// Sources/NotificationCore/RawCapture.swift
import Foundation

/// One banner observed at the Accessibility boundary, before any parsing.
public struct RawCapture: Equatable, Sendable {
    public let timestamp: Date
    public let rawText: String
    public let subrole: String

    public init(timestamp: Date, rawText: String, subrole: String) {
        self.timestamp = timestamp
        self.rawText = rawText
        self.subrole = subrole
    }
}
