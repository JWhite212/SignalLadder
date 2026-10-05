// Sources/NotificationCore/EscalationEditing.swift
import Foundation

/// How the rule editor's ladder controls change a rule's escalation, as pure
/// functions: the four presets and which one a ladder is, what each control
/// writes, and what is set aside so that choosing back restores it rather
/// than a default. Kept out of the view, as `AlertEditing` is, so every
/// transition is tested and the view cannot lose what the user chose.
///
/// Three rules run through all of it:
/// - Showing a ladder is pure and writes nothing. Only a control the user
///   touches writes, and each control changes exactly one field, so a value
///   nobody edited is never rewritten. That includes a value the controls
///   would never write, such as an interval of 0 in a hand-written file.
/// - A preset is an editing convenience, derived from the ladder and never
///   stored. The file holds the explicit ladder, and a preset never carries
///   what could switch a rule off or swallow a page: it owns tiers 2 and 3,
///   never a Shortcut, and never a snooze opt-in.
/// - Whatever a choice drops is set aside, never discarded, and whatever it
///   adds is taken from what was set aside before a default is used.
public enum EscalationEditing {
    // MARK: - Presets

    /// The four ways to answer "If I don't acknowledge".
    ///
    /// Each is a frozen literal, deliberately not a reference to
    /// `PanelAlert.defaultDelaySeconds` and its siblings. A preset is
    /// recognised by its numbers, so changing a default later must be a
    /// conscious act here, and not a quiet turning of every On call ladder in
    /// every file into Custom.
    public enum Preset: CaseIterable, Hashable, Sendable {
        /// Nothing after the first alert.
        case off
        /// A silent panel, until acknowledged.
        case gentle
        /// A panel, and then the first alert's sound again: §14's defaults.
        case onCall
        /// A panel sooner, and then the same, with no limit on repeats or
        /// time, until it is acknowledged.
        case wakeMe

        /// When a repeat comes and when it stops.
        public struct Timing: Equatable, Sendable {
            public let intervalSeconds: Double
            /// nil for no limit.
            public let maxRepeats: Int?
            /// nil for no limit.
            public let maxDurationSeconds: Double?
        }

        public var tier2: PanelAlert? {
            switch self {
            case .off: return nil
            case .gentle, .onCall: return PanelAlert(delaySeconds: 10)
            case .wakeMe: return PanelAlert(delaySeconds: 5)
            }
        }

        /// nil for the presets that do not repeat.
        public var repeating: Timing? {
            switch self {
            case .off, .gentle: return nil
            case .onCall: return Timing(intervalSeconds: 30, maxRepeats: 20, maxDurationSeconds: 600)
            case .wakeMe: return Timing(intervalSeconds: 15, maxRepeats: nil, maxDurationSeconds: nil)
            }
        }

        /// The ladder this preset is, repeating `action`. A preset never
        /// holds tier 4, and Off holds nothing.
        public func ladder(repeating action: AlertAction) -> Escalation? {
            guard self != .off else { return nil }
            let tier3 = repeating.map {
                RepeatAlert(action: action, intervalSeconds: $0.intervalSeconds,
                            maxRepeats: $0.maxRepeats, maxDurationSeconds: $0.maxDurationSeconds)
            }
            return Escalation(tier2: tier2, tier3: tier3)
        }

        /// Whether `escalation` is this preset. Tier 4 is ignored, and so is
        /// the repeat's action, so a Shortcut added beside a preset, or a
        /// different sound chosen for its repeat, does not flip the picker. A
        /// silent repeat is not ignored: it repeats nothing, which no preset
        /// does.
        public func matches(_ escalation: Escalation?) -> Bool {
            guard let escalation else { return self == .off }
            guard self != .off, escalation.tier2 == tier2 else { return false }
            switch (repeating, escalation.tier3) {
            case (nil, nil):
                return true
            case (let timing?, let tier3?):
                return tier3.action != .silent
                    && tier3.intervalSeconds == timing.intervalSeconds
                    && tier3.maxRepeats == timing.maxRepeats
                    && tier3.maxDurationSeconds == timing.maxDurationSeconds
            default:
                return false
            }
        }
    }

