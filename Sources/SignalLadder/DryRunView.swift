// Sources/SignalLadder/DryRunView.swift
import SwiftUI
import NotificationCore

/// The selected rule tried on every notification held in memory (§7.3):
/// what it matches, what a rule above takes first, and — always — whether
/// any of this is in effect yet.
struct DryRunView: View {
    @ObservedObject var model: RuleEditorModel
    let id: Rule.ID

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        if let run = model.dryRun(for: id) {
            VStack(alignment: .leading, spacing: 8) {
                Text(EditorText.dryRunHeadline(run)).font(.headline)

                if let note = EditorText.notInEffect(hasProblems: run.ruleHasProblems, isOff: run.ruleIsOff,
                                                     isUnsaved: model.isUnsaved(id)) {
                    Label(note, systemImage: "info.circle").foregroundStyle(.orange).font(.callout)
                }

                if let claimed = EditorText.claimed(run) {
                    HStack {
                        Label(claimed, systemImage: "arrow.up.circle").font(.callout)
                        if let index = run.moveAboveIndex, let claimer = run.claimers.first {
                            Button(EditorText.moveAbove(claimer.name)) { model.move(id, to: index) }
                        }
                    }
                }

                let shown = run.rows.filter { $0.verdict != .notMatched }
                if !shown.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(shown, id: \.entryID) { row in
                            if let entry = model.captures.first(where: { $0.id == row.entryID }) {
                                DryRunRow(entry: entry, verdict: row.verdict, time: Self.time)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

private struct DryRunRow: View {
    let entry: InspectorEntry
    let verdict: DryRun.Verdict
    let time: DateFormatter

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch verdict {
            case .matched:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .claimedBy:
                Image(systemName: "arrow.up.circle").foregroundStyle(.orange)
            case .notMatched:
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
            Text(time.string(from: entry.captured.timestamp)).monospacedDigit().foregroundStyle(.secondary)
            Text(entry.captured.appNameGuess.isEmpty ? "(unknown app)" : entry.captured.appNameGuess).bold()
            Text(entry.captured.title).lineLimit(1)
            if case .claimedBy(_, let name) = verdict {
                Text("— taken by “\(name)”").foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}
