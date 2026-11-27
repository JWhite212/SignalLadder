// Sources/NotificationCore/SoundRenderTickets.swift
import Foundation

/// The numbers renders are asked for with, so that a result that is not the newest is dropped and the window can say
/// it is catching up (sound editor plan, Ruling 6).
///
/// Each request is given the next number. A render runs off the main actor and comes back with the number it was
/// asked for under, and only the newest is taken: while a newer one is under way the window goes on with the last
/// it took, and says so.
public struct SoundRenderTickets: Equatable, Sendable {
    private var requested = 0
    private var finished = 0

    public init() {}

    /// Whether a render has been asked for and its result not yet taken.
    public var isCatchingUp: Bool { requested > finished }

    /// The number to ask the next render under.
    public mutating func request() -> Int {
        requested += 1
        return requested
    }

    /// Whether the result of render `number` is to be taken. It is when it is the newest that was asked for and
    /// has not been taken; one that is older is dropped, however late it comes, and so is one that was never asked
    /// for.
    public mutating func accept(_ number: Int) -> Bool {
        guard number == requested, number > finished else { return false }
        finished = number
        return true
    }

    /// Forgets every render under way: none is taken, and the window is not waiting for one. Numbers are not
    /// reused.
    public mutating func cancelAll() {
        finished = requested
    }
}
