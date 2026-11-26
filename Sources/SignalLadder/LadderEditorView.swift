// Sources/SignalLadder/LadderEditorView.swift
import SwiftUI
import NotificationCore

/// What a rule does, tier by tier: a choice between four presets for what
/// happens if nobody acknowledges, a sentence that says what the ladder is, and
/// then the ladder itself as four capsules, one for each tier, with the selected
/// tier's settings beneath (M7 plan, Stage 6b). Tier 1 is the rule's first
/// alert. A tier the rule has is a capsule in its colour, and one it has not is
/// an outline whose settings are the switch that turns it on. Until 1.3 the
/// first alert stood above the presets and tiers 2 to 4 were behind a
/// disclosure called Customise. After the ladder comes the box that
/// lets a snooze hold the whole rule, ladder included, with the sentences that say
/// what it does for this rule (M5 plan, Task 4, Ruling 12, O8).
///
/// Thin by design, and held to it: this file may hold no word of its own (the
/// strict list in `ViewLiteralsTests`), so every label and sentence is
/// `EditorText`'s, and every change a control makes is an
/// `EscalationEditing` function, tested in the core. The view holds what the
/// controls set aside, which is state of this view and not of the rule, so
/// that choosing back restores what was chosen before and not a default. All
/// four tiers' settings stay in the view and only the selected one is shown, so
/// a number half typed and a test's message are still there on coming back to
/// a tier. It is reset with each rule, since `RuleEditorView` gives every
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
    /// What the first alert's editor has set aside, which the rule's pane holds.
    @Binding var firstAlertSetAside: AlertEditing.SetAside
    /// The tier whose settings are shown: the first alert, until a capsule is chosen.
    @State private var selectedTier = LadderStrip.firstTier
    /// Counts the clicks on the choice. A click that leaves the ladder as it
    /// was, on a preset already chosen or one that cannot be, would leave the
    /// control showing the segment clicked, since nothing the view reads has
    /// changed. The choice reads the count and every click changes it, so
    /// every click asks the control to show the ladder again.
    @State private var clicks = 0

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

            // The preset called On call is not On-call mode, the switch in the
            // menu, and this says so beside it.
            if let note = EditorText.onCallPresetNote(shown: EscalationEditing.shown(for: escalation)) {
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            // Shown once for the rule, and here whichever alert it is about, the
            // first among them: a tier's settings are out of sight while another
            // tier is selected, and this must not be.
            if EscalationEditing.mutedOutputNoteSite(firstAlert: rule.alert, escalation: escalation) != nil,
               model.outputIsSilent {
                Label(EditorText.outputSilentNote, systemImage: "speaker.slash")
                    .font(.callout).faultOutlined()
            }

            capsules(usable: usable)
                .padding(.top, 4)
            tiers(usable: usable)

            snoozeSwitch
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
        case .changed(let edit):
            apply(edit)
            reselect(after: edit)
        case .needsConfirmation(let name): confirmingOff = name
        case .unchanged: break
        }
    }

    private func answerOff(_ answer: EscalationEditing.OffAnswer) {
        let edit = EscalationEditing.answeringOff(answer, escalation: rule.escalation, setAside: setAside)
        apply(edit)
        reselect(after: edit)
        confirmingOff = nil
    }

    /// A preset may have removed the tier whose settings were shown, and then
    /// the first alert's are shown instead, which is the core's to say. It is
    /// asked of the rule as the edit leaves it.
    private func reselect(after edit: EscalationEditing.Edit) {
        var edited = rule
        edited.escalation = edit.escalation
        selectedTier = LadderStrip(for: edited).selection(afterPreset: selectedTier)
    }

    private func apply(_ edit: EscalationEditing.Edit) {
        rule.escalation = edit.escalation
        setAside = edit.setAside
    }

    // MARK: - The tiers

    /// The ladder as four capsules. One the rule has is filled in its tier's
    /// colour, and one it has not is an outline, so the two differ by more than
    /// colour. The selected one has a line round it. While the ladder cannot be
    /// used, which is while the rule has no alert, tiers 2 to 4 cannot be chosen.
    /// A capsule's shape. A rounded rectangle and not `Capsule`, whose ends were
    /// drawn cut flat at this size when the editor was drawn offscreen.
    private static let capsule = RoundedRectangle(cornerRadius: 12, style: .continuous)

    private func capsules(usable: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(LadderStrip(for: rule).segments, id: \.tier) { segment in
                let isSelected = segment.tier == selectedTier
                Button { select(segment.tier) } label: {
                    HStack(spacing: 4) {
                        // A Shortcut that is not found is said in tier 4's
                        // settings, which are out of sight while another tier
                        // is selected, so its capsule is marked too.
                        if segment.tier == Self.finalTier, hasShortcutWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        Text(EditorText.tierHeading(segment.tier))
                    }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(segment.isOn ? AnyShapeStyle(NightWatchPalette.ink) : AnyShapeStyle(.primary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if segment.isOn {
                                Self.capsule.fill(NightWatchPalette.block(segment.tone))
                            } else {
                                Self.capsule.strokeBorder(.secondary, lineWidth: 1.5)
                            }
                        }
                        .padding(3)
                        .overlay {
                            if isSelected { Self.capsule.strokeBorder(.primary, lineWidth: 2) }
                        }
                        // A point of room, so the line is not cut at the button's edge.
                        .padding(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(segment.tier != LadderStrip.firstTier && !usable)
                .accessibilityLabel(EditorText.tierCapsule(segment.tier, isOn: segment.isOn))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityValue(segment.tier == Self.finalTier && hasShortcutWarning ? EditorText.shortcutNotFoundAdvice : "")
            }
        }
        .frame(maxWidth: 460)
    }

    private static let finalTier = 4

    /// Whether the rule's last step is a Shortcut the Shortcuts app does not list.
    private var hasShortcutWarning: Bool {
        rule.escalation?.tier4?.action.shortcutName != nil && !model.warnings(in: rule).isEmpty
    }

    /// Shows a tier's settings. The keyboard is taken from whatever field had
    /// it first, so a number being typed in the tier that is left is settled,
    /// and no key goes to a field that is out of sight.
    private func select(_ tier: Int) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        selectedTier = tier
    }

    /// The four tiers' settings, all of them in the view and one of them shown:
    /// the others have no height, cannot be reached and are not read out, and
    /// keep what was typed into them.
    private func tiers(usable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(LadderStrip(for: rule).segments, id: \.tier) { segment in
                let isShown = segment.tier == selectedTier
                settings(of: segment.tier)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: isShown ? nil : 0, alignment: .top)
                    .clipped()
                    .opacity(isShown ? 1 : 0)
                    .disabled(!isShown || (segment.tier != LadderStrip.firstTier && !usable))
                    .accessibilityHidden(!isShown)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func settings(of tier: Int) -> some View {
        switch tier {
        case 2: tier2
        case 3: tier3
        case 4: tier4
        default: tier1
        }
    }

    /// Tier 1 is the rule's first alert. It has no switch: its kind, None among
    /// them, is the choice beneath. The note that the output is muted is not
    /// shown here but above the capsules, where it is in view whichever tier is
    /// selected.
    private var tier1: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(EditorText.tierHeading(LadderStrip.firstTier)).fontWeight(.semibold)
                Text(EditorText.tierSummary(LadderStrip.firstTier)).foregroundStyle(.secondary)
            }
            AlertEditorView(model: model, action: $rule.alert, setAside: $firstAlertSetAside,
                            kinds: AlertEditing.offeredKinds(for: .first), role: .first,
                            showsMutedOutputNote: false)
        }
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
            // A test that did not start is a fault, as a sound's failed test is in
            // `AlertEditorView`: the page to the phone would not go.
            if report.started {
                Label(report.text, systemImage: "checkmark.circle").foregroundStyle(.secondary).font(.callout)
            } else {
                Label(report.text, systemImage: "exclamationmark.triangle").font(.callout).faultOutlined()
            }
        }
        if !model.warnings(in: rule).isEmpty {
            Label(EditorText.shortcutNotFoundAdvice, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .faultOutlined()
        }
    }

    // MARK: - The snooze

    /// The box that lets a snooze hold this rule, and what it does for it. It is
    /// never disabled: while the rule makes no sound or ends in a Shortcut the box
    /// does nothing, the caption says so, and the tick is kept in case that changes.
    /// What it does is `Rule.snoozeMayHold`'s, and which sentences say so is
    /// `EditorText.snoozeCaption(for:)`'s; no preset sets it (Ruling 3).
    private var snoozeSwitch: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $rule.quietWhenSnoozed) {
                Text(SnoozeText.ruleSwitchLabel)
            }
            .toggleStyle(.switch)
            .accessibilityLabel(EditorText.label(.snoozeSwitch))

            Text(EditorText.snoozeCaption(for: rule))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
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
