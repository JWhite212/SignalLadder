// Sources/SignalLadder/RuleEditorView.swift
import SwiftUI
import NotificationCore

/// The rule editor (§7.4): rules on the left, in priority order; the selected
/// rule on the right. Thin — every sentence comes from `EditorText`, every
/// decision from the tested core.
struct RuleEditorView: View {
    @ObservedObject var model: RuleEditorModel
    let actions: RuleEditorActions

    var body: some View {
        VStack(spacing: 0) {
            if let reason = model.readOnly {
                ReadOnlyView(reason: reason, openInTextEditor: actions.openInTextEditor, reload: model.putIntoEffect)
            } else {
                SaveBar(model: model, save: actions.save, revert: actions.revert)
                Divider()
                HSplitView {
                    RuleListView(model: model, delete: actions.delete)
                        .frame(minWidth: 230, idealWidth: 270, maxWidth: 400)
                    Group {
                        if let id = model.selection, model.rules.contains(where: { $0.id == id }) {
                            // A new identity per rule, so nothing the pane
                            // remembers — a test sound's error — carries over
                            // to a different rule.
                            RuleDetailView(model: model, id: id)
                                .id(id)
                        } else {
                            EmptyEditorView(hasRules: !model.rules.isEmpty, addRule: model.addRule)
                        }
                    }
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}

/// Says, always in words, whether what is on screen is in effect.
private struct SaveBar: View {
    @ObservedObject var model: RuleEditorModel
    let save: () -> Void
    /// Asks first (`RuleEditorWindowController.revert`).
    let revert: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            let state = model.saveState
            let said = EditorText.saveState(state)
            Label(said.text, systemImage: said.isWarning ? "exclamationmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(said.isWarning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .font(said.isWarning ? .callout.weight(.semibold) : .callout)
            if state == .fileNotInEffect {
                Button(EditorText.putIntoEffect, action: model.putIntoEffect)
            }
            Spacer()
            Button(EditorText.revert, action: revert)
                .disabled(!model.hasUnsavedChanges)
            Button(EditorText.save, action: save)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canSave)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - The list

private struct RuleListView: View {
    @ObservedObject var model: RuleEditorModel
    /// Asks first when the rule would lose work (`RuleEditorWindowController.delete`).
    let delete: (Rule.ID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                ForEach($model.rules) { $rule in
                    let isSelected = model.selection == rule.id
                    RuleRow(rule: $rule, position: RuleOrder.position(of: rule.id, in: model.rules),
                            isSelected: isSelected, hasProblems: !model.problems(in: rule).isEmpty)
                        .tag(rule.id)
                        // The selected rule is navy, which is the design's one
                        // use of it in this window beside Save, and not the
                        // system's highlight, which this stands in place of.
                        .listRowBackground(RuleRowGround(isSelected: isSelected))
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            ForEach(RuleOrder.Direction.allCases, id: \.self) { direction in
                                Button(EditorText.moveWord(direction)) { model.step(rule.id, direction) }
                                    .disabled(!model.canStep(rule.id, direction))
                            }
                            Divider()
                            Button(EditorText.duplicate) { model.duplicate(rule.id) }
                            Button(EditorText.delete, role: .destructive) { delete(rule.id) }
                        }
                        // Drag is the mouse's way to set the order, which is
                        // priority. These are the keyboard's and VoiceOver's.
                        .accessibilityActions {
                            ForEach(RuleOrder.Direction.allCases, id: \.self) { direction in
                                if model.canStep(rule.id, direction) {
                                    Button(EditorText.moveWord(direction)) { model.step(rule.id, direction) }
                                }
                            }
                        }
                }
                .onMove(perform: model.move)
            }
            .onDeleteCommand { if let id = model.selection { delete(id) } }
            // An inset panel: the list sits in a block a shade off the window's
            // ground, with its corners rounded.
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(8)

            Divider()
            HStack(spacing: 4) {
                Button(action: model.addRule) { Image(systemName: "plus") }
                    .help(EditorText.addARule)
                Button {
                    if let id = model.selection { delete(id) }
                } label: { Image(systemName: "minus") }
                    .help(EditorText.deleteTheSelectedRule)
                    .disabled(model.selection == nil)
                Spacer()
                Text(EditorText.topRuleWins).font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }
}

/// What is behind a row: navy for the selected rule, and nothing otherwise.
private struct RuleRowGround: View {
    let isSelected: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // On a dark window the ground's own navy is too near the window's
        // colour to be seen, so the selected row takes the shade above it.
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? (scheme == .dark ? NightWatchPalette.raised : NightWatchPalette.ground) : .clear)
            .padding(.horizontal, 4)
    }
}

/// How far the rule's ladder reaches: a segment for each tier, filled in the
/// tier's colour when the rule has it and hollow when it has not, so the two
/// differ by more than colour. What it shows is `LadderStrip`'s.
private struct LadderStripView: View {
    let strip: LadderStrip
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(strip.segments, id: \.tier) { segment in
                if segment.isOn {
                    Capsule().fill(NightWatchPalette.block(segment.tone)).frame(width: 16, height: 4)
                } else {
                    Capsule().strokeBorder(.tertiary, lineWidth: 1).frame(width: 16, height: 4)
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .help(strip.description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strip.description)
    }
}

private struct RuleRow: View {
    @Binding var rule: Rule
    /// The row's place in the list, from 1, which is the rule's priority.
    let position: Int?
    let isSelected: Bool
    let hasProblems: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let position {
                Text(EditorText.position(position))
                    .font(.mono(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)
                    .help(EditorText.priority(position))
                    .accessibilityLabel(EditorText.priority(position))
            }
            // The handle shows that a row can be dragged. The whole row
            // moves: a move allowed only while the pointer was over the
            // handle was refused outright on macOS 27.2, and a click on the
            // switch still lands at once without it.
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
                .help(EditorText.dragToChangePriority)
                // A screen reader has the row's Move Up and Move Down instead.
                .accessibilityHidden(true)
            Toggle("", isOn: $rule.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .buttonStyle(.plain)
                .help(rule.isEnabled ? EditorText.onSwitchOff : EditorText.offSwitchOn)
                .accessibilityLabel(EditorText.ruleRowName(rule.name))
            VStack(alignment: .leading, spacing: 1) {
                Text(EditorText.ruleRowName(rule.name))
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                Text(EditorText.alertSummary(rule.alert, escalation: rule.escalation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                LadderStripView(strip: LadderStrip(for: rule), isEnabled: rule.isEnabled)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            if hasProblems {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.primary)
                    .help(EditorText.ruleHasProblems)
            }
        }
        .padding(.vertical, 4)
        // On navy the label colours are the dark appearance's, whatever the
        // system's, so the words and marks of the selected row stay readable.
        .environment(\.colorScheme, isSelected ? .dark : scheme)
    }

    @Environment(\.colorScheme) private var scheme
}

// MARK: - States

private struct ReadOnlyView: View {
    let reason: RulesDocument.ReadOnlyReason
    let openInTextEditor: () -> Void
    /// What Put into Effect does: reloads the rules, and with them this editor, which
    /// holds no draft while it is read-only.
    let reload: () -> Void

    var body: some View {
        let text = EditorText.readOnly(reason)
        VStack(alignment: .leading, spacing: 12) {
            Label(text.title, systemImage: "lock.doc")
                .font(.headline)
            ForEach(text.detail, id: \.self) { line in
                Text(line).font(.callout.monospaced()).textSelection(.enabled)
            }
            Text(EditorText.readOnlyNextStep).font(.callout)
            HStack {
                Button(SetupText.openRulesFileTitle, action: openInTextEditor)
                Button(StatusMenuText.reloadRulesTitle, action: reload)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct EmptyEditorView: View {
    let hasRules: Bool
    let addRule: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(hasRules ? EditorText.selectARule : EditorText.emptyState)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            if !hasRules {
                Button(EditorText.addARuleByHand, action: addRule)
            }
        }
        .padding(40)
    }
}
