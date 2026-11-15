import CoreAudio
import Foundation
import Testing
@testable import Fader

/// The once-a-second refresh that finds playing apps and the output device. It asks Core Audio
/// and macOS's privacy service, which can take seconds to answer, so it must never make the
/// main thread wait: that froze clicks, the shortcut recorder and global shortcuts.
@MainActor
struct MixerRefreshTests {
    /// A pretend Core Audio, so tests never touch real devices or apps.
    /// It is asked from a background thread, hence the lock.
    final class FakeAudio: AudioSystem, @unchecked Sendable {
        private let lock = NSLock()
        private let busy = DispatchGroup()
        private let asked = DispatchSemaphore(value: 0)
        private var storedDevice: OutputDevice?
        private var storedProcesses: [AudioProcess]
        private var storedPermission: AudioCapturePermission.Status
        private var storedScans = 0
        private var storedPermissionChecks = 0

        init(
            device: OutputDevice? = nil,
            processes: [AudioProcess] = [],
            permission: AudioCapturePermission.Status = .denied
        ) {
            storedDevice = device
            storedProcesses = processes
            storedPermission = permission
        }

        var processes: [AudioProcess] {
            get { lock.withLock { storedProcesses } }
            set { lock.withLock { storedProcesses = newValue } }
        }
        /// How many times the list of audio processes was read.
        var scans: Int { lock.withLock { storedScans } }
        /// How many times the permission was looked up.
        var permissionChecks: Int { lock.withLock { storedPermissionChecks } }

        /// Makes every answer take its time, like coreaudiod sometimes does with the JBL Go 4 and
        /// AirPods connected, until `answer()`. Capped at 1 s per call so a failing test can't hang.
        func beSlow() { busy.enter() }
        func answer() { busy.leave() }

        /// Returns once a refresh has started asking.
        func waitUntilAsked() async {
            await Task.detached { [self] in waitUntilAskedBlocking() }.value
        }
        private nonisolated func waitUntilAskedBlocking() {
            _ = asked.wait(timeout: .now() + 2)
        }

        func defaultOutputDevice() -> OutputDevice? {
            asked.signal()
            _ = busy.wait(timeout: .now() + 1)
            return lock.withLock { storedDevice }
        }
        func audioProcesses() -> [AudioProcess] {
            asked.signal()
            _ = busy.wait(timeout: .now() + 1)
            return lock.withLock {
                storedScans += 1
                return storedProcesses
            }
        }
        func permissionStatus() -> AudioCapturePermission.Status {
            asked.signal()
            _ = busy.wait(timeout: .now() + 1)
            return lock.withLock {
                storedPermissionChecks += 1
                return storedPermission
            }
        }
    }

    /// A process id that belongs to no running app, so the app's name comes from its bundle ID.
    static func process(_ bundleID: String, id: AudioObjectID, playing: Bool) -> AudioProcess {
        AudioProcess(objectID: id, pid: 99_000 + pid_t(id), bundleID: bundleID, isRunningOutput: playing)
    }

    static let player = process("com.example.player", id: 1, playing: true)
    static let quiet = process("com.example.quiet", id: 2, playing: false)

    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FaderTests-\(UUID().uuidString)")
        .appendingPathComponent("settings.json")

    func makeModel(_ audio: FakeAudio) -> MixerModel {
        MixerModel(store: SettingsStore(fileURL: fileURL), audio: audio)
    }

    @Test func showsAppsThatPlaySound() async {
        let audio = FakeAudio(processes: [Self.player, Self.quiet])
        let model = makeModel(audio)
        model.refresh()
        await model.waitForRefresh()
        #expect(model.rows.map(\.id) == ["com.example.player"])
        #expect(model.rows.first?.isPlaying == true)
        #expect(model.permission == .denied)
    }

    /// The bug: a slow Core Audio answer used to freeze the whole app until it came.
    @Test func refreshDoesNotWaitForCoreAudio() async {
        let audio = FakeAudio(processes: [Self.player])
        let model = makeModel(audio)
        audio.beSlow()
        let started = Date()
        model.refresh()
        let waited = Date().timeIntervalSince(started)
        #expect(waited < 0.5, "refresh() made the main thread wait \(waited) s")
        await audio.waitUntilAsked()
        #expect(model.rows.isEmpty)  // still waiting for Core Audio, and the app keeps going
        audio.answer()

        await model.waitForRefresh()
        #expect(model.rows.map(\.id) == ["com.example.player"])
    }

    /// While Core Audio is slow, the 1 s timer and change notifications keep asking for refreshes.
    /// They must not pile up: they become one more refresh once the slow one is done.
    @Test func refreshesDuringASlowOneBecomeOneMore() async {
        let audio = FakeAudio(processes: [Self.player])
        let model = makeModel(audio)
        audio.beSlow()
        model.refresh()
        await audio.waitUntilAsked()
        for _ in 0..<5 { model.refresh() }
        audio.answer()
        await model.waitForRefresh()
        #expect(audio.scans == 2)
    }

    @Test func rowsFollowTheNewestRefresh() async {
        let audio = FakeAudio(processes: [Self.player])
        let model = makeModel(audio)
        model.refresh()
        await model.waitForRefresh()
        audio.processes = []
        model.refresh()
        await model.waitForRefresh()
        #expect(model.rows.isEmpty)
    }

    /// The log showed a permission lookup every second while access wasn't granted yet.
    @Test func permissionIsNotLookedUpEveryRefresh() async {
        let audio = FakeAudio(processes: [Self.player], permission: .unknown)
        let model = makeModel(audio)
        for _ in 0..<3 {
            model.refresh()
            await model.waitForRefresh()
        }
        #expect(audio.permissionChecks == 1)
    }

    @Test func aRefreshFinishingAfterQuitChangesNothing() async {
        let audio = FakeAudio(processes: [Self.player])
        let model = makeModel(audio)
        audio.beSlow()
        model.refresh()
        await audio.waitUntilAsked()
        model.shutdown()
        audio.answer()
        await model.waitForRefresh()
        #expect(model.rows.isEmpty)
    }
}

/// When Fader asks macOS whether it may record system audio.
struct PermissionCheckScheduleTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func asksRightAwayAtFirst() {
        #expect(PermissionCheckSchedule().isDue(permission: .unknown, now: start))
    }

    @Test func asksAgainOnlyAfterTheInterval() {
        var schedule = PermissionCheckSchedule()
        schedule.checked(at: start)
        #expect(!schedule.isDue(permission: .denied, now: start + 1))
        #expect(!schedule.isDue(permission: .unknown, now: start + 4.9))
        #expect(schedule.isDue(permission: .denied, now: start + PermissionCheckSchedule.interval))
    }

    @Test func neverAsksOnceGranted() {
        #expect(!PermissionCheckSchedule().isDue(permission: .authorized, now: start))
    }

    @Test func aFailedLookupKeepsTheLastAnswer() {
        #expect(PermissionCheckSchedule.merge(.authorized, with: .unknown) == .authorized)
        #expect(PermissionCheckSchedule.merge(.denied, with: nil) == .denied)
        #expect(PermissionCheckSchedule.merge(.unknown, with: .denied) == .denied)
        #expect(PermissionCheckSchedule.merge(.denied, with: .authorized) == .authorized)
    }
}
