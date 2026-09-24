// docs/dev/spikes/audio-headroom.swift — run: swiftc -O audio-headroom.swift -o /tmp/ah && /tmp/ah
// Offline, silent measurement of §5.16's audio claims. Renders to memory via
// AVAudioEngine manual rendering — nothing reaches an output device.
import AVFoundation
import AudioToolbox

struct Result { let peak: Float; let clipped: Int; let frames: Int }

func peakOf(_ buffer: AVAudioPCMBuffer) -> Float {
    var peak: Float = 0
    for ch in 0..<Int(buffer.format.channelCount) {
        let p = buffer.floatChannelData![ch]
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(p[i])) }
    }
    return peak
}

func dB(_ amplitude: Float) -> String {
    amplitude <= 0 ? "-inf" : String(format: "%+.2f", 20 * log10(amplitude))
}

/// Renders `file` through player → EQ(globalGain) → [limiter] → mainMixer, offline.
func render(_ url: URL, gainDB: Float, limiter: Bool) throws -> Result {
    let file = try AVAudioFile(forReading: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate,
                               channels: file.processingFormat.channelCount)!
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 0)
    eq.globalGain = gainDB
    engine.attach(player); engine.attach(eq)

    var tail: AVAudioNode = eq
    engine.connect(player, to: eq, format: format)
    if limiter {
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: kAudioUnitSubType_PeakLimiter,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        let lim = AVAudioUnitEffect(audioComponentDescription: desc)
        engine.attach(lim)
        engine.connect(eq, to: lim, format: format)
        tail = lim
    }
    engine.connect(tail, to: engine.mainMixerNode, format: format)

    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try engine.start()
    player.scheduleFile(file, at: nil)
    player.play()

    let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    var peak: Float = 0, clipped = 0, frames = 0
    // Render the file plus a short tail so a limiter's release is included.
    let total = AVAudioFramePosition(file.length) + AVAudioFramePosition(format.sampleRate * 0.2)
    while engine.manualRenderingSampleTime < total {
        let n = min(AVAudioFrameCount(4096), AVAudioFrameCount(total - engine.manualRenderingSampleTime))
        guard try engine.renderOffline(n, to: out) == .success else { break }
        for ch in 0..<Int(out.format.channelCount) {
            let p = out.floatChannelData![ch]
            for i in 0..<Int(out.frameLength) {
                let a = abs(p[i]); peak = max(peak, a); if a > 1.0 { clipped += 1 }
            }
        }
        frames += Int(out.frameLength)
    }
    engine.stop()
    return Result(peak: peak, clipped: clipped, frames: frames)
}

let dir = URL(fileURLWithPath: "/System/Library/Sounds")
let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    .filter { $0.hasSuffix(".aiff") }.sorted()

print("sound       src-peak  headroom | +6dB raw: peak  clipped | +6dB limited: peak  clipped | +12dB limited: peak  clipped")
for name in names {
    let url = dir.appendingPathComponent(name)
    let src = try render(url, gainDB: 0, limiter: false)
    let raw6 = try render(url, gainDB: 6.02, limiter: false)
    let lim6 = try render(url, gainDB: 6.02, limiter: true)
    let lim12 = try render(url, gainDB: 12, limiter: true)
    let label = name.replacingOccurrences(of: ".aiff", with: "").padding(toLength: 10, withPad: " ", startingAt: 0)
    print("\(label)  \(dB(src.peak)) dB  \(dB(1/src.peak)) | \(dB(raw6.peak)) \(String(format: "%7d", raw6.clipped)) | \(dB(lim6.peak)) \(String(format: "%7d", lim6.clipped)) | \(dB(lim12.peak)) \(String(format: "%7d", lim12.clipped))")
}
print("EQ globalGain range check: set +24 ->", { let e = AVAudioUnitEQ(numberOfBands: 0); e.globalGain = 24; return e.globalGain }(),
      " set +30 ->", { let e = AVAudioUnitEQ(numberOfBands: 0); e.globalGain = 30; return e.globalGain }())
