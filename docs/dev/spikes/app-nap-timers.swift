// docs/dev/spikes/app-nap-timers.swift — does App Nap delay a background menu-bar app's timers?
// (§11: "ProcessInfo.beginActivity prevents App Nap delaying Tier 3 re-alerts" — unverified.)
//
// Build into a minimal accessory app, since App Nap applies to apps, not command-line tools:
//   swiftc -O app-nap-timers.swift -o AppNapSpike
//   mkdir -p AppNapSpike.app/Contents/MacOS && mv AppNapSpike AppNapSpike.app/Contents/MacOS/
//   (Info.plist: CFBundleIdentifier, CFBundleExecutable AppNapSpike, LSUIElement true)
//   codesign -s - AppNapSpike.app
// Run, without activating it:
//   open -g -n AppNapSpike.app --args <label> <statusItem 0|1> <activity 0|1> <interval s> <duration s> <out.jsonl>
//
// Each fire writes {"label", "n", "late_ms"}: how long after it was due, measured on the
// monotonic clock from the first fire, so lateness never accumulates across fires.
import AppKit

let args = CommandLine.arguments
let label = args[1]
let wantsStatusItem = args[2] == "1"
let holdsActivity = args[3] == "1"
let interval = Double(args[4])!
let duration = Double(args[5])!
let out = URL(fileURLWithPath: args[6])

func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

final class Spike: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var activity: NSObjectProtocol?
    var timer: Timer?
    var start: UInt64 = 0
    var fires = 0
    let handle: FileHandle

    override init() {
        FileManager.default.createFile(atPath: out.path, contents: nil)
        handle = try! FileHandle(forWritingTo: out)
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        if wantsStatusItem {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.button?.title = "⏱"
        }
        if holdsActivity {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "App Nap spike")
        }
        start = now()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.fired() }
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func fired() {
        fires += 1
        let due = start + UInt64(Double(fires) * interval * 1e9)
        let late = (Double(now()) - Double(due)) / 1e6
        let line = "{\"label\":\"\(label)\",\"n\":\(fires),\"late_ms\":\(String(format: "%.1f", late))}\n"
        handle.write(Data(line.utf8))
        if Double(fires) * interval >= duration { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = Spike()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
