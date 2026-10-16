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
                .foregroundStyle(said.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .font(.callout)
            if state == .fileNotInEffect {
                Button(EditorText.putIntoEffect, action: model.putIntoEffect)
            }
            Spacer()
            Button("Revert", action: revert)
                .disabled(!model.hasUnsavedChanges)
            Button("Save", action: save)
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
                    RuleRow(rule: $rule, hasProblems: !model.problems(in: rule).isEmpty)
                        .tag(rule.id)
                        .contextMenu {
                            ForEach(RuleOrder.Direction.allCases, id: \.self) { direction in
                                Button(EditorText.moveWord(direction)) { model.step(rule.id, direction) }
                                    .disabled(!model.canStep(rule.id, direction))
                            }
                            Divider()
                            Button("Duplicate") { model.duplicate(rule.id) }
                            Button("Delete", role: .destructive) { delete(rule.id) }
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

            Divider()
            HStack(spacing: 4) {
                Button(action: model.addRule) { Image(systemName: "plus") }
                    .help("Add a rule")
                Button {
                    if let id = model.selection { delete(id) }
                } label: { Image(systemName: "minus") }
                    .help("Delete the selected rule")
                    .disabled(model.selection == nil)
                Spacer()
                Text("Top rule wins").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }
}

private struct RuleRow: View {
    @Binding var rule: Rule
    let hasProblems: Bool

    var body: some View {
        HStack(spacing: 8) {
            // The handle shows that a row can be dragged. The whole row
            // moves: a move allowed only while the pointer was over the
            // handle was refused outright on macOS 27.2, and a click on the
            // switch still lands at once without it.
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
                .help("Drag to change priority")
                // A screen reader has the row's Move Up and Move Down instead.
                .accessibilityHidden(true)
            Toggle("", isOn: $rule.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .buttonStyle(.plain)
                .help(rule.isEnabled ? "On — switch off" : "Off — switch on")
                .accessibilityLabel(EditorText.ruleRowName(rule.name))
            VStack(alignment: .leading, spacing: 1) {
                Text(EditorText.ruleRowName(rule.name))
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                Text(EditorText.alertSummary(rule.alert, escalation: rule.escalation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if hasProblems {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This rule has problems and will not run")
            }
        }
        .padding(.vertical, 2)
    }
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
                Button("Open Rules File in Text Editor", action: openInTextEditor)
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
            Text(hasRules ? "Select a rule to edit it." : EditorText.emptyState)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            if !hasRules {
                Button("Add a Rule by Hand", action: addRule)
            }
        }
        .padding(40)
    }
}
