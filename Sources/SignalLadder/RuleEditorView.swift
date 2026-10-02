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
                ReadOnlyView(reason: reason, openInTextEditor: actions.openInTextEditor)
            } else {
                SaveBar(model: model, save: actions.save)
                Divider()
                HSplitView {
                    RuleListView(model: model)
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
            Button("Revert", action: model.revert)
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

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                ForEach($model.rules) { $rule in
                    RuleRow(rule: $rule, hasProblems: !model.problems(in: rule).isEmpty)
                        .tag(rule.id)
                        .contextMenu {
                            Button("Duplicate") { model.duplicate(rule.id) }
                            Button("Delete", role: .destructive) { model.delete(rule.id) }
                        }
                }
                .onMove(perform: model.move)
            }
            .onDeleteCommand { if let id = model.selection { model.delete(id) } }

            Divider()
            HStack(spacing: 4) {
                Button(action: model.addRule) { Image(systemName: "plus") }
                    .help("Add a rule")
                Button {
                    if let id = model.selection { model.delete(id) }
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
    /// Rows move only by their handle, so a click on the switch is never
    /// taken for the start of a drag and lands late.
    @State private var overHandle = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
                .onHover { overHandle = $0 }
                .help("Drag to change priority")
            Toggle("", isOn: $rule.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .buttonStyle(.plain)
                .help(rule.isEnabled ? "On — switch off" : "Off — switch on")
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.name.isEmpty ? "Unnamed rule" : rule.name)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                Text(EditorText.alertSummary(rule.alert))
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
        .moveDisabled(!overHandle)
    }
}

// MARK: - States

private struct ReadOnlyView: View {
    let reason: RulesDocument.ReadOnlyReason
    let openInTextEditor: () -> Void

    var body: some View {
        let text = EditorText.readOnly(reason)
        VStack(alignment: .leading, spacing: 12) {
            Label(text.title, systemImage: "lock.doc")
                .font(.headline)
            ForEach(text.detail, id: \.self) { line in
                Text(line).font(.callout.monospaced()).textSelection(.enabled)
            }
            Button("Open Rules File in Text Editor", action: openInTextEditor)
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
