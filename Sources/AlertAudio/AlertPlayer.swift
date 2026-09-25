// Sources/AlertAudio/AlertPlayer.swift
import AVFoundation
import AudioToolbox
import NotificationCore

/// Plays a rule's sound: level-matched, gain-applied, limited, and reported.
///
/// The graph is the spec's (§5.16): player → EQ (global gain) → Apple
/// PeakLimiter → main mixer. It is wired once. Every sound is converted to one
/// internal format when first loaded, so a new sound never re-plumbs the graph
/// mid-alert, and its peak is measured on the converted audio — what is
/// actually played.
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

        public var description: String {
            switch self {
            case .soundNotFound(let name): return "sound \"\(name)\" was not found"
            case .unreadable(let name, let reason): return "sound \"\(name)\" could not be read: \(reason)"
            case .silent(let name): return "sound \"\(name)\" is silent"
            case .tooLong(let name): return "sound \"\(name)\" is longer than \(Int(AlertPlayer.maximumSeconds)) seconds"
            case .engineFailed(let reason): return "the audio engine failed: \(reason)"
            case .alertPlaying: return "an alert is playing — try again when it has finished"
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

    private let library: SoundLibrary
    private let readOutput: () -> OutputState
    let mode: Mode

    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 0)
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0, componentFlagsMask: 0))

    private var cache: [URL: (buffer: AVAudioPCMBuffer, peak: Float)] = [:]
    /// Bumped on every play, so the end of an interrupted sound does not stop
    /// the engine under the sound that interrupted it.
    private(set) var generation = 0

    /// Whether the sound playing now is a real alert — as opposed to a test
    /// sound, or nothing. A test sound is refused while it is: trying out a
    /// sound in the editor must never cut off the alert it is being set up
    /// for. Cleared when the alert finishes or the output changes.
    public private(set) var isPlayingAlert = false
    nonisolated(unsafe) private var configurationObserver: NSObjectProtocol?

    public convenience init(library: SoundLibrary = SoundLibrary(),
                            readOutput: @escaping () -> OutputState = OutputState.current) {
        self.init(library: library, readOutput: readOutput, mode: .live)
    }

    init(library: SoundLibrary, readOutput: @escaping () -> OutputState, mode: Mode) {
        self.library = library
        self.readOutput = readOutput
        self.mode = mode
        engine.attach(player)
        engine.attach(eq)
        engine.attach(limiter)
        engine.connect(player, to: eq, format: Self.format)
        engine.connect(eq, to: limiter, format: Self.format)
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
        player.stop()
        engine.stop()
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
        guard let url = library.url(for: name) else { throw Failure.soundNotFound(name) }
        let displayName = url.deletingPathExtension().lastPathComponent
        let (buffer, peak) = try load(url, as: displayName)
        guard let gain = Loudness.appliedGainDB(forPeak: peak, ruleGainDB: ruleGainDB) else {
            throw Failure.silent(displayName)
        }

        eq.globalGain = Float(gain)
        if !engine.isRunning {
            do { try engine.start() } catch { throw Failure.engineFailed(error.localizedDescription) }
        }

        generation += 1
        let thisPlay = generation
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.finished(thisPlay) }
        }
        // Unconditional: a no-op when already playing, and never skipped on
        // the word of an `isPlaying` a device change may have left stale.
        player.play()
        // Whatever was playing has just been cut off, so this is now the
        // whole truth about what is playing.
        isPlayingAlert = isAlert

        return Report(sound: displayName, appliedGainDB: gain, output: readOutput())
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

    /// Only the most recent sound's completion counts; an interrupted one's
    /// arrives after its replacement has started, and must neither stop the
    /// engine under it nor declare the alert over.
    func finished(_ play: Int) {
        guard play == generation else { return }
        isPlayingAlert = false
        guard mode == .live else { return }
        player.stop()
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
