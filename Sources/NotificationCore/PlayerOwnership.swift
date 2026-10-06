// Sources/NotificationCore/PlayerOwnership.swift
import Foundation

extension AlertOutcome {
    /// Whether the alert reached the player, and so is what it now plays: a
    /// sound or a line that started, even when its other half could not. One
    /// that failed or was silent left whatever was playing alone: the player
    /// resolves a sound and finds a voice before it claims the graph, so a
    /// missing one never cuts off the alert before it. A match a snooze held
    /// never went near the player, nor did one that joined an escalation and
    /// stayed silent, and each leaves it as it was.
    public var tookThePlayer: Bool {
        switch self {
        case .played, .spoke, .playedAndSpoke, .playedButNotSpoken, .spokeButNotPlayed: return true
        case .failed, .couldNotSpeak, .silentByRule, .noAlertSet, .snoozed, .joinedEscalation: return false
        }
    }
}

/// Whose alert the player last started: an escalation's, or an ordinary
/// rule's. Acknowledging the last escalation stops the sound only when it is
/// an escalation's (ruling 8): the player cannot tell whose sound it is, and
/// an ordinary rule's alert that began since must not be cut off.
///
/// Decided by what each alert did, not what it asked for. An escalation's
/// repeat that could not play leaves an ordinary alert playing, and
/// acknowledging must not then stop it; an ordinary alert that could not play
/// leaves an escalation's sound playing, and acknowledging must stop that.
public struct PlayerOwnership: Equatable, Sendable {
    public private(set) var escalationOwnsIt = false

    public init() {}

    /// - Parameter byEscalation: a tier 3 or tier 4 alert, or the tier 1 of
    ///   a rule with a ladder.
    public mutating func alertSetOff(_ outcome: AlertOutcome, byEscalation: Bool) {
        if outcome.tookThePlayer { escalationOwnsIt = byEscalation }
    }
}