    /// What the picker shows as chosen.
    public enum Shown: Hashable, Sendable {
        case preset(Preset)
        /// Any ladder that is none of the presets: another interval, a tier 3
        /// alone, a tier 4 alone, an empty `{}`, a silent repeat.
        case custom
    }

    /// Which preset a ladder is, or Custom. Nil is Off. Pure: it writes
    /// nothing, and it can show any ladder the type can hold, a hand-written
    /// one with a problem in it included, so that the problem can be fixed in
    /// the editor.
    public static func shown(for escalation: Escalation?) -> Shown {
        guard let preset = Preset.allCases.first(where: { $0.matches(escalation) }) else { return .custom }
        return .preset(preset)
    }

    /// The picker's segments: the four presets, and Custom only while the
    /// ladder is custom or a custom one is set aside, so that the selection
    /// always has a segment and Custom is there to go back to.
    public static func segments(for escalation: Escalation?, setAside: SetAside) -> [Shown] {
        let presets = Preset.allCases.map(Shown.preset)
        return shown(for: escalation) == .custom || setAside.custom != nil ? presets + [.custom] : presets
    }

    /// Whether a preset can be chosen. Every preset but Off needs a first
    /// alert to repeat: with none, choosing one would make a rule the loader
    /// refuses, or set Silent for the user, which is not the editor's choice
    /// to make.
    public static func isAvailable(_ preset: Preset, forAlert alert: AlertAction?) -> Bool {
        preset == .off || alert != nil
    }

    /// Whether the picker can be used at all. With no first alert it is
    /// disabled, unless a hand-written ladder exists, so that Off can still
    /// remove it.
    public static func isPickerEnabled(for escalation: Escalation?, alert: AlertAction?) -> Bool {
        alert != nil || escalation != nil
    }

    // MARK: - What the repeat plays

    /// What a repeat plays, and what a switched-on final step starts as.
    ///
    /// The first of `candidates` that is not silent wins, so what the user
    /// already set is kept. A silent one counts as absent: only a
    /// hand-written file can hold one, the loader refuses it, and keeping it
    /// would leave the rule refused after a preset was chosen. Failing those,
    /// it is derived from the first alert: its sound without its speech, so
    /// a sentence that comes with a sound is not read out twenty times; else
    /// its speech, since a rule that only speaks has chosen nothing else; else,
    /// for a silent first alert, the default sound at 0 dB.
    public static func derivedAction(candidates: [AlertAction?], firstAlert: AlertAction?,
                                     defaultSound: String) -> AlertAction {
        if let kept = candidates.lazy.compactMap({ $0 }).first(where: { $0 != .silent }) { return kept }
        switch firstAlert {
        case .sound(let name, let gainDB)?, .soundAndSpeak(let name, let gainDB, _)?:
            return .sound(name: name, gainDB: gainDB)
        case .speak(let speech)?:
            return .speak(speech)
        case .silent?, nil:
            return .sound(name: defaultSound, gainDB: 0)
        }
    }

    // MARK: - What is set aside

    /// Everything the ladder controls drop, held above the disclosure by the
    /// view and reset with each rule, so that choosing back restores it. Each
    /// value has its own slot: a tier's alert editor has a set-aside of its
    /// own, independent of tier 1's and of the other tier's.
    public struct SetAside: Equatable, Sendable {
        /// Tiers 2 to 4, whole, as last dropped.
        public var tier2: PanelAlert?
        public var tier3: RepeatAlert?
        public var tier4: FinalAlert?
        /// The repeat limit and the time limit, each as its own number, so
        /// "no limit" and then un-ticking restores the number and not a
        /// default.
        public var maxRepeats: Int?
        public var maxDurationSeconds: Double?
        /// Tier 4's alert while a Shortcut is chosen, and its Shortcut's name
        /// while an alert is, so neither is lost by trying the other.
        public var finalAlert: AlertAction?
        public var shortcutName: String?
        /// The Custom ladder, set aside by choosing a preset over it, or by
        /// removing a ladder, whole: tier 4 included.
        public var custom: Escalation?
        /// What each later alert's own choices have set aside.
        public var tier3Alert = AlertEditing.SetAside()
        public var tier4Alert = AlertEditing.SetAside()

