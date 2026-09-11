// Sources/SignalLadder/InspectorView.swift
import SwiftUI
import NotificationCore

struct InspectorView: View {
    @ObservedObject var model: InspectorModel

    var body: some View {
        Group {
            if let message = model.emptyStateMessage {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.entries) { entry in
                    InspectorRow(entry: entry)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 380)
    }
}

private struct InspectorRow: View {
    let entry: InspectorEntry
    @State private var showsRaw = false

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.captured.appNameGuess.isEmpty ? "(no app name)" : entry.captured.appNameGuess)
                    .font(.headline)
                Spacer()
                Text(Self.time.string(from: entry.captured.timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(entry.captured.title).font(.body)
            if !entry.captured.subtitle.isEmpty {
                Text(entry.captured.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            if !entry.captured.body.isEmpty {
                Text(entry.captured.body).font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                // The subrole is shown because it is a matchable field, and
                // users cannot write rules against fields they have never seen.
                Label(entry.captured.subrole, systemImage: "tag")
                Label(recentText, systemImage: "chart.bar")
                if entry.suppressedRepeatCount > 0 {
                    Label("\(entry.suppressedRepeatCount) suppressed", systemImage: "square.on.square")
                }
                Label(matchText, systemImage: "line.3.horizontal.decrease.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // §7.2 item 6. Always empty in M2c — nothing evaluates yet — but a
            // warning raised during evaluation and then not shown would be a
            // silent failure in the one window built to make failures visible.
            ForEach(entry.annotation?.warnings ?? [], id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            DisclosureGroup("Raw", isExpanded: $showsRaw) {
                Text(entry.captured.rawText.isEmpty ? "(empty description)" : entry.captured.rawText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    /// Reads as a floor when the buffer overflowed inside the window, because
    /// that is what the number is.
    private var recentText: String {
        let n = entry.context.recentCountForApp
        return entry.context.recentCountIsUnderCounted ? "\(n)+ in the last hour" : "\(n) in the last hour"
    }

    /// Three distinct states, deliberately. "Not evaluated" is not "matched
    /// nothing" — the spec calls matching nothing the most common confusion.
    private var matchText: String {
        guard let annotation = entry.annotation else { return "Not evaluated — no rules yet" }
        return annotation.ruleName.map { "Matched \($0)" } ?? "Matched no rule"
    }
}
