import AudioToolbox
import CoreAudio
import Observation

/// An output device's own volume and mute: the ones the volume keys and Control Center change.
protocol OutputVolumeControl {
    var volume: Float? { get }  // nil if this output's volume can't be changed from the Mac
    var isMuted: Bool? { get }  // nil if this output can't be muted
    func setVolume(_ volume: Float)
    func setMuted(_ muted: Bool)
}

/// The overall volume row at the top of the menu.
@MainActor
@Observable
final class MainVolumeModel {
    private(set) var isAvailable = false
    private(set) var volume: Float = 1
    private(set) var isMuted = false
    private(set) var canMute = false

    @ObservationIgnored private var control: (any OutputVolumeControl)?

    /// Switches to a new output device (nil when there is none).
    func attach(_ control: (any OutputVolumeControl)?) {
        self.control = control
        reload()
    }

    /// Reads the device again, e.g. after the volume keys changed it.
    func reload() {
        let deviceVolume = control?.volume
        isAvailable = deviceVolume != nil
        volume = deviceVolume ?? 1
        let deviceMute = control?.isMuted
        canMute = deviceMute != nil
        isMuted = deviceMute ?? false
    }

    func setVolume(_ volume: Float) {
        guard isAvailable, let control else { return }
        control.setVolume(min(max(volume, 0), 1))
        reload()
    }

    func toggleMute() {
        guard canMute, let control else { return }
        control.setMuted(!isMuted)
        reload()
    }
}

/// `OutputVolumeControl` for a real Core Audio output device.
struct DeviceVolumeControl: OutputVolumeControl {
    let deviceID: AudioObjectID

    private static let volumeSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    private static let muteSelector = kAudioDevicePropertyMute
    private static let scope = kAudioObjectPropertyScopeOutput

    var volume: Float? {
        guard CA.isSettable(deviceID, Self.volumeSelector, scope: Self.scope) else { return nil }
        return CA.value(deviceID, Self.volumeSelector, scope: Self.scope, default: Float32(1))
    }

    var isMuted: Bool? {
        guard CA.isSettable(deviceID, Self.muteSelector, scope: Self.scope) else { return nil }
        return CA.value(deviceID, Self.muteSelector, scope: Self.scope, default: UInt32(0)) != 0
    }

    func setVolume(_ volume: Float) {
        CA.set(deviceID, Self.volumeSelector, scope: Self.scope, Float32(volume))
    }

    func setMuted(_ muted: Bool) {
        CA.set(deviceID, Self.muteSelector, scope: Self.scope, UInt32(muted ? 1 : 0))
    }
}