        public init() {}

        /// Whether any tier is set aside.
        public var holdsLadder: Bool { tier2 != nil || tier3 != nil || tier4 != nil }

        /// Adds what `ladder` holds, keeping what was set aside before: a tier
        /// that is absent from `ladder` does not clear its slot. A silent alert
        /// and a blank Shortcut name are not kept in the slots that restore an
        /// alert or a name.
        func keeping(_ ladder: Escalation?) -> SetAside {
            guard let ladder else { return self }
            var kept = self
            if let tier2 = ladder.tier2 { kept.tier2 = tier2 }
            if let tier3 = ladder.tier3 {
                kept.tier3 = tier3
                if let repeats = tier3.maxRepeats { kept.maxRepeats = repeats }
                if let duration = tier3.maxDurationSeconds { kept.maxDurationSeconds = duration }
            }
            if let tier4 = ladder.tier4 {
                kept.tier4 = tier4
                switch tier4.action {
                case .alert(let alert) where alert != .silent: kept.finalAlert = alert
                case .shortcut(let name) where !EscalationEditing.isBlank(name): kept.shortcutName = name
                case .alert, .shortcut: break
                }
            }
            return kept
        }
    }

    /// A ladder, and what is set aside beside it: what a control produces.
    ///
    /// An edit carries no field of the rule beside its ladder, which is how no
    /// control reaches `quietWhenSnoozed` (M5 plan, Ruling 3). A test pins the
    /// two fields.
    public struct Edit: Equatable, Sendable {
        public var escalation: Escalation?
        public var setAside: SetAside

        public init(escalation: Escalation?, setAside: SetAside) {
            self.escalation = escalation
            self.setAside = setAside
        }
    }

    // MARK: - Choosing a preset

    /// What choosing a segment does.
    public enum Choice: Equatable, Sendable {
        case changed(Edit)
        /// Off over a ladder that holds a Shortcut: nothing yet. The view
        /// asks inline, with the picker where it was, and `answeringOff`
        /// decides what the answer does.
        case needsConfirmation(shortcutName: String)
        /// The preset is already shown, or it is not available.
        case unchanged
    }

    /// Choosing a preset.
    ///
    /// A preset owns tiers 2 and 3 and leaves tier 4 alone, so a Shortcut
    /// beside a preset stays. The repeat plays what the ladder's own repeat
    /// plays, else what was set aside, else what `derivedAction` makes of the
    /// first alert, a silent one counting as none. Choosing a preset over a
    /// Custom ladder sets the whole ladder aside as the Custom ladder. Over
    /// Off, tier 4 comes back from what was set aside, unless it is a silent
    /// alert or a blank Shortcut name.
    ///
    /// Off drops the ladder, and a Shortcut with it, which is why it asks once
    /// when there is one: the phone page is the alert that matters most, and
    /// a slip would discard a name the user may not have written down.
    public static func choose(_ preset: Preset, escalation: Escalation?, setAside: SetAside,
                              firstAlert: AlertAction?, defaultSound: String) -> Choice {
        if preset == .off {
            guard let escalation else { return .unchanged }
            if let name = escalation.tier4?.action.shortcutName { return .needsConfirmation(shortcutName: name) }
            // Over a bare preset the tiers go aside, and choosing a preset
            // again brings them back. Over a Custom ladder, the whole ladder
            // goes aside too, for Custom to restore.
            return .changed(dropping(escalation, setAside: setAside, asCustom: shown(for: escalation) == .custom))
        }
        guard isAvailable(preset, forAlert: firstAlert), shown(for: escalation) != .preset(preset) else {
            return .unchanged
        }

        var aside = setAside.keeping(escalation)
        if let escalation, !escalation.isEmpty, shown(for: escalation) == .custom { aside.custom = escalation }

        let action = derivedAction(candidates: [escalation?.tier3?.action, setAside.tier3?.action],
                                   firstAlert: firstAlert, defaultSound: defaultSound)
        var ladder = preset.ladder(repeating: action) ?? Escalation()
        if let escalation, !escalation.isEmpty {
            ladder.tier4 = escalation.tier4
        } else if let held = setAside.tier4, isRestorable(held) {
            ladder.tier4 = held
        }
        return .changed(Edit(escalation: ladder, setAside: aside))
    }

