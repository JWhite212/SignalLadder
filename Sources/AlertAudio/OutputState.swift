// Sources/AlertAudio/OutputState.swift
import CoreAudio
import AudioToolbox

/// Whether the Mac could have made a sound audible when an alert played.
///
/// An alert plays through the default output device at that device's volume.
/// If the device is muted, or its volume is at zero, the alert "played" and
/// nobody heard it. The app records what it did, and this is how it avoids
/// implying more: the Inspector says the output was muted rather than letting
/// "Played" stand for "heard".
///
/// Read through CoreAudio's device properties, which need no permission.
public struct OutputState: Equatable, Sendable {
    /// nil when the device does not report a mute control.
    public let muted: Bool?
    /// 0…1, nil when the device has no volume control (some external
    /// interfaces), in which case the level cannot be judged.
    public let volume: Float?

    public init(muted: Bool?, volume: Float?) {
        self.muted = muted
        self.volume = volume
    }

    /// Below this the device is treated as silent. The volume slider's lowest
    /// non-zero step is about 0.06; anything under this is off in practice.
    public static let inaudibleVolume: Float = 0.02

    /// True only when the device positively reports that nothing would be
    /// heard. Unknown is not silent: claiming the output was muted when it may
    /// not have been would be the same error in the opposite direction.
    public var isEffectivelySilent: Bool {
        muted == true || (volume.map { $0 < Self.inaudibleVolume } ?? false)
    }

    /// The default output device's state now.
    public static func current() -> OutputState {
        guard let device = defaultOutputDevice() else { return OutputState(muted: nil, volume: nil) }
        return OutputState(muted: readMute(device), volume: readVolume(device))
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func readMute(_ device: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value != 0 : nil
    }

    private static func readVolume(_ device: AudioObjectID) -> Float? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
