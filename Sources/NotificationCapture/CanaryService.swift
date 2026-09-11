// Sources/NotificationCapture/CanaryService.swift
import Foundation
import UserNotifications

/// Proves the pipeline is alive by sending a notification through it.
///
/// Absence of notifications proves nothing — it may simply be quiet. A failed
/// round trip proves something. This is the only positive evidence the app
/// ever has that capture works.
///
/// Main-actor isolated: `pendingMarker` and `continuation` are touched both by
/// the timeout Task and by the capture callback, and a race there would either
/// resume the continuation twice (a crash) or leave it hanging forever.
@MainActor
public final class CanaryService {
    /// Recognisable, and unlikely to occur in real traffic.
    private static let markerPrefix = "SignalLadder canary "

    private var pendingMarker: String?
    private var continuation: CheckedContinuation<Bool, Never>?

    public init() {}

    /// True if a captured notification was ours. Callers MUST consult this and
    /// exclude matches from user-visible counts and history — the canary is
    /// the app talking to itself, not a notification the user received.
    public func noteCapture(rawText: String) -> Bool {
        guard let marker = pendingMarker, rawText.contains(marker) else { return false }
        pendingMarker = nil
        continuation?.resume(returning: true)
        continuation = nil
        return true
    }

    /// Returns nil when no canary ran, which is NOT the same as one that ran
    /// and failed. Reporting false here would drive the health model to
    /// "blind" on the strength of a test that never executed.
    public func run(timeout: TimeInterval = 5.0) async -> Bool? {
        // A concurrent run would overwrite pendingMarker and continuation
        // before the first call's timeout or capture could observe them,
        // orphaning that continuation: never resumed, hanging forever with no
        // crash and no diagnostic.
        guard pendingMarker == nil else { return nil }

        let marker = Self.markerPrefix + UUID().uuidString
        pendingMarker = marker

        let content = UNMutableNotificationContent()
        content.title = "SignalLadder self-test"
        content.body = marker

        let request = UNNotificationRequest(
            identifier: marker,
            content: content,
            trigger: nil   // deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            pendingMarker = nil
            // A post that never happened says nothing about whether capture
            // works. Delivery problems are diagnosed separately.
            return nil
        }

        let captured = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            self.continuation = c
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if self.pendingMarker == marker {
                    self.pendingMarker = nil
                    self.continuation?.resume(returning: false)
                    self.continuation = nil
                }
            }
        }

        // Do not leave our own test notification sitting in Notification Centre.
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [marker])

        return captured
    }
}
