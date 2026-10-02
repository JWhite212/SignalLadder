// Sources/NotificationCore/EditorText.swift
import Foundation

/// Every sentence the rule editor shows, worded here where it is tested.
///
/// The editor is where it is easiest to believe you are protected when you
/// are not: a rule can look finished and be unsaved, switched off, or broken.
/// Every line says which.
public enum EditorText {
    // MARK: - The dry-run

    /// "In this draft: matches 3 of the last 50 notifications."
    public static func dryRunHeadline(_ run: DryRun) -> String {
        let total = run.rows.count
        guard total > 0 else { return "In this draft: no notifications captured yet to try this rule on." }
        let count = run.matchedCount
        let found = count == 0 ? "none" : "\(count)"
        let verb = run.ruleIsOff ? "would match" : "matches"
        let when = run.ruleIsOff ? " when switched on" : ""
        return "In this draft: \(verb) \(found) of the last \(total) notification\(total == 1 ? "" : "s")\(when)."
    }

    /// Said whenever notifications this rule matches go to a rule above it.
    public static func claimed(_ run: DryRun) -> String? {
        let count = run.claimedCount
        guard count > 0 else { return nil }
        let them = count == 1 ? "1 more is" : "\(count) more are"
        let claimers = run.claimers
        let by = claimers.count == 1 ? "“\(claimers[0].name)”, above it" : "\(claimers.count) rules above it"
        return "\(them) taken first by \(by)."
    }

    public static func moveAbove(_ name: String) -> String { "Move Above “\(name)”" }

    /// Why what the dry-run shows is not yet what happens, or nil when it is.
    /// The most serious reason wins: a broken rule will not run even once
    /// saved and switched on.
    public static func notInEffect(hasProblems: Bool, isOff: Bool, isUnsaved: Bool) -> String? {
        if hasProblems { return "Not in effect: this rule has problems, and will not run until they are fixed." }
        if isOff { return "Not in effect: this rule is switched off." }
        if isUnsaved { return "Not in effect until you save." }
        return nil
    }

    // MARK: - The builder

    public static func fieldName(_ field: Field) -> String {
        switch field {
        case .app: return "App"
        case .title: return "Title"
        case .subtitle: return "Subtitle"
        case .body: return "Body"
        case .raw: return "Any text"
        case .subrole: return "Banner kind"
        }
    }

    public static func operatorName(_ op: Operator) -> String {
        switch op {
        case .equals: return "is"
        case .notEquals: return "is not"
        case .contains: return "contains"
        case .matches: return "matches pattern"
        }
    }

    /// One condition in words, for a menu: "Title contains “All Hands”".
    /// A long value is shortened here only — the condition keeps all of it.
    public static func describe(_ condition: RuleCondition, limit: Int = 48) -> String {
        switch condition {
        case .field(let field, let op, let value):
            let shown = value.isEmpty ? "empty" : "“\(value.count > limit ? value.prefix(limit) + "…" : Substring(value))”"
            return "\(fieldName(field)) \(operatorName(op)) \(shown)"
        case .and(let children): return "All of \(children.count) conditions"
        case .or(let children): return "Any of \(children.count) conditions"
        case .not(let inner): return "Not: \(describe(inner, limit: limit))"
        }
    }

