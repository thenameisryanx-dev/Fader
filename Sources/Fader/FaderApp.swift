import AppKit
import SwiftUI

@main
struct FaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar icon and its menu are `MenuBarController`, set up by the delegate.
        // A SwiftUI app needs at least one scene; this one never shows anything.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore()
    lazy var model = MixerModel(store: store)

    private let hud = HUDController()
    private var repeatTimer: Timer?
    private var settingsWindow: NSWindow?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        menuBar = MenuBarController(rootView: MenuView(model: model, openSettings: { [weak self] in
            self?.showSettings()  // first, so closing the menu leaves Fader active for Settings
            self?.menuBar?.close()
        }))

        let hotKeys = HotKeyCenter.shared
        hotKeys.onPress = { [weak self] binding in self?.hotKeyPressed(binding) }
        hotKeys.onRelease = { [weak self] _ in self?.stopRepeating() }
        hotKeys.install()
        hotKeys.update(store.settings.shortcuts)
        store.onShortcutsChanged = { hotKeys.update($0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Fader Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, store: store))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Shortcuts

    private func hotKeyPressed(_ binding: ShortcutBinding) {
        stopRepeating()
        perform(binding)
        guard binding.action.repeatsWhileHeld else { return }
        // Carbon hotkeys don't auto-repeat, so emulate the system key-repeat timing.
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
                    MainActor.assumeIsolated { self?.perform(binding) }
                }
            }
        }
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func perform(_ binding: ShortcutBinding) {
        guard let bundleID = model.resolve(binding.target) else {
            NSSound.beep()
            return
        }
        let step = store.settings.volumeStep
        switch binding.action {
        case .volumeUp: model.adjustVolume(for: bundleID, by: step)
        case .volumeDown: model.adjustVolume(for: bundleID, by: -step)
        case .toggleMute: model.toggleMute(bundleID)
        }
        hud.show(
            name: model.displayName(for: bundleID),
            icon: model.icon(for: bundleID),
            volume: model.volume(for: bundleID),
            muted: model.isMuted(bundleID)
        )
    }
}
