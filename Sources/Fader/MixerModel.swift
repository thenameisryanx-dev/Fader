import AppKit
import AudioToolbox
import CoreAudio
import Observation
import os

let logger = Logger(subsystem: "com.ryan.Fader", category: "mixer")

/// Slider position (0...1) to linear gain. Squaring roughly matches how loud things sound.
enum VolumeCurve {
    static func gain(_ volume: Float) -> Float { volume * volume }
}

@MainActor
@Observable
final class MixerModel {
    struct AppRow: Identifiable, Equatable {
        let id: String  // bundle ID
        let name: String
        let icon: NSImage?
        let isPlaying: Bool
        let volume: Float
        let isMuted: Bool
    }

    private(set) var rows: [AppRow] = []
    private(set) var outputDevice: OutputDevice?
    private(set) var permission: AudioCapturePermission.Status = .unknown
    let mainVolume = MainVolumeModel()

    @ObservationIgnored let store: SettingsStore
    @ObservationIgnored private let audio: any AudioSystem

    private struct LiveApp {
        var identity: AppIdentity
        var processIDs: [AudioObjectID]
        var isPlaying: Bool
        var hasPlayed: Bool
    }

    @ObservationIgnored private let resolver = AppIdentityResolver()
    @ObservationIgnored private var liveApps: [String: LiveApp] = [:]
    @ObservationIgnored private var taps: [String: AppTap] = [:]
    @ObservationIgnored private var tapFailures: [String: Date] = [:]
    @ObservationIgnored private var systemListeners: [PropertyListener] = []
    @ObservationIgnored private var deviceListeners: [PropertyListener] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pendingRebuild: DispatchWorkItem?
    @ObservationIgnored private var lastFrontmostBundleID: String?
    @ObservationIgnored private var lastControlledBundleID: String?
    @ObservationIgnored private var permissionSchedule = PermissionCheckSchedule()
    /// The clock used to space out permission lookups; tests freeze it.
    @ObservationIgnored var now: () -> Date = Date.init
    /// The refresh that's waiting for Core Audio right now, if any.
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    /// A refresh was asked for while one was on its way, so do one more afterwards.
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var isShutDown = false

    /// What one look at Core Audio found.
    private struct Scan: Sendable {
        let permission: AudioCapturePermission.Status?  // nil when it wasn't looked up this time
        let device: OutputDevice?
        let processes: [AudioProcess]
    }

    private nonisolated static let hiddenBundleIDs: Set<String> = [
        "com.apple.coreaudiod",
        "com.apple.systemsoundserverd",
        "systemsoundserverd",  // what Core Audio actually reports for system sounds
        "com.apple.audio.AudioComponentRegistrar",
    ]

    /// System audio processes that aren't apps the user would want to turn down.
    nonisolated static func isHidden(_ bundleID: String) -> Bool {
        hiddenBundleIDs.contains(bundleID)
    }

    /// Tests pass a pretend `audio` so they never touch real devices or apps.
    init(store: SettingsStore, audio: any AudioSystem = CoreAudioSystem()) {
        self.store = store
        self.audio = audio
    }

