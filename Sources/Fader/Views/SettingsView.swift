import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    let model: MixerModel
    let store: SettingsStore

    @State private var editor: EditorRequest?

    var body: some View {
        Form {
            Section {
                if store.settings.shortcuts.isEmpty {
                    Text("No shortcuts yet. Add one to change an app's volume from the keyboard.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.settings.shortcuts) { binding in
                    ShortcutRow(binding: binding, model: model, store: store) {
                        editor = EditorRequest(draft: ShortcutDraft(editing: binding))
                    }
                }
                HStack {
                    Button("Add Shortcut…") { editor = EditorRequest(draft: ShortcutDraft()) }
                    Spacer()
                }
                Picker("Each press changes volume by", selection: Binding(
                    get: { store.settings.volumeStep },
                    set: { store.setVolumeStep($0) }
                )) {
                    Text("2%").tag(Float(0.02))
                    Text("5%").tag(Float(0.05))
                    Text("10%").tag(Float(0.10))
                }
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Shortcuts work as soon as Fader launches. Pick a specific app to always control it, or “Frontmost app” to control whatever you're using. Double-click a shortcut to change it. The Mac's own volume keys can't be recorded.")
                    .foregroundStyle(.secondary)
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
        .sheet(item: $editor) { request in
            ShortcutEditor(draft: request.draft, model: model, store: store) { editor = nil }
        }
    }
}

/// Opens the shortcut sheet; a new id each time so the sheet starts fresh.
private struct EditorRequest: Identifiable {
    let id = UUID()
    let draft: ShortcutDraft
}

@MainActor
private func targetName(_ target: ShortcutTarget, model: MixerModel) -> String {
    switch target {
    case .frontmost: "Frontmost app"
    case .app(let bundleID): model.displayName(for: bundleID)
    }
}

private struct ShortcutRow: View {
    let binding: ShortcutBinding
    let model: MixerModel
    let store: SettingsStore
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(binding.action.title)
                Text(targetName(binding.target, model: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if HotKeyCenter.shared.failedIDs.contains(binding.id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("macOS didn't accept this combination, usually because another app already uses it. Double-click to pick a different one.")
            }
            KeyCap(text: binding.key.display)
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Change this shortcut")
            Button {
                store.removeShortcut(id: binding.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this shortcut")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }

    @ViewBuilder private var icon: some View {
        switch binding.target {
        case .frontmost:
            Image(systemName: "macwindow").foregroundStyle(.secondary)
        case .app(let bundleID):
            if let image = model.icon(for: bundleID) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app").foregroundStyle(.secondary)
            }
        }
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// The sheet for adding or changing shortcuts: record the keys, pick the action, pick the app.
private struct ShortcutEditor: View {
    @State var draft: ShortcutDraft
    let model: MixerModel
    let store: SettingsStore
    let onClose: () -> Void

    private enum TargetChoice: Hashable {
        case target(ShortcutTarget)
        case otherApp
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(draft.actions) { action in
                        LabeledContent(draft.actions.count > 1 ? action.title : "Shortcut") {
                            KeyRecorderView(key: keyBinding(for: action))
                        }
                    }
                    Picker("Action", selection: $draft.kind) {
                        ForEach(ShortcutAction.allCases) { action in
                            Text(action.title).tag(ShortcutDraft.Kind.single(action))
                        }
                        if !draft.isEditing {
                            Divider()
                            Text("Up, down and mute (3 shortcuts)").tag(ShortcutDraft.Kind.fullSet)
                        }
                    }
                    Picker("App", selection: targetChoice) {
                        Text("Frontmost app").tag(TargetChoice.target(.frontmost))
                        Divider()
                        ForEach(appChoices, id: \.bundleID) { app in
                            Text(app.name).tag(TargetChoice.target(.app(bundleID: app.bundleID)))
                        }
                        Divider()
                        Text("Other app…").tag(TargetChoice.otherApp)
                    }
                } footer: {
                    footer
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(draft.isEditing ? "Save" : "Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSave(existing: store.settings.shortcuts))
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
    }

    @ViewBuilder private var footer: some View {
        let problems = draft.problems(existing: store.settings.shortcuts)
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                    Label(message(for: problem), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } else if !draft.isComplete {
            Text(draft.actions.count > 1
                 ? "Click each box and press the keys you want for it."
                 : "Click the box and press the keys you want, for example ⌃⌥↑.")
                .foregroundStyle(.secondary)
        }
    }

    private func message(for problem: ShortcutDraft.Problem) -> String {
        switch problem {
        case .sameKeyTwice(let key):
            "\(key.display) is used twice. Each action needs its own keys."
        case .alreadyUsed(let key, let other):
            "\(key.display) is already used for \(other.action.title) → \(targetName(other.target, model: model))."
        }
    }

    private func keyBinding(for action: ShortcutAction) -> Binding<RecordedKey?> {
        Binding(
            get: { draft.key(for: action) },
            set: { draft.setKey($0, for: action) }
        )
    }

    /// Running apps and apps seen before, plus the one this shortcut already uses.
    private var appChoices: [(bundleID: String, name: String)] {
        var apps = model.knownApps()
        if case .app(let bundleID) = draft.target, !apps.contains(where: { $0.bundleID == bundleID }) {
            apps.insert((bundleID, model.displayName(for: bundleID)), at: 0)
        }
        return apps
    }

    private var targetChoice: Binding<TargetChoice> {
        Binding(
            get: { .target(draft.target) },
            set: { choice in
                switch choice {
                case .target(let target): draft.target = target
                case .otherApp: chooseOtherApp()
                }
            }
        )
    }

    private func chooseOtherApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let app = AppBundleInfo.read(at: url),
              app.bundleID != Bundle.main.bundleIdentifier
        else { return }
        store.rememberAppName(app.name, for: app.bundleID)
        draft.target = .app(bundleID: app.bundleID)
    }

    private func save() {
        let bindings = draft.bindings()
        if draft.isEditing, let binding = bindings.first {
            store.updateShortcut(binding)
        } else {
            store.addShortcuts(bindings)
        }
        onClose()
    }
}

/// Click, then press a key combination. Esc or clicking elsewhere cancels.
private struct KeyRecorderView: View {
    @Binding var key: RecordedKey?
    @State private var recorder = KeyRecorderController(hotKeys: HotKeyCenter.shared)

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                if recorder.isRecording {
                    recorder.cancel()
                } else {
                    recorder.start(in: NSApp.keyWindow)
                }
            } label: {
                label
                    .frame(minWidth: 140)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(recorder.isRecording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(recorder.isRecording ? Color.accentColor : Color.primary.opacity(0.15))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(recorder.isRecording ? "Press the keys, or Esc to cancel" : "Click, then press the keys you want")
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { recorder.frameInWindow = $0 }

            if recorder.isRecording, let rejection = recorder.rejection {
                Text(rejection.message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 240, alignment: .trailing)
            }
        }
        .onAppear { recorder.onRecord = { key = $0 } }
        .onDisappear { recorder.cancel() }
    }

    @ViewBuilder private var label: some View {
        if recorder.isRecording {
            HStack(spacing: 6) {
                Image(systemName: "record.circle").foregroundStyle(.red)
                Text(recorder.heldModifiers.isEmpty ? "Press keys…" : recorder.heldModifiers + "…")
                    .font(.body.monospaced())
            }
        } else if let key {
            Text(key.display).font(.body.monospaced())
        } else {
            Text("Click to record").foregroundStyle(.secondary)
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
