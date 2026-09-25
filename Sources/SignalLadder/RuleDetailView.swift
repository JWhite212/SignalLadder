// Sources/SignalLadder/RuleDetailView.swift
import SwiftUI
import NotificationCore

/// The selected rule: its name, whether it is on, and its problems.
///
/// Bound to the rule by id, never by position: a binding that outlives its
/// rule (SwiftUI can ask once more after a delete) reads a placeholder and
/// writes nothing, instead of trapping on a stale index.
struct RuleDetailView: View {
    @ObservedObject var model: RuleEditorModel
    let id: Rule.ID

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
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