    /// Choosing a segment of the picker, whichever it is.
    public static func choose(_ shown: Shown, escalation: Escalation?, setAside: SetAside,
                              firstAlert: AlertAction?, defaultSound: String) -> Choice {
        switch shown {
        case .preset(let preset):
            return choose(preset, escalation: escalation, setAside: setAside, firstAlert: firstAlert,
                          defaultSound: defaultSound)
        case .custom:
            return chooseCustom(escalation: escalation, setAside: setAside)
        }
    }

    /// Choosing Custom: the custom ladder that was set aside, exactly, tier 4
    /// included. The ladder it replaces goes aside tier by tier. Does nothing
    /// when the ladder is already custom, or when none is set aside.
    public static func chooseCustom(escalation: Escalation?, setAside: SetAside) -> Choice {
        guard let custom = setAside.custom, shown(for: escalation) != .custom else { return .unchanged }
        return .changed(Edit(escalation: custom, setAside: setAside.keeping(escalation)))
    }

    /// What the inline question's two buttons do.
    public enum OffAnswer: Sendable {
        /// Drop the ladder, the Shortcut with it.
        case remove
        /// Leave everything as it was.
        case keep
    }

    /// Remove sets the whole ladder aside as the Custom ladder, so the Custom
    /// segment restores it exactly, tier 4 included. Keep changes nothing.
    public static func answeringOff(_ answer: OffAnswer, escalation: Escalation?, setAside: SetAside) -> Edit {
        switch answer {
        case .keep:
            return Edit(escalation: escalation, setAside: setAside)
        case .remove:
            guard let escalation else { return Edit(escalation: nil, setAside: setAside) }
            return dropping(escalation, setAside: setAside, asCustom: true)
        }
    }

    /// Off: the tiers go aside, and the ladder too when it should come back
    /// as it was. An empty ladder has nothing to bring back.
    private static func dropping(_ ladder: Escalation, setAside: SetAside, asCustom: Bool) -> Edit {
        var aside = setAside.keeping(ladder)
        if asCustom, !ladder.isEmpty { aside.custom = ladder }
        return Edit(escalation: nil, setAside: aside)
    }

    // MARK: - Tiers

    /// Tier 2 on or off. Switched on, it comes back as it was set aside, or
    /// with the default delay. Switching off the last tier is Off, and
    /// switching on the first from Off builds that tier alone.
    public static func settingTier2(_ on: Bool, in escalation: Escalation?, setAside: SetAside) -> Edit {
        var ladder = escalation ?? Escalation()
        var aside = setAside
        if on {
            guard ladder.tier2 == nil else { return Edit(escalation: escalation, setAside: setAside) }
            ladder.tier2 = setAside.tier2 ?? PanelAlert()
        } else {
            guard let tier2 = ladder.tier2 else { return Edit(escalation: escalation, setAside: setAside) }
            aside.tier2 = tier2
            ladder.tier2 = nil
        }
        return Edit(escalation: normalised(ladder), setAside: aside)
    }

