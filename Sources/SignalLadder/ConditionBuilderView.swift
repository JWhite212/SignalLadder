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
                    Text(EditorText.not).font(.callout.weight(.semibold))
                    Spacer()
                    Button(EditorText.removeNot) { edit { $0.negating(at: path) } }
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
        case .time(let window):
            timeRow(window)
        case .screenLocked(let locked):
            lockRow(locked)
        case .appSent(let frequency):
            sentRow(frequency)
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
                    Text(EditorText.allOfThese).tag(true)
                    Text(EditorText.anyOfThese).tag(false)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(EditorText.label(.conditionGroupMode))
                Spacer()
                Menu {
                    Button(EditorText.addCondition) { edit { $0.inserting(.blank, intoGroupAt: path, at: children.count) } }
                    Menu(EditorText.addConditionOn) {
                        ForEach(Array(ConditionKinds.offered.enumerated()), id: \.offset) { _, kind in
                            Button(kind.name) { edit { $0.inserting(kind.start, intoGroupAt: path, at: children.count) } }
                        }
                    }
                    Button(EditorText.addAnyOfGroup) {
                        edit { $0.inserting(.or([.blank]), intoGroupAt: path, at: children.count) }
                    }
                    Button(EditorText.addAllOfGroup) {
                        edit { $0.inserting(.and([.blank]), intoGroupAt: path, at: children.count) }
                    }
                    Divider()
                    Button(EditorText.negateGroup) { edit { $0.negating(at: path) } }
                    if children.count == 1 {
                        Button(EditorText.ungroup) { edit { $0.unwrapping(at: path) } }
                    }
                    if !path.isEmpty {
                        Button(EditorText.removeGroup, role: .destructive) { edit { $0.removing(at: path) } }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(EditorText.label(.groupOptions))
            }
            if children.isEmpty {
                Text(EditorText.emptyGroup)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
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
            .accessibilityLabel(EditorText.label(.conditionField))

            Picker("", selection: Binding(
                get: { if case .field(_, let op, _) = node { return op }; return .contains },
                set: { op in if case .field(let field, _, let value) = node { set(.field(field, op, value)) } })) {
                ForEach(Operator.allCases, id: \.self) { Text(EditorText.operatorName($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(EditorText.label(.conditionOperator))

            TextField(EditorText.valuePlaceholder, text: Binding(
                get: { if case .field(_, _, let value) = node { return value }; return "" },
                set: { value in if case .field(let field, let op, _) = node { set(.field(field, op, value)) } }))
                .textFieldStyle(.roundedBorder)

            optionsMenu
        }
    }

    /// What can be done to one condition, of whatever kind.
    private var optionsMenu: some View {
        Menu {
            Button(EditorText.negate) { edit { $0.negating(at: path) } }
            Button(EditorText.groupWithAllOf) { edit { $0.wrapping(at: path, in: .and) } }
            Button(EditorText.groupWithAnyOf) { edit { $0.wrapping(at: path, in: .or) } }
            if !path.isEmpty {
                Divider()
                Button(EditorText.remove, role: .destructive) { edit { $0.removing(at: path) } }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(EditorText.label(.conditionOptions))
    }

    // MARK: - Time of day

    private func timeRow(_ window: TimeWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(EditorText.timeIs)
                timePicker(EditorText.label(.conditionTimeFrom), minute: window.from) { minute in
                    var changed = window
                    changed.from = minute
                    set(.time(changed))
                }
                Text(EditorText.timeTo)
                timePicker(EditorText.label(.conditionTimeTo), minute: window.to) { minute in
                    var changed = window
                    changed.to = minute
                    set(.time(changed))
                }
                Spacer()
                optionsMenu
            }
            HStack(spacing: 4) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Toggle(EditorText.dayName(day), isOn: Binding(
                        get: { window.days.contains(day) },
                        set: { isOn in
                            var changed = window
                            if isOn { changed.days.insert(day) } else { changed.days.remove(day) }
                            set(.time(changed))
                        }))
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .accessibilityLabel(EditorText.dayLabel(day))
                }
            }
            if window.wrapsMidnight {
                Text(EditorText.nextDayNote).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// A time of day, held as minutes after midnight. The date it is shown
    /// on is a fixed one with no clock change in it, so every minute exists.
    private func timePicker(_ label: String, minute: Int, set: @escaping (Int) -> Void) -> some View {
        DatePicker(label, selection: Binding(
            get: { TimeOfDayPicking.date(forMinute: minute) },
            set: { set(TimeOfDayPicking.minute(of: $0)) }), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(label)
    }

    // MARK: - Screen lock

    private func lockRow(_ locked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(EditorText.screenIs)
                Picker(EditorText.screenLockLabel, selection: Binding(get: { locked }, set: { set(.screenLocked($0)) })) {
                    Text(EditorText.screenLockedChoice).tag(true)
                    Text(EditorText.screenNotLockedChoice).tag(false)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(EditorText.label(.conditionScreenLock))
                Spacer()
                optionsMenu
            }
            Text(EditorText.screenLockNote).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - How often the app is sending

    private func sentRow(_ frequency: AppFrequency) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(EditorText.appSentAtLeast)
                Stepper(value: Binding(get: { frequency.atLeast }, set: {
                    set(.appSent(AppFrequency(atLeast: $0, withinMinutes: frequency.withinMinutes)))
                }), in: AppFrequency.countRange) {
                    Text(verbatim: String(frequency.atLeast)).monospacedDigit()
                }
                .accessibilityLabel(EditorText.label(.conditionSentCount))
                Text(EditorText.appSentInTheLast)
                Stepper(value: Binding(get: { frequency.withinMinutes }, set: {
                    set(.appSent(AppFrequency(atLeast: frequency.atLeast, withinMinutes: $0)))
                }), in: AppFrequency.minutesRange) {
                    Text(EditorText.minutes(frequency.withinMinutes)).monospacedDigit()
                }
                .accessibilityLabel(EditorText.label(.conditionSentMinutes))
                Spacer()
                optionsMenu
            }
            Text(EditorText.appSentNote).font(.caption).foregroundStyle(.secondary)
        }
    }
}
