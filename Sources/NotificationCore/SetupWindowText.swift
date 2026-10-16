// Sources/NotificationCore/SetupWindowText.swift
import Foundation

extension SetupText {
    // MARK: - The window's own labels

    /// A label the guide's window shows that no step's words hold (M5 plan, Task 8, Ruling
    /// 18): the rail, what each state is called and how it is read aloud, the window's own
    /// button, the headings over the two lists of apps, what VoiceOver reads for a row in
    /// them, the label of the practice line's selectable text, the two sentences that
    /// stand where a modal alert used to (Ruling 22) and the two that stand beside a button
    /// whose press came to nothing. A step's own words
    /// (`words(for:facts:time:)`) and the summary are not here: they are made once, and the
    /// window shows what they hold.
    public struct WindowLabel: Equatable, Sendable {
        /// What a label is, so that a test can hold each kind to what it must be.
        public enum Kind: Equatable, Sendable {
            /// A heading over a list.
            case heading
            /// A short caption beside or above something.
            case caption
            /// The label of a button, shown or spoken. It carries its verb.
            case button
            /// What VoiceOver reads for something that is not a button.
            case description
            /// A sentence shown beside a button after a press that came to something.
            case message
        }

        public let kind: Kind
        /// What the window's source writes to show it: `SetupText.railHeading` for a
        /// constant, `SetupText.stateLabel(` for a function. A scan finds a label nobody
        /// shows by looking for this text, and several labels share a reference when one
        /// function makes them. The view writes every label that is not a message. A
        /// message is a sentence the coordinator hands back from a press, for the view to
        /// show beside the button (`SetupCoordinator.press`), so the coordinator writes its
        /// reference, as the name of the function and without a parenthesis, since it may
        /// hand the function over as it is.
        public let reference: String
        /// What it says. For a label made from an app's name it is the function applied to
        /// `sampleApp`, and for the message about the rules file the fixed part of the
        /// sentence.
        public let text: String
    }

    /// Stands for an app's name wherever `windowLabels` has to show a label made from one.
    /// A noun phrase and not a name, so that no label in the list names an app.
    public static let sampleApp = "the app"

    // MARK: The rail

    /// Heads the rail of steps, and is what VoiceOver calls the list.
    public static let railHeading = "Setup steps"

    /// "Step 3 of 8", which the window shows above a step's title. The steps are counted
    /// from one, as a person counts them, and not from the plan's zero, so Notifications,
    /// the plan's step 2, reads "Step 3 of 8" (see `SetupStep`).
    public static func stepPosition(of step: SetupStep) -> String {
        let number = (SetupStep.allCases.firstIndex(of: step) ?? 0) + 1
        return "Step \(number) of \(SetupStep.allCases.count)"
    }

    /// What VoiceOver reads for a row of the rail: its place and its title. The row's state
    /// is read beside it as its value (`stateDescription(for:)`), because the icon that shows
    /// it is not read.
    public static func railRowLabel(for step: SetupStep) -> String {
        "\(stepPosition(of: step)): \(title(for: step))"
    }

    // MARK: What a state is called

    /// The short label of each state, shown beside a step's name in the rail so that a state
    /// is not told by colour or by an icon alone. None says more than the state does.
    ///
    /// **A step that is done on the user's word says so in its label.** The step shown large
    /// is never a done one (`SetupPlan.current` passes over every step that is done), so the
    /// rail is where a sighted user sees a step that is done, and a green tick and "Done" on
    /// the muting that only the user can vouch for would read as something SignalLadder had
    /// checked. A step done on a fact the app read is "Done" and no more; what each rests on
    /// is said in full to VoiceOver (`stateDescription(for:)`) and in the summary, which keeps
    /// what was read apart from the user's word.
    public static let stateDone = "Done"
    public static let stateDoneYourWord = "Done, your word"
    public static let stateOutstanding = "To do"
    public static let stateUnknown = "Not known yet"
    /// Only the mute step is ever this, and for two reasons: it waits for the first rule, or
    /// the rule is made and SignalLadder has no app to name. In the second the user still
    /// has the sound to turn off, so the label does not say there is nothing to do.
    public static let stateNotApplicable = "Not yet"
    public static let stateBlocked = "Blocked"
    public static let stateSkipped = "Skipped"

    /// The short label of a state. No `switch` here has a default arm, so a state added
    /// later has to be named.
    public static func stateLabel(for state: SetupPlan.State) -> String {
        switch state {
        case .done(.fact): return stateDone
        case .done(.yourWord): return stateDoneYourWord
        case .outstanding: return stateOutstanding
        case .unknown: return stateUnknown
        case .notApplicable: return stateNotApplicable
        case .blocked: return stateBlocked
        case .skipped: return stateSkipped
        }
    }

