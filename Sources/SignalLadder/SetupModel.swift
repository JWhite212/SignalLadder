// Sources/SignalLadder/SetupModel.swift
import Combine
import Foundation
import NotificationCore

/// What the Setup Guide's window shows and does (M5 plan, Task 8, Rulings 10, 16, 20 and
/// 22, O13).
///
/// **It decides nothing.** The app target has no tests, so every value the window shows is
/// made by the core from the facts it is handed: each step's state is `SetupPlan.evaluate`,
/// the step shown is `SetupPlan.current` (and none is the summary), what that step says is
/// `SetupText.words(for:facts:time:)` and the summary is `SetupText.summary(_:time:)`,
/// both through the coordinator, which hands them the menu's formatter for a moment. What a
/// press does is the coordinator's, which carries out what the core says, and what comes
/// of the press is what the core says too: whether the window closes
/// (`SetupText.ButtonAction.closesWindow`), what the box's tick is after a read
/// (`SetupPlan.LoginItemBox.tickedAfterReading(wasShown:wasTicked:)`) and which app is
/// picked (`SetupText.listedApp(_:among:)`). What this holds of its own is what the user
/// did in the window: the app they picked in a step's list, the tick they gave the last
/// step's box, and the sentence the last press handed back.
///
/// **The rail is not clickable.** It shows where the user is, and there is no going back
/// or jumping to a step: the step shown is the plan's, so a permission taken away after it
/// was done brings its step back, and a step that is done is passed over.
///
/// **A read is made when asked.** `refresh(from:)` takes the facts the caller gathered
/// (`SetupCoordinator.facts()`), and nothing here reads the system, a clock or the
/// preferences, and nothing starts a timer (Ruling 20). The window calls it when it is
/// shown and when it comes to the front; the app delegate calls it, through the
/// controller, when the menu opens and from `syncInspector`, which every capture and
/// health change takes.
///
/// **A sentence beside a button stands until the next press, a change of step, a different
/// pick or the window's closing.** It is what the last press handed back (the lookup that did
/// not find the app, the rules file that was not opened, a request the system did not enable,
/// a press about an app that could do nothing), shown where the user pressed. A read that
/// leaves the guide on the same step does not take it away, so coming back from System
/// Settings, which reads again, does not lose what it said to look for there. A different
/// pick does, because what it says is about the app that was picked, or about there being
/// none ("Choose an app in the list first" does not stand beside a pick). Closing the window
/// does, because it ends the visit the press was made in, and the app has established
/// nothing of the next: a guide shown again on the same step does not carry a sentence from
/// the last time beside its buttons.
///
/// This file holds no string literal and may hold no word of its own (the baseline list in
/// `ViewLiteralsTests`, and `SetupWiringTests`).
@MainActor
final class SetupModel: ObservableObject {
    private let coordinator: SetupCoordinator

    /// Each step's state, in the plan's order (`SetupPlan.evaluate`): the rail.
    @Published private(set) var readings: [SetupPlan.Reading] = []
    /// The step shown (`SetupPlan.current`), or nil, which is the summary.
    @Published private(set) var current: SetupStep?
    /// Everything the current step says, or nil while the summary is shown.
    @Published private(set) var words: SetupText.StepWords?
    /// The summary, or nil while a step is shown.
    @Published private(set) var summary: SetupText.Summary?
    /// The mute checklist as the facts held it, for the mark beside each app the mute step
    /// lists.
    @Published private(set) var muteChecklist = MuteChecklist()
    /// The tick of the last step's box. It starts ticked when the core says the box is shown,
    /// and is the user's after that.
    @Published var boxTicked = false
    /// What the last press handed back to show beside the button, if it did.
    @Published private(set) var message: String?
    /// Whether a press is being carried out, so that a second cannot start beside it: the
    /// request for notifications waits for the user to answer macOS's own prompt, and Check
    /// again on "Prove it can read" waits for a self-test.
    @Published private(set) var isPressing = false

    /// The app the user picked in each step's list. A step is a key, so a pick made in one
    /// step is not carried into another. A name stays here after its list changes, and is
    /// no pick once it is not listed (`pickedApp`).
    @Published private var picks: [SetupStep: String] = [:]
    private var boxWasShown = false

    /// Closes the window, which the controller sets. The core says which presses call it.
    var closeWindow: () -> Void = {}

    init(coordinator: SetupCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - What is shown

    /// What is read now: every step's state, the step shown or the summary, the words, the
    /// mute checklist and the box's tick. Made from `facts`, which one pass of the window
    /// reads once, so that the rail and the step cannot differ.
    func refresh(from facts: SetupFacts) {
        let step = SetupPlan.current(facts)
        if step != current { message = nil }
        readings = SetupPlan.evaluate(facts)
        current = step
        words = step.map { coordinator.words(for: $0, facts: facts) }
        summary = step == nil ? coordinator.summary(facts) : nil
        muteChecklist = facts.muteChecklist
        let box = SetupPlan.loginItemBox(for: facts.loginItem)
        boxTicked = box.tickedAfterReading(wasShown: boxWasShown, wasTicked: boxTicked)
        boxWasShown = box.isShown
    }

    /// Whether the user has confirmed an app muted, as the checklist holds it.
    func isConfirmed(_ app: String) -> Bool {
        muteChecklist.isConfirmed(app)
    }

    // MARK: - What the user picks and ticks

    /// The app picked in the current step's list, as that list writes it now, or nil when
    /// none is picked or the name picked is no longer listed (`SetupText.listedApp`).
    var pickedApp: String? {
        guard let current else { return nil }
        return SetupText.listedApp(picks[current], among: words?.apps ?? [])
    }

    /// The user picked a row of the current step's list, or none. A sentence beside the buttons
    /// was about the pick before, so a different pick takes it away.
    func pick(_ app: String?) {
        guard let current else { return }
        if picks[current] != app { message = nil }
        picks[current] = app
    }

    /// The window closed, which ends the visit: the sentence a press handed back in it is not
    /// shown when the guide is shown again. The picks stay, and are checked against the list
    /// when they are used (`pickedApp`), as they are after any other read.
    func windowDidClose() {
        message = nil
    }

    // MARK: - What a press does

    /// Carries out one button, and then reads again. The coordinator does what the core says
    /// the button does (a permission, a pane of System Settings, a record, the rule editor),
    /// reads again what the core says it reads again, and hands back the sentence to show
    /// beside the button if the press came to one; the facts are then gathered afresh, so the
    /// window shows what is so after the press and not what it expected. The window closes
    /// when the core says so (`closesWindow`): "Not now" and Finish, whose close is recorded as
    /// every close is.
    ///
    /// The summary follows the last step, and it has one button, Finish, which reads no step
    /// (`SetupPlan.continuing` is asked only of Continue).
    func press(_ action: SetupText.ButtonAction) async {
        guard !isPressing else { return }
        isPressing = true
        let sentence = await coordinator.press(action, on: current ?? .keepItRunning, app: pickedApp,
                                               boxTicked: boxTicked)
        isPressing = false
        message = sentence
        refresh(from: coordinator.facts())
        if action.closesWindow { closeWindow() }
    }
}
