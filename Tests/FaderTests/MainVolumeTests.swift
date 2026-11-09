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
        private var storedReads = 0
        private let busy = DispatchGroup()

        init(volume: Float?, isMuted: Bool?) {
            storedVolume = volume
            storedMute = isMuted
        }

        /// Reading is slow too while the device is busy: the JBL Go 4 took 5 s to report its
        /// volume while it was stuck on a change from the volume keys.
        var volume: Float? {
            get {
                _ = busy.wait(timeout: .now() + 1)
                return lock.withLock {
                    storedReads += 1
                    return storedVolume
                }
            }
            set { lock.withLock { storedVolume = newValue } }  // the volume keys changing it
        }
        var isMuted: Bool? {
            get {
                _ = busy.wait(timeout: .now() + 1)
                return lock.withLock { storedMute }
            }
            set { lock.withLock { storedMute = newValue } }
        }
        /// Every volume the app sent, in order.
        var volumeWrites: [Float] { lock.withLock { storedWrites } }
        /// How many times the volume was read.
        var volumeReads: Int { lock.withLock { storedReads } }

        /// Makes the device take its time answering, like the JBL Go 4 did (5 s per change),
        /// until `answer()`. Capped at 1 s per call so a failing test can't hang forever.
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

    @Test func showsTheDevicesVolumeAndMute() async {
        let main = MainVolumeModel()
        main.attach(FakeOutput(volume: 0.27, isMuted: true))
        await main.waitForDevice()
        #expect(main.isAvailable)
        #expect(main.volume == 0.27)
        #expect(main.isMuted)
        #expect(main.canMute)
    }

    @Test func movingTheSliderChangesTheDevice() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        await main.waitForDevice()
        main.setVolume(0.8)
        await main.waitForDevice()
        #expect(output.volume == 0.8)
        #expect(main.volume == 0.8)
    }

    @Test func volumeStaysBetweenZeroAndFull() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        await main.waitForDevice()
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
        await main.waitForDevice()
        main.toggleMute()
        await main.waitForDevice()
        #expect(output.isMuted == true)
        #expect(main.isMuted)
        main.toggleMute()
        await main.waitForDevice()
        #expect(output.isMuted == false)
    }

    @Test func picksUpChangesFromVolumeKeys() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        await main.waitForDevice()
        output.volume = 0.25
        output.isMuted = true
        main.reload()  // what the device listener calls
        await main.waitForDevice()
        #expect(main.volume == 0.25)
        #expect(main.isMuted)
    }

    @Test func switchingOutputsShowsTheNewOutputsVolume() async {
        let main = MainVolumeModel()
        main.attach(FakeOutput(volume: 0.3, isMuted: false))
        await main.waitForDevice()
        main.attach(FakeOutput(volume: 0.9, isMuted: false))
        await main.waitForDevice()
        #expect(main.volume == 0.9)
    }

    /// Some outputs (e.g. many HDMI displays) control volume themselves; the row is hidden for them.
    @Test func outputWithoutAdjustableVolumeIsUnavailable() async {
        let output = FakeOutput(volume: nil, isMuted: nil)
        let main = MainVolumeModel()
        main.attach(output)
        await main.waitForDevice()
        #expect(!main.isAvailable)
        main.setVolume(0.5)
        main.toggleMute()
        await main.waitForDevice()
        #expect(output.volume == nil)
        #expect(output.isMuted == nil)
    }

    @Test func noOutputIsUnavailable() async {
        let main = MainVolumeModel()
        main.attach(FakeOutput(volume: 0.5, isMuted: false))
        await main.waitForDevice()
        main.attach(nil)
        await main.waitForDevice()
        #expect(!main.isAvailable)
    }

    @Test func outputWithoutMuteStillHasVolume() async {
        let output = FakeOutput(volume: 0.5, isMuted: nil)
        let main = MainVolumeModel()
        main.attach(output)
        await main.waitForDevice()
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
        await main.waitForDevice()
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
        await main.waitForDevice()
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
        await main.waitForDevice()
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
        await main.waitForDevice()
        output.beSlow()

        main.setVolume(0.9)
        main.reload()  // a device notification arrives mid-drag
        #expect(main.volume == 0.9)

        output.answer()
        await main.waitForDevice()
        #expect(main.volume == 0.9)
    }

    // MARK: Volume keys on a slow device (the system volume freeze)

    /// Pressing a volume key makes the device report a change, and the row reads the device back.
    /// That read used to happen on the main thread, so a busy JBL froze the menu for 5 s per press.
    @Test func volumeKeysOnASlowDeviceDoNotFreezeTheMenu() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        await main.waitForDevice()
        output.beSlow()
        output.volume = 0.25  // a volume key press

        let started = Date()
        main.reload()  // what the device listener calls
        #expect(Date().timeIntervalSince(started) < 0.2)

        output.answer()
        await main.waitForDevice()
        #expect(main.volume == 0.25)
    }

    /// Every key press sends a notification. A busy device used to get one read per press, one
    /// after another, so the menu stayed frozen long after the last press. Now it gets the read
    /// already on its way plus one more for the newest value, however many presses came in.
    @Test func manyKeyPressesOnASlowDeviceDoNotPileUpReads() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        await main.waitForDevice()
        let readsBefore = output.volumeReads
        output.beSlow()

        for step in 1...10 {
            output.volume = 0.5 - Float(step) * 0.0625 / 2
            main.reload()
        }
        output.answer()
        await main.waitForDevice()
        #expect(output.volumeReads - readsBefore <= 2)
        #expect(main.volume == output.volume)
    }

    /// Plugging in or switching to a slow output must not freeze the menu either.
    @Test func switchingToASlowOutputDoesNotFreezeTheMenu() async {
        let output = FakeOutput(volume: 0.7, isMuted: false)
        let main = MainVolumeModel()
        output.beSlow()

        let started = Date()
        main.attach(output)
        #expect(Date().timeIntervalSince(started) < 0.2)

        output.answer()
        await main.waitForDevice()
        #expect(main.isAvailable)
        #expect(main.volume == 0.7)
    }

    /// A slow read of the old output must not overwrite the new output's volume when it finishes.
    @Test func lateReadFromTheOldOutputIsIgnored() async {
        let old = FakeOutput(volume: 0.2, isMuted: false)
        let new = FakeOutput(volume: 0.9, isMuted: false)
        let main = MainVolumeModel()
        main.attach(old)
        await main.waitForDevice()
        old.beSlow()
        main.reload()  // stuck on the old output
        main.attach(new)

        old.answer()
        await main.waitForDevice()
        #expect(main.volume == 0.9)
    }

    /// If a slow read finishes after the slider moved, it would put the slider back where it was.
    @Test func lateReadDoesNotUndoTheSlider() async {
        let output = FakeOutput(volume: 0.5, isMuted: false)
        let main = MainVolumeModel()
        main.attach(output)
        await main.waitForDevice()
        output.beSlow()
        main.reload()  // a volume key press; the read gets stuck
        try? await Task.sleep(for: .milliseconds(50))
        main.setVolume(0.8)  // then the slider moves

        output.answer()
        await main.waitForDevice()
        #expect(main.volume == 0.8)
        #expect(output.volume == 0.8)
    }
}
