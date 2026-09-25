// Sources/SignalLadder/ConditionBuilderView.swift
import SwiftUI
import NotificationCore

/// The condition tree, edited in place (§5.14).
///
/// Every node is bound straight to the rule's `RuleCondition` through its
/// index path: reading is `condition(at:)`, writing is `replacing(at:with:)`.
/// There is no second tree to drift from. Both are total, so a row that
/// SwiftUI asks about once more after its node was deleted reads a
/// placeholder and writes nothing — it cannot trap.
///
/// Rows are identified by their path. Typing changes a value, never a path,
/// so focus stays put; adding or removing a node redraws the rows around it.
struct ConditionBuilderView: View {
    @Binding var rule: Rule

    var body: some View {
        ConditionNodeView(rule: $rule, path: [])
    }
}

private struct ConditionNodeView: View {
    @Binding var rule: Rule
    let path: ConditionPath

    private var node: RuleCondition { rule.condition.condition(at: path) ?? .blank }

    /// Writes one node back into the tree; a stale path writes nothing.
    private func set(_ replacement: RuleCondition) {
        if let updated = rule.condition.replacing(at: path, with: replacement) { rule.condition = updated }
    }

    /// Applies a structural edit; one that no longer applies does nothing.
    private func edit(_ change: (RuleCondition) -> RuleCondition?) {
        if let updated = change(rule.condition) { rule.condition = updated }
    }

    var body: some View {
        switch node {
        case .and(let children), .or(let children):
            group(children: children)
        case .not:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Not").font(.callout.weight(.semibold))
                    Spacer()
                    Button("Remove “Not”") { edit { $0.negating(at: path) } }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                // Type-erased where the tree recurses: an opaque type cannot
                // contain itself.
                AnyView(ConditionNodeView(rule: $rule, path: path + [0]))
                    .padding(.leading, 18)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        case .field:
            fieldRow
        }
    }

    // MARK: - A group

    @ViewBuilder
    private func group(children: [RuleCondition]) -> some View {
        let isAll: Bool = { if case .and = node { return true }; return false }()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { isAll }, set: { wantAll in
                    if wantAll != isAll { edit { $0.switchingGroup(at: path) } }
                })) {
                    Text("All of these").tag(true)
                    Text("Any of these").tag(false)
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Menu {
                    Button("Add Condition") { edit { $0.inserting(.blank, intoGroupAt: path, at: children.count) } }
                    Button("Add “Any of” Group") {
                        edit { $0.inserting(.or([.blank]), intoGroupAt: path, at: children.count) }
                    }
                    Button("Add “All of” Group") {
                        edit { $0.inserting(.and([.blank]), intoGroupAt: path, at: children.count) }
                    }
                    Divider()
                    Button("Negate Group") { edit { $0.negating(at: path) } }
                    if children.count == 1 {
                        Button("Ungroup") { edit { $0.unwrapping(at: path) } }
                    }
                    if !path.isEmpty {
                        Button("Remove Group", role: .destructive) { edit { $0.removing(at: path) } }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if children.isEmpty {
                Text("Empty — add a condition.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            ForEach(children.indices, id: \.self) { index in
                AnyView(ConditionNodeView(rule: $rule, path: path + [index]))
            }
            .padding(.leading, 18)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
    }

    // MARK: - A single condition

    private var fieldRow: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { if case .field(let field, _, _) = node { return field }; return .title },
                set: { field in if case .field(_, let op, let value) = node { set(.field(field, op, value)) } })) {
                ForEach(Field.allCases, id: \.self) { Text(EditorText.fieldName($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            Picker("", selection: Binding(
                get: { if case .field(_, let op, _) = node { return op }; return .contains },
                set: { op in if case .field(let field, _, let value) = node { set(.field(field, op, value)) } })) {
                ForEach(Operator.allCases, id: \.self) { Text(EditorText.operatorName($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            TextField("value", text: Binding(
                get: { if case .field(_, _, let value) = node { return value }; return "" },
                set: { value in if case .field(let field, let op, _) = node { set(.field(field, op, value)) } }))
                .textFieldStyle(.roundedBorder)

            Menu {
                Button("Negate") { edit { $0.negating(at: path) } }
                Button("Group with “All of”") { edit { $0.wrapping(at: path, in: .and) } }
                Button("Group with “Any of”") { edit { $0.wrapping(at: path, in: .or) } }
                if !path.isEmpty {
                    Divider()
                    Button("Remove", role: .destructive) { edit { $0.removing(at: path) } }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
