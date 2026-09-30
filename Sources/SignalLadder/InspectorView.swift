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
                    InspectorRow(entry: entry, makeRule: model.onMakeRule.map { make in { make(entry) } })
                }
            }
        }
        .frame(minWidth: 560, minHeight: 380)
    }
}

private struct InspectorRow: View {
    let entry: InspectorEntry
    /// Opens the rule editor with a new rule seeded from this notification
    /// (§7.3 step 2) — the fastest way from "that one mattered" to a rule.
    let makeRule: (() -> Void)?
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
                if let makeRule {
                    Button("Make a Rule from This…", action: makeRule)
                        .buttonStyle(.link)
                        .font(.caption)
                }
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

            // What was done about the match. Warnings — a sound that could
            // not play, or played into a muted output — are coloured, because
            // either means the user was not alerted when a rule said so.
            if let alert = entry.alertOutcome {
                Label(InspectorRowText.alert(alert), systemImage: Self.symbol(for: alert))
                    .font(.caption)
                    .foregroundStyle(alert.needsAttention ? Color.orange : Color.secondary)
                // Only here: the menu's copy of the line above never carries
                // what was said, because the menu is seen at a glance.
                if let said = alert.spokenText {
                    Text("Said: “\(said)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            // What the rest of the ladder did. Warned about, like the alert
            // above, when a repeat or the final tier did not sound or run.
            if let escalation = entry.escalation {
                Label(InspectorRowText.escalation(escalation, time: Self.time.string(from:)),
                      systemImage: "bell.and.waves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(escalation.needsAttention ? Color.orange : Color.secondary)
            }

            // A dry run of the rules loaded now. Its own line, never merged
            // into the outcome above, so what would happen can never be read
            // as what did.
            if let preview = InspectorRowText.preview(entry) {
                Label(preview, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

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

    private static func symbol(for alert: AlertOutcome) -> String {
        switch alert {
        case .played(_, _, outputSilent: false): return "speaker.wave.2"
        case .spoke(_, _, _, outputSilent: false), .playedAndSpoke(_, _, _, _, _, outputSilent: false):
            return "waveform"
        case .played(_, _, outputSilent: true), .spoke(_, _, _, outputSilent: true),
             .playedAndSpoke(_, _, _, _, _, outputSilent: true):
            return "speaker.slash"
        case .silentByRule: return "moon"
        case .noAlertSet: return "speaker"
        case .failed, .couldNotSpeak, .playedButNotSpoken, .spokeButNotPlayed: return "exclamationmark.triangle"
        }
    }

    /// What happened when this arrived. Wording lives in the core, where it is
    /// tested, because wording is where this window has misled before.
    private var matchText: String { InspectorRowText.outcome(entry) }
}
