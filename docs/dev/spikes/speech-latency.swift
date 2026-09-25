// docs/dev/spikes/speech-latency.swift — build: swiftc -O speech-latency.swift -o /tmp/sl
// How long until a spoken alert can be heard. Renders with AVSpeechSynthesizer.write (nothing
// is spoken aloud) and times each utterance:
//   first  — write() to the first non-empty buffer (processing latency)
//   lead   — audio before the first sample above -40 dBFS (silence the listener waits through)
//   heard  — first + lead: when sound would start if buffers were played as they arrive
//   rtf    — render time / audio duration; below 1, streaming never runs dry
// Modes (one JSON line per trial):
//   /tmp/sl voices                               English voices: identifier, quality, name
//   /tmp/sl once  <voiceID> <short|long>         a fresh process: synthesizer and voice made here
//   /tmp/sl warm  <voiceID> <short|long> <n> <gapSeconds>
//                                                 one synthesizer, n utterances, idle gap before each
//   /tmp/sl fresh <voiceID> <short|long> <n>     a new synthesizer per utterance, in a warm process
// NOTE write() delivers on the main thread: wait by pumping the run loop, never by blocking.
import AVFoundation

let texts = [
    "short": "Microsoft Teams: you were mentioned in All Hands",
    "long": "Microsoft Teams: Priya Shah mentioned you in Incident Bridge. The payments API is returning errors for about a third of requests since the last deploy; can you take a look at the rollback plan before we page the database team?",
]

func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func ms(_ from: UInt64, _ to: UInt64) -> Double { Double(to &- from) / 1_000_000 }

func pump(until done: () -> Bool, timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)
    while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
}

struct Trial {
    var firstMs = -1.0, leadMs = -1.0, totalMs = -1.0, audioS = 0.0, buffers = 0
    var json: String {
        let heard = firstMs < 0 || leadMs < 0 ? -1 : firstMs + leadMs
        let rtf = audioS > 0 ? totalMs / 1000 / audioS : -1
        return String(format: #""first_ms":%.1f,"lead_ms":%.1f,"heard_ms":%.1f,"total_ms":%.1f,"audio_s":%.2f,"rtf":%.3f,"buffers":%d"#,
                      firstMs, leadMs, heard, totalMs, audioS, rtf, buffers)
    }
}

func render(_ synth: AVSpeechSynthesizer, _ voice: AVSpeechSynthesisVoice, _ text: String) -> Trial {
    let u = AVSpeechUtterance(string: text)
    u.voice = voice
    var t = Trial(), finished = false, framesBefore = 0.0, rate = 0.0, heard = false
    let start = now()
    synth.write(u) { buf in
        guard let pcm = buf as? AVAudioPCMBuffer else { return }
        let at = now()
        if pcm.frameLength == 0 { if !finished { finished = true; t.totalMs = ms(start, at) }; return }
        if t.firstMs < 0 { t.firstMs = ms(start, at); rate = pcm.format.sampleRate }
        t.buffers += 1
        if !heard {
            let n = Int(pcm.frameLength)
            var hit: Int? = nil
            if let f = pcm.floatChannelData { for i in 0..<n where abs(f[0][i]) > 0.01 { hit = i; break } }
            else if let s = pcm.int16ChannelData { for i in 0..<n where abs(Int(s[0][i])) > 327 { hit = i; break } }
            if let hit { heard = true; t.leadMs = (framesBefore + Double(hit)) / rate * 1000 }
        }
        framesBefore += Double(pcm.frameLength)
    }
    pump(until: { finished }, timeout: 30)
    t.audioS = rate > 0 ? framesBefore / rate : 0
    return t
}

func voice(_ id: String) -> AVSpeechSynthesisVoice {
    guard let v = AVSpeechSynthesisVoice(identifier: id) else { fatalError("no voice \(id)") }
    return v
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "voices":
    for v in AVSpeechSynthesisVoice.speechVoices() where v.language.hasPrefix("en") {
        print("\(v.identifier)\tq\(v.quality.rawValue)\t\(v.language)\t\(v.name)")
    }
case "once":
    let t0 = now()
    let synth = AVSpeechSynthesizer()
    let t1 = now()
    let v = voice(args[2])
    let t2 = now()
    let t = render(synth, v, texts[args[3]]!)
    print(String(format: #"{"mode":"once","voice":"%@","text":"%@","init_ms":%.1f,"voice_ms":%.1f,%@}"#,
                 args[2], args[3], ms(t0, t1), ms(t1, t2), t.json))
case "warm":
    let synth = AVSpeechSynthesizer(), v = voice(args[2]), n = Int(args[4])!, gap = Double(args[5])!
    _ = render(synth, v, "Warming up.")
    for i in 0..<n {
        pump(until: { false }, timeout: gap)
        print(String(format: #"{"mode":"warm","voice":"%@","text":"%@","gap_s":%.0f,"i":%d,%@}"#,
                     args[2], args[3], gap, i, render(synth, v, texts[args[3]]!).json))
    }
case "fresh":
    let v = voice(args[2]), n = Int(args[4])!
    _ = render(AVSpeechSynthesizer(), v, "Warming up.")
    for i in 0..<n {
        let synth = AVSpeechSynthesizer()
        print(String(format: #"{"mode":"fresh","voice":"%@","text":"%@","i":%d,%@}"#,
                     args[2], args[3], i, render(synth, v, texts[args[3]]!).json))
    }
default:
    print("modes: voices | once <voice> <short|long> | warm <voice> <short|long> <n> <gap> | fresh <voice> <short|long> <n>")
}
