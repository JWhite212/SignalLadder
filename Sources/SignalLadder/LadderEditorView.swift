// Sources/SignalLadder/LadderEditorView.swift
import SwiftUI
import NotificationCore

/// What happens after a rule's first alert if nobody acknowledges it: a choice
/// between four presets, a sentence that says what the ladder is, and, behind
/// Customise, every control of tiers 2 to 4.
///
/// Thin by design, and held to it: this file may hold no word of its own (the
/// strict list in `ViewLiteralsTests`), so every label and sentence is
/// `EditorText`'s, and every change a control makes is an
/// `EscalationEditing` function, tested in the core. The view holds what the
/// controls set aside, which is state of this view and not of the rule, so
/// that choosing back restores what was chosen before and not a default. It
/// lives above the disclosure, which may discard what is inside it when it is
/// collapsed, and is reset with each rule, since `RuleEditorView` gives every
/// rule's detail an identity of its own.
struct LadderEditorView: View {
    @ObservedObject var model: RuleEditorModel
    @Binding var rule: Rule
    /// Everything the ladder's controls have dropped, whole, to restore.
    @State private var setAside = EscalationEditing.SetAside()
    /// The Shortcut that Off is waiting to remove, while the inline question
    /// is asked. The question is dropped by any change to the ladder, so a
    /// stale one never survives an edit made under it.
    @State private var confirmingOff: String?
    /// Whether Customise is open: at first only when the ladder is Custom,
    /// then wherever the user leaves it.
    @State private var customiseOpen: Bool
    /// Counts the clicks on the choice. A click that leaves the ladder as it
    /// was, on a preset already chosen or one that cannot be, would leave the
    /// control showing the segment clicked, since nothing the view reads has
    /// changed. The choice reads the count and every click changes it, so
    /// every click asks the control to show the ladder again.
    @State private var clicks = 0

    init(model: RuleEditorModel, rule: Binding<Rule>) {
        self.model = model
        _rule = rule
        _customiseOpen = State(initialValue: EscalationEditing.customiseStartsOpen(for: rule.wrappedValue.escalation))
    }

    // MARK: - The choice and the sentence

