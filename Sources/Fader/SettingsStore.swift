import Foundation
import Observation

struct AppPrefs: Codable, Equatable {
    /// Volume (0...1 slider position) per output device UID.
    var deviceVolumes: [String: Float] = [:]
    /// The most recent volume set on any device; used for devices the app hasn't played on yet.
    var lastVolume: Float?
    var muted = false

    init() {}

    // Missing keys fall back to defaults so settings files from older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceVolumes = try c.decodeIfPresent([String: Float].self, forKey: .deviceVolumes) ?? [:]
        lastVolume = try c.decodeIfPresent(Float.self, forKey: .lastVolume)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    }
}

enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case volumeUp, volumeDown, toggleMute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .toggleMute: "Mute / unmute"
        }
    }

    var repeatsWhileHeld: Bool { self != .toggleMute }
}

enum ShortcutTarget: Codable, Hashable {
    case frontmost
    case app(bundleID: String)
}

struct ShortcutBinding: Codable, Equatable, Identifiable {
    var id = UUID()
    var key: RecordedKey
    var action: ShortcutAction
    var target: ShortcutTarget
}

struct FaderSettings: Codable, Equatable {
    var apps: [String: AppPrefs] = [:]
    var appNames: [String: String] = [:]
    var deviceNames: [String: String] = [:]
    var shortcuts: [ShortcutBinding] = []
    var volumeStep: Float = 0.05

    init() {}

    // Missing keys fall back to defaults so settings files from older versions still load.
    // Any field added later must be decoded the same way.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FaderSettings()
        apps = try c.decodeIfPresent([String: AppPrefs].self, forKey: .apps) ?? defaults.apps
        appNames = try c.decodeIfPresent([String: String].self, forKey: .appNames) ?? defaults.appNames
        deviceNames = try c.decodeIfPresent([String: String].self, forKey: .deviceNames) ?? defaults.deviceNames
        shortcuts = try c.decodeIfPresent([ShortcutBinding].self, forKey: .shortcuts) ?? defaults.shortcuts
        volumeStep = try c.decodeIfPresent(Float.self, forKey: .volumeStep) ?? defaults.volumeStep
    }
}

/// Persists everything to ~/Library/Application Support/Fader/settings.json.
@MainActor
@Observable
final class SettingsStore {
    private(set) var settings: FaderSettings

    @ObservationIgnored var onShortcutsChanged: (([ShortcutBinding]) -> Void)?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    /// Tests pass their own file so they never touch the real settings.
    init(fileURL: URL = SettingsStore.defaultFileURL) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        self.fileURL = fileURL
        settings = (try? JSONDecoder().decode(FaderSettings.self, from: Data(contentsOf: fileURL))) ?? FaderSettings()
    }

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fader", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    // MARK: Volumes

    func volume(for bundleID: String, deviceUID: String?) -> Float {
        let prefs = settings.apps[bundleID]
        if let deviceUID, let volume = prefs?.deviceVolumes[deviceUID] { return volume }
        return prefs?.lastVolume ?? 1
    }

    func setVolume(_ volume: Float, for bundleID: String, deviceUID: String) {
        let volume = min(max(volume, 0), 1)
        mutate {
            $0.apps[bundleID, default: AppPrefs()].deviceVolumes[deviceUID] = volume
            $0.apps[bundleID, default: AppPrefs()].lastVolume = volume
        }
    }

    func forgetVolume(for bundleID: String, deviceUID: String) {
        mutate { $0.apps[bundleID]?.deviceVolumes[deviceUID] = nil }
    }

    func isMuted(_ bundleID: String) -> Bool {
        settings.apps[bundleID]?.muted ?? false
    }

    func setMuted(_ muted: Bool, for bundleID: String) {
        mutate { $0.apps[bundleID, default: AppPrefs()].muted = muted }
    }

    // MARK: Names

    func rememberAppName(_ name: String, for bundleID: String) {
        guard settings.appNames[bundleID] != name else { return }
        mutate { $0.appNames[bundleID] = name }
    }

    func rememberDeviceName(_ name: String, for uid: String) {
        guard settings.deviceNames[uid] != name else { return }
        mutate { $0.deviceNames[uid] = name }
    }

    // MARK: Shortcuts

    func addShortcut(_ binding: ShortcutBinding) {
        mutate { $0.shortcuts.append(binding) }
        onShortcutsChanged?(settings.shortcuts)
    }

    func removeShortcut(id: UUID) {
        mutate { $0.shortcuts.removeAll { $0.id == id } }
        onShortcutsChanged?(settings.shortcuts)
    }

    func setVolumeStep(_ step: Float) {
        mutate { $0.volumeStep = step }
    }

    // MARK: Persistence

    private func mutate(_ change: (inout FaderSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        settings = copy
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