    /// What each kind of alert does, beside the choice, worded for the step
    /// the alert is: the first alert plays when a notification matches, a
    /// repeat each time the ladder repeats, a final alert once.
    public static func alertMeaning(_ alert: AlertAction?, role: AlertEditing.Role = .first) -> String {
        switch role {
        case .first:
            switch alert {
            case nil: return "Matching notifications are marked in the Inspector. Nothing plays."
            case .silent: return "Matching notifications are claimed and stay quiet: no rule below can sound for them."
            case .sound: return "Plays this sound when a notification matches."
            case .speak: return "Speaks a line built from the notification when one matches."
            case .soundAndSpeak: return "Plays this sound, then speaks a line built from the notification."
            }
        case .repeating:
            switch alert {
            case nil: return "There is no alert here, so nothing repeats."
            case .silent: return "This repeat is silent, so it repeats nothing. Choose a sound or speech."
            case .sound: return "Plays this sound again each time the ladder repeats."
            case .speak: return "Speaks a line built from the notification each time the ladder repeats."
            case .soundAndSpeak:
                return "Plays this sound, then speaks a line built from the notification, each time the ladder repeats."
            }
        case .final:
            switch alert {
            case nil: return "There is no alert here, so nothing happens at the final step."
            case .silent: return "This final alert is silent, so it would do nothing. Choose a sound or speech, or a Shortcut."
            case .sound: return "Plays this sound once, if nobody has acknowledged by then."
            case .speak: return "Speaks a line built from the notification once, if nobody has acknowledged by then."
            case .soundAndSpeak:
                return "Plays this sound, then speaks a line built from the notification, once, if nobody has acknowledged by then."
            }
        }
    }

    public static let outputSilentNote = "The Mac's sound output is muted or at zero volume — you won't hear it."

    public static let speechTemplateHelp =
        "{app}, {title} and {body} are filled from the notification. Test Speech uses a made-up one."

    /// A gain beside its slider: "0 dB", "+6 dB", "−12 dB", with a true minus.
    public static func gainText(_ gainDB: Double) -> String {
        gainDB == 0 ? "0 dB" : "\(gainDB > 0 ? "+" : "−")\(Int(abs(gainDB))) dB"
    }

    // MARK: - The ladder

    /// Heads the choice between the presets.
    public static let ifIDontAcknowledge = "If I don't acknowledge"

    /// Heads the disclosure that holds every tier control.
    public static let customise = "Customise…"

    /// "Tier 3": the words the panel and the Inspector already use.
    public static func tierHeading(_ tier: Int) -> String { "Tier \(tier)" }

    public static func presetName(_ preset: EscalationEditing.Preset) -> String {
        switch preset {
        case .off: return "Off"
        case .gentle: return "Gentle"
        case .onCall: return "On call"
        case .wakeMe: return "Wake me"
        }
    }

    public static let customName = "Custom"

    /// What a ladder that is none of the presets is called in a row of the
    /// rule list.
    static let customLadder = "custom ladder"

    /// A segment of the choice between the presets.
    public static func segmentName(_ shown: EscalationEditing.Shown) -> String {
        switch shown {
        case .preset(let preset): return presetName(preset)
        case .custom: return customName
        }
    }

    /// The two segments of tier 4's choice.
    public static func finalKindName(_ kind: EscalationEditing.FinalKind) -> String {
        switch kind {
        case .alert: return "Alert"
        case .shortcut: return "Shortcut"
        }
    }

    /// What a preset does, beside its name. Made from the preset's own
    /// numbers, so what is said cannot drift from what is written. The repeat
    /// is the first alert's, since what plays is decided by the rule.
    public static func presetMeaning(_ preset: EscalationEditing.Preset) -> String {
        var sentences: [String] = []
        if let tier2 = preset.tier2 { sentences.append(panelSentence(afterSeconds: tier2.delaySeconds)) }
        if let timing = preset.repeating {
            sentences.append(repeatSentence(who: "the first alert repeats", intervalSeconds: timing.intervalSeconds,
                                            maxRepeats: timing.maxRepeats, maxDurationSeconds: timing.maxDurationSeconds))
        }
        return sentences.isEmpty ? nothingAfterTheFirstAlert : sentences.joined(separator: " ")
    }

    /// Beside the choice, under On call and Wake me, while the ladder has no
    /// final step: nothing else here can reach someone away from the Mac.
    public static func shortcutNudge(shown: EscalationEditing.Shown, escalation: Escalation?) -> String? {
        guard case .preset(let preset) = shown, preset == .onCall || preset == .wakeMe,
              escalation?.tier4 == nil else { return nil }
        return "A Shortcut can page your phone if nobody answers. Add one as the final step, under “\(customise)”."
    }

