// Sources/SignalLadder/RuleDetailView.swift
import SwiftUI
import NotificationCore

/// The selected rule: its name and switch, its problems, its condition, its
/// alert, and the dry-run that proves it.
///
/// Bound to the rule by id, never by position: a binding that outlives its
/// rule (SwiftUI can ask once more after a delete) reads a placeholder and
/// writes nothing, instead of trapping on a stale index.
struct RuleDetailView: View {
    @ObservedObject var model: RuleEditorModel
    let id: Rule.ID
    /// What the first alert's choices have set aside. Local to this view, which
    /// `RuleEditorView` rebuilds for each rule it shows, so a sound set aside on
    /// one rule is never restored into the next.
    @State private var alertSetAside = AlertEditing.SetAside()

    private var rule: Binding<Rule> {
        Binding(
            get: { [model, id] in model.rules.first { $0.id == id } ?? Rule(name: "", condition: .blank) },
            set: { [model, id] updated in
                if let index = model.rules.firstIndex(where: { $0.id == id }) { model.rules[index] = updated }
            })
    }

    var body: some View {
        let current = rule.wrappedValue
        let problems = model.problems(in: current)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TextField("Rule name", text: rule.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                    Toggle("On", isOn: rule.isEnabled)
                        .toggleStyle(.switch)
                }

                if !problems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(problems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.callout)
                }

                section("When a notification matches") {
                    ConditionBuilderView(rule: rule)
                    HStack(spacing: 12) {
                        Button("Add Condition") { rule.wrappedValue.condition = rule.wrappedValue.condition.adding(.blank) }
                        if let source = model.source {
                            Menu("Add Condition from This Notification") {
                                ForEach(Array(RuleSeed.offers(from: source).enumerated()), id: \.offset) { _, offer in
                                    Button(EditorText.describe(offer)) {
                                        rule.wrappedValue.condition = rule.wrappedValue.condition.adding(offer)
                                    }
                                }
                            }
                            .fixedSize()
                        }
                    }
                    if model.source != nil {
                        Text(EditorText.savedTextCaption).font(.caption).foregroundStyle(.secondary)
                    }
                }

                section("Then") {
                    // The note that the output is muted is shown once for the
                    // rule: here when the first alert sounds, else under the
                    // ladder, when something after it does.
                    AlertEditorView(model: model, action: rule.alert, setAside: $alertSetAside,
                                    kinds: AlertEditing.offeredKinds(for: .first), role: .first,
                                    showsMutedOutputNote: EscalationEditing.mutedOutputNoteSite(
                                        firstAlert: current.alert, escalation: current.escalation) == .firstAlert)
                    LadderEditorView(model: model, rule: rule)
                }

                section("Tried on recent notifications") {
                    DryRunView(model: model, id: id)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}