    /// Tier 3 on or off. Switched on, it comes back whole from what was set
    /// aside, unless that repeat was silent, in which case it starts as the
    /// derived action at the default timings.
    public static func settingTier3(_ on: Bool, in escalation: Escalation?, setAside: SetAside,
                                    firstAlert: AlertAction?, defaultSound: String) -> Edit {
        var ladder = escalation ?? Escalation()
        var aside = setAside
        if on {
            guard ladder.tier3 == nil else { return Edit(escalation: escalation, setAside: setAside) }
            if let held = setAside.tier3, held.action != .silent {
                ladder.tier3 = held
            } else {
                let action = derivedAction(candidates: [], firstAlert: firstAlert, defaultSound: defaultSound)
                ladder.tier3 = RepeatAlert(action: action)
            }
        } else {
            guard ladder.tier3 != nil else { return Edit(escalation: escalation, setAside: setAside) }
            aside = aside.keeping(Escalation(tier3: ladder.tier3))
            ladder.tier3 = nil
        }
        return Edit(escalation: normalised(ladder), setAside: aside)
    }

    /// Tier 4 on or off. Switched on, it comes back whole from what was set
    /// aside, unless that was a silent alert or a blank Shortcut name, in
    /// which case it starts as an alert derived as a preset's repeat is: never
    /// silent, and never a blank Shortcut name.
    public static func settingTier4(_ on: Bool, in escalation: Escalation?, setAside: SetAside,
                                    firstAlert: AlertAction?, defaultSound: String) -> Edit {
        var ladder = escalation ?? Escalation()
        var aside = setAside
        if on {
            guard ladder.tier4 == nil else { return Edit(escalation: escalation, setAside: setAside) }
            if let held = setAside.tier4, isRestorable(held) {
                ladder.tier4 = held
            } else {
                let action = derivedAction(candidates: [setAside.finalAlert, ladder.tier3?.action, setAside.tier3?.action],
                                           firstAlert: firstAlert, defaultSound: defaultSound)
                ladder.tier4 = FinalAlert(action: .alert(action))
            }
        } else {
            guard ladder.tier4 != nil else { return Edit(escalation: escalation, setAside: setAside) }
            aside = aside.keeping(Escalation(tier4: ladder.tier4))
            ladder.tier4 = nil
        }
        return Edit(escalation: normalised(ladder), setAside: aside)
    }

    // MARK: - Values

    /// The least a time the controls write: one second.
    public static let minimumSeconds: Double = 1
    /// The fewest repeats the controls write: one.
    public static let minimumRepeats = 1

    /// A time as a control writes it: at least one second, and finite, since a
    /// file cannot hold anything else. The loader's messages about zero and
    /// negative values are therefore reachable only from a hand-written file.
    public static func clampedSeconds(_ seconds: Double) -> Double {
        if seconds.isNaN { return minimumSeconds }
        return min(max(seconds, minimumSeconds), Double.greatestFiniteMagnitude)
    }

    /// A count of repeats as a control writes it: at least one.
    public static func clampedRepeats(_ repeats: Int) -> Int {
        max(repeats, minimumRepeats)
    }

    /// Typed seconds: nil unless the text is a finite number, so a half-typed
    /// value writes nothing.
    public static func parseSeconds(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else { return nil }
        return value
    }