    /// Said while no preset but Off can be chosen, for want of a first alert.
    public static let chooseWhatPlaysFirst = "Choose what plays first (Silent is fine) to use a preset."

    /// Beside a preset that cannot be chosen yet.
    public static func presetHint(forAlert alert: AlertAction?) -> String? {
        alert == nil ? chooseWhatPlaysFirst : nil
    }

    private static let nothingAfterTheFirstAlert = "Nothing happens after the first alert."

    /// The sentence beneath the choice: what the ladder does, in order. It
    /// describes the actual ladder, a Shortcut included, whichever segment is
    /// chosen, and says something for every ladder the type can hold. Nothing
    /// an alert says is in it, only the sound's name and the Shortcut's.
    public static func ladderSentence(_ escalation: Escalation?) -> String {
        guard let escalation else { return nothingAfterTheFirstAlert }
        guard !escalation.isEmpty else {
            return "This ladder has no steps, so nothing happens after the first alert."
        }
        var sentences: [String] = []
        if let tier2 = escalation.tier2 { sentences.append(panelSentence(afterSeconds: tier2.delaySeconds)) }
        if let tier3 = escalation.tier3 {
            sentences.append(repeatSentence(who: repeatPhrase(tier3.action), intervalSeconds: tier3.intervalSeconds,
                                            maxRepeats: tier3.maxRepeats, maxDurationSeconds: tier3.maxDurationSeconds))
        }
        if let tier4 = escalation.tier4 { sentences.append(finalSentence(tier4)) }
        return sentences.joined(separator: " ")
    }

    /// What is said after Off took a ladder away, and how to bring it back.
    /// Custom is named only while there is a custom ladder for it to restore.
    public static func offSentence(setAside: EscalationEditing.SetAside) -> String {
        if let custom = setAside.custom {
            return "\(nothingAfterTheFirstAlert) Choose \(customName) to bring back the ladder you set aside. "
                + ladderSentence(custom)
        }
        if setAside.holdsLadder {
            return "\(nothingAfterTheFirstAlert) Choose a preset to bring the ladder back."
        }
        return nothingAfterTheFirstAlert
    }

