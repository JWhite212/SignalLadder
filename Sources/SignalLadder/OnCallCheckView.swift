// Sources/SignalLadder/OnCallCheckView.swift
import SwiftUI
import NotificationCore

/// What the on-call check says: a heading, every finding on a line of its own
/// with the urgent ones first, and one button.
///
/// Thin by design, and held to it: this file may hold no word of its own (the
/// strict list in `ViewLiteralsTests`), so every sentence and label is
/// `OnCallText`'s or a finding's, and which findings there are, in what order, which
/// of them is urgent and each symbol are `OnCallCheck`'s. It shows no notification
/// content and no app name, since a shared screen shows it. `OnCallWiringTests`
/// holds each line that carries one of these answers to the screen, and refuses a
/// symbol name written here.
struct OnCallCheckView: View {
    @ObservedObject var model: OnCallCheckModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.lines.enumerated()), id: \.offset) { _, finding in
                        row(finding)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 300, idealHeight: 420)
    }

    private var header: some View {
        HStack(spacing: 10) {
            // Nothing urgent is not "all is well": the app checks only what it can read,
            // so `OnCallCheck` gives the heading a bell and no tick.
            Image(systemName: OnCallCheck.headingSymbol(hasUrgent: model.hasUrgent))
                .font(.title2)
                .foregroundStyle(model.hasUrgent ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            Text(model.summary)
                .font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(16)
    }

    private func row(_ finding: OnCallCheck.Finding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: finding.symbol)
                .foregroundStyle(finding.isUrgent ? Color.orange : Color.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(finding.text)
                .foregroundStyle(finding.isUrgent ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(finding.spokenText)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            // Not the window's default button: the window opens by itself and activates the
            // app, so a Return meant for what the user was typing would post a self-test.
            Button(OnCallText.checkButton) {
                Task { await model.runCheck() }
            }
            .disabled(model.isChecking)
            if model.isChecking {
                ProgressView().controlSize(.small)
            }
            Text(OnCallText.checkButtonNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
    }
}
