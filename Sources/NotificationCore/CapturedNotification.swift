// Sources/NotificationCore/CapturedNotification.swift
import Foundation

/// A parsed notification. `appNameGuess` is named for what it is: the result
/// of a lossy heuristic over an undocumented format.
public struct CapturedNotification: Equatable, Sendable {
    public let timestamp: Date
    public let appNameGuess: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let rawText: String
    public let subrole: String

    public init(timestamp: Date,
                appNameGuess: String,
                title: String,
                subtitle: String,
                body: String,
                rawText: String,
                subrole: String) {
        self.timestamp = timestamp
        self.appNameGuess = appNameGuess
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.rawText = rawText
        self.subrole = subrole
    }
}
