import Testing
@testable import Fader

/// The overall volume row: the output device's own volume and mute, as changed by the volume keys.
@MainActor
struct MainVolumeTests {
    /// A pretend output device, so tests never change the real volume.
    final class FakeOutput: OutputVolumeControl {
        var volume: Float?
        var isMuted: Bool?
        init(volume: Float?, isMuted: Bool?) {
            self.volume = volume
            self.isMuted = isMuted
        }
        func setVolume(_ volume: Float) { self.volume = volume }
        func setMuted(_ muted: Bool) { isMuted = muted }
    }

    @Test func showsTheDevicesVolumeAndMute() {
        let main = MainVolumeModel()
        main.attach(FakeOutput(volume: 0.27, isMuted: true))
        #expect(main.isAvailable)
        #expect(main.volume == 0.27)
        #expect(main.isMuted)
        #expect(main.canMute)
    }

    @Test func movingTheSliderChangesTheDevice() {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        main.setVolume(0.8)
        #expect(output.volume == 0.8)
        #expect(main.volume == 0.8)
    }

    @Test func volumeStaysBetweenZeroAndFull() {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        main.setVolume(1.3)
        #expect(output.volume == 1)
        main.setVolume(-0.2)
        #expect(output.volume == 0)
    }

    @Test func muteButtonTogglesTheDevice() {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        main.toggleMute()
        #expect(output.isMuted == true)
        #expect(main.isMuted)
        main.toggleMute()
        #expect(output.isMuted == false)
    }

    @Test func picksUpChangesFromVolumeKeys() {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        output.volume = 0.25
        output.isMuted = true
        main.reload()  // what the device listener calls
        #expect(main.volume == 0.25)
        #expect(main.isMuted)
    }

    @Test func switchingOutputsShowsTheNewOutputsVolume() {
        let main = MainVolumeModel()
        main.attach(FakeOutput(volume: 0.3, isMuted: false))
        main.attach(FakeOutput(volume: 0.9, isMuted: false))
        #expect(main.volume == 0.9)
    }

    /// Some outputs (e.g. many HDMI displays) control volume themselves; the row is hidden for them.
    @Test func outputWithoutAdjustableVolumeIsUnavailable() {
        let output = FakeOutput(volume: nil, isMuted: nil)
        let main = MainVolumeModel()
        main.attach(output)
        #expect(!main.isAvailable)
        main.setVolume(0.5)
        main.toggleMute()
        #expect(output.volume == nil)
        #expect(output.isMuted == nil)
    }

    @Test func noOutputIsUnavailable() {
        let main = MainVolumeModel()
        main.attach(FakeOutput(volume: 0.5, isMuted: false))
        main.attach(nil)
        #expect(!main.isAvailable)
    }

    @Test func outputWithoutMuteStillHasVolume() {
        let output = FakeOutput(volume: 0.5, isMuted: nil)
        let main = MainVolumeModel()
        main.attach(output)
        #expect(main.isAvailable)
        #expect(!main.canMute)
        main.toggleMute()
        #expect(output.isMuted == nil)
    }
}
