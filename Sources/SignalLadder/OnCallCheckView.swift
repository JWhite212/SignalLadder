// Sources/SignalLadder/OnCallCheckView.swift
import SwiftUI
import NotificationCore

/// What the on-call check says: a heading, every finding on a line of its own
/// with the urgent ones first, the button a finding carries beneath it (the login
/// finding's, where the status allows one) and what a press of that button came to
/// when it did not do what was asked, and the one button that checks again.
///
/// Thin by design, and held to it: this file may hold no word of its own (the
/// strict list in `ViewLiteralsTests`), so every sentence and label is
/// `OnCallText`'s, `LaunchAtLoginText`'s or a finding's, and which findings there
/// are, in what order, which of them is urgent, each symbol and whether a finding
/// has a button are `OnCallCheck`'s. It shows no notification content and no app
/// name, since a shared screen shows it. `OnCallWiringTests` holds each line that
/// carries one of these answers to the screen, and refuses a symbol name written
/// here.
struct OnCallCheckView: View {
    @ObservedObject var model: OnCallCheckModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.lines.enumerated()), id: \.offset) { _, finding in
                        VStack(alignment: .leading, spacing: 6) {
                            row(finding)
                            if let action = finding.action {
                                actionButton(action)
                                if let message = model.message {
                                    pressMessage(message)
                                }
                            }
                        }
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

    /// The finding's own button, under its row and in line with its words, so that
    /// acting on the finding is one click by the user and nothing is switched on
    /// silently (O12). Its words and what it does are the core's
    /// (`LaunchAtLoginText.label(for:)`, `LaunchAtLogin.Action`). It is its own
    /// accessibility element, apart from the row's, so that VoiceOver can press it.
    private func actionButton(_ action: LaunchAtLogin.Action) -> some View {
        Button(LaunchAtLoginText.label(for: action)) { model.perform(action) }
            .padding(.leading, 28)
    }

    /// What the press of the finding's button came to, when it failed or changed
    /// nothing, beneath the button that was pressed and in line with it, so that a
    /// press that did nothing is not silent (Global Constraints: an unknown login-item
    /// error is shown as a failure). The words are the core's
    /// (`LaunchAtLoginText.message(after:statusAfter:)`), carried to the model, and
    /// there is none unless the press made one.
    private func pressMessage(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 28)
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
