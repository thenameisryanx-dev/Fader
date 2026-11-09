import AudioToolbox
import CoreAudio
import Observation

/// An output device's own volume and mute: the ones the volume keys and Control Center change.
/// Read and changed from a background thread only, because some devices take seconds to answer.
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
    @ObservationIgnored private var reading: Task<Void, Never>?
    /// A notification came in while a read was on its way, so read once more afterwards.
    @ObservationIgnored private var readAgain = false
    /// Go up on every device switch and every slider or mute change, so a read that started
    /// before one of those can be recognised as out of date.
    @ObservationIgnored private var attachCount = 0
    @ObservationIgnored private var changeCount = 0

    /// Switches to a new output device (nil when there is none).
    func attach(_ control: (any OutputVolumeControl)?) {
        self.control = control
        attachCount += 1
        unsentVolume = nil
        unsentMute = nil
        show(volume: nil, isMuted: nil)  // hidden until the new device has answered
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
        changeCount += 1
        send()
    }

    func toggleMute() {
        guard canMute, control != nil else { return }
        isMuted.toggle()
        unsentMute = isMuted
        changeCount += 1
        send()
    }

    /// Returns once every change has reached the device and the row shows what it reports.
    func waitForDevice() async {
        while true {
            if let sending {
                await sending.value
            } else if let reading {
                await reading.value
            } else {
                return
            }
        }
    }

    /// Reads the device off the main thread: while the JBL Go 4 was stuck on a change from the
    /// volume keys it took 5 s to report its volume, and reading on the main thread froze the menu.
    /// One read at a time; notifications that arrive meanwhile become a single read afterwards.
    private func read() {
        guard reading == nil else {
            readAgain = true
            return
        }
        reading = Task {
            repeat {
                readAgain = false
                guard let control else { break }
                let readingFor = (attachCount, changeCount)
                let (volume, isMuted) = await Task.detached { (control.volume, control.isMuted) }.value
                // Throw the answer away if the output changed meanwhile (then read the new one), or
                // the slider or mute button was used meanwhile (`send` reads again once that's done).
                if readingFor.0 != attachCount {
                    readAgain = true
                } else if readingFor.1 == changeCount, sending == nil {
                    show(volume: volume, isMuted: isMuted)
                }
            } while readAgain
            reading = nil
        }
    }

    private func show(volume deviceVolume: Float?, isMuted deviceMute: Bool?) {
        isAvailable = deviceVolume != nil
        volume = deviceVolume ?? 1
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
