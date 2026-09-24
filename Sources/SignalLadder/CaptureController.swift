// Sources/SignalLadder/CaptureController.swift
import Foundation
import NotificationCore
import NotificationCapture

@MainActor
final class CaptureController {
    private(set) var captureCount = 0

    /// Everything captured, newest first, for the Inspector. In memory only.
    let history = CaptureRingBuffer()

    var onChange: (() -> Void)?
    var onAttach: (() -> Void)?

    private var watcher: AXBannerWatcher?
    private let dedupe = CaptureDeduplicator()
    private let canary: CanaryService
    private var pendingSuppressedRepeats = 0

    /// Notifications this app posts — self-tests and health alarms alike —
    /// travel the real pipeline and are indistinguishable from user traffic.
    /// Neither is a notification the user received.
    ///
    /// Notification Centre renders the *display* name in the banner, so that is
    /// what `appNameGuess` will hold; `CFBundleName` is only the fallback for a
    /// bundle that declares no display name.
    private let ownAppName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)

    /// False whenever the watcher is absent or detached — either way nothing
    /// can be captured, which the health model needs to know.
    var observerAttached: Bool { watcher?.isAttached ?? false }

    /// Accessibility events seen, banner or not. Snapshotted either side of a
    /// self-test to tell "the alert was never drawn" from "it was drawn and we
    /// missed it".
    var observerEventCount: Int { watcher?.observerEventCount ?? 0 }

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
            // Both text sources are offered: the description the marker was
            // historically matched against is allowed to be empty, so a
            // description-only check can miss a canary that was captured.
            if self.canary.noteCapture(rawText: notification.rawText,
                                       textChildren: textChildren) { return }

            // Backstop for everything this app posts — alarms, which carry no
            // marker, and a self-test whose marker match failed for any reason.
            // Name alone would be too loose a net: it would silently drop a
            // real notification from any app sharing our name. SelfNotification
            // requires our wording as well.
            if SelfNotification.isOwnNotification(notification, ownAppName: ownAppName) { return }

            let decision = self.dedupe.admit(notification.rawText, at: notification.timestamp)
            if decision.isRepeat {
                // Recorded on the row it duplicates. Dedupe keys on content
                // within a short window, which cannot tell one banner re-firing
                // during animation from two genuinely distinct alerts carrying
                // identical text — and a noisy channel produces exactly the
                // latter. Showing the count is how we find out which is
                // happening, since M1 recorded this path has never been
                // observed firing in the wild.
                //
                // The fallback exists for a case that should not occur: the
                // duplicated row already evicted, which needs ~50 distinct
                // captures inside dedupe's 1.5s window. Holding the count for
                // the next admission is worse than attributing it correctly —
                // it can land on an unrelated app's notification — but it is
                // better than discarding evidence silently.
                if !self.history.noteSuppressedRepeat(matching: notification.rawText) {
                    self.pendingSuppressedRepeats += 1
                }
                self.onChange?()
                return
            }

            self.captureCount += 1
            self.history.record(notification, suppressedRepeatCount: self.pendingSuppressedRepeats)
            self.pendingSuppressedRepeats = 0
            self.onChange?()
        }
        watcher.onAttach = { [weak self] in self?.onAttach?() }
        watcher.start()
        self.watcher = watcher
    }

    var isRunning: Bool { watcher != nil }
}