    /// The question that replaces the sentence while Off waits for an answer.
    public static func offQuestion(shortcutName: String) -> String {
        if shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Remove this ladder, including its Shortcut?"
        }
        return "Remove this ladder, including the Shortcut “\(shortcutName)”?"
    }

    public static let removeLadder = "Remove"
    public static let keepLadder = "Keep"

    /// What sits beneath the choice: the question while Off waits, the Off
    /// sentence while there is no ladder, else the ladder's sentence.
    ///
    /// - Parameter confirmingShortcut: the Shortcut a pending Off would remove,
    ///   or nil when no question is pending.
    public static func underChoice(escalation: Escalation?, setAside: EscalationEditing.SetAside,
                                   confirmingShortcut: String?) -> String {
        if let name = confirmingShortcut { return offQuestion(shortcutName: name) }
        guard let escalation else { return offSentence(setAside: setAside) }
        return ladderSentence(escalation)
    }

    /// Beneath a repeat with neither limit, which is Wake me's own: a repeat
    /// that never ends holds the Mac awake for as long as anything is pending.
    public static func unlimitedRepeatCaption(for escalation: Escalation?) -> String? {
        guard let tier3 = escalation?.tier3, tier3.maxRepeats == nil, tier3.maxDurationSeconds == nil else { return nil }
        return "With no limit on repeats or time, the Mac stays awake and keeps sounding until you acknowledge it."
    }

    /// A limit's switch.
    public static let noLimit = "No limit"

    /// Beside a limit's switch, while it is ticked: what ticking it does, and
    /// no more. "It repeats until you acknowledge it" is true only when
    /// neither limit is left, so while the other limit is still set the hint
    /// says that the repeats still stop, and when. Nil while this limit is a
    /// number, since there is nothing to say about a switch that is off, and
    /// when there is no repeat to limit.
    public static func noLimitHint(_ limit: EscalationEditing.Limit, in escalation: Escalation?) -> String? {
        guard let tier3 = escalation?.tier3 else { return nil }
        switch limit {
        case .repeats:
            guard tier3.maxRepeats == nil else { return nil }
            guard let time = tier3.maxDurationSeconds else {
                return "No limit on repeats: it repeats until you acknowledge it."
            }
            return "No limit on repeats: it still stops after \(duration(time))."
        case .duration:
            guard tier3.maxDurationSeconds == nil else { return nil }
            guard let count = tier3.maxRepeats else {
                return "No time limit: it repeats until you acknowledge it."
            }
            return "No time limit: it still stops after \(readable(count: count)) repeat\(count == 1 ? "" : "s")."
        }
    }

    // MARK: Testing a Shortcut

    public static let testShortcut = "Test Shortcut"

    /// The button's help. A Shortcut that pages a phone will page it.
    public static let testShortcutHelp = "This really runs the Shortcut."

    /// The result of a test that started, never "worked": a Shortcut that fails
    /// after it starts is still one that started. A test that did not start
    /// shows the runner's own reason as it is.
    public static func shortcutTestStarted(_ name: String) -> String { "Started “\(name)”" }

    /// Beside the name field, when the Shortcuts app does not list the name:
    /// advice, and not a problem, since a name that is not found never refuses
    /// a rule. It says what the name does and not whether this rule is in
    /// effect: the pane shows it beside a draft that is not saved, and beside
    /// a rule the loader would refuse for another reason, and the line that
    /// says whether the rule is in effect is `notInEffect`'s.
    public static let shortcutNotFoundAdvice =
        "Not found in the Shortcuts app. The name must match one there exactly, including capitals, spaces and "
        + "punctuation. A name that is not found does not switch the rule off. Test Shortcut tries the name before "
        + "you save."

    // MARK: Words for assistive technology

    /// Every control of the ladder that has no visible words of its own, or
    /// whose words are not enough on their own.
    public enum Control: CaseIterable, Sendable {
        case ladderChoice
        case tier2Switch, tier2Delay
        case tier3Switch, tier3Interval
        case tier3MaxRepeats, tier3NoRepeatLimit, tier3MaxDuration, tier3NoTimeLimit
        case tier4Switch, tier4Delay, tier4Kind, tier4ShortcutName, tier4TestShortcut
    }

    /// What a screen reader says for a control. Each is distinct, and says
    /// the tier, since the same sort of control appears in more than one.
    public static func label(_ control: Control) -> String {
        switch control {
        case .ladderChoice: return ifIDontAcknowledge
        case .tier2Switch: return "Tier 2, show a panel until acknowledged"
        case .tier2Delay: return "Tier 2 delay, in seconds"
        case .tier3Switch: return "Tier 3, repeat the alert"
        case .tier3Interval: return "Tier 3 time between repeats, in seconds"
        case .tier3MaxRepeats: return "Tier 3 most repeats"
        case .tier3NoRepeatLimit: return "Tier 3, no limit on repeats"
        case .tier3MaxDuration: return "Tier 3 longest time repeating, in seconds"
        case .tier3NoTimeLimit: return "Tier 3, no limit on time"
        case .tier4Switch: return "Tier 4, a final step"
        case .tier4Delay: return "Tier 4 delay, in seconds"
        case .tier4Kind: return "Tier 4 final step is an alert or a Shortcut"
        case .tier4ShortcutName: return "Tier 4 Shortcut name"
        case .tier4TestShortcut: return testShortcut
        }
    }

    /// The label of an alert editor's kind picker, which has no visible words.
    public static func alertPickerLabel(for role: AlertEditing.Role) -> String {
        switch role {
        case .first: return "Alert when a notification matches"
        case .repeating: return "Tier 3 alert"
        case .final: return "Tier 4 alert"
        }
    }

    // MARK: Numbers

    /// A time as it is typed into a field: in seconds, plain digits, and
    /// whatever the type holds. Whole numbers carry no decimal point, as long
    /// as they fit an `Int`; a hand-written file can hold any number, and
    /// converting one that does not fit traps.
    public static func fieldText(seconds: Double) -> String {
        seconds == seconds.rounded() && abs(seconds) < 1e15 ? String(Int(seconds)) : String(seconds)
    }

    public static func fieldText(count: Int) -> String { String(count) }

    /// A time as it reads in a sentence, in the largest units that hold it:
    /// "10 seconds", "1 minute 30 seconds", "2 hours". Anything that is not a
    /// whole number of seconds from a minute up, 0, a negative and a fraction
    /// included, reads in seconds, so that no value the type holds is hidden.
    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "a time that cannot be shown" }
        let magnitude = abs(seconds)
        guard magnitude >= 60, magnitude == magnitude.rounded(), magnitude < 1e15 else {
            return "\(readable(seconds)) second\(seconds == 1 ? "" : "s")"
        }
        let total = Int(magnitude)
        let parts = [(total / 3600, "hour"), (total % 3600 / 60, "minute"), (total % 60, "second")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        return (seconds < 0 ? "−" : "") + parts.joined(separator: " ")
    }

    /// Beside a field typed in seconds, from a minute up, since seconds are
    /// harder to read: "10 minutes" beside 600. Nil below a minute, where the
    /// field already says it.
    public static func secondsCaption(_ seconds: Double) -> String? {
        guard seconds.isFinite, abs(seconds) >= 60 else { return nil }
        return duration(seconds)
    }

    /// A number in a sentence, with a true minus.
    private static func readable(_ value: Double) -> String {
        let text = fieldText(seconds: value)
        return text.hasPrefix("-") ? "−" + text.dropFirst() : text
    }

    private static func readable(count: Int) -> String {
        count < 0 ? "−\(count.magnitude)" : "\(count)"
    }

    private static func panelSentence(afterSeconds: Double) -> String {
        "After \(duration(afterSeconds)) a panel stays on screen until you acknowledge it."
    }

    /// "Every 30 seconds, Hero plays again, at most 20 times or 10 minutes,
    /// whichever comes first."
    ///
    /// Said by the coordinator's own rule for whether a repeat is due
    /// (`RepeatAlert.timeLimitAllowsRepeat`), so that a ladder that never
    /// repeats is not described as one that does: a time limit that ends
    /// before the first repeat is due allows none.
    private static func repeatSentence(who: String, intervalSeconds: Double, maxRepeats: Int?,
                                       maxDurationSeconds: Double?) -> String {
        if let ends = maxDurationSeconds,
           !RepeatAlert.timeLimitAllowsRepeat(number: 1, intervalSeconds: intervalSeconds, maxDurationSeconds: ends) {
            return "It never repeats: the first repeat would come after \(duration(intervalSeconds)), "
                + "and the time limit ends at \(duration(ends))."
        }
        let times: String? = maxRepeats.map { $0 == 1 ? "once" : "\(readable(count: $0)) times" }
        let limit: String
        switch (times, maxDurationSeconds) {
        case (let times?, let duration?): limit = "at most \(times) or \(Self.duration(duration)), whichever comes first"
        case (let times?, nil): limit = "at most \(times)"
        case (nil, let duration?): limit = "for at most \(Self.duration(duration))"
        case (nil, nil): limit = "with no limit on repeats or time"
        }
        return "Every \(duration(intervalSeconds)), \(who), \(limit)."
    }

    /// What a repeat does, as the subject of a sentence.
    private static func repeatPhrase(_ action: AlertAction) -> String {
        switch action {
        case .sound(let name, _): return "\(name) plays again"
        case .speak: return "the line is spoken again"
        case .soundAndSpeak(let name, _, _): return "\(name) plays and the line is spoken again"
        case .silent: return "nothing sounds again, as it is silent"
        }
    }

    private static func finalSentence(_ tier4: FinalAlert) -> String {
        let after = "After \(duration(tier4.afterSeconds)) it"
        switch tier4.action {
        case .alert(.sound(let name, _)): return "\(after) plays \(name)."
        case .alert(.speak): return "\(after) speaks the line."
        case .alert(.soundAndSpeak(let name, _, _)): return "\(after) plays \(name) and speaks the line."
        case .alert(.silent): return "\(after) does nothing, as it is silent."
        case .shortcut(let name):
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(after) starts a Shortcut that has no name yet."
            }
            return "\(after) starts the Shortcut “\(name)”."
        }
    }

    // MARK: - The document

    public static let unsavedChanges = "Unsaved changes — not in effect until you save"

    /// Whether what the editor shows is what the app is running.
    public enum SaveState: Equatable, Sendable {
        /// The draft differs from the file.
        case unsaved
        /// The draft is the file, but the file declares a version too low for
        /// a rule it holds, so the loader refuses that rule and the app is
        /// not running it. Save writes the version the rules need, and a
        /// reload would change nothing, so Put into Effect is not offered.
        case fileNeedsNewerVersion(declared: Int, needed: Int)
        /// The draft is the file, but the file is not what the app is
        /// running — it was edited by hand and not yet reloaded.
        case fileNotInEffect
        /// The draft is the file, and the file is what the app is running.
        /// `notRunning` counts saved rules that will not run because they
        /// have problems.
        case inEffect(notRunning: Int)
    }

    /// - Parameters:
    ///   - fileIsInEffect: whether the file the editor read is the one the
    ///     rules in effect were read from.
    ///   - fileVersion: the version the file the editor read declares, or nil
    ///     for no file. Not defaulted: a state that forgot it would call a
    ///     file clean that the loader refuses a rule of.
    ///   - broken: whether a rule has problems, and so will not run.
    public static func saveState(draft: [Rule], saved: [Rule], fileIsInEffect: Bool, fileVersion: Int?,
                                 broken: (Rule) -> Bool) -> SaveState {
        if draft != saved { return .unsaved }
        // Before the file being out of effect: a reload of this file would
        // refuse the same rule again, and only a save can fix it.
        if RulesDocument.fileNeedsRewriting(rules: saved, fileVersion: fileVersion), let fileVersion {
            return .fileNeedsNewerVersion(declared: fileVersion, needed: RuleSetCodec.version(for: saved))
        }
        if !fileIsInEffect { return .fileNotInEffect }
        return .inEffect(notRunning: saved.filter { $0.isEnabled && broken($0) }.count)
    }

    public static func saveState(_ state: SaveState) -> (text: String, isWarning: Bool) {
        switch state {
        case .unsaved:
            return (unsavedChanges, true)
        case .fileNeedsNewerVersion(let declared, let needed):
            // No rule's name: the rules the file holds are the ones that
            // need it, and the editor marks each in its list.
            return ("rules.json declares version \(declared) but holds a rule that needs \(needed), "
                    + "so that rule is not running — Save writes version \(needed) and puts it into effect", true)
        case .fileNotInEffect:
            return ("rules.json has changed since it was put into effect — these rules are not running yet", true)
        case .inEffect(let notRunning) where notRunning > 0:
            let them = notRunning == 1 ? "1 rule has problems and does not run" : "\(notRunning) rules have problems and do not run"
            return ("Saved and in effect — except that \(them)", true)
        case .inEffect:
            return ("Saved and in effect", false)
        }
    }

    public static let putIntoEffect = "Put into Effect"

    public static let emptyState = "No rules yet. To make your first, open the Inspector and choose Make a Rule from This on a notification you want to hear about."

    /// Beside "Add Condition from This Notification": the text chosen becomes
    /// part of a rule, and rules are saved to disk.
    public static let savedTextCaption = "The text you add is saved in your rules file."

    public static func readOnly(_ reason: RulesDocument.ReadOnlyReason) -> (title: String, detail: [String]) {
        switch reason {
        case .unreadable(let why):
            return ("The rules file can't be read, so it can't be edited here.", [why])
        case .newerVersion(let version):
            return ("The rules file was written by a newer SignalLadder (format \(version)).",
                    ["Editing it here could lose what this version doesn't understand."])
        case .undecodable(let problems):
            let count = problems.count == 1 ? "1 rule" : "\(problems.count) rules"
            return ("\(count) in the file can't be read, so saving here would drop \(problems.count == 1 ? "it" : "them"). Fix \(problems.count == 1 ? "it" : "them") in a text editor.",
                    problems.map(\.description))
        }
    }

    /// A rule's alert in a word or two, for its row in the list.
    public static func alertSummary(_ alert: AlertAction?) -> String {
        switch alert {
        case nil: return "No alert"
        case .silent: return "Silent"
        case .sound(let name, let gainDB): return name + InspectorRowText.gainSuffix(gainDB)
        case .speak(let speech): return "Spoken" + InspectorRowText.gainSuffix(speech.gainDB)
        case .soundAndSpeak(let name, let gainDB, _): return name + InspectorRowText.gainSuffix(gainDB) + ", spoken"
        }
    }

    /// As `alertSummary(_:)`, and what the rest of the ladder is: a preset by
    /// name, or a custom ladder, and a Shortcut when the last step is one. A
    /// rule with no ladder, or an empty one, reads as its alert alone.
    public static func alertSummary(_ alert: AlertAction?, escalation: Escalation?) -> String {
        let summary = alertSummary(alert)
        guard let escalation, !escalation.isEmpty else { return summary }
        let ladder: String
        switch EscalationEditing.shown(for: escalation) {
        case .preset(let preset): ladder = presetName(preset)
        case .custom: ladder = customLadder
        }
        let shortcut = escalation.tier4?.action.shortcutName == nil ? "" : ", with a Shortcut"
        return "\(summary), escalating: \(ladder)\(shortcut)"
    }

    public static let closeTitle = "Save changes to your rules?"
    public static let closeDetail = "Changes are not in effect until you save them, and are lost if you don't."

    // MARK: - A save that was refused

    public static let conflictTitle = "rules.json changed since you opened it"

    /// What happened on disk, so the user knows what Save Anyway would replace.
    public static func conflictDetail(_ change: RulesChange) -> String {
        switch change.file {
        case .unchanged:
            return "Nothing has changed."
        case .deleted:
            return "It was deleted\(listed(" with", change.removed))."
        case .created:
            return "It was created\(listed(" with", change.added))."
        case .unreadable:
            return "It was edited into something that can no longer be read as rules."
        case .edited:
            let renames = change.renamed.map { "“\($0.from)” to “\($0.to)”" }.joined(separator: ", ")
            let parts = [part("Added", change.added), part("Removed", change.removed),
                         renames.isEmpty ? nil : "Renamed: \(renames).",
                         part("Changed", change.changed)]
                .compactMap { $0 }
            return parts.isEmpty ? "Only its formatting changed." : parts.joined(separator: " ")
        }
    }

    public static let conflictKeepNote = "Save Anyway keeps the version on disk as a dated copy beside rules.json."

    private static func part(_ label: String, _ names: [String]) -> String? {
        names.isEmpty ? nil : "\(label): \(quoted(names))."
    }

    private static func listed(_ prefix: String, _ names: [String]) -> String {
        names.isEmpty ? "" : "\(prefix) \(quoted(names))"
    }

    private static func quoted(_ names: [String]) -> String {
        names.map { "“\($0)”" }.joined(separator: ", ")
    }
}
