// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SignalLadder",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotificationCore"),
        .target(
            name: "NotificationCapture",
            dependencies: ["NotificationCore"]
        ),
        .executableTarget(
            name: "signalladder-probe",
            dependencies: ["NotificationCore", "NotificationCapture"]
        ),
        .testTarget(
            name: "NotificationCoreTests",
            dependencies: ["NotificationCore"]
        ),
    ]
)