    /// A typed count: nil unless the text is a whole number.
    public static func parseCount(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A new time over an old one. The value already there is kept as it is,
    /// out of range or not: only an edit is clamped.
    private static func written(_ seconds: Double, over old: Double) -> Double {
        seconds == old ? old : clampedSeconds(seconds)
    }

    /// Tier 2's delay. Nothing changes when there is no tier 2.
    public static func settingDelay(_ seconds: Double, in escalation: Escalation?) -> Escalation? {
        guard var ladder = escalation, let tier2 = ladder.tier2 else { return escalation }
        ladder.tier2 = PanelAlert(delaySeconds: written(seconds, over: tier2.delaySeconds))
        return ladder
    }

    /// Tier 3's alert, as its alert editor writes it. Nothing changes when
    /// there is no tier 3, or when the editor writes no alert at all, which
    /// a step after the first has no kind for.
    public static func settingRepeatAction(_ action: AlertAction?, in escalation: Escalation?) -> Escalation? {
        guard let action, var ladder = escalation, ladder.tier3 != nil else { return escalation }
        ladder.tier3?.action = action
        return ladder
    }

    /// The time between repeats.
    public static func settingInterval(_ seconds: Double, in escalation: Escalation?) -> Escalation? {
        guard var ladder = escalation, let tier3 = ladder.tier3 else { return escalation }
        ladder.tier3?.intervalSeconds = written(seconds, over: tier3.intervalSeconds)
        return ladder
    }

    /// The most repeats. Writing a number is asking for a limit.
    public static func settingMaxRepeats(_ repeats: Int, in escalation: Escalation?) -> Escalation? {
        guard var ladder = escalation, let tier3 = ladder.tier3 else { return escalation }
        ladder.tier3?.maxRepeats = tier3.maxRepeats == repeats ? repeats : clampedRepeats(repeats)
        return ladder
    }

    /// The longest the repeats go on. Writing a number is asking for a limit.
    public static func settingMaxDuration(_ seconds: Double, in escalation: Escalation?) -> Escalation? {
        guard var ladder = escalation, let tier3 = ladder.tier3 else { return escalation }
        if let old = tier3.maxDurationSeconds {
            ladder.tier3?.maxDurationSeconds = written(seconds, over: old)
        } else {
            ladder.tier3?.maxDurationSeconds = clampedSeconds(seconds)
        }
        return ladder
    }

    /// The two limits on a repeat.
    public enum Limit: Hashable, Sendable { case repeats, duration }

    /// "No limit" on one limit, or the limit back. Un-ticking restores that
    /// limit's own number, from what was set aside, and only that limit's:
    /// the other is left as it is. With nothing set aside it is the default.
    public static func settingNoLimit(_ noLimit: Bool, on limit: Limit, in escalation: Escalation?,
                                      setAside: SetAside) -> Edit {
        guard var ladder = escalation, let tier3 = ladder.tier3 else {
            return Edit(escalation: escalation, setAside: setAside)
        }
        var aside = setAside
        switch (limit, noLimit) {
        case (.repeats, true):
            guard let held = tier3.maxRepeats else { return Edit(escalation: escalation, setAside: setAside) }
            aside.maxRepeats = held
            ladder.tier3?.maxRepeats = nil
        case (.repeats, false):
            guard tier3.maxRepeats == nil else { return Edit(escalation: escalation, setAside: setAside) }
            ladder.tier3?.maxRepeats = setAside.maxRepeats ?? RepeatAlert.defaultMaxRepeats
        case (.duration, true):
            guard let held = tier3.maxDurationSeconds else { return Edit(escalation: escalation, setAside: setAside) }
            aside.maxDurationSeconds = held
            ladder.tier3?.maxDurationSeconds = nil
        case (.duration, false):
            guard tier3.maxDurationSeconds == nil else { return Edit(escalation: escalation, setAside: setAside) }
            ladder.tier3?.maxDurationSeconds = setAside.maxDurationSeconds ?? RepeatAlert.defaultMaxDurationSeconds
        }
        return Edit(escalation: ladder, setAside: aside)
    }

    /// Tier 4's delay. Nothing changes when there is no tier 4.
    public static func settingFinalDelay(_ seconds: Double, in escalation: Escalation?) -> Escalation? {
        guard var ladder = escalation, let tier4 = ladder.tier4 else { return escalation }
        ladder.tier4?.afterSeconds = written(seconds, over: tier4.afterSeconds)
        return ladder
    }

    /// What tier 4 is: an alert or a Shortcut.
    public enum FinalKind: CaseIterable, Hashable, Sendable { case alert, shortcut }

    public static func kind(of action: FinalAction) -> FinalKind {
        switch action {
        case .alert: return .alert
        case .shortcut: return .shortcut
        }
    }

    /// Tier 4's choice between an alert and a Shortcut. Each sets itself aside
    /// when the other is chosen, so neither is lost by trying the other. An
    /// alert comes back as it was, or derived when there was none; a Shortcut
    /// comes back with its name, or with none yet, to be typed.
    public static func choosingFinal(_ kind: FinalKind, in escalation: Escalation?, setAside: SetAside,
                                     firstAlert: AlertAction?, defaultSound: String) -> Edit {
        guard var ladder = escalation, let tier4 = ladder.tier4, Self.kind(of: tier4.action) != kind else {
            return Edit(escalation: escalation, setAside: setAside)
        }
        var aside = setAside
        switch (tier4.action, kind) {
        case (.alert(let alert), .shortcut):
            if alert != .silent { aside.finalAlert = alert }
            ladder.tier4?.action = .shortcut(name: setAside.shortcutName ?? "")
        case (.shortcut(let name), .alert):
            if !isBlank(name) { aside.shortcutName = name }
            let alert = derivedAction(candidates: [setAside.finalAlert, ladder.tier3?.action, setAside.tier3?.action],
                                      firstAlert: firstAlert, defaultSound: defaultSound)
            ladder.tier4?.action = .alert(alert)
        default:
            break
        }
        return Edit(escalation: ladder, setAside: aside)
    }

    /// Tier 4's alert, as its alert editor writes it. Nothing changes unless
    /// tier 4 is an alert, or when the editor writes no alert at all.
    public static func settingFinalAlert(_ alert: AlertAction?, in escalation: Escalation?) -> Escalation? {
        guard let alert, var ladder = escalation, case .alert? = ladder.tier4?.action else { return escalation }
        ladder.tier4?.action = .alert(alert)
        return ladder
    }

    /// Tier 4's Shortcut name, as typed. Nothing changes unless tier 4 is a
    /// Shortcut. A blank name is a problem the editor reports, not one it
    /// prevents typing.
    public static func settingShortcutName(_ name: String, in escalation: Escalation?) -> Escalation? {
        guard var ladder = escalation, case .shortcut? = ladder.tier4?.action else { return escalation }
        ladder.tier4?.action = .shortcut(name: name)
        return ladder
    }

    /// Whether a limit is "No limit". False when there is no repeat to limit.
    public static func hasNoLimit(on limit: Limit, in escalation: Escalation?) -> Bool {
        guard let tier3 = escalation?.tier3 else { return false }
        switch limit {
        case .repeats: return tier3.maxRepeats == nil
        case .duration: return tier3.maxDurationSeconds == nil
        }
    }

    // MARK: - Typed numbers

    /// The five numbers of a ladder that a user types: a time in seconds, and
    /// the most repeats.
    public enum NumberField: CaseIterable, Hashable, Sendable {
        case tier2Delay
        case tier3Interval
        case tier3MaxRepeats
        case tier3MaxDuration
        case tier4Delay
    }

    /// A time in seconds that `field` holds, or nil when the ladder holds none:
    /// there is no such tier, the field is a count, or its limit is "No limit".
    public static func seconds(of field: NumberField, in escalation: Escalation?) -> Double? {
        switch field {
        case .tier2Delay: return escalation?.tier2?.delaySeconds
        case .tier3Interval: return escalation?.tier3?.intervalSeconds
        case .tier3MaxDuration: return escalation?.tier3?.maxDurationSeconds
        case .tier4Delay: return escalation?.tier4?.afterSeconds
        case .tier3MaxRepeats: return nil
        }
    }

    /// The number as its field shows it, or nil when the ladder holds none.
    /// Any value the type can hold is shown as it is, 0, a negative and a
    /// fraction included, so that a hand-written problem can be fixed here.
    public static func fieldText(_ field: NumberField, in escalation: Escalation?) -> String? {
        if field == .tier3MaxRepeats { return escalation?.tier3?.maxRepeats.map(EditorText.fieldText(count:)) }
        return seconds(of: field, in: escalation).map(EditorText.fieldText(seconds:))
    }

    /// Whether `text` is what a control would have written to make the number
    /// the ladder holds: the text typed as it is, or clamped as an edit is.
    /// A field asks it when the ladder changes under it, to tell its own
    /// edit, which it leaves alone, from a change made elsewhere, which it
    /// shows. Text that is not a number stands for nothing, so half-typed
    /// text is replaced when the ladder changes, and is never mistaken for
    /// an edit.
    public static func textStandsFor(_ text: String, field: NumberField, in escalation: Escalation?) -> Bool {
        if field == .tier3MaxRepeats {
            guard let held = escalation?.tier3?.maxRepeats, let typed = parseCount(text) else { return false }
            return typed == held || clampedRepeats(typed) == held
        }
        guard let held = seconds(of: field, in: escalation), let typed = parseSeconds(text) else { return false }
        return typed == held || clampedSeconds(typed) == held
    }

    /// The ladder after `text` was typed into `field`. Only an edit writes:
    /// text that is not yet a number writes nothing, and one that is the
    /// number the ladder holds leaves it as it is, out of range or not,
    /// because each setter keeps a number equal to the one it would replace.
    /// A number that is written is clamped, as the controls write.
    public static func typing(_ text: String, into field: NumberField, of escalation: Escalation?) -> Escalation? {
        if field == .tier3MaxRepeats {
            guard let typed = parseCount(text) else { return escalation }
            return settingMaxRepeats(typed, in: escalation)
        }
        guard let typed = parseSeconds(text) else { return escalation }
        switch field {
        case .tier2Delay: return settingDelay(typed, in: escalation)
        case .tier3Interval: return settingInterval(typed, in: escalation)
        case .tier3MaxDuration: return settingMaxDuration(typed, in: escalation)
        case .tier4Delay: return settingFinalDelay(typed, in: escalation)
        case .tier3MaxRepeats: return escalation
        }
    }

    // MARK: - What the view asks

    /// Whether the Customise disclosure starts open: only while the ladder is
    /// Custom, since then the four presets cannot say what the ladder is.
    /// After that it follows the user.
    public static func customiseStartsOpen(for escalation: Escalation?) -> Bool {
        shown(for: escalation) == .custom
    }

    /// Where the note that the Mac's sound output is muted is shown, so that
    /// it is shown once for a rule and not once for each alert it holds: with
    /// the first alert, when that alert makes a sound or speaks; else with the
    /// ladder, when a repeat or a final alert does; else nowhere, since there
    /// is nothing to hear.
    public enum NoteSite: Equatable, Sendable {
        case firstAlert
        case ladder
    }

    public static func mutedOutputNoteSite(firstAlert: AlertAction?, escalation: Escalation?) -> NoteSite? {
        if makesSound(firstAlert) { return .firstAlert }
        if let escalation, escalation.alerts.contains(where: { makesSound($0.action) }) { return .ladder }
        return nil
    }

    private static func makesSound(_ alert: AlertAction?) -> Bool {
        alert?.soundName != nil || alert?.speech != nil
    }

    // MARK: - Helpers

    /// A ladder with no tier left is Off.
    private static func normalised(_ ladder: Escalation) -> Escalation? {
        ladder.isEmpty ? nil : ladder
    }

    fileprivate static func isBlank(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether a set-aside tier 4 may come back: not a silent alert and not a
    /// blank Shortcut name, which the loader refuses and which would switch
    /// the whole rule off.
    private static func isRestorable(_ tier4: FinalAlert) -> Bool {
        switch tier4.action {
        case .alert(let alert): return alert != .silent
        case .shortcut(let name): return !isBlank(name)
        }
    }
}
