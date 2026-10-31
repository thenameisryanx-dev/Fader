import Foundation
import Testing
@testable import Fader

/// The overall volume row: the output device's own volume and mute, as changed by the volume keys.
@MainActor
struct MainVolumeTests {
    /// A pretend output device, so tests never change the real volume.
    /// Changes arrive from a background thread, hence the lock.
    final class FakeOutput: OutputVolumeControl, @unchecked Sendable {
        private let lock = NSLock()
        private var storedVolume: Float?
        private var storedMute: Bool?
        private var storedWrites: [Float] = []
        private let busy = DispatchGroup()

        init(volume: Float?, isMuted: Bool?) {
            storedVolume = volume
            storedMute = isMuted
        }

        var volume: Float? {
            get { lock.withLock { storedVolume } }
            set { lock.withLock { storedVolume = newValue } }
        }
        var isMuted: Bool? {
            get { lock.withLock { storedMute } }
            set { lock.withLock { storedMute = newValue } }
        }
        /// Every volume the app sent, in order.
        var volumeWrites: [Float] { lock.withLock { storedWrites } }

        /// Makes the device take its time answering, like the JBL Go 4 did (5 s per change),
        /// until `answer()`. Capped at 1 s per change so a failing test can't hang forever.
        func beSlow() { busy.enter() }
        func answer() { busy.leave() }

        func setVolume(_ volume: Float) {
            _ = busy.wait(timeout: .now() + 1)
            lock.withLock {
                storedVolume = volume
                storedWrites.append(volume)
            }
        }
        func setMuted(_ muted: Bool) {
            _ = busy.wait(timeout: .now() + 1)
            isMuted = muted
        }
    }

    @Test func showsTheDevicesVolumeAndMute() {
        let main = MainVolumeModel()
        main.attach(FakeOutput(volume: 0.27, isMuted: true))
        #expect(main.isAvailable)
        #expect(main.volume == 0.27)
        #expect(main.isMuted)
        #expect(main.canMute)
    }

    @Test func movingTheSliderChangesTheDevice() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        main.setVolume(0.8)
        await main.waitForDevice()
        #expect(output.volume == 0.8)
        #expect(main.volume == 0.8)
    }

    @Test func volumeStaysBetweenZeroAndFull() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        main.setVolume(1.3)
        await main.waitForDevice()
        #expect(output.volume == 1)
        main.setVolume(-0.2)
        await main.waitForDevice()
        #expect(output.volume == 0)
    }

    @Test func muteButtonTogglesTheDevice() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        main.toggleMute()
        await main.waitForDevice()
        #expect(output.isMuted == true)
        #expect(main.isMuted)
        main.toggleMute()
        await main.waitForDevice()
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
    @Test func outputWithoutAdjustableVolumeIsUnavailable() async {
        let output = FakeOutput(volume: nil, isMuted: nil)
        let main = MainVolumeModel()
        main.attach(output)
        #expect(!main.isAvailable)
        main.setVolume(0.5)
        main.toggleMute()
        await main.waitForDevice()
        #expect(output.volume == nil)
        #expect(output.isMuted == nil)
    }

    @Test func noOutputIsUnavailable() {
        let main = MainVolumeModel()
        main.attach(FakeOutput(volume: 0.5, isMuted: false))
        main.attach(nil)
        #expect(!main.isAvailable)
    }

    @Test func outputWithoutMuteStillHasVolume() async {
        let output = FakeOutput(volume: 0.5, isMuted: nil)
        let main = MainVolumeModel()
        main.attach(output)
        #expect(main.isAvailable)
        #expect(!main.canMute)
        main.toggleMute()
        await main.waitForDevice()
        #expect(output.isMuted == nil)
    }

    // MARK: Slow devices (the JBL Go 4 freeze)

    /// The menu used to wait for the device on every slider step, freezing for seconds at a time.
    @Test func slowDeviceDoesNotFreezeTheSlider() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        output.beSlow()

        let started = Date()
        main.setVolume(0.3)
        #expect(Date().timeIntervalSince(started) < 0.2)
        #expect(main.volume == 0.3)  // the slider follows the finger right away

        output.answer()
        await main.waitForDevice()
        #expect(output.volume == 0.3)
    }

    @Test func slowDeviceDoesNotFreezeTheMuteButton() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        output.beSlow()

        let started = Date()
        main.toggleMute()
        #expect(Date().timeIntervalSince(started) < 0.2)
        #expect(main.isMuted)

        output.answer()
        await main.waitForDevice()
        #expect(output.isMuted == true)
    }

    /// A drag sends ~100 values a second. A busy device gets only the newest one, not a backlog.
    @Test func draggingWhileTheDeviceIsBusySendsOnlyTheLatestVolume() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        output.beSlow()

        main.setVolume(0.4)  // the device starts on this one and gets stuck
        try? await Task.sleep(for: .milliseconds(50))
        main.setVolume(0.3)
        main.setVolume(0.2)
        main.setVolume(0.1)

        output.answer()
        await main.waitForDevice()
        #expect(output.volumeWrites == [0.4, 0.1])
        #expect(main.volume == 0.1)
    }

    /// While our change is on its way the device still reports the old volume; showing that
    /// would make the slider jump back under the finger.
    @Test func sliderDoesNotJumpBackWhileTheDeviceIsBusy() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        output.beSlow()

        main.setVolume(0.9)
        main.reload()  // a device notification arrives mid-drag
        #expect(main.volume == 0.9)

        output.answer()
        await main.waitForDevice()
        #expect(main.volume == 0.9)
    }
}
