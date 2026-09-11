// Sources/SignalLadder/CaptureController.swift
import Foundation
import NotificationCore
import NotificationCapture

/// Owns the capture pipeline and exposes just enough state for the UI.
///
/// Deliberately does not retain notification content: M2a only needs to prove
/// the app captures at all. The Inspector's ring buffer arrives in a later
/// milestone, and keeping content out until then means there is nothing to
/// accidentally persist.
final class CaptureController {
    private(set) var captureCount = 0
    private(set) var lastCaptureAt: Date?

    /// Called on the main queue whenever the counters change.
    var onChange: (() -> Void)?

    private var watcher: AXBannerWatcher?

    func start() {
        let watcher = AXBannerWatcher { [weak self] raw, textChildren in
            guard let self else { return }
            let notification = NotificationFieldExtractor.extract(raw, textChildren: textChildren)
            self.captureCount += 1
            self.lastCaptureAt = notification.timestamp
            // Content is intentionally dropped here, not stored.
            self.onChange?()
        }
        watcher.start()
        self.watcher = watcher
    }
}
