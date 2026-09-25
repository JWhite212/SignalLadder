// Sources/SignalLadder/AlertEditorView.swift
import AppKit
import SwiftUI
import NotificationCore

/// What the rule does on a match: nothing, stay quiet on purpose, play a
/// sound, speak a line, or play a sound and then speak — each at a chosen
/// gain, and each with a way to try it as the alert will play it, which never
/// cuts off a real alert.
///
/// How the choices change the rule is `AlertEditing`, tested in the core; the
/// view only shows it.
struct AlertEditorView: View {
    @ObservedObject var model: RuleEditorModel
    @Binding var rule: Rule
    /// Why the last test did not play, shown until the next try.
    @State private var testMessage: String?
    /// Speech set aside by switching it off, restored by switching it on.
    @State private var rememberedSpeech: SpeechAction?

    /// Read & Speak (Spoken Content before macOS 26), where voices are added.
    private static let voiceSettings = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent")!

    private var kind: Binding<AlertEditing.Kind> {
        Binding(
            get: { AlertEditing.kind(of: rule.alert) },
            set: { kind in
                let (alert, remembered) = AlertEditing.choosing(kind, from: rule.alert, remembered: rememberedSpeech,
                                                                defaultSound: model.defaultSound, defaultVoice: model.defaultVoice)
                rule.alert = alert
                rememberedSpeech = remembered
                if let voice = alert?.speech?.voiceIdentifier { model.prepareVoice(voice) }
            })
    }

    private var alsoSpeak: Binding<Bool> {
        Binding(
            get: { if case .soundAndSpeak = rule.alert { return true }; return false },
            set: { on in
                let (alert, remembered) = AlertEditing.settingAlsoSpeak(on, on: rule.alert, remembered: rememberedSpeech,
                                                                        defaultVoice: model.defaultVoice)
                rule.alert = alert
                rememberedSpeech = remembered
                if on, let voice = alert?.speech?.voiceIdentifier { model.prepareVoice(voice) }
            })
    }

    private var soundName: Binding<String> {
        Binding(
            // Shown with the library's own spelling: sound names match
            // ignoring case, but a picker only selects an exact tag.
            get: {
                guard let name = rule.alert?.soundName else { return "" }
                return model.availableSounds.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
            },
            set: { rule.alert = AlertEditing.replacingSound(in: rule.alert, name: $0) })
    }

    private var soundGain: Binding<Double> {
        Binding(
            get: {
                switch rule.alert {
                case .sound(_, let gain)?, .soundAndSpeak(_, let gain, _)?: return gain
                default: return 0
                }
            },
            set: { rule.alert = AlertEditing.replacingSound(in: rule.alert, gainDB: $0.rounded()) })
    }

    /// One field of the rule's speech.
    private func speech<Value>(_ keyPath: WritableKeyPath<SpeechAction, Value>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { rule.alert?.speech?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard var speech = rule.alert?.speech else { return }
                speech[keyPath: keyPath] = value
                rule.alert = AlertEditing.replacingSpeech(in: rule.alert, with: speech)
            })
    }

    private var voice: Binding<String> {
        Binding(
            get: { rule.alert?.speech?.voiceIdentifier ?? "" },
            set: { identifier in
                speech(\.voiceIdentifier, default: "").wrappedValue = identifier
                model.prepareVoice(identifier)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: kind) {
                Text("No Alert").tag(AlertEditing.Kind.none)
                Text("Silent").tag(AlertEditing.Kind.silent)
                Text("Sound").tag(AlertEditing.Kind.sound)
                Text("Speech").tag(AlertEditing.Kind.speech)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Text(EditorText.alertMeaning(rule.alert))
                .font(.callout)
                .foregroundStyle(.secondary)

            if let name = rule.alert?.soundName {
                soundControls(name: name)
                Toggle("Also speak it", isOn: alsoSpeak)
            }
            if let speech = rule.alert?.speech {
                speechControls(speech)
            }
            if rule.alert?.soundName != nil || rule.alert?.speech != nil {
                if let testMessage {
                    Label(testMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                if model.outputIsSilent {
                    Label(EditorText.outputSilentNote, systemImage: "speaker.slash").foregroundStyle(.orange).font(.callout)
                }
            }
        }
        .onChange(of: rule.alert) { _, _ in testMessage = nil }
        .onChange(of: rule.id) { _, _ in rememberedSpeech = nil }
    }

    @ViewBuilder
    private func soundControls(name: String) -> some View {
        HStack(spacing: 10) {
            Picker("Sound", selection: soundName) {
                // A sound the rule names but that cannot be found is still
                // listed, so the choice shows what the rule says.
                if !model.availableSounds.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    Text("\(name) (not found)").tag(name)
                }
                ForEach(model.availableSounds, id: \.self) { Text($0).tag($0) }
            }
            .fixedSize()
            Button("Test Sound") {
                testMessage = model.testSound(name, gainDB: soundGain.wrappedValue)
            }
        }
        gainRow(soundGain)
    }

    @ViewBuilder
    private func speechControls(_ speech: SpeechAction) -> some View {
        let voices = model.availableVoices
        HStack(spacing: 10) {
            Picker("Voice", selection: voice) {
                // As for sounds: a voice the rule names that is not installed
                // is still shown, so the choice shows what the rule says.
                if !voices.contains(where: { $0.id == speech.voiceIdentifier }) {
                    Text("\(speech.voiceIdentifier) (not installed)").tag(speech.voiceIdentifier)
                }
                ForEach(voices) { Text("\($0.name) — \($0.language)").tag($0.id) }
            }
            .fixedSize()
            Button("More Voices…") { NSWorkspace.shared.open(Self.voiceSettings) }
                .buttonStyle(.link)
        }
        HStack(spacing: 10) {
            Text("Says")
            TextField(SpeechAction.defaultTemplate, text: self.speech(\.template, default: SpeechAction.defaultTemplate))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Button("Test Speech") {
                testMessage = model.testSpeech(speech)
            }
        }
        Text(EditorText.speechTemplateHelp)
            .font(.caption)
            .foregroundStyle(.secondary)
        sliderRow("Rate", value: self.speech(\.rate, default: 0.5), in: SpeechAction.rateRange, step: 0.05)
        sliderRow("Pitch", value: self.speech(\.pitchMultiplier, default: 1), in: SpeechAction.pitchRange, step: 0.05)
        gainRow(self.speech(\.gainDB, default: 0), label: "Speech gain")
    }

    private func gainRow(_ gain: Binding<Double>, label: String = "Gain") -> some View {
        HStack(spacing: 10) {
            Text(label)
            Slider(value: gain, in: AlertAction.gainRange, step: 1)
                .frame(maxWidth: 260)
            Text(EditorText.gainText(gain.wrappedValue))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }

    /// Rate and pitch in their own units, shown as numbers: no friendlier
    /// unit is established for either.
    private func sliderRow(_ label: String, value: Binding<Float>, in range: ClosedRange<Float>, step: Float) -> some View {
        HStack(spacing: 10) {
            Text(label)
            Slider(value: value, in: range, step: step)
                .frame(maxWidth: 260)
            Text(String(format: "%.2f", value.wrappedValue))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }
}
