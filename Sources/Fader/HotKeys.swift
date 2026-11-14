import AppKit
import Carbon.HIToolbox
import Observation

/// A key combination as recorded from the user.
struct RecordedKey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    var display: String { Self.symbols(forCarbonModifiers: carbonModifiers) + keyLabel }

    /// Two keys are the same shortcut when the key and modifiers match, whatever the label says.
    func isSameCombination(as other: RecordedKey) -> Bool {
        keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }

    /// Returns nil for combinations that would be unsafe to grab globally
    /// (plain letters without ⌘, ⌥ or ⌃, except function keys).
    init?(event: NSEvent) {
        self.init(
            keyCode: Int(event.keyCode),
            modifierFlags: event.modifierFlags,
            characters: event.charactersIgnoringModifiers
        )
    }

    init?(keyCode: Int, modifierFlags: NSEvent.ModifierFlags, characters: String?) {
        guard case .success(let key) = Self.make(
            keyCode: keyCode, modifierFlags: modifierFlags, characters: characters
        ) else { return nil }
        self = key
    }

    private init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    /// Turns a key press into a shortcut, or says why it can't be one.
    static func make(
        keyCode: Int, modifierFlags: NSEvent.ModifierFlags, characters: String?
    ) -> Result<RecordedKey, KeyRejection> {
        let modifiers = carbonModifiers(for: modifierFlags)
        let isFunctionKey = functionKeys[keyCode] != nil
        let hasAnchor = modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
        guard hasAnchor || isFunctionKey else { return .failure(.needsModifier) }

        let label = functionKeys[keyCode]
            ?? specialKeys[keyCode]
            ?? characters?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let label, !label.isEmpty else { return .failure(.unsupportedKey) }

        return .success(RecordedKey(keyCode: UInt32(keyCode), carbonModifiers: modifiers, keyLabel: label))
    }

    static func carbonModifiers(for modifierFlags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    /// Modifier symbols in the standard Mac order: ⌃⌥⇧⌘.
    static func symbols(forCarbonModifiers modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_Return: "↩", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Tab: "⇥", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
}

/// Why a key press can't become a shortcut, in words shown under the recorder.
enum KeyRejection: Error, Equatable {
    /// A plain letter, number or symbol: grabbing it everywhere would stop you typing it.
    case needsModifier
    /// A key with no name we can show, like a lone modifier.
    case unsupportedKey

    var message: String {
        switch self {
        case .needsModifier: "Add ⌃, ⌥ or ⌘ so normal typing still works (F-keys work on their own)."
        case .unsupportedKey: "That key can't be used for a shortcut. Try another one."
        }
    }
}

/// The part of `HotKeyCenter` the recorder needs, so tests can use a stand-in.
@MainActor
protocol HotKeyPausing: AnyObject {
    func setSuspended(_ suspended: Bool)
}

/// Global hotkeys via Carbon's RegisterEventHotKey: works without Accessibility permission
/// and is registered at launch, not when the menu is first opened.
@MainActor
@Observable
final class HotKeyCenter: HotKeyPausing {
    static let shared = HotKeyCenter()

    /// Bindings the system refused, usually because another app already owns the combination.
    private(set) var failedIDs: Set<UUID> = []

    @ObservationIgnored var onPress: ((ShortcutBinding) -> Void)?
    @ObservationIgnored var onRelease: ((ShortcutBinding) -> Void)?

    @ObservationIgnored private var handlerRef: EventHandlerRef?
    @ObservationIgnored private var registered: [UInt32: (ref: EventHotKeyRef, binding: ShortcutBinding)] = [:]
    @ObservationIgnored private var bindings: [ShortcutBinding] = []
    @ObservationIgnored private var suspended = false

    private static let signature: OSType = "FADR".utf8.reduce(0) { $0 << 8 | OSType($1) }

    func install() {
        guard handlerRef == nil else { return }
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, events.count, &events, nil, &handlerRef)
    }

    func update(_ bindings: [ShortcutBinding]) {
        self.bindings = bindings
        if !suspended { registerAll() }
    }

    /// Pauses all hotkeys while the user records a new one, so existing combos can be re-recorded.
    func setSuspended(_ suspended: Bool) {
        self.suspended = suspended
        if suspended { unregisterAll() } else { registerAll() }
    }

    private func registerAll() {
        unregisterAll()
        var failed = Set<UUID>()
        for (index, binding) in bindings.enumerated() {
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.key.keyCode, binding.key.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                registered[id.id] = (ref, binding)
            } else {
                failed.insert(binding.id)
            }
        }
        if failed != failedIDs { failedIDs = failed }
    }

    private func unregisterAll() {
        for entry in registered.values { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
    }

    fileprivate func handle(id: UInt32, pressed: Bool) {
        guard let binding = registered[id]?.binding else { return }
        if pressed { onPress?(binding) } else { onRelease?(binding) }
    }
}

private func hotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    MainActor.assumeIsolated {
        HotKeyCenter.shared.handle(id: hotKeyID.id, pressed: pressed)
    }
    return noErr
}
