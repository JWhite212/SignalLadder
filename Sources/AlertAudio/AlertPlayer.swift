// Sources/AlertAudio/AlertPlayer.swift
// @preconcurrency: in the macOS 26.5 SDK (Xcode 26.6), AVAudioConverter's input block is
// @Sendable and AVAudioPCMBuffer is not Sendable, so returning a buffer from
// it is an error under -warnings-as-errors. The converter calls that block
// synchronously, on the calling thread, before convert returns, so the
// buffer never crosses a thread.
@preconcurrency import AVFoundation
import AudioToolbox
import NotificationCore
import os

/// Plays a rule's sound: level-matched, gain-applied, limited, and reported.
///
/// The graph is the spec's (§5.16), with speech beside the sound:
///
///     player → EQ ────────┐
///                         ├→ alert mixer → Apple PeakLimiter → main mixer
///     speech → speech EQ ─┘
///
/// It is wired once. Every sound is converted to one internal format when
/// first loaded, so a new sound never re-plumbs the graph mid-alert, and its
/// peak is measured on the converted audio — what is actually played. Sound
/// and speech meet ahead of the one limiter: each keeps its own gain, and
/// both share one safety net.
///
/// The engine runs only while a sound plays. A running engine holds the output
/// device awake, which would break the app's near-zero idle cost; starting it
/// on demand adds a few milliseconds to an alert, and nothing to the hours
/// between alerts.
///
/// A new sound interrupts one still playing (§5.15): two alarms at once is
/// noise, not information.
///
/// Sounds are prepared when the rules load, not when an alert fires: decoding
/// then happens off the capture path, and a file that cannot play is a rule
/// problem reported at load rather than silence at the incident.
@MainActor
public final class AlertPlayer {
    public struct Report: Equatable, Sendable {
        /// The name as the library knows it, e.g. "Glass" for a rule's "glass".
        public let sound: String
        /// Level-matching plus the rule's gain.
        public let appliedGainDB: Double
        public let output: OutputState
    }

    public struct SpeechReport: Equatable, Sendable {
        /// The voice's own name, e.g. "Daniel".
        public let voiceName: String
        /// Level-matching plus the rule's gain.
        public let appliedGainDB: Double
        /// False when the voice had not been measured yet, so it spoke at the
        /// default level, which errs quiet.
        public let calibrated: Bool
        public let output: OutputState
    }

    /// What a sound-and-speech alert did with each part. Each is attempted
    /// whether or not the other could be: a voice that has gone must not
    /// silence the sound, nor a missing sound the speech.
    public struct CombinedReport: Equatable, Sendable {
        public let sound: Result<Report, Failure>
        public let speech: Result<SpeechReport, Failure>
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case soundNotFound(String)
        case unreadable(sound: String, reason: String)
        /// The file's audio is below the silence floor: "played" would be a
        /// report of something nobody could hear.
        case silent(String)
        /// Longer than `maximumSeconds`. Every sound is decoded whole into
        /// memory, so a long file dropped into the Sounds folder by mistake
        /// would cost the app gigabytes at the moment it most needs to work.
        case tooLong(String)
        case engineFailed(String)
        /// A test sound was asked for while a real alert was playing.
        case alertPlaying
        case voiceNotFound(String)
        /// The voice renders audio that cannot be brought to the speech format.
        case voiceUnplayable(String)
        /// A voice's level could not be measured in time. It still speaks, at
        /// the default level, and is measured again next time.
        case calibrationTimedOut(String)

        public var description: String {
            switch self {
            case .soundNotFound(let name): return "sound \"\(name)\" was not found"
            case .unreadable(let name, let reason): return "sound \"\(name)\" could not be read: \(reason)"
            case .silent(let name): return "sound \"\(name)\" is silent"
            case .tooLong(let name): return "sound \"\(name)\" is longer than \(Int(AlertPlayer.maximumSeconds)) seconds"
            case .engineFailed(let reason): return "the audio engine failed: \(reason)"
            case .alertPlaying: return "an alert is playing — try again when it has finished"
            case .voiceNotFound(let id): return "voice \"\(id)\" is not installed"
            case .calibrationTimedOut(let id): return "voice \"\(id)\" could not be measured in time"
            case .voiceUnplayable(let id): return "voice \"\(id)\" renders audio that cannot be played"
            }
        }
    }

