// Sources/SignalLadder/CaptureController.swift
import Foundation
import NotificationCore
import NotificationCapture

@MainActor
final class CaptureController {
    private(set) var captureCount = 0
    private(set) var lastCaptureAt: Date?

    var onChange: (() -> Void)?

    private var watcher: AXBannerWatcher?
    private let dedupe = CaptureDeduplicator()
    private let canary: CanaryService

    /// False whenever the watcher is absent or detached — either way nothing
    /// can be captured, which the health model needs to know.
    var observerAttached: Bool { watcher?.isAttached ?? false }

    init(canary: CanaryService) {
        self.canary = canary
    }

    func start() {
        let watcher = AXBannerWatcher { [weak self] raw, textChildren in
            guard let self else { return }
            let notification = NotificationFieldExtractor.extract(raw, textChildren: textChildren)

            // The canary is the app talking to itself. It must be recognised
            // BEFORE dedupe and excluded from the count, or self-tests would
            // inflate a number the user reads as real traffic.
            if self.canary.noteCapture(rawText: notification.rawText) { return }

            let decision = self.dedupe.admit(notification.rawText, at: notification.timestamp)
            guard !decision.isRepeat else { return }

            self.captureCount += 1
            self.lastCaptureAt = notification.timestamp
            // Content is intentionally dropped here, not stored.
            self.onChange?()
        }
        watcher.start()
        self.watcher = watcher
    }

    var isRunning: Bool { watcher != nil }
}
