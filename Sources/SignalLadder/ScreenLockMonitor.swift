// Sources/SignalLadder/ScreenLockMonitor.swift
import CoreGraphics
import Foundation

/// Whether the screen is locked, for the rules that ask.
///
/// macOS says when the screen locks and unlocks, and those two notices are
/// kept here as they arrive. Before the first of them, the answer is what the
/// login session reported once at launch, and nil if it reported nothing: a
/// lock nobody read is not recorded as unlocked. It reads nothing else about
/// the session and sends nothing anywhere.
@MainActor
final class ScreenLockMonitor {
    private(set) var isLocked: Bool?
    private var observers: [NSObjectProtocol] = []

    init() {
        isLocked = Self.readSession()
        let center = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isLocked = locked }
            })
        }
    }

    deinit {
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    /// The session's own word on the lock, or nil when there is no session to
    /// ask. The key is absent while the screen is unlocked.
    private static func readSession() -> Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
