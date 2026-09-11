// Sources/SignalLadder/CaptureController.swift
import Foundation
import NotificationCore
import NotificationCapture

@MainActor
final class CaptureController {
    private(set) var captureCount = 0

    var onChange: (() -> Void)?
    var onAttach: (() -> Void)?

    private var watcher: AXBannerWatcher?
    private let dedupe = CaptureDeduplicator()
    private let canary: CanaryService

    /// Notifications this app posts — self-tests and health alarms alike —
    /// travel the real pipeline and are indistinguishable from user traffic.
    /// Neither is a notification the user received.
    private let ownAppName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String

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

            if let ownAppName, notification.appNameGuess == ownAppName { return }

            let decision = self.dedupe.admit(notification.rawText, at: notification.timestamp)
            guard !decision.isRepeat else { return }

            self.captureCount += 1
            // Content is intentionally dropped here, not stored.
            self.onChange?()
        }
        watcher.onAttach = { [weak self] in self?.onAttach?() }
        watcher.start()
        self.watcher = watcher
    }

    var isRunning: Bool { watcher != nil }
}
