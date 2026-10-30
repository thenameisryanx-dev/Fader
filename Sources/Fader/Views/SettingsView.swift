import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    let model: MixerModel
    let store: SettingsStore

    var body: some View {
        Form {
            Section {
                if store.settings.shortcuts.isEmpty {
                    Text("No shortcuts yet").foregroundStyle(.secondary)
                }
                ForEach(store.settings.shortcuts) { binding in
                    ShortcutRow(binding: binding, model: model, store: store)
                }
                NewShortcutRow(model: model, store: store)
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Shortcuts work as soon as Fader launches. Pick a specific app to always control it, or “Frontmost app” to control whatever you're using.")
                    .foregroundStyle(.secondary)
            }

            Section("Shortcut step") {
                Picker("Each press changes volume by", selection: Binding(
                    get: { store.settings.volumeStep },
                    set: { store.setVolumeStep($0) }
                )) {
                    Text("2%").tag(Float(0.02))
                    Text("5%").tag(Float(0.05))
                    Text("10%").tag(Float(0.10))
                }
            }

            Section {
                SavedVolumesList(model: model, store: store)
            } header: {
                Text("Saved volumes per output device")
            } footer: {
                Text("Each app remembers its volume separately for every speaker or headphone. On a device it hasn't played on yet, an app starts at the last volume you set for it.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 520)
    }
}

private struct ShortcutRow: View {
    let binding: ShortcutBinding
    let model: MixerModel
    let store: SettingsStore

    var body: some View {
        HStack {
            Text(binding.key.display)
                .font(.body.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            Text(binding.action.title)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Text(targetName)
            Spacer()
            if HotKeyCenter.shared.failedIDs.contains(binding.id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This combination is already used by another app or shortcut.")
            }
            Button {
                store.removeShortcut(id: binding.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var targetName: String {
        switch binding.target {
        case .frontmost: "Frontmost app"
        case .app(let bundleID): model.displayName(for: bundleID)
        }
    }
}

private struct NewShortcutRow: View {
    let model: MixerModel
    let store: SettingsStore

    @State private var target: ShortcutTarget = .frontmost
    @State private var action: ShortcutAction = .volumeUp
    @State private var key: RecordedKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("App", selection: $target) {
                    Text("Frontmost app").tag(ShortcutTarget.frontmost)
                    Divider()
                    ForEach(model.knownApps(), id: \.bundleID) { app in
                        Text(app.name).tag(ShortcutTarget.app(bundleID: app.bundleID))
                    }
                }
                Picker("Action", selection: $action) {
                    ForEach(ShortcutAction.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            HStack {
                ShortcutRecorder(key: $key)
                Spacer()
                Button("Add Shortcut") {
                    guard let key else { return }
                    store.addShortcut(ShortcutBinding(key: key, action: action, target: target))
                    self.key = nil
                }
                .disabled(key == nil)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Click, then press a key combination. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var key: RecordedKey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(title) {
            recording ? stop() : start()
        }
        .onDisappear { stop() }
    }

    private var title: String {
        if recording { return "Press a shortcut… (Esc to cancel)" }
        return key?.display ?? "Record Shortcut"
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.setSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
            } else if let recorded = RecordedKey(event: event) {
                key = recorded
                stop()
            } else {
                NSSound.beep()  // needs ⌘, ⌥ or ⌃ so it doesn't steal normal typing
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKeyCenter.shared.setSuspended(false)
        }
    }
}

private struct SavedVolumesList: View {
    let model: MixerModel
    let store: SettingsStore

    var body: some View {
        let apps = store.settings.apps
            .filter { !$0.value.deviceVolumes.isEmpty }
            .map { (bundleID: $0.key, prefs: $0.value, name: model.displayName(for: $0.key)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if apps.isEmpty {
            Text("Move an app's slider and its volume is saved for the current device.")
                .foregroundStyle(.secondary)
        }
        ForEach(apps, id: \.bundleID) { app in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let icon = model.icon(for: app.bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(app.name).font(.headline)
                }
                ForEach(app.prefs.deviceVolumes.sorted(by: { $0.key < $1.key }), id: \.key) { uid, volume in
                    HStack {
                        Label(store.settings.deviceNames[uid] ?? uid, systemImage: "hifispeaker")
                            .foregroundStyle(uid == model.outputDevice?.uid ? .primary : .secondary)
                        Spacer()
                        Text("\(Int((volume * 100).rounded()))%").monospacedDigit()
                        Button {
                            store.forgetVolume(for: app.bundleID, deviceUID: uid)
                            model.refresh()
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Forget this device's volume")
                    }
                    .padding(.leading, 24)
                }
            }
        }
    }
}
