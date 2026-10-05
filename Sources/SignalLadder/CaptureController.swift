// Sources/SignalLadder/CaptureController.swift
import Foundation
import NotificationCore
import NotificationCapture

/// Connects the Accessibility observer to the capture pipeline, and nothing
/// more.
///
/// Every decision about a banner — self-test, own alarm, repeat, record, rule
/// match, alert — lives in `CapturePipeline`, in the tested core. It used to live in
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

    /// - Parameters:
    ///   - beginEscalation: starts a matched rule's ladder. The pipeline is
    ///     built here, so this is where it is handed over.
    ///   - holdForSnooze: whether a snooze holds a live match of a rule, which is
    ///     the snooze controller's own verdict and which it counts (M5 plan,
    ///     Task 4, Ruling 13). Handed to the pipeline as it is given, with no
    ///     default, so nothing can be built that forgets to connect it.
    init(canary: CanaryService, playSound: @escaping CapturePipeline.SoundPlayer,
         speak: @escaping CapturePipeline.SpeechPlayer,
         playAndSpeak: @escaping CapturePipeline.SoundAndSpeechPlayer,
         beginEscalation: @escaping (Rule, CapturedNotification, UUID) -> Void,
         holdForSnooze: @escaping (Rule) -> Bool) {
        // Notification Centre renders the *display* name in the banner, so
        // that is what `appNameGuess` will hold; `CFBundleName` is only the
        // fallback for a bundle that declares no display name.
        let ownAppName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)

        pipeline = CapturePipeline(ownAppName: ownAppName, isSelfTest: { [canary] raw, children in
            canary.noteCapture(rawText: raw, textChildren: children)
        }, playSound: playSound, speak: speak, playAndSpeak: playAndSpeak, beginEscalation: beginEscalation,
           holdForSnooze: holdForSnooze)
    }

    /// Where a row's escalation has got to, from the coordinator. Takes the
    /// same path to the menu, the glyph and the Inspector that a capture does,
    /// so they follow a tier firing, a cap, an acknowledgement, a sleep or a
    /// Shortcut's late report.
    func recordEscalation(entryID: UUID, _ summary: EscalationSummary) {
        pipeline.recordEscalation(entryID: entryID, summary, at: Date())
        onChange?()
    }

    /// A test of a Shortcut from the editor started it. Takes the same path to
    /// the menu and the glyph that a launch from an escalation does, so a held
    /// failure of that Shortcut goes from both at once.
    func shortcutStartedInTest(named name: String) {
        pipeline.shortcutStartedInTest(named: name)
        onChange?()
    }

    /// Nothing more will be recorded for this row's escalation.
    func escalationRetired(entryID: UUID) {
        pipeline.escalationRetired(entryID: entryID)
    }

    func start() {
        let watcher = AXBannerWatcher { [weak self] raw, textChildren in
            guard let self else { return }
            if self.pipeline.process(raw, textChildren: textChildren).changesWhatTheUserSees {
                self.onChange?()
            }
        }
        watcher.onAttach = { [weak self] in self?.onAttach?() }
        watcher.start()
        self.watcher = watcher
    }

    var isRunning: Bool { watcher != nil }
}
