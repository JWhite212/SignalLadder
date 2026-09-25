// Sources/SignalLadder/AlertEditorView.swift
import SwiftUI
import NotificationCore

/// What the rule does on a match: nothing, stay quiet on purpose, or play a
/// sound at a chosen gain — and a way to hear that sound as the alert will
/// play it, which never cuts off a real alert.
struct AlertEditorView: View {
    @ObservedObject var model: RuleEditorModel
    @Binding var rule: Rule
    /// Why the last test sound did not play, shown until the next try.
    @State private var testMessage: String?

    private enum Kind: Hashable { case none, silent, sound, speech }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                switch rule.alert {
                case nil: return .none
                case .silent: return .silent
                case .sound: return .sound
                case .speak, .soundAndSpeak: return .speech
                }
            },
            set: { kind in
                switch kind {
                case .none: rule.alert = nil
                case .silent: rule.alert = .silent
                case .sound:
                    if case .sound = rule.alert { return }
                    // Sound only, keeping the sound a rule that also spoke had.
                    if case .soundAndSpeak(let name, let gainDB, _) = rule.alert {
                        rule.alert = .sound(name: name, gainDB: gainDB)
                        return
                    }
                    let available = model.availableSounds
                    let name = available.first { $0.caseInsensitiveCompare("Glass") == .orderedSame } ?? available.first ?? "Glass"
                    rule.alert = .sound(name: name, gainDB: 0)
                // Offered only for a rule that already speaks, until the
                // editor has speech controls; choosing it changes nothing.
                case .speech: return
                }
            })
    }

    private var soundName: Binding<String> {
        Binding(
            // Shown with the library's own spelling: sound names match
            // ignoring case, but a picker only selects an exact tag.
            get: {
                guard case .sound(let name, _) = rule.alert else { return "" }
                return model.availableSounds.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
            },
            set: { name in if case .sound(_, let gain) = rule.alert { rule.alert = .sound(name: name, gainDB: gain) } })
    }

    private var gain: Binding<Double> {
        Binding(
            get: { if case .sound(_, let gain) = rule.alert { return gain }; return 0 },
            set: { gain in if case .sound(let name, _) = rule.alert { rule.alert = .sound(name: name, gainDB: gain.rounded()) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: kind) {
                Text("No Alert").tag(Kind.none)
                Text("Silent").tag(Kind.silent)
                Text("Sound").tag(Kind.sound)
                if rule.alert?.speech != nil {
                    Text("Speech").tag(Kind.speech)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Text(EditorText.alertMeaning(rule.alert))
                .font(.callout)
                .foregroundStyle(.secondary)

            if case .sound(let name, let gainDB) = rule.alert {
                HStack(spacing: 10) {
                    Picker("Sound", selection: soundName) {
                        // A sound the rule names but that cannot be found is
                        // still listed, so the choice shows what the rule says.
                        if !model.availableSounds.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                            Text("\(name) (not found)").tag(name)
                        }
                        ForEach(model.availableSounds, id: \.self) { Text($0).tag($0) }
                    }
                    .fixedSize()
                    Button("Test Sound") {
                        testMessage = model.testSound(name, gainDB: gainDB)
                    }
                }
                HStack(spacing: 10) {
                    Text("Gain")
                    Slider(value: gain, in: AlertAction.gainRange, step: 1)
                        .frame(maxWidth: 260)
                    Text(gainDB == 0 ? "0 dB" : "\(gainDB > 0 ? "+" : "−")\(Int(abs(gainDB))) dB")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                if let testMessage {
                    Label(testMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                if model.outputIsSilent {
                    Label(EditorText.outputSilentNote, systemImage: "speaker.slash").foregroundStyle(.orange).font(.callout)
                }
            }
        }
        .onChange(of: rule.alert) { _, _ in testMessage = nil }
    }
}