    var body: some View {
        let escalation = rule.escalation
        let usable = EscalationEditing.isPickerEnabled(for: escalation, alert: rule.alert)
        VStack(alignment: .leading, spacing: 8) {
            Text(EditorText.ifIDontAcknowledge)
                .font(.subheadline.weight(.medium))
                .padding(.top, 8)

            Picker(selection: choice) {
                ForEach(EscalationEditing.segments(for: escalation, setAside: setAside), id: \.self) {
                    Text(EditorText.segmentName($0)).tag($0)
                }
            } label: {
                Text(EditorText.label(.ladderChoice))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(EditorText.label(.ladderChoice))
            .disabled(!usable)

            if let hint = EditorText.presetHint(forAlert: rule.alert) {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }

            Text(EditorText.underChoice(escalation: escalation, setAside: setAside, confirmingShortcut: confirmingOff))
                .font(.callout)
                .foregroundStyle(confirmingOff == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)

            if confirmingOff != nil {
                HStack(spacing: 10) {
                    Button(EditorText.removeLadder, role: .destructive) { answerOff(.remove) }
                    Button(EditorText.keepLadder) { answerOff(.keep) }
                }
            }

            if let nudge = EditorText.shortcutNudge(shown: EscalationEditing.shown(for: escalation),
                                                    escalation: escalation) {
                Text(nudge).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if EscalationEditing.mutedOutputNoteSite(firstAlert: rule.alert, escalation: escalation) == .ladder,
               model.outputIsSilent {
                Label(EditorText.outputSilentNote, systemImage: "speaker.slash")
                    .foregroundStyle(.orange).font(.callout)
            }

            DisclosureGroup(isExpanded: $customiseOpen) {
                tiers
            } label: {
                Text(EditorText.customise)
            }
            .disabled(!usable)
            .padding(.top, 4)
        }
        // The question belongs to the ladder it was asked of.
        .onChange(of: rule.escalation) { _, _ in confirmingOff = nil }
    }

    private var choice: Binding<EscalationEditing.Shown> {
        Binding(
            get: { _ = clicks; return EscalationEditing.shown(for: rule.escalation) },
            set: { choose($0) })
    }

    private func choose(_ shown: EscalationEditing.Shown) {
        clicks += 1
        confirmingOff = nil
        switch EscalationEditing.choose(shown, escalation: rule.escalation, setAside: setAside,
                                        firstAlert: rule.alert, defaultSound: model.defaultSound) {
        case .changed(let edit): apply(edit)
        case .needsConfirmation(let name): confirmingOff = name
        case .unchanged: break
        }
    }

    private func answerOff(_ answer: EscalationEditing.OffAnswer) {
        apply(EscalationEditing.answeringOff(answer, escalation: rule.escalation, setAside: setAside))
        confirmingOff = nil
    }

    private func apply(_ edit: EscalationEditing.Edit) {
        rule.escalation = edit.escalation
        setAside = edit.setAside
    }

    // MARK: - The tiers

    private var tiers: some View {
        VStack(alignment: .leading, spacing: 14) {
            tier2
            tier3
            tier4
        }
        // Full width and indented under its heading: a disclosure's content
        // is otherwise set in a column beside the heading's own words.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.top, 8)
    }

    private func tierSwitch(_ tier: Int, label: EditorText.Control, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Text(EditorText.tierHeading(tier)).fontWeight(.semibold)
                Text(EditorText.tierSummary(tier)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .accessibilityLabel(EditorText.label(label))
    }

    private var tier2: some View {
        VStack(alignment: .leading, spacing: 6) {
            tierSwitch(2, label: .tier2Switch, isOn: Binding(
                get: { rule.escalation?.tier2 != nil },
                set: { apply(EscalationEditing.settingTier2($0, in: rule.escalation, setAside: setAside)) }))
            if rule.escalation?.tier2 != nil {
                lone(.tier2Delay)
                    .padding(.leading, 20)
            }
        }
    }

    private var tier3: some View {
        VStack(alignment: .leading, spacing: 8) {
            tierSwitch(3, label: .tier3Switch, isOn: Binding(
                get: { rule.escalation?.tier3 != nil },
                set: {
                    apply(EscalationEditing.settingTier3($0, in: rule.escalation, setAside: setAside,
                                                         firstAlert: rule.alert, defaultSound: model.defaultSound))
                }))
            if rule.escalation?.tier3 != nil {
                VStack(alignment: .leading, spacing: 8) {
                    AlertEditorView(model: model, action: repeatAction, setAside: $setAside.tier3Alert,
                                    kinds: AlertEditing.offeredKinds(for: .repeating), role: .repeating,
                                    showsMutedOutputNote: false)
                    numbers
                    if let caption = EditorText.unlimitedRepeatCaption(for: rule.escalation) {
                        Text(caption).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    /// The interval and the two limits, in one grid, so that their words,
    /// numbers, units, captions in minutes and No limit boxes are each in a
    /// column of their own and the boxes line up with each other. A hint
    /// stands under the limit it is about.
    private var numbers: some View {
        Grid(alignment: .leading, horizontalSpacing: Self.columnGap, verticalSpacing: Self.rowGap) {
            GridRow {
                lead(.tier3Interval)
                NumberFieldView(field: .tier3Interval, escalation: $rule.escalation)
            }
            limitRows(.tier3MaxRepeats, .repeats, noLimitLabel: .tier3NoRepeatLimit)
            limitRows(.tier3MaxDuration, .duration, noLimitLabel: .tier3NoTimeLimit)
        }
    }

    /// The space between the cells of a row of numbers, on its own or in the
    /// grid of tier 3, and the space before a No limit box, which is that gap
    /// and what makes up the difference.
    private static let columnGap: CGFloat = 6
    private static let boxGap: CGFloat = 16
    /// The space between rows of the grid, and how much nearer a hint is drawn
    /// to the row it is about than the rows are to each other.
    private static let rowGap: CGFloat = 8
    private static let hintLift: CGFloat = 6

    /// The word before a number: "After", "Every", "At most", "Stop after".
    private func lead(_ field: EscalationEditing.NumberField) -> some View {
        Text(EditorText.fieldLead(field))
    }

    /// A number on its own: a grid of one row, laid out as the same cells are
    /// among others.
    private func lone(_ field: EscalationEditing.NumberField) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Self.columnGap) {
            GridRow {
                lead(field)
                NumberFieldView(field: field, escalation: $rule.escalation)
            }
        }
    }

    /// One limit on the repeats, as the rows of a grid: its word, its number
    /// while it has one, and its No limit box in the column the other limit's
    /// is in, which keeps the number it sets aside. While the limit is off the
    /// cells of its number are left empty, so that its word and its box stay in
    /// their columns.
    @ViewBuilder
    private func limitRows(_ field: EscalationEditing.NumberField, _ limit: EscalationEditing.Limit,
                           noLimitLabel: EditorText.Control) -> some View {
        GridRow {
            lead(field)
            if EscalationEditing.hasNoLimit(on: limit, in: rule.escalation) {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                    .gridCellColumns(NumberFieldView.cellCount)
            } else {
                NumberFieldView(field: field, escalation: $rule.escalation)
            }
            Toggle(EditorText.noLimit, isOn: Binding(
                get: { EscalationEditing.hasNoLimit(on: limit, in: rule.escalation) },
                set: {
                    apply(EscalationEditing.settingNoLimit($0, on: limit, in: rule.escalation, setAside: setAside))
                }))
                .toggleStyle(.checkbox)
                .accessibilityLabel(EditorText.label(noLimitLabel))
                .padding(.leading, Self.boxGap - Self.columnGap)
        }
        if let hint = EditorText.noLimitHint(limit, in: rule.escalation) {
            Text(hint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -Self.hintLift)
        }
    }

    private var repeatAction: Binding<AlertAction?> {
        Binding(
            get: { rule.escalation?.tier3?.action },
            set: { rule.escalation = EscalationEditing.settingRepeatAction($0, in: rule.escalation) })
    }

    private var tier4: some View {
        VStack(alignment: .leading, spacing: 8) {
            tierSwitch(4, label: .tier4Switch, isOn: Binding(
                get: { rule.escalation?.tier4 != nil },
                set: {
                    apply(EscalationEditing.settingTier4($0, in: rule.escalation, setAside: setAside,
                                                         firstAlert: rule.alert, defaultSound: model.defaultSound))
                }))
            if let tier4 = rule.escalation?.tier4 {
                VStack(alignment: .leading, spacing: 8) {
                    lone(.tier4Delay)
                    Picker(selection: finalKind) {
                        ForEach(EscalationEditing.FinalKind.allCases, id: \.self) {
                            Text(EditorText.finalKindName($0)).tag($0)
                        }
                    } label: {
                        Text(EditorText.label(.tier4Kind))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel(EditorText.label(.tier4Kind))

                    switch tier4.action {
                    case .alert:
                        AlertEditorView(model: model, action: finalAlert, setAside: $setAside.tier4Alert,
                                        kinds: AlertEditing.offeredKinds(for: .final), role: .final,
                                        showsMutedOutputNote: false)
                    case .shortcut(let name):
                        shortcutControls(name: name)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    private var finalKind: Binding<EscalationEditing.FinalKind> {
        Binding(
            get: { rule.escalation?.tier4.map { EscalationEditing.kind(of: $0.action) } ?? .alert },
            set: {
                apply(EscalationEditing.choosingFinal($0, in: rule.escalation, setAside: setAside,
                                                      firstAlert: rule.alert, defaultSound: model.defaultSound))
            })
    }

    private var finalAlert: Binding<AlertAction?> {
        Binding(
            get: { rule.escalation?.tier4?.action.alertAction },
            set: { rule.escalation = EscalationEditing.settingFinalAlert($0, in: rule.escalation) })
    }

    // MARK: - A Shortcut

    private var shortcutName: Binding<String> {
        Binding(
            get: { rule.escalation?.tier4?.action.shortcutName ?? "" },
            set: { rule.escalation = EscalationEditing.settingShortcutName($0, in: rule.escalation) })
    }

    /// The name, a button that really runs it, how that ended, and, when the
    /// Shortcuts app does not list the name, the advice on what that means.
    /// The advice is shown for a draft that is not saved and for a rule with
    /// other problems as well, and says nothing of whether the rule is in
    /// effect, which the dry-run's line below says. Names are free text, so
    /// the advice is how a typo is found.
    @ViewBuilder
    private func shortcutControls(name: String) -> some View {
        HStack(spacing: 10) {
            TextField(EditorText.shortcutNamePrompt, text: shortcutName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .accessibilityLabel(EditorText.label(.tier4ShortcutName))
            Button(EditorText.testShortcut) { model.testShortcut(name: name) }
                .help(EditorText.testShortcutHelp)
                .disabled(!ShortcutTest.canRun(name: name, pending: model.isTestingShortcut))
                .accessibilityLabel(EditorText.label(.tier4TestShortcut))
        }
        if let report = ShortcutTest.shown(model.shortcutTest, forField: name) {
            Label(report.text, systemImage: report.started ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(report.started ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .font(.callout)
        }
        if !model.warnings(in: rule).isEmpty {
            Label(EditorText.shortcutNotFoundAdvice, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - A typed number

/// One number of the ladder, typed as text this view holds, as the cells of a
/// row of a grid: the field, the unit and the caption in minutes. A caller
/// puts them in a `GridRow` after the word that leads them, alone or beside
/// the cells of other rows, so that numbers that are shown together share
/// their columns.
/// The text is written back only when it is edited, so a value nobody edited,
/// out of range or not, is never rewritten, and half-typed text writes
/// nothing. What a number is worth, and whether the text still stands for it,
/// are `EscalationEditing`'s.
private struct NumberFieldView: View {
    /// How many cells it fills, every one of them: a number with no caption
    /// leaves the last empty, so that what follows is in the same column.
    static let cellCount = 3

    let field: EscalationEditing.NumberField
    @Binding var escalation: Escalation?
    @State private var text: String
    @FocusState private var focused: Bool

    init(field: EscalationEditing.NumberField, escalation: Binding<Escalation?>) {
        self.field = field
        _escalation = escalation
        _text = State(initialValue: EscalationEditing.fieldText(field, in: escalation.wrappedValue) ?? "")
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 84)
            .focused($focused)
            .accessibilityLabel(EditorText.fieldLabel(field))
            .onChange(of: text) { _, typed in write(typed) }
            // The ladder changed under the field, by a preset or a
            // restore: show what it holds now. Not when the text is the
            // edit that made it, which is the user's to finish typing.
            .onChange(of: escalation) { _, _ in
                if !EscalationEditing.textStandsFor(text, field: field, in: escalation) { settle() }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { settle() }
            }
            .onSubmit { settle() }
        Text(EditorText.fieldUnit(field))
        if let caption = EditorText.fieldCaption(field, in: escalation) {
            Text(caption).foregroundStyle(.secondary)
        } else {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
        }
    }

    private func write(_ typed: String) {
        let written = EscalationEditing.typing(typed, into: field, of: escalation)
        if written != escalation { escalation = written }
    }

    /// Shows what the ladder holds, as the field leaves the user's hands.
    private func settle() {
        if let held = EscalationEditing.fieldText(field, in: escalation), held != text { text = held }
    }
}