    /// What VoiceOver reads for a state, in place of its icon. A step that is done says what
    /// it rests on, in the words the step uses, so that a fact the app read is not heard as
    /// the user's word or the other way about. A step that was skipped or is blocked is said
    /// to be not done.
    public static func stateDescription(for state: SetupPlan.State) -> String {
        switch state {
        case .done(.fact): return "Done. \(basisRead)"
        case .done(.yourWord): return "Done. \(basisYourWord)"
        case .outstanding: return "Still to do"
        case .unknown: return "Not known yet: SignalLadder has not read this"
        case .notApplicable: return "Not available yet"
        case .blocked: return "Blocked, so not done"
        case .skipped: return "Skipped, so not done"
        }
    }

    /// One of each state, for listing every label and for the tests: both bases of a step
    /// that is done, and a blocked step with the one reason there is.
    static let everyState: [SetupPlan.State] = [
        .done(.fact), .done(.yourWord), .outstanding, .unknown, .notApplicable,
        .blocked(.rulesFileReadOnly(.newerVersion(0))), .skipped,
    ]

    /// The symbol drawn beside a step in the rail for its state. It is the core's, as the
    /// check window's are (`OnCallText.urgentSymbol`), so that the window decides nothing
    /// about what a tick means (Ruling 10): **a tick is drawn for a step that is done and
    /// for nothing else.** A step that was skipped, is blocked, is not known yet or has
    /// nothing to do yet never wears one, and each of the six states has a symbol of its
    /// own. The two bases of a done step share it, since what it rests on is said in words
    /// beside it (`stateLabel(for:)`, `stateDescription(for:)`).
    /// A symbol is only a second way to tell a state: the label beside it says it in words
    /// (`stateLabel(for:)`), and the window hides the symbol from VoiceOver.
    ///
    /// Each name is one the system knows (a test asks it), and each is older than the macOS
    /// 14 floor. No `switch` here has a default arm, so a state added later has to be
    /// drawn.
    public static func stateSymbol(for state: SetupPlan.State) -> String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .outstanding: return "circle"
        case .unknown: return "questionmark.circle"
        case .notApplicable: return "minus.circle"
        case .blocked: return "exclamationmark.triangle.fill"
        case .skipped: return "arrow.right.circle"
        }
    }

    // MARK: The window's own button

    /// Whether the window shows its own button, "Not now", while it shows `step`, where nil
    /// is the summary, as `SetupPlan.current(_:)` answers it when no step has anything left
    /// for the user. **It is shown on every step and not on the summary**, where Finish is:
    /// the summary is the end of the guide and has its own way out, and a step is a place
    /// the user may want to leave and come back to (O13). Closing the window is the same
    /// act and is recorded in the same way, so the user who closes it and the user who
    /// presses the button leave the same record. No `switch` here has a default arm, so a
    /// step added later has to say.
    public static func windowShowsNotNow(on step: SetupStep?) -> Bool {
        guard let step else { return false }
        switch step {
        case .howItWorks, .accessibility, .notifications, .proveItCanRead, .firstRule, .muteSourceApp, .focus,
             .keepItRunning:
            return true
        }
    }

    // MARK: The lists of apps

    /// The heading over the apps the first rule's step offers, which are the apps banners
    /// were read from, and over the apps the mute step lists; nil for every other step,
    /// which lists none. The names are the user's to choose from and are in the rows, and
    /// not in these headings.
    public static func appListHeading(for step: SetupStep) -> String? {
        switch step {
        case .firstRule: return "Apps SignalLadder has read banners from"
        case .muteSourceApp: return "Apps to mute"
        case .howItWorks, .accessibility, .notifications, .proveItCanRead, .focus, .keepItRunning: return nil
        }
    }

    /// What VoiceOver reads for a row in the first rule's list of apps, which the user picks
    /// from and which "Make a Rule from This…" then acts on. The name is the one the row
    /// shows, and the label says what picking the row is for.
    public static func ruleAppRowLabel(for app: String) -> String {
        "\(app), an app to make a rule from"
    }

    /// What VoiceOver reads for a row in the mute step's list of apps, which the user ticks
    /// by "I've Turned Its Sound Off": the menu's own words for an app and whether the user
    /// has confirmed it, which say "not confirmed" and not that it is not muted. The tick is
    /// the user's word.
    public static func muteAppRowLabel(for app: String, confirmed: Bool) -> String {
        MuteWalkthroughText.appItem(app, confirmed: confirmed)
    }

    /// A row of a step's list of apps, as the window shows it.
    public struct AppRow: Equatable, Sendable {
        /// What the row shows.
        public let text: String
        /// What VoiceOver reads for it.
        public let voiceOver: String
    }

    /// The row a step's list has for an app (M5 plan, Task 8, Ruling 10): which of the two
    /// wordings a row has is by the step, so the choice is made here and tested, and the
    /// window shows what it is handed and names no step.
    ///
    /// - **The first rule's list** shows the name alone, and VoiceOver says what picking it is
    ///   for (`ruleAppRowLabel(for:)`). Whether the user has confirmed it muted is not its
    ///   business.
    /// - **The mute step's list** shows the menu's own words for an app and whether the user
    ///   has said it is muted, and VoiceOver reads the same (`muteAppRowLabel(for:confirmed:)`).
    /// - **A step that lists no apps** (`appListHeading(for:)` is nil) has no row to word, and
    ///   would show the name alone.
    ///
    /// No `switch` here has a default arm, so a step added later has to say what its rows read.
    ///
    /// - Parameter confirmed: whether the user has confirmed the app muted, which the mute
    ///   step's row says and no other step's.
    public static func appRow(_ app: String, on step: SetupStep, confirmed: Bool) -> AppRow {
        switch step {
        case .muteSourceApp:
            let label = muteAppRowLabel(for: app, confirmed: confirmed)
            return AppRow(text: label, voiceOver: label)
        case .firstRule:
            return AppRow(text: app, voiceOver: ruleAppRowLabel(for: app))
        case .howItWorks, .accessibility, .notifications, .proveItCanRead, .focus, .keepItRunning:
            return AppRow(text: app, voiceOver: app)
        }
    }

    /// The app the user picked, as the step lists it now, or nil when none is picked or the
    /// name picked is not in the list. The window holds the name the user picked for each
    /// step, and the list it was picked from is made again with every read (captures arrive,
    /// an app is confirmed, a rule is made), so the pick is checked against the list each
    /// time it is used: **an app is acted on only while it is listed**, and a name left over
    /// from a list that has changed is no pick at all, which the press then says
    /// (`pickAnAppFirst`) and does not guess at. That matters most for confirming a mute,
    /// which is the user's word and must be about an app they saw.
    ///
    /// Names are compared as rules and the mute checklist compare them (ignoring case,
    /// accents and surrounding spaces, `appNames(_:)`), and the answer is the name as the
    /// list writes it, so what the press acts on is exactly a row of the list. A blank
    /// name is never a pick.
    public static func listedApp(_ picked: String?, among apps: [String]) -> String? {
        guard let picked else { return nil }
        let key = MuteWalkthrough.key(picked)
        guard !key.isEmpty else { return nil }
        return apps.first { MuteWalkthrough.key($0) == key }
    }

    /// What VoiceOver reads for the practice line, which the first rule's step shows as text
    /// to select. It says the line is text, since the window does not run it or copy it.
    public static let practiceCommandLabel = "Practice command, text to select"

    // MARK: Where a modal alert used to stand

    /// Said beside the app's button when the lookup of the app did not find it, or found more
    /// than one: the pane the button opened, and why it is not the app's own page.
    public static let muteLookupOpened = "System Settings was asked to open at Notifications and not at an app's page."

    /// The menu's alert says this before it opens the pane; the guide has no alert (Ruling
    /// 22), so it says it beside the button instead. nil when the lookup found exactly one
    /// app, whose page the button opens.
    ///
    /// **It names the app**, as the alert does, because the user has to know what to look for
    /// in a list in another window, which is the one place a count would not do. The name is
    /// the one the row shows, and it is the name the user picked from the list the step
    /// offers. The bundle identifiers of the apps that matched are the lookup's own reading
    /// of the apps on this Mac, and hold no notification text.
    public static func muteLookupMessage(for app: String, resolution: BundleResolution) -> String? {
        guard let fallback = MuteWalkthroughText.lookupFallback(app, resolution) else { return nil }
        var message = "\(fallback.title) \(muteLookupOpened) \(MuteWalkthroughText.findInList(app))"
        if case .ambiguous(let ids) = resolution { message += " \(MuteWalkthroughText.found(ids))" }
        return message
    }

    /// Said when the rules file could not be made ready to open, which is the one way the
    /// button that opens the rules file in a text editor fails. It says only what was read:
    /// that no editor was opened. It does not say that a file could not be created, since
    /// the error may be that nothing was attempted: a `rules.json` that is a link to a file
    /// that cannot be found is refused before any file is made (`RulesFile.createIfMissing`
    /// calls `refuseBrokenLink()` first), and the reason given says which it was.
    public static let rulesFileNotReady = "SignalLadder could not get its rules file ready, so no text editor was opened."
    /// Leads the reason the system or the rules file's own code gave.
    public static let reasonLead = "The reason given was:"

    /// The sentence the guide shows beside its button for the rules file when opening it
    /// failed, in place of the alert the menu shows (Ruling 22).
    ///
    /// **The reason may be shown, because it cannot hold notification text.** The only error
    /// that reaches here is the one `RuleStore.createExampleIfMissing()` throws, and that
    /// call creates a folder and writes a fixed example at the rules file's own path, or
    /// finds that path is a link to a file that cannot be found. So the error is the
    /// system's about that path (a Cocoa or POSIX error, whose own sentence names the file
    /// and the folder), or the rules file's own, whose sentence names where the link points.
    /// Neither reads a notification.
    public static func rulesFileNotOpened(_ error: Error) -> String {
        let reason = reasonGiven(by: error)
        guard !reason.isEmpty else { return rulesFileNotReady }
        return "\(rulesFileNotReady) \(reasonLead) \(reason)\(reason.hasSuffix(".") ? "" : ".")"
    }

    /// What an error says for itself: the system's localised sentence for one of its own
    /// domains, and for any other error its description (`CustomStringConvertible`, as the
    /// rules file's read error has), since `localizedDescription` of such an error is a line
    /// that names its type and not what failed.
    static func reasonGiven(by error: Error) -> String {
        let system = error as NSError
        let said = system.domain == NSCocoaErrorDomain || system.domain == NSPOSIXErrorDomain
            ? system.localizedDescription : String(describing: error)
        return said.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Where a press comes to nothing

    /// Said beside a button that is about an app (making a rule from one, confirming one
    /// muted, opening its notification settings) when the user has picked none in the step's
    /// list. It asks for a pick and says nothing of what was read, so that the button is
    /// never one that does nothing and says nothing.
    public static let pickAnAppFirst = "Choose an app in the list first."
    /// Said beside "Make a Rule from This…" when the app the user picked has no banner left
    /// to make the rule from. The buffer of captures is a fixed size, so the newest banner of
    /// an app can have gone by the time of the press (`SetupCapture.newestEntry(forApp:in:)`
    /// finds none). "That app" is the row the user picked, so no name is repeated.
    public static let noBannerFromThatApp = "SignalLadder no longer has a banner it read from that app, so it cannot make a rule from one. Choose another app in the list."

    // MARK: Every label

    /// Every label the guide's window shows that is not a step's words or the summary's, each
    /// with the kind it is and what the window's source writes to show it, so that a test can
    /// hold them to what they must be and a scan of `SetupView.swift` can find one that
    /// nobody shows. A label made from an app's name is listed once, from `sampleApp`.
    public static let windowLabels: [WindowLabel] = makeWindowLabels()

    private static func makeWindowLabels() -> [WindowLabel] {
        var all: [WindowLabel] = []
        func add(_ kind: WindowLabel.Kind, _ reference: String, _ text: String) {
            all.append(WindowLabel(kind: kind, reference: reference, text: text))
        }
        add(.heading, "SetupText.railHeading", railHeading)
        for step in SetupStep.allCases {
            add(.caption, "SetupText.stepPosition(", stepPosition(of: step))
            add(.description, "SetupText.railRowLabel(", railRowLabel(for: step))
        }
        for state in everyState {
            add(.description, "SetupText.stateDescription(", stateDescription(for: state))
        }
        for state in everyState {
            add(.caption, "SetupText.stateLabel(", stateLabel(for: state))
        }
        add(.button, "SetupText.label(for: .notNow)", label(for: .notNow))
        for step in SetupStep.allCases {
            if let heading = appListHeading(for: step) { add(.heading, "SetupText.appListHeading(", heading) }
        }
        add(.description, "SetupText.appRow(", appRow(sampleApp, on: .firstRule, confirmed: false).voiceOver)
        for confirmed in [false, true] {
            add(.description, "SetupText.appRow(", appRow(sampleApp, on: .muteSourceApp, confirmed: confirmed).voiceOver)
        }
        add(.description, "SetupText.practiceCommandLabel", practiceCommandLabel)
        let ambiguous = BundleResolution.ambiguous(["first.example", "second.example"])
        for resolution in [BundleResolution.notFound, ambiguous] {
            if let message = muteLookupMessage(for: sampleApp, resolution: resolution) {
                add(.message, "SetupText.muteLookupMessage(", message)
            }
        }
        add(.message, "SetupText.rulesFileNotOpened", rulesFileNotReady)
        add(.message, "SetupText.pickAnAppFirst", pickAnAppFirst)
        add(.message, "SetupText.noBannerFromThatApp", noBannerFromThatApp)
        return all
    }

    // MARK: - Settings' Setup group

    /// The button in Settings' Setup group, which opens the guide's window. It carries its
    /// verb and ends in an ellipsis, as the buttons that open a window do.
    public static let openGuideButton = "Open the Setup Guide…"

    /// Said when nothing the plan reads has been stored.
    public static let guideNotStarted = "The Setup Guide has not been started."
    /// Said when the guide was begun and neither closed nor finished.
    public static let guideInProgress = "The Setup Guide was started and has not been finished."
    /// Said when the guide was closed before it was finished, by "Not now" or by closing its
    /// window, which are one act (O13).
    public static let guideClosed = "You closed the Setup Guide before finishing it."
    /// Said when the guide was finished.
    public static let guideFinished = "You finished the Setup Guide."

    /// The line in Settings' Setup group: where the guide stands, from the progress, and
    /// whether what it requires is done, from the plan (`SetupPlan.standing(_:)`,
    /// `SetupPlan.configuration(_:)`). It reads nothing else and says nothing the plan did
    /// not establish.
    ///
    /// - A guide **finished** is said finished, whatever else was recorded and whatever the
    ///   configuration reads: a permission taken away afterwards is the health line's to
    ///   say, as the nudge leaves it (`SetupPlan.nudgeLine(_:guideIsOpen:)`).
    /// - A guide **in progress** is said started and not finished. The configuration is not
    ///   said: the guide is the place for it.
    /// - A guide **not started** or **closed** adds what the configuration reads. Done, it
    ///   names the three steps the plan counts (Accessibility, Notifications and a first
    ///   rule) and says they are done; so a Mac that was set up before the guide existed, or
    ///   by hand, reads as not started with those done, and not as set up by either route,
    ///   which the plan does not know. Not configured, it says at least one of them is still
    ///   to do, which is what the menu's nudge says too. Not known, because the notification
    ///   fact has not been read yet, it says nothing of them.
    public static func settingsLine(progress: SetupProgress, configuration: SetupPlan.Configuration) -> String {
        switch SetupPlan.standing(progress) {
        case .finished: return guideFinished
        case .inProgress: return guideInProgress
        case .notStarted: return addingWhatIsRequired(to: guideNotStarted, configuration)
        case .closed: return addingWhatIsRequired(to: guideClosed, configuration)
        }
    }

    /// The line for the facts: the progress they hold and the configuration the plan reads
    /// from them, so that the app hands over the facts and combines nothing (Ruling 10).
    ///
    /// **The facts must be built after the rules are loaded**, as the nudge's must be. This
    /// makes Settings a second reader of `SetupPlan.configuration`, which reads the rules'
    /// status, and the rules fact has no "not read yet": a store that has not loaded reads
    /// `.noRulesFile` (`RuleStore.status` before `reload()`), which the plan takes for an
    /// upgrader with no rule, so a line made too early would tell a configured upgrader that
    /// at least one of the three is still to do (see `SetupFacts.ruleStatus`). The app builds
    /// its status item before `reloadRules()` runs at launch and builds no menu and gathers
    /// no facts until after it, so Settings' model is first given facts by the rebuild that
    /// `reloadRules()` ends in, and a wiring test of the app's sources holds that order (M5
    /// plan, Task 7 note under `SetupPlan`).
    public static func settingsLine(_ facts: SetupFacts) -> String {
        settingsLine(progress: facts.progress, configuration: SetupPlan.configuration(facts))
    }

    /// The three steps the plan counts, in the nudge's words and in the plan's order.
    private static var requiredWords: String {
        MuteWalkthroughText.list(SetupPlan.requiredSteps.compactMap { nudgeWord(for: $0) })
    }

    private static func addingWhatIsRequired(to said: String, _ configuration: SetupPlan.Configuration) -> String {
        switch configuration {
        case .configured: return "\(said) \(requiredWords) are done."
        case .notConfigured: return "\(said) At least one of \(requiredWords) is still to do."
        case .unknown: return said
        }
    }
}
