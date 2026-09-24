// docs/dev/spikes/speech-render.swift — run: swiftc -O speech-render.swift -o /tmp/sr && /tmp/sr
// Renders speech to buffers with AVSpeechSynthesizer.write (nothing is spoken) and reports format and level.
// NOTE the run-loop pump: write() delivers on the main thread, so blocking main to wait for it deadlocks.
import AVFoundation
let voices = AVSpeechSynthesisVoice.speechVoices()
let en = voices.filter { $0.language.hasPrefix("en") }
print("installed voices: \(voices.count) total, \(en.count) English")
print("  English qualities:", Dictionary(grouping: en, by: { $0.quality.rawValue }).mapValues(\.count).sorted { $0.key < $1.key }.map { "q\($0.key)=\($0.value)" }.joined(separator: " "))
print("  sample:", en.prefix(6).map { "\($0.name) [\($0.language)]" }.joined(separator: ", "))

let synth = AVSpeechSynthesizer()
let u = AVSpeechUtterance(string: "Microsoft Teams: you were mentioned in All Hands")
u.voice = en.first(where: { $0.language == "en-GB" }) ?? en.first
var formats = Set<String>(), buffers = 0, frames: AVAudioFrameCount = 0, peak: Float = 0
let done = DispatchSemaphore(value: 0)
var finished = false
synth.write(u) { buf in
    guard let pcm = buf as? AVAudioPCMBuffer else { return }
    if pcm.frameLength == 0 { if !finished { finished = true; done.signal() }; return }
    buffers += 1; frames += pcm.frameLength
    formats.insert("\(pcm.format.commonFormat.rawValue)@\(Int(pcm.format.sampleRate))Hz x\(pcm.format.channelCount) interleaved=\(pcm.format.isInterleaved)")
    if let f = pcm.floatChannelData { for i in 0..<Int(pcm.frameLength) { peak = max(peak, abs(f[0][i])) } }
    else if let s = pcm.int16ChannelData { for i in 0..<Int(pcm.frameLength) { peak = max(peak, abs(Float(s[0][i]) / 32768)) } }
}
let deadline = Date().addingTimeInterval(20)
while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
let waited: DispatchTimeoutResult = finished ? .success : .timedOut
let rate = formats.first.flatMap { f in Double(f.split(separator: "@")[1].split(separator: "H")[0]) } ?? 0
print("write(): \(waited == .success ? "completed" : "TIMED OUT") — \(buffers) buffers, \(frames) frames (~\(rate > 0 ? String(format: "%.1f", Double(frames)/rate) : "?")s)")
print("  buffer formats:", formats.sorted())
print(String(format: "  peak %.2f dBFS  (headroom for gain: %.1f dB)", 20*log10(max(peak, 1e-9)), -20*log10(max(peak, 1e-9))))
print("  commonFormat key: 1=float32 3=int16")
