import AudioToolbox
import CoreAudio
import Observation

/// An output device's own volume and mute: the ones the volume keys and Control Center change.
/// Changes are made from a background thread, because some devices take seconds to answer.
protocol OutputVolumeControl: Sendable {
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
    /// Changes not sent to the device yet. Only the newest of each is kept, so a slow device
    /// gets the latest slider position instead of a backlog of every step of the drag.
    @ObservationIgnored private var unsentVolume: Float?
    @ObservationIgnored private var unsentMute: Bool?
    @ObservationIgnored private var sending: Task<Void, Never>?

    /// Switches to a new output device (nil when there is none).
    func attach(_ control: (any OutputVolumeControl)?) {
        self.control = control
        unsentVolume = nil
        unsentMute = nil
        read()
    }

    /// Reads the device again, e.g. after the volume keys changed it.
    func reload() {
        // While our own changes are on their way the device still reports older values,
        // which would make the slider jump back. `send` reads the device once it's done.
        guard sending == nil else { return }
        read()
    }

    func setVolume(_ volume: Float) {
        guard isAvailable, control != nil else { return }
        self.volume = min(max(volume, 0), 1)
        unsentVolume = self.volume
        send()
    }

    func toggleMute() {
        guard canMute, control != nil else { return }
        isMuted.toggle()
        unsentMute = isMuted
        send()
    }

    /// Returns once every change has reached the device.
    func waitForDevice() async {
        while let sending { await sending.value }
    }

    private func read() {
        let deviceVolume = control?.volume
        isAvailable = deviceVolume != nil
        volume = deviceVolume ?? 1
        let deviceMute = control?.isMuted
        canMute = deviceMute != nil
        isMuted = deviceMute ?? false
    }

    private func send() {
        guard sending == nil else { return }  // the running task picks up the newest values
        sending = Task {
            while let control, unsentVolume != nil || unsentMute != nil {
                let volume = unsentVolume
                let mute = unsentMute
                unsentVolume = nil
                unsentMute = nil
                // Off the main thread: a device can take seconds to answer (the JBL Go 4 took 5),
                // and the menu has to keep responding meanwhile.
                await Task.detached {
                    if let volume { control.setVolume(volume) }
                    if let mute { control.setMuted(mute) }
                }.value
            }
            sending = nil
            read()
        }
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
