import AppKit
import Testing
@testable import Fader

/// Per-app, per-device volume memory and the settings file.
@MainActor
struct SettingsStoreTests {
    // Each test gets its own throwaway file, never the real settings.
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FaderTests-\(UUID().uuidString)")
        .appendingPathComponent("settings.json")

    @Test func newAppStartsAtFullVolume() {
        let store = SettingsStore(fileURL: fileURL)
        #expect(store.volume(for: "com.spotify.client", deviceUID: "jbl") == 1)
        #expect(store.isMuted("com.spotify.client") == false)
    }

    @Test func volumeIsRememberedSeparatelyPerDevice() {
        let store = SettingsStore(fileURL: fileURL)
        store.setVolume(0.3, for: "com.spotify.client", deviceUID: "jbl")
        store.setVolume(0.7, for: "com.spotify.client", deviceUID: "airpods")

        #expect(store.volume(for: "com.spotify.client", deviceUID: "jbl") == 0.3)
        #expect(store.volume(for: "com.spotify.client", deviceUID: "airpods") == 0.7)
    }

    @Test func appsDontAffectEachOther() {
        let store = SettingsStore(fileURL: fileURL)
        store.setVolume(0.3, for: "com.spotify.client", deviceUID: "jbl")
        #expect(store.volume(for: "us.zoom.xos", deviceUID: "jbl") == 1)
    }

    @Test func newDeviceStartsAtLastVolumeSet() {
        let store = SettingsStore(fileURL: fileURL)
        store.setVolume(0.3, for: "com.spotify.client", deviceUID: "jbl")
        store.setVolume(0.6, for: "com.spotify.client", deviceUID: "airpods")
        #expect(store.volume(for: "com.spotify.client", deviceUID: "new-headphones") == 0.6)
    }

    @Test func forgettingADeviceFallsBackToLastVolume() {
        let store = SettingsStore(fileURL: fileURL)
        store.setVolume(0.3, for: "com.spotify.client", deviceUID: "jbl")
        store.setVolume(0.6, for: "com.spotify.client", deviceUID: "airpods")
        store.forgetVolume(for: "com.spotify.client", deviceUID: "jbl")
        #expect(store.volume(for: "com.spotify.client", deviceUID: "jbl") == 0.6)
    }

    @Test func volumeStaysBetweenZeroAndOne() {
        let store = SettingsStore(fileURL: fileURL)
        store.setVolume(1.4, for: "a", deviceUID: "jbl")
        store.setVolume(-0.2, for: "b", deviceUID: "jbl")
        #expect(store.volume(for: "a", deviceUID: "jbl") == 1)
        #expect(store.volume(for: "b", deviceUID: "jbl") == 0)
    }

    @Test func muteIsRememberedAndKeepsVolume() {
        let store = SettingsStore(fileURL: fileURL)
        store.setVolume(0.4, for: "com.spotify.client", deviceUID: "jbl")
        store.setMuted(true, for: "com.spotify.client")
        #expect(store.isMuted("com.spotify.client"))
        #expect(store.volume(for: "com.spotify.client", deviceUID: "jbl") == 0.4)
    }

    @Test func settingsSurviveARestart() {
        let store = SettingsStore(fileURL: fileURL)
        store.setVolume(0.3, for: "com.spotify.client", deviceUID: "jbl")
        store.setMuted(true, for: "us.zoom.xos")
        store.addShortcut(ShortcutBinding(
            key: RecordedKey(keyCode: 126, modifierFlags: [.option, .shift], characters: nil)!,
            action: .volumeUp,
            target: .app(bundleID: "com.spotify.client")
        ))
        store.saveNow()

        let reopened = SettingsStore(fileURL: fileURL)
        #expect(reopened.settings == store.settings)
    }

    @Test func addingAndRemovingShortcutsNotifiesHotKeys() {
        let store = SettingsStore(fileURL: fileURL)
        var reported: [ShortcutBinding] = []
        store.onShortcutsChanged = { reported = $0 }

        let binding = ShortcutBinding(
            key: RecordedKey(keyCode: 125, modifierFlags: [.option], characters: nil)!,
            action: .volumeDown,
            target: .frontmost
        )
        store.addShortcut(binding)
        #expect(reported == [binding])
        store.removeShortcut(id: binding.id)
        #expect(reported.isEmpty)
    }

    // MARK: Settings files from older versions

    /// A settings file exactly as version 0.1 writes it. If this stops loading,
    /// updating the app would wipe everyone's saved volumes and shortcuts.
    @Test func loadsSettingsFileFromVersion0_1() throws {
        let json = """
        {
          "appNames" : { "com.spotify.client" : "Spotify" },
          "apps" : {
            "com.spotify.client" : {
              "deviceVolumes" : { "jbl" : 0.3, "airpods" : 0.7 },
              "lastVolume" : 0.7,
              "muted" : false
            }
          },
          "deviceNames" : { "jbl" : "JBL Go 4" },
          "shortcuts" : [
            {
              "action" : "volumeUp",
              "id" : "6F1B2C3D-0000-4000-8000-000000000001",
              "key" : { "carbonModifiers" : 2560, "keyCode" : 126, "keyLabel" : "↑" },
              "target" : { "app" : { "bundleID" : "com.spotify.client" } }
            },
            {
              "action" : "toggleMute",
              "id" : "6F1B2C3D-0000-4000-8000-000000000002",
              "key" : { "carbonModifiers" : 2048, "keyCode" : 46, "keyLabel" : "M" },
              "target" : { "frontmost" : {} }
            }
          ],
          "volumeStep" : 0.1
        }
        """
        try write(json)
        let store = SettingsStore(fileURL: fileURL)

        #expect(store.volume(for: "com.spotify.client", deviceUID: "jbl") == 0.3)
        #expect(store.volume(for: "com.spotify.client", deviceUID: "airpods") == 0.7)
        #expect(store.settings.volumeStep == 0.1)
        #expect(store.settings.shortcuts.count == 2)
        #expect(store.settings.shortcuts[0].target == .app(bundleID: "com.spotify.client"))
        #expect(store.settings.shortcuts[1].target == .frontmost)
        #expect(store.settings.shortcuts[1].action == .toggleMute)
    }

    @Test func missingFieldsUseDefaults() throws {
        try write(#"{ "apps" : { "com.spotify.client" : { "deviceVolumes" : { "jbl" : 0.5 } } } }"#)
        let store = SettingsStore(fileURL: fileURL)

        #expect(store.volume(for: "com.spotify.client", deviceUID: "jbl") == 0.5)
        #expect(store.isMuted("com.spotify.client") == false)
        #expect(store.settings.volumeStep == 0.05)
        #expect(store.settings.shortcuts.isEmpty)
    }

    @Test func corruptFileStartsFresh() throws {
        try write("not json")
        let store = SettingsStore(fileURL: fileURL)
        #expect(store.settings == FaderSettings())
    }

    private func write(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
