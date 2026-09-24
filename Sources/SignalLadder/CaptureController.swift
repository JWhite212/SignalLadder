// Sources/SignalLadder/CaptureController.swift
import Foundation
import NotificationCore
import NotificationCapture

/// Connects the Accessibility observer to the capture pipeline, and nothing
/// more.
///
/// Every decision about a banner — self-test, own alarm, repeat, record, rule
/// match — lives in `CapturePipeline`, in the tested core. It used to live in
/// a closure here, in a target with no tests, which is why two reviews in a
/// row named it the riskiest path in the app.
@MainActor
final class CaptureController {
    var onChange: (() -> Void)?
    var onAttach: (() -> Void)?

    let pipeline: CapturePipeline
    private var watcher: AXBannerWatcher?

    var captureCount: Int { pipeline.captureCount }
    var history: CaptureRingBuffer { pipeline.history }

    /// False whenever the watcher is absent or detached — either way nothing
    /// can be captured, which the health model needs to know.
    var observerAttached: Bool { watcher?.isAttached ?? false }

    /// Accessibility events seen, banner or not. Snapshotted either side of a
    /// self-test to tell "the alert was never drawn" from "it was drawn and we
    /// missed it".
    var observerEventCount: Int { watcher?.observerEventCount ?? 0 }

    init(canary: CanaryService) {
        // Notification Centre renders the *display* name in the banner, so
        // that is what `appNameGuess` will hold; `CFBundleName` is only the
        // fallback for a bundle that declares no display name.
        let ownAppName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)

        pipeline = CapturePipeline(ownAppName: ownAppName, isSelfTest: { [canary] raw, children in
            canary.noteCapture(rawText: raw, textChildren: children)
        })
    }

    func start() {
        let watcher = AXBannerWatcher { [weak self] raw, textChildren in
            guard let self else { return }
            switch self.pipeline.process(raw, textChildren: textChildren) {
            case .selfTest, .ownNotification:
                // The app talking to itself changes nothing the user sees.
                return
            case .suppressedRepeat, .recorded:
                self.onChange?()
            }
        }
        watcher.onAttach = { [weak self] in self?.onAttach?() }
        watcher.start()
        self.watcher = watcher
    }

    var isRunning: Bool { watcher != nil }
}
