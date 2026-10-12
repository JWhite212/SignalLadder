// Sources/SignalLadder/SetupView.swift
import SwiftUI
import NotificationCore

/// What the Setup Guide says: a rail of the eight steps with where each stands, beside the
/// step the plan has next, large, and when no step has anything left, the summary (M5 plan,
/// Task 8, Rulings 10, 16 and 18, O13).
///
/// **The rail shows where the user is and does nothing else.** Each row is a step's name
/// with its state in words and in a symbol, a step done on the user's word saying so in the
/// words, and is read by VoiceOver as its place and title with the state as its value,
/// since a symbol is not read. The step the plan has next is marked. It is not a button:
/// there is no going back, no jumping, and no ninth row for the summary, which takes the
/// step's place.
///
/// **A step is shown in the order the core gives it:** its place and title, what it says
/// before it asks, what it has read, the lines under that, the practice line to select, the
/// list of apps to pick from, the last step's box, and its buttons, in the order the core
/// gives them, with the sentence the last press handed back beside them. The step shown is
/// never one that is done (`SetupPlan.current` passes over those), so what a done step rests
/// on is not said here: the rail says it in the label beside the step
/// (`SetupText.stateLabel(for:)`) and to VoiceOver, and the summary under its headings.
///
/// "Not now" is the window's own button, shown where the core says (every step, and not the
/// summary, where Finish is). No button is the window's default button, because the window
/// opens by itself and a Return meant for something else must not ask macOS for a permission
/// or change the user's login items: nothing is asked until the user presses its button
/// (Ruling 16).
///
/// **The practice line is text to select.** The app never runs it and never copies it
/// (Ruling 16); the user selects it and pastes it where they choose.
///
/// Thin by design, and held to it: this file may hold no word of its own (the strict list in
/// `ViewLiteralsTests`) and none of the symbols it draws, so every label, sentence and
/// symbol is `SetupText`'s, and what each step is, says and offers is `SetupPlan`'s and
/// `SetupText`'s. It shows app names only where a step lists them, to choose from, and never
/// a title or a body. `SetupWiringTests` holds each line that carries one of these answers
/// to the screen, and `SetupTextTests` that every label of `SetupText.windowLabels` is
/// written here or, for a sentence the coordinator hands back, there.
struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            rail
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    content
                        .frame(maxWidth: 640, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
                if SetupText.windowShowsNotNow(on: model.current) {
                    Divider()
                    footer
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 900, maxWidth: .infinity,
               minHeight: 520, idealHeight: 640, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: The rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(SetupText.railHeading)
                .font(.headline)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            ForEach(model.readings, id: \.step) { reading in
                railRow(reading)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 250, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SetupText.railHeading)
    }

    private func railRow(_ reading: SetupPlan.Reading) -> some View {
        let isCurrent = reading.step == model.current
        return HStack(spacing: 10) {
            Image(systemName: SetupText.stateSymbol(for: reading.state))
                .foregroundStyle(reading.state.isDone ? Color.green : Color.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(SetupText.title(for: reading.step))
                    .fontWeight(isCurrent ? .semibold : .regular)
                Text(SetupText.stateLabel(for: reading.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isCurrent ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SetupText.railRowLabel(for: reading.step))
        .accessibilityValue(SetupText.stateDescription(for: reading.state))
        .accessibilityAddTraits(isCurrent ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    // MARK: The step, or the summary

    @ViewBuilder
    private var content: some View {
        if let words = model.words {
            stepView(words)
        } else if let summary = model.summary {
            summaryView(summary)
        }
    }

    private func stepView(_ words: SetupText.StepWords) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(SetupText.stepPosition(of: words.step))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(words.title)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            paragraphs(words.why)
            Text(words.status)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            paragraphs(words.detail)
            if let line = words.selectable {
                practiceLine(line)
            }
            if !words.apps.isEmpty {
                appList(words)
            }
            if let label = words.tickBox {
                Toggle(label, isOn: $model.boxTicked)
            }
            buttons(words.buttons)
            pressMessage
        }
    }

    private func summaryView(_ summary: SetupText.Summary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.title)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(summary.readHeading)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            paragraphs(summary.read)
            Text(summary.wordHeading)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            paragraphs(summary.word)
            paragraphs([summary.onCall, summary.snooze])
            buttons(summary.buttons)
            pressMessage
        }
    }

    private func paragraphs(_ lines: [String]) -> some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(line)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The practice line, as text for the user to select. It is not a button and carries no
    /// copy: the user selects it and copies it themselves. VoiceOver reads what it is and
    /// then the line.
    private func practiceLine(_ line: String) -> some View {
        Text(line)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(SetupText.practiceCommandLabel)
            .accessibilityValue(line)
    }

    // MARK: The list of apps

    /// The apps a step lists, to pick one from: the first rule's step lists the apps banners
    /// were read from, and the mute step the apps to mute. The step's own buttons act on the
    /// app picked, and say so beside the button when none is.
    private func appList(_ words: SetupText.StepWords) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let heading = SetupText.appListHeading(for: words.step) {
                Text(heading)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            List(words.apps, id: \.self, selection: Binding(get: { model.pickedApp }, set: { model.pick($0) })) { app in
                appRow(app, on: words.step)
            }
            .listStyle(.bordered)
            .frame(height: CGFloat(min(words.apps.count, 6)) * 28 + 12)
        }
    }

    /// A row of the list, as the core words it for the step (`SetupText.appRow`): the view
    /// hands over the step and whether the user has confirmed the app, and names no step.
    private func appRow(_ app: String, on step: SetupStep) -> some View {
        let row = SetupText.appRow(app, on: step, confirmed: model.isConfirmed(app))
        return Text(row.text)
            .accessibilityLabel(row.voiceOver)
    }

    // MARK: Buttons

    /// A step's buttons, in the order the core gives them, on a line if they fit and one
    /// above the other if they do not. All are disabled while a press is being carried out,
    /// with a spinner beside them, so that a second press cannot start beside the first.
    private func buttons(_ buttons: [SetupText.StepButton]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                buttonRow(buttons)
            }
            VStack(alignment: .leading, spacing: 8) {
                buttonRow(buttons)
            }
        }
        .disabled(model.isPressing)
    }

    @ViewBuilder
    private func buttonRow(_ buttons: [SetupText.StepButton]) -> some View {
        ForEach(buttons, id: \.action) { button in
            Button(button.label) {
                Task { await model.press(button.action) }
            }
        }
        if model.isPressing {
            ProgressView().controlSize(.small)
        }
    }

    /// What the last press handed back, beside the buttons it came from.
    @ViewBuilder
    private var pressMessage: some View {
        if let message = model.message {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The window's own button

    private var footer: some View {
        HStack {
            Spacer()
            Button(SetupText.label(for: .notNow)) {
                Task { await model.press(.notNow) }
            }
            .disabled(model.isPressing)
        }
        .padding(12)
    }
}