    func start() {
        systemListeners = [
            PropertyListener(object: .system, selector: kAudioHardwarePropertyProcessObjectList) { [weak self] in
                self?.refresh()
            },
            PropertyListener(object: .system, selector: kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
                self?.refresh()
            },
        ]
        // Process "is playing" state has no cheap listener for every process; a 1 s poll is plenty.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let id = app?.bundleIdentifier, id != Bundle.main.bundleIdentifier {
                    self?.lastFrontmostBundleID = id
                }
            }
        }
        refresh()
    }

    func shutdown() {
        isShutDown = true
        refreshAgain = false
        timer?.invalidate()
        systemListeners = []
        deviceListeners = []
        taps.values.forEach { $0.invalidate() }
        taps.removeAll()
        store.saveNow()
    }

    // MARK: Permission

    func requestPermission() {
        AudioCapturePermission.request { [weak self] _ in
            guard let self else { return }
            let audio = self.audio
            Task {
                // Looked up off the main thread, like every other question to macOS (see `refresh`).
                let status = await Task.detached { audio.permissionStatus() }.value
                self.permission = status == .unknown ? .authorized : status  // TCC lookup unavailable; let the system decide
                self.permissionSchedule.checked(at: self.now())
                self.refresh()
            }
        }
    }

    // MARK: Volume control

    func setVolume(_ volume: Float, for bundleID: String) {
        guard let uid = outputDevice?.uid else { return }
        store.setVolume(volume, for: bundleID, deviceUID: uid)
        lastControlledBundleID = bundleID
        apply(bundleID)
    }

    func toggleMute(_ bundleID: String) {
        store.setMuted(!store.isMuted(bundleID), for: bundleID)
        lastControlledBundleID = bundleID
        apply(bundleID)
    }

    func adjustVolume(for bundleID: String, by delta: Float) {
        if delta > 0, store.isMuted(bundleID) {
            store.setMuted(false, for: bundleID)
        }
        setVolume(volume(for: bundleID) + delta, for: bundleID)
    }

    func volume(for bundleID: String) -> Float {
        store.volume(for: bundleID, deviceUID: outputDevice?.uid)
    }

    func isMuted(_ bundleID: String) -> Bool { store.isMuted(bundleID) }

    // MARK: Shortcut targets

    func resolve(_ target: ShortcutTarget) -> String? {
        switch target {
        case .app(let bundleID):
            return bundleID
        case .frontmost:
            let ownID = Bundle.main.bundleIdentifier
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            return Self.pickFrontmostTarget(
                frontmost: frontmost == ownID ? lastFrontmostBundleID : frontmost,
                lastControlled: lastControlledBundleID,
                hasPlayed: Set(liveApps.filter(\.value.hasPlayed).keys),
                playingInOrder: rows.filter(\.isPlaying).map(\.id)
            )
        }
    }

    /// Prefers the frontmost app if it makes sound; otherwise whatever was last controlled
    /// (if still playing), then the first playing app, then the frontmost app anyway.
    nonisolated static func pickFrontmostTarget(
        frontmost: String?,
        lastControlled: String?,
        hasPlayed: Set<String>,
        playingInOrder: [String]
    ) -> String? {
        if let frontmost, hasPlayed.contains(frontmost) { return frontmost }
        if let lastControlled, playingInOrder.contains(lastControlled) { return lastControlled }
        return playingInOrder.first ?? frontmost
    }

    func displayName(for bundleID: String) -> String {
        liveApps[bundleID]?.identity.name ?? store.settings.appNames[bundleID] ?? bundleID
    }

    func icon(for bundleID: String) -> NSImage? {
        if let icon = liveApps[bundleID]?.identity.icon { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Apps to offer when creating a shortcut: anything seen playing, plus running regular apps.
    func knownApps() -> [(bundleID: String, name: String)] {
        var names = store.settings.appNames
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier {
                names[id] = app.localizedName ?? id
            }
        }
        return names.map { ($0.key, $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Refresh

    /// Looks for apps playing sound and the current output device.
    ///
    /// Core Audio and macOS's privacy service answer from other processes (coreaudiod, tccd), and
    /// with the JBL Go 4 and AirPods connected an answer sometimes took seconds. Asking on the main
    /// thread froze clicks and shortcuts until then (one shortcut arrived 4.2 s late), so the
    /// questions go to a background thread and only the answers are handled here.
    /// One refresh at a time; requests that come in meanwhile become a single refresh afterwards.
    func refresh() {
        guard !isShutDown else { return }
        guard refreshing == nil else {
            refreshAgain = true
            return
        }
        refreshing = Task {
            repeat {
                refreshAgain = false
                let checkPermission = permissionSchedule.isDue(permission: permission, now: now())
                if checkPermission { permissionSchedule.checked(at: now()) }
                let audio = self.audio
                let scan = await Task.detached {
                    Scan(
                        permission: checkPermission ? audio.permissionStatus() : nil,
                        device: audio.defaultOutputDevice(),
                        processes: audio.audioProcesses()
                    )
                }.value
                guard !isShutDown else { break }  // quitting: leave the taps alone
                show(scan)
            } while refreshAgain
            refreshing = nil
        }
    }

    /// Returns once the refresh on its way (and any queued after it) has finished.
    func waitForRefresh() async {
        while let refreshing { await refreshing.value }
    }

    private func show(_ scan: Scan) {
        permission = PermissionCheckSchedule.merge(permission, with: scan.permission)

        let device = scan.device
        if device != outputDevice {
            outputDevice = device
            observe(device)
            if let device {
                store.rememberDeviceName(device.name, for: device.uid)
                logger.notice("Output device: \(device.name, privacy: .public)")
            }
        }

        let processes = scan.processes
        resolver.prune(keeping: Set(processes.map(\.pid)))
        let ownPID = getpid()
        var next: [String: LiveApp] = [:]
        for process in processes where process.pid != ownPID {
            guard let identity = resolver.identity(for: process),
                  !Self.isHidden(identity.key) else { continue }
            var app = next[identity.key] ?? LiveApp(
                identity: identity,
                processIDs: [],
                isPlaying: false,
                hasPlayed: liveApps[identity.key]?.hasPlayed ?? false
            )
            app.processIDs.append(process.objectID)
            app.isPlaying = app.isPlaying || process.isRunningOutput
            app.hasPlayed = app.hasPlayed || process.isRunningOutput
            next[identity.key] = app
        }
        liveApps = next
        for (bundleID, app) in liveApps where app.hasPlayed {
            store.rememberAppName(app.identity.name, for: bundleID)
        }

        reconcileTaps()
        rebuildRows()
        logLevels()
    }

    private func apply(_ bundleID: String) {
        if let tap = taps[bundleID] {
            tap.setGain(gain(for: bundleID))
        } else {
            reconcileTaps()
        }
        rebuildRows()
    }

    private func gain(for bundleID: String) -> Float {
        store.isMuted(bundleID) ? 0 : VolumeCurve.gain(volume(for: bundleID))
    }

    /// Makes the set of taps match what's needed: only apps that aren't at 100% get tapped,
    /// so everything else keeps playing through the system untouched.
    private func reconcileTaps() {
        guard permission == .authorized, let device = outputDevice else {
            removeAllTaps()
            return
        }

        for bundleID in Array(taps.keys) where liveApps[bundleID] == nil {
            taps.removeValue(forKey: bundleID)?.invalidate()
        }

        for (bundleID, app) in liveApps {
            let gain = gain(for: bundleID)
            if let tap = taps[bundleID] {
                if tap.deviceUID == device.uid, tap.processIDs == Set(app.processIDs) {
                    tap.setGain(gain)
                    continue
                }
                // The device changed or the app started a new audio process; start over.
                taps.removeValue(forKey: bundleID)?.invalidate()
            }
            guard gain < 0.999 else { continue }
            if let failedAt = tapFailures[bundleID], Date().timeIntervalSince(failedAt) < 5 { continue }

            do {
                taps[bundleID] = try AppTap(
                    appName: app.identity.name,
                    processIDs: app.processIDs,
                    outputDeviceUID: device.uid,
                    gain: gain
                )
                tapFailures[bundleID] = nil
                logger.notice("Tapped \(bundleID, privacy: .public) on \(device.name, privacy: .public)")
            } catch {
                tapFailures[bundleID] = Date()
                logger.error("Could not tap \(bundleID, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func removeAllTaps() {
        guard !taps.isEmpty else { return }
        taps.values.forEach { $0.invalidate() }
        taps.removeAll()
    }

    private func observe(_ device: OutputDevice?) {
        deviceListeners = []
        mainVolume.attach(device.map { DeviceVolumeControl(deviceID: $0.id) })
        guard let device else { return }
        // A sample-rate switch (e.g. AirPods entering call mode) invalidates the aggregate devices.
        deviceListeners = [
            PropertyListener(object: device.id, selector: kAudioDevicePropertyNominalSampleRate) { [weak self] in
                self?.scheduleRebuild()
            },
        ]
        // Keep the overall volume row in step with the volume keys and Control Center.
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            deviceListeners.append(
                PropertyListener(object: device.id, selector: selector, scope: kAudioObjectPropertyScopeOutput) {
                    [weak self] in self?.mainVolume.reload()
                }
            )
        }
    }

    private func scheduleRebuild() {
        pendingRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                logger.notice("Output format changed; rebuilding taps")
                self.removeAllTaps()
                self.reconcileTaps()
            }
        }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func rebuildRows() {
        let next = liveApps
            .filter { $0.value.hasPlayed || taps[$0.key] != nil }
            .map { bundleID, app in
                AppRow(
                    id: bundleID,
                    name: app.identity.name,
                    icon: app.identity.icon,
                    isPlaying: app.isPlaying,
                    volume: volume(for: bundleID),
                    isMuted: store.isMuted(bundleID)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if next != rows { rows = next }
    }

    private func logLevels() {
        for (bundleID, tap) in taps {
            let peak = tap.takePeak()
            logger.debug("Level \(bundleID, privacy: .public): \(peak, format: .fixed(precision: 3))")
        }
    }
}
