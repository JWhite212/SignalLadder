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
        case engineFailed(String)

        public var description: String {
            switch self {
            case .soundNotFound(let name): return "sound \"\(name)\" was not found"
            case .unreadable(let name, let reason): return "sound \"\(name)\" could not be read: \(reason)"
            case .silent(let name): return "sound \"\(name)\" is silent"
            case .engineFailed(let reason): return "the audio engine failed: \(reason)"
            }
        }
    }

    /// Live plays through the default output device. Offline renders into
    /// memory and never reaches a speaker, so the real graph can be tested.
    enum Mode { case live, offline }

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
    private var generation = 0

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
    }

    /// Plays `name` for a rule asking for `ruleGainDB`, and reports what was
    /// done. Throws rather than returning quietly whenever the sound could not
    /// be made audible — a failure must be recorded as one.
    @discardableResult
    public func play(sound name: String, ruleGainDB: Double) throws -> Report {
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
        if !player.isPlaying { player.play() }

        return Report(sound: displayName, appliedGainDB: gain, output: readOutput())
    }

    private func finished(_ play: Int) {
        // Only the most recent sound may stop the engine; an interrupted one's
        // completion arrives after its replacement has started.
        guard play == generation, mode == .live else { return }
        player.stop()
        engine.stop()
    }

    private func load(_ url: URL, as name: String) throws -> (buffer: AVAudioPCMBuffer, peak: Float) {
        if let cached = cache[url] { return cached }
        do {
            let file = try AVAudioFile(forReading: url)
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
