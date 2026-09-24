// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SignalLadder",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SignalLadder", targets: ["SignalLadder"]),
    ],
    targets: [
        .target(name: "NotificationCore"),
        .target(
            name: "NotificationCapture",
            dependencies: ["NotificationCore"]
        ),
        // Playback, kept out of NotificationCore (which may not touch files or
        // audio hardware) and out of the app target (which has no tests), so
        // the audio path is tested — by rendering the real graph offline.
        .target(
            name: "AlertAudio",
            dependencies: ["NotificationCore"]
        ),
        .executableTarget(
            name: "signalladder-probe",
            dependencies: ["NotificationCore", "NotificationCapture"]
        ),
        .executableTarget(
            name: "SignalLadder",
            dependencies: ["NotificationCore", "NotificationCapture", "AlertAudio"]
        ),
        .testTarget(
            name: "NotificationCoreTests",
            dependencies: ["NotificationCore"]
        ),
        .testTarget(
            name: "AlertAudioTests",
            dependencies: ["AlertAudio"]
        ),
    ]
)
