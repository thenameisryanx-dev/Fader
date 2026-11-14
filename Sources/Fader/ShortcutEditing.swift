import AppKit
import Carbon.HIToolbox
import Observation

/// What the "Add / Edit Shortcut" sheet is filling in. Pure data, so the rules are unit-tested.
struct ShortcutDraft: Equatable {
    enum Kind: Hashable {
        /// One shortcut for one action.
        case single(ShortcutAction)
        /// Volume up, volume down and mute for the same app, each with its own key.
        case fullSet
    }

    /// Something that stops the draft from being saved.
    enum Problem: Equatable {
        /// The same key is used for two actions inside this set.
        case sameKeyTwice(RecordedKey)
        /// Another saved shortcut already uses this key.
        case alreadyUsed(RecordedKey, by: ShortcutBinding)
    }

    /// The shortcut being changed, or nil when adding new ones.
    private(set) var editingID: UUID?
    var target: ShortcutTarget = .frontmost
    var kind: Kind = .single(.volumeUp)
    /// The key for a single shortcut. Kept when you switch actions.
    var singleKey: RecordedKey?
    /// The keys for a full set, one per action.
    var setKeys: [ShortcutAction: RecordedKey] = [:]

    init() {}

    init(editing binding: ShortcutBinding) {
        editingID = binding.id
        target = binding.target
        kind = .single(binding.action)
        singleKey = binding.key
    }

    var isEditing: Bool { editingID != nil }

    /// The actions that need a key, in display order.
    var actions: [ShortcutAction] {
        switch kind {
        case .single(let action): [action]
        case .fullSet: ShortcutAction.allCases
        }
    }

    func key(for action: ShortcutAction) -> RecordedKey? {
        switch kind {
        case .single: singleKey
        case .fullSet: setKeys[action]
        }
    }

    mutating func setKey(_ key: RecordedKey?, for action: ShortcutAction) {
        switch kind {
        case .single: singleKey = key
        case .fullSet: setKeys[action] = key
        }
    }

    /// Every action has a key.
    var isComplete: Bool { actions.allSatisfy { key(for: $0) != nil } }

    /// Clashes with each other or with `existing` shortcuts. The shortcut being edited doesn't count.
    func problems(existing: [ShortcutBinding]) -> [Problem] {
        var problems: [Problem] = []
        var seen: [RecordedKey] = []
        for action in actions {
            guard let key = key(for: action) else { continue }
            if seen.contains(where: { $0.isSameCombination(as: key) }) {
                if !problems.contains(.sameKeyTwice(key)) { problems.append(.sameKeyTwice(key)) }
                continue
            }
            seen.append(key)
            if let other = existing.first(where: { $0.id != editingID && $0.key.isSameCombination(as: key) }) {
                problems.append(.alreadyUsed(key, by: other))
            }
        }
        return problems
    }

    func canSave(existing: [ShortcutBinding]) -> Bool {
        isComplete && problems(existing: existing).isEmpty
    }

    /// The shortcuts to save. An edited shortcut keeps its id, so it stays in the same place.
    func bindings() -> [ShortcutBinding] {
        actions.compactMap { action in
            guard let key = key(for: action) else { return nil }
            var binding = ShortcutBinding(key: key, action: action, target: target)
            if let editingID { binding.id = editingID }
            return binding
        }
    }
}

/// Reads the bundle identifier and name of an app the user picked with "Other app…".
enum AppBundleInfo {
    static func read(at url: URL) -> (bundleID: String, name: String)? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return (bundleID, name)
    }
}

/// Records one key combination. A class rather than SwiftUI view state, so the recording
/// state is always current inside the key-event callback, and so it can be unit-tested.
///
/// While recording, every Fader shortcut is paused (otherwise pressing an existing shortcut
/// would change a volume instead of being recorded). Every way recording ends resumes them.
@MainActor
@Observable
final class KeyRecorderController {
    enum Outcome: Equatable {
        case recorded(RecordedKey)
        case rejected(KeyRejection)
        case cancelled
    }

    private(set) var isRecording = false
    /// Modifier keys held down right now, e.g. "⌃⌥", so you can see the recorder is listening.
    private(set) var heldModifiers = ""
    /// Why the last key press was refused, shown under the recorder.
    private(set) var rejection: KeyRejection?

    @ObservationIgnored var onRecord: ((RecordedKey) -> Void)?
    /// Where the recorder is in its window (top-left origin), so a click elsewhere cancels.
    @ObservationIgnored var frameInWindow: CGRect = .zero

    @ObservationIgnored private let hotKeys: HotKeyPausing
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    init(hotKeys: HotKeyPausing) {
        self.hotKeys = hotKeys
    }

    // MARK: Logic (tested)

    /// Starts listening. Calling it again while recording does nothing.
    func begin() {
        guard !isRecording else { return }
        isRecording = true
        rejection = nil
        heldModifiers = ""
        hotKeys.setSuspended(true)
    }

    /// Stops listening without recording anything. Safe to call any number of times.
    func cancel() {
        guard isRecording else { return }
        finish()
    }

    @discardableResult
    func handleKeyDown(keyCode: Int, modifierFlags: NSEvent.ModifierFlags, characters: String?) -> Outcome? {
        guard isRecording else { return nil }
        if keyCode == kVK_Escape {
            cancel()
            return .cancelled
        }
        switch RecordedKey.make(keyCode: keyCode, modifierFlags: modifierFlags, characters: characters) {
        case .success(let key):
            finish()
            onRecord?(key)
            return .recorded(key)
        case .failure(let reason):
            rejection = reason
            return .rejected(reason)
        }
    }

    func handleFlagsChanged(_ modifierFlags: NSEvent.ModifierFlags) {
        guard isRecording else { return }
        heldModifiers = RecordedKey.symbols(forCarbonModifiers: RecordedKey.carbonModifiers(for: modifierFlags))
    }

    /// A click outside the recorder cancels; a click on it is handled by its own button.
    func handleClick(atTopLeftPoint point: CGPoint) {
        guard isRecording, !frameInWindow.contains(point) else { return }
        cancel()
    }

    private func finish() {
        isRecording = false
        heldModifiers = ""
        hotKeys.setSuspended(false)
        removeMonitors()
    }

    // MARK: Event plumbing (checked by hand, see TESTING.md)

    /// Starts recording and listens to this app's key presses and clicks.
    func start(in window: NSWindow?) {
        guard !isRecording else { return }
        begin()
        self.window = window
        // The callback runs on the main thread, like this class.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
            self?.route(event) ?? event
        }
        if let window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }
        }
    }

    private func route(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            handleKeyDown(
                keyCode: Int(event.keyCode),
                modifierFlags: event.modifierFlags,
                characters: event.charactersIgnoringModifiers
            )
            return nil  // never let a key being recorded type or trigger anything
        case .flagsChanged:
            handleFlagsChanged(event.modifierFlags)
            return event
        case .leftMouseDown:
            if event.window !== window {
                cancel()
            } else if let content = event.window?.contentView {
                var point = content.convert(event.locationInWindow, from: nil)
                if !content.isFlipped { point.y = content.bounds.height - point.y }
                handleClick(atTopLeftPoint: point)
            }
            return event
        default:
            return event
        }
    }

    private func removeMonitors() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        window = nil
    }
}