    /// Live plays through the default output device. Offline renders into
    /// memory and never reaches a speaker, so the real graph can be tested.
    enum Mode { case live, offline }

    /// An alert is a sound, not a recording. Anything longer is refused
    /// before it is decoded.
    nonisolated public static let maximumSeconds: Double = 30

    /// One internal format for every sound: the graph is connected once.
    static let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    /// Speech's format: float32, 22,050 Hz, mono — what Apple's own voices
    /// render (measured). Eloquence voices render at 16,000 Hz and are
    /// converted to it before they are scheduled.
    static let speechFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22_050,
                                            channels: 1, interleaved: false)!

    private let library: SoundLibrary
    private let readOutput: () -> OutputState
    let mode: Mode

    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 0)
    private let speechPlayer = AVAudioPlayerNode()
    private let speechEQ = AVAudioUnitEQ(numberOfBands: 0)
    private let alertMixer = AVAudioMixerNode()
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0, componentFlagsMask: 0))

    private var cache: [URL: (buffer: AVAudioPCMBuffer, peak: Float)] = [:]

    /// When a part counts as finished: once heard, live. Offline nothing is
    /// ever played back, so "played back" never fires; there, rendered is the
    /// nearest thing a test can observe.
    private var completion: AVAudioPlayerNodeCompletionCallbackType {
        mode == .live ? .dataPlayedBack : .dataRendered
    }
    /// Bumped once per alert, so the end of an interrupted one does not stop
    /// the engine under the alert that interrupted it.
    private(set) var generation = 0

    /// Parts of the current alert still to finish: a sound, speech, or both.
    private var partsPlaying = 0

    /// Whether the sound playing now is a real alert — as opposed to a test
    /// sound, or nothing. A test sound is refused while it is: trying out a
    /// sound in the editor must never cut off the alert it is being set up
    /// for. Cleared when the alert finishes or the output changes.
    public private(set) var isPlayingAlert = false
    nonisolated(unsafe) private var configurationObserver: NSObjectProtocol?

    // MARK: Speech state

    /// The synthesizer alerts and tests speak through, held for the app's
    /// lifetime. The first speech after a quiet spell takes up to ~2.5 s to
    /// start; a held synthesizer was heard within 130 ms after 30 minutes idle
    /// (measured).
    private var speaker: AVSpeechSynthesizer?
    /// The synthesizer voices are measured on, also held. Apart from the
    /// speaker because a synthesizer says one thing at a time: an alert
    /// sharing it would wait behind a calibration, or be lost behind one that
    /// hung. Holding it also keeps the process's speech service started.
    private var calibrator: AVSpeechSynthesizer?
    /// Each voice's peak, from one silent render of `calibrationPhrase`.
    private(set) var speechPeaks: [String: Float] = [:]
    /// Voices whose audio could not be brought to the speech format.
    private(set) var unplayableVoices: Set<String> = []
    private var calibrations: [String: Task<Void, Error>] = [:]
    /// Counted, so a test can prove a voice is measured once.
    private(set) var calibrationRenders = 0
    /// What the speaker is saying, as a token: an alert, a test or a warm-up;
    /// 0 when it is saying nothing. A new alert cuts off whatever it is, and
    /// only the utterance holding the token may clear it.
    private var speakerOccupant = 0
    private var lastOccupant = 0
    /// How long speech may go without finishing before its part of the alert
    /// is ended anyway. Rendering runs at least 13 times faster than real
    /// time and a line is capped at 240 characters, so even a cold start
    /// finishes well inside it.
    var speechStallTimeout: TimeInterval = 15
    /// The alert whose speech last ended, so a test can wait for it.
    private(set) var lastSpeechEnded: Int?
    /// Called with every spoken alert's latency, for tests.
    var onSpeechLatency: ((_ seconds: Double, _ calibrated: Bool) -> Void)?

    static let calibrationPhrase = "This is how loud this voice speaks."
    private static let speechLog = Logger(subsystem: "com.jamiewhite.signalladder", category: "speech")

    public convenience init(library: SoundLibrary = SoundLibrary(),
                            readOutput: @escaping () -> OutputState = OutputState.current) {
        self.init(library: library, readOutput: readOutput, mode: .live)
    }

    init(library: SoundLibrary, readOutput: @escaping () -> OutputState, mode: Mode) {
        self.library = library
        self.readOutput = readOutput
        self.mode = mode
        for node in [player, eq, speechPlayer, speechEQ, alertMixer, limiter] as [AVAudioNode] {
            engine.attach(node)
        }
        engine.connect(player, to: eq, format: Self.format)
        engine.connect(eq, to: alertMixer, fromBus: 0, toBus: 0, format: Self.format)
        engine.connect(speechPlayer, to: speechEQ, format: Self.speechFormat)
        engine.connect(speechEQ, to: alertMixer, fromBus: 0, toBus: 1, format: Self.speechFormat)
        engine.connect(alertMixer, to: limiter, format: Self.format)
        engine.connect(limiter, to: engine.mainMixerNode, format: Self.format)
        if mode == .offline {
            try? engine.enableManualRenderingMode(.offline, format: Self.format, maximumFrameCount: 4096)
        }

        // A change of output device or its format stops the engine. Posted on
        // an audio thread, so the work hops to the main actor.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.outputChanged() }
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    /// The device went away or changed. Resets to the state between alerts —
    /// engine stopped, player stopped, nothing pending — so the next alert
    /// starts cleanly on whatever the output now is, instead of trusting flags
    /// the change may have left stale. A completion still owed by the sound
    /// that was cut off is disowned by the generation bump.
    func outputChanged() {
        generation += 1
        isPlayingAlert = false
        partsPlaying = 0
        player.stop()
        speechPlayer.stop()
        engine.stop()
        stopSpeakerIfOccupied()
        if mode == .live {
            // Picks up the new device's format; the rest of the graph is
            // fixed at `format` and needs nothing.
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        }
    }

    /// Decodes, converts and measures `name` now, so an alert never waits on
    /// the disk. Throws what `play` would: a sound that cannot be heard is
    /// refused here, where the rule can be reported.
    public func prepare(sound name: String) throws {
        guard let url = library.url(for: name) else { throw Failure.soundNotFound(name) }
        let displayName = url.deletingPathExtension().lastPathComponent
        let (_, peak) = try load(url, as: displayName)
        guard Loudness.appliedGainDB(forPeak: peak, ruleGainDB: 0) != nil else { throw Failure.silent(displayName) }
    }

    /// Drops every decoded sound. Called before the rules are prepared again,
    /// so a file edited since is read afresh and a sound no rule uses is not
    /// held in memory.
    public func forgetPreparedSounds() {
        cache.removeAll()
    }

    /// Plays `name` for a rule asking for `ruleGainDB`, and reports what was
    /// done. Throws rather than returning quietly whenever the sound could not
    /// be made audible — a failure must be recorded as one.
    ///
    /// A real alert: it cuts off a test sound, and nothing cuts it off but
    /// another alert.
    @discardableResult
    public func play(sound name: String, ruleGainDB: Double) throws -> Report {
        try start(name, ruleGainDB: ruleGainDB, isAlert: true)
    }

    /// Plays a rule's sound so the user can judge it — through the same graph,
    /// at the same level-matching and gain, so it sounds like the real thing
    /// (§7.5). Refused while a real alert plays. Recorded nowhere.
    @discardableResult
    public func testSound(_ name: String, ruleGainDB: Double) throws -> Report {
        guard !isPlayingAlert else { throw Failure.alertPlaying }
        return try start(name, ruleGainDB: ruleGainDB, isAlert: false)
    }

    private func start(_ name: String, ruleGainDB: Double, isAlert: Bool) throws -> Report {
        // Resolved before the graph is claimed: a sound that cannot play
        // throws without cutting off whatever was playing.
        let sound = try resolve(name, ruleGainDB: ruleGainDB)
        let thisPlay = try beginAlert(parts: 1, isAlert: isAlert)
        return schedule(sound, for: thisPlay)
    }

    /// A sound, loaded and level-matched, ready to schedule.
    struct ResolvedSound {
        let buffer: AVAudioPCMBuffer
        let displayName: String
        let gainDB: Double
    }

    func resolve(_ name: String, ruleGainDB: Double) throws -> ResolvedSound {
        guard let url = library.url(for: name) else { throw Failure.soundNotFound(name) }
        let displayName = url.deletingPathExtension().lastPathComponent
        let (buffer, peak) = try load(url, as: displayName)
        guard let gain = Loudness.appliedGainDB(forPeak: peak, ruleGainDB: ruleGainDB) else {
            throw Failure.silent(displayName)
        }
        return ResolvedSound(buffer: buffer, displayName: displayName, gainDB: gain)
    }

    /// Claims the graph for a new alert: stops whatever either node was
    /// playing, starts the engine, and returns the generation every part of
    /// this alert is scheduled under. Called once per alert however many parts
    /// it has. A sound and its speech each claiming the graph would each stop
    /// everything, and the second would cut off the first.
    ///
    /// - Parameter parts: how many parts must finish before the alert is over.
    func beginAlert(parts: Int, isAlert: Bool) throws -> Int {
        player.stop()
        speechPlayer.stop()
        stopSpeakerIfOccupied()
        if !engine.isRunning {
            do { try engine.start() } catch { throw Failure.engineFailed(error.localizedDescription) }
        }
        generation += 1
        partsPlaying = parts
        // Whatever was playing has just been cut off, so this is now the
        // whole truth about what is playing.
        isPlayingAlert = isAlert
        return generation
    }

    /// Schedules a resolved sound as a part of the alert `play`.
    @discardableResult
    func schedule(_ sound: ResolvedSound, for play: Int) -> Report {
        eq.globalGain = Float(sound.gainDB)
        player.scheduleBuffer(sound.buffer, at: nil, options: .interrupts, completionCallbackType: completion) { [weak self] _ in
            DispatchQueue.main.async { self?.finished(play) }
        }
        // Unconditional: a no-op when already playing, and never skipped on
        // the word of an `isPlaying` a device change may have left stale.
        player.play()
        return Report(sound: sound.displayName, appliedGainDB: sound.gainDB, output: readOutput())
    }

    // MARK: - Speech, as a part of an alert

    /// Level-matching plus the rule's gain for the speech part.
    func setSpeechGain(_ gainDB: Double) {
        speechEQ.globalGain = Float(gainDB)
    }

    /// Schedules one rendered buffer of speech for the alert `play`, in
    /// `speechFormat`. Dropped if that alert has been interrupted since:
    /// buffers go on arriving after an utterance is cut off, and must not play
    /// under the alert that cut it off.
    func scheduleSpeech(_ buffer: AVAudioPCMBuffer, for play: Int) {
        guard play == generation else { return }
        speechPlayer.scheduleBuffer(buffer)
        speechPlayer.play()
    }

    /// The end of the speech for `play`. Its part finishes once everything
    /// scheduled before this has been heard: the synthesizer's last callback
    /// carries no audio to hang a completion on, so a single silent frame does.
    func endSpeech(for play: Int) {
        guard play == generation else { return }
        lastSpeechEnded = play
        let marker = AVAudioPCMBuffer(pcmFormat: Self.speechFormat, frameCapacity: 1)!
        marker.frameLength = 1
        marker.floatChannelData![0][0] = 0
        speechPlayer.scheduleBuffer(marker, at: nil, options: [], completionCallbackType: completion) { [weak self] _ in
            DispatchQueue.main.async { self?.finished(play) }
        }
        speechPlayer.play()
    }

    /// Plays a rule's sound and describes the result as the Inspector records
    /// it. Never throws: at an incident a failure is recorded, not raised.
    ///
    /// The row keeps the rule's gain as written — the number the user chose —
    /// not the level-matching applied beneath it.
    public func outcome(ofPlaying name: String, ruleGainDB: Double) -> AlertOutcome {
        do {
            let report = try play(sound: name, ruleGainDB: ruleGainDB)
            return .played(sound: report.sound, gainDB: ruleGainDB, outputSilent: report.output.isEffectivelySilent)
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// Only the most recent alert's completions count; an interrupted one's
    /// arrive after its replacement has started, and must neither stop the
    /// engine under it nor declare the alert over. An alert with a sound and
    /// speech is over only when both have finished.
    func finished(_ play: Int) {
        guard play == generation else { return }
        partsPlaying -= 1
        guard partsPlaying <= 0 else { return }
        isPlayingAlert = false
        guard mode == .live else { return }
        player.stop()
        speechPlayer.stop()
        engine.stop()
    }

    private func load(_ url: URL, as name: String) throws -> (buffer: AVAudioPCMBuffer, peak: Float) {
        if let cached = cache[url] { return cached }
        do {
            let file = try AVAudioFile(forReading: url)
            guard Double(file.length) <= Self.maximumSeconds * file.processingFormat.sampleRate else {
                throw Failure.tooLong(name)
            }
            guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                throw Failure.unreadable(sound: name, reason: "it is empty")
            }
            try file.read(into: source)
            let converted = try convert(source, name: name)
            let loaded = (converted, Self.peak(of: converted))
            cache[url] = loaded
            return loaded
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.unreadable(sound: name, reason: error.localizedDescription)
        }
    }

    private func convert(_ source: AVAudioPCMBuffer, name: String) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: source.format, to: Self.format) else {
            throw Failure.unreadable(sound: name, reason: "its format cannot be converted")
        }
        let ratio = Self.format.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else {
            throw Failure.unreadable(sound: name, reason: "no buffer for conversion")
        }
        var supplied = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return source
        }
        if let conversionError { throw Failure.unreadable(sound: name, reason: conversionError.localizedDescription) }
        return output
    }

    static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[i])) }
        }
        return peak
    }

    // MARK: - Speaking

    /// Measures `voiceIdentifier`'s level with one silent render, once, and in
    /// doing so starts the speech service and warms the synthesizer. Called
    /// in the background when rules load, and when the editor's voice picker
    /// chooses a voice. Nothing waits on it: an alert for a voice not yet
    /// measured speaks at once, at the default level.
    public func prepareSpeech(voiceIdentifier id: String) async throws {
        guard let voice = Self.installedVoice(id) else { throw Failure.voiceNotFound(id) }
        if unplayableVoices.contains(id) { throw Failure.voiceUnplayable(id) }
        if speechPeaks[id] != nil { return }
        if let running = calibrations[id] {
            try await running.value
            return
        }
        let calibration = Task { @MainActor in
            speechPeaks[id] = try await measure(voice)
            warmSpeaker(with: voice)
        }
        calibrations[id] = calibration
        defer { calibrations[id] = nil }
        try await calibration.value
    }

    /// Speaks `text` as a real alert: it cuts off whatever was playing, and
    /// nothing cuts it off but another alert. Returns as soon as speech is
    /// asked for; the audio follows as it renders.
    @discardableResult
    public func speak(_ text: String, voiceIdentifier: String, rate: Float, pitchMultiplier: Float,
                      ruleGainDB: Double) throws -> SpeechReport {
        let voice = try findVoice(voiceIdentifier)
        let play = try beginAlert(parts: 1, isAlert: true)
        return startSpeech(text, voice: voice, rate: rate, pitchMultiplier: pitchMultiplier,
                           ruleGainDB: ruleGainDB, for: play)
    }

    /// Speaks `text` so the user can judge it, through the same graph and
    /// level-matching as an alert. Refused while a real alert plays.
    @discardableResult
    public func testSpeech(_ text: String, voiceIdentifier: String, rate: Float, pitchMultiplier: Float,
                           ruleGainDB: Double) throws -> SpeechReport {
        guard !isPlayingAlert else { throw Failure.alertPlaying }
        let voice = try findVoice(voiceIdentifier)
        let play = try beginAlert(parts: 1, isAlert: false)
        return startSpeech(text, voice: voice, rate: rate, pitchMultiplier: pitchMultiplier,
                           ruleGainDB: ruleGainDB, for: play)
    }

    /// A sound, then speech, as one alert: the graph is claimed once, the
    /// sound is scheduled before speech is asked for, and each part is
    /// attempted whether or not the other could be.
    public func playAndSpeak(sound name: String, soundGainDB: Double, text: String, voiceIdentifier: String,
                             rate: Float, pitchMultiplier: Float, speechGainDB: Double) -> CombinedReport {
        let sound = Result { try resolve(name, ruleGainDB: soundGainDB) }.mapError(Self.failure)
        let voice = Result { try findVoice(voiceIdentifier) }.mapError(Self.failure)
        if case .failure(let soundFailure) = sound, case .failure(let voiceFailure) = voice {
            return CombinedReport(sound: .failure(soundFailure), speech: .failure(voiceFailure))
        }
        var parts = 0
        if case .success = sound { parts += 1 }
        if case .success = voice { parts += 1 }
        let play: Int
        do {
            play = try beginAlert(parts: parts, isAlert: true)
        } catch {
            let failure = Self.failure(error)
            return CombinedReport(sound: .failure(failure), speech: .failure(failure))
        }
        let soundReport = sound.map { schedule($0, for: play) }
        let speechReport = voice.map {
            startSpeech(text, voice: $0, rate: rate, pitchMultiplier: pitchMultiplier, ruleGainDB: speechGainDB, for: play)
        }
        return CombinedReport(sound: soundReport, speech: speechReport)
    }

    /// Speaks a rule's line and describes the result as the Inspector records
    /// it. Never throws: at an incident a failure is recorded, not raised.
    public func outcome(ofSpeaking text: String, speech: SpeechAction) -> AlertOutcome {
        do {
            let report = try speak(text, voiceIdentifier: speech.voiceIdentifier, rate: speech.rate,
                                   pitchMultiplier: speech.pitchMultiplier, ruleGainDB: speech.gainDB)
            return .spoke(text: text, voice: report.voiceName, gainDB: speech.gainDB,
                          outputSilent: report.output.isEffectivelySilent)
        } catch {
            return .couldNotSpeak(String(describing: error))
        }
    }

    /// A rule's sound and then its line, as one alert, described part by part.
    public func outcome(ofPlaying name: String, ruleGainDB: Double, thenSpeaking text: String,
                        speech: SpeechAction) -> AlertOutcome {
        let report = playAndSpeak(sound: name, soundGainDB: ruleGainDB, text: text,
                                  voiceIdentifier: speech.voiceIdentifier, rate: speech.rate,
                                  pitchMultiplier: speech.pitchMultiplier, speechGainDB: speech.gainDB)
        switch (report.sound, report.speech) {
        case (.success(let sound), .success(let spoken)):
            return .playedAndSpoke(sound: sound.sound, soundGainDB: ruleGainDB, text: text, voice: spoken.voiceName,
                                   speechGainDB: speech.gainDB, outputSilent: sound.output.isEffectivelySilent)
        case (.success(let sound), .failure(let failure)):
            return .playedButNotSpoken(sound: sound.sound, gainDB: ruleGainDB, reason: failure.description,
                                       outputSilent: sound.output.isEffectivelySilent)
        case (.failure(let failure), .success(let spoken)):
            return .spokeButNotPlayed(text: text, voice: spoken.voiceName, gainDB: speech.gainDB,
                                      reason: failure.description, outputSilent: spoken.output.isEffectivelySilent)
        case (.failure(let soundFailure), .failure(let speechFailure)):
            return .failed("\(soundFailure), and could not speak: \(speechFailure)")
        }
    }

    /// The installed voice with this identifier, or nil. "Installed" means
    /// listed by `speechVoices()`, the same test the rules loader uses.
    /// `AVSpeechSynthesisVoice(identifier:)` cannot be trusted for this: on the
    /// macOS 15 CI runner (2026-09-29) it returned a fallback voice (Samantha)
    /// for an identifier that is not installed rather than nil, so a misspelt
    /// voice would speak in someone else's voice instead of being reported.
    static func installedVoice(_ id: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().first { $0.identifier == id }
    }

    private func findVoice(_ id: String) throws -> AVSpeechSynthesisVoice {
        guard let voice = Self.installedVoice(id) else { throw Failure.voiceNotFound(id) }
        if unplayableVoices.contains(id) { throw Failure.voiceUnplayable(id) }
        return voice
    }

    private static func failure(_ error: Error) -> Failure {
        error as? Failure ?? .engineFailed(String(describing: error))
    }

    private func speakerSynthesizer() -> AVSpeechSynthesizer {
        if let speaker { return speaker }
        let made = AVSpeechSynthesizer()
        speaker = made
        return made
    }

    private func calibratorSynthesizer() -> AVSpeechSynthesizer {
        if let calibrator { return calibrator }
        let made = AVSpeechSynthesizer()
        calibrator = made
        return made
    }

    /// Takes the speaker for a new utterance and returns its token.
    private func occupySpeaker() -> Int {
        lastOccupant += 1
        speakerOccupant = lastOccupant
        return lastOccupant
    }

    private func stopSpeakerIfOccupied() {
        guard speakerOccupant != 0 else { return }
        speaker?.stopSpeaking(at: .immediate)
        speakerOccupant = 0
    }

    /// A first utterance through the speaker with this voice, silent and
    /// discarded, so an alert's first line is not also the speaker's first.
    /// Only when the speaker is free, and any alert cuts it off.
    private func warmSpeaker(with voice: AVSpeechSynthesisVoice) {
        guard speakerOccupant == 0 else { return }
        let synthesizer = speakerSynthesizer()
        let occupant = occupySpeaker()
        let utterance = AVSpeechUtterance(string: Self.calibrationPhrase)
        utterance.voice = voice
        synthesizer.write(utterance) { [weak self] buffer in
            Self.onMain {
                guard let self, let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength == 0 else { return }
                if self.speakerOccupant == occupant { self.speakerOccupant = 0 }
            }
        }
    }

    /// Asks for speech and schedules its buffers as they arrive, under
    /// `play`. Buffers for an alert that has since been interrupted are
    /// dropped by `scheduleSpeech`, whatever the synthesizer does after being
    /// told to stop — that is unmeasured, so nothing relies on it.
    private func startSpeech(_ text: String, voice: AVSpeechSynthesisVoice, rate: Float, pitchMultiplier: Float,
                             ruleGainDB: Double, for play: Int) -> SpeechReport {
        let synthesizer = speakerSynthesizer()
        let measured = speechPeaks[voice.identifier]
        // Unmeasured, it plays as if it peaked at full scale: at most about a
        // decibel quieter than measured, and never louder.
        let gain = Loudness.appliedGainDB(forPeak: measured ?? 1, ruleGainDB: ruleGainDB) ?? ruleGainDB
        setSpeechGain(gain)
        let occupant = occupySpeaker()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        let converter = SpeechConverter()
        let started = DispatchTime.now().uptimeNanoseconds
        let firstBuffer = Flag()
        let scheduledAudio = Flag()
        // Ended once, whichever comes first: the synthesizer's last callback,
        // or the watchdog. Ended twice, a sound-and-speech alert would be
        // declared over while its sound was still playing.
        let ended = Flag()
        synthesizer.write(utterance) { [weak self] buffer in
            Self.onMain {
                guard let self, let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    guard ended.set() else { return }
                    if let tail = converter.flush() { self.scheduleSpeech(tail, for: play) }
                    if self.speakerOccupant == occupant { self.speakerOccupant = 0 }
                    // "Spoke" was reported when speech was asked for; a line
                    // that produced nothing playable must at least leave a
                    // trace. No words, as ever.
                    if scheduledAudio.set() { Self.speechLog.notice("spoken line produced no playable audio") }
                    self.endSpeech(for: play)
                    return
                }
                // Once the part has ended — by the watchdog, the synthesizer
                // having been told to stop — nothing more of it is heard,
                // even while its alert's sound plays on.
                guard !ended.isSet else { return }
                if firstBuffer.set() {
                    let seconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
                    self.logSpeechLatency(seconds, calibrated: measured != nil)
                }
                if let converted = converter.convert(pcm) {
                    _ = scheduledAudio.set()
                    self.scheduleSpeech(converted, for: play)
                }
            }
        }
        // A synthesizer that stops calling back would otherwise leave the
        // alert unfinished — Test Sound and Test Speech refused, and the
        // engine running — until the next alert.
        DispatchQueue.main.asyncAfter(deadline: .now() + speechStallTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, ended.set() else { return }
                Self.speechLog.notice("speech did not finish in time; its part of the alert was ended")
                if self.speakerOccupant == occupant { self.stopSpeakerIfOccupied() }
                self.endSpeech(for: play)
            }
        }
        if measured == nil {
            let id = voice.identifier
            Task { try? await self.prepareSpeech(voiceIdentifier: id) }
        }
        return SpeechReport(voiceName: voice.name, appliedGainDB: gain, calibrated: measured != nil, output: readOutput())
    }

    /// Renders `calibrationPhrase` silently and returns its peak. Waits on the
    /// synthesizer's callback, never by blocking or pumping the main run loop.
    ///
    /// Each buffer also goes through the converter an alert would use, so a
    /// voice whose audio cannot be played is refused here, before any alert
    /// reports having spoken with it.
    private func measure(_ voice: AVSpeechSynthesisVoice) async throws -> Float {
        let synthesizer = calibratorSynthesizer()
        calibrationRenders += 1
        let utterance = AVSpeechUtterance(string: Self.calibrationPhrase)
        utterance.voice = voice
        let id = voice.identifier
        let converter = SpeechConverter()
        return try await withCheckedThrowingContinuation { continuation in
            let done = Flag()
            var peak: Float = 0
            var playable = true
            synthesizer.write(utterance) { [weak self] buffer in
                Self.onMain {
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength == 0 {
                        guard done.set() else { return }
                        if playable {
                            continuation.resume(returning: peak)
                        } else {
                            self?.unplayableVoices.insert(id)
                            continuation.resume(throwing: Failure.voiceUnplayable(id))
                        }
                    } else {
                        peak = max(peak, Self.peak(of: pcm))
                        if converter.convert(pcm) == nil { playable = false }
                    }
                }
            }
            // A calibration must not wait for ever. Stopping the calibrator
            // also clears anything queued behind the one that hung.
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                MainActor.assumeIsolated {
                    guard done.set() else { return }
                    self?.calibrator?.stopSpeaking(at: .immediate)
                    continuation.resume(throwing: Failure.calibrationTimedOut(id))
                }
            }
        }
    }

    /// The only record a spoken alert leaves: how long it took, never what it
    /// said. There is no parameter a sentence could be passed through.
    func logSpeechLatency(_ seconds: Double, calibrated: Bool) {
        // Notice, not info: info is kept in memory only, and this log exists
        // to be read after a night of idle.
        Self.speechLog.notice("speech began \(seconds * 1000, format: .fixed(precision: 1)) ms after it was asked for (voice \(calibrated ? "measured" : "not yet measured", privacy: .public))")
        onSpeechLatency?(seconds, calibrated)
    }

    /// The synthesizer calls back on the main thread (measured); if it ever
    /// does not, the work hops there rather than racing the main actor.
    private static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.async { work() }
        }
    }

    // MARK: - Offline rendering, for tests

    /// Pulls rendered audio out of the offline graph and measures it.
    func renderOffline(seconds: Double) throws -> (peak: Float, samplesOverFullScale: Int) {
        precondition(mode == .offline, "offline rendering only")
        let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        var peak: Float = 0
        var over = 0
        var remaining = AVAudioFrameCount(seconds * Self.format.sampleRate)
        while remaining > 0 {
            let frames = min(4096, remaining)
            guard try engine.renderOffline(frames, to: out) == .success else { break }
            if let channels = out.floatChannelData {
                for channel in 0..<Int(out.format.channelCount) {
                    for i in 0..<Int(out.frameLength) {
                        let sample = abs(channels[channel][i])
                        peak = max(peak, sample)
                        if sample > 1.0 { over += 1 }
                    }
                }
            }
            remaining -= frames
        }
        return (peak, over)
    }
}
