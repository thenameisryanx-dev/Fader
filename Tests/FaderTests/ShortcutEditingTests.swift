import AppKit
import Carbon.HIToolbox
import Testing
@testable import Fader

private let ctrlOptUp = RecordedKey(keyCode: kVK_UpArrow, modifierFlags: [.control, .option], characters: nil)!
private let ctrlOptDown = RecordedKey(keyCode: kVK_DownArrow, modifierFlags: [.control, .option], characters: nil)!
private let ctrlOptM = RecordedKey(keyCode: kVK_ANSI_M, modifierFlags: [.control, .option], characters: "m")!

/// Why the recorder refuses a key, shown to the user.
struct KeyRejectionTests {
    @Test func plainLetterNeedsAModifier() {
        let result = RecordedKey.make(keyCode: kVK_ANSI_S, modifierFlags: [], characters: "s")
        #expect(result == .failure(.needsModifier))
    }

    @Test func shiftAloneIsNotEnough() {
        let result = RecordedKey.make(keyCode: kVK_ANSI_S, modifierFlags: [.shift], characters: "S")
        #expect(result == .failure(.needsModifier))
    }

    @Test func keyWithNoNameIsUnsupported() {
        let result = RecordedKey.make(keyCode: 0x7F, modifierFlags: [.control], characters: nil)
        #expect(result == .failure(.unsupportedKey))
    }

    @Test func everyRejectionExplainsItself() {
        #expect(KeyRejection.needsModifier.message.contains("⌘"))
        #expect(!KeyRejection.unsupportedKey.message.isEmpty)
    }

    @Test func sameCombinationIgnoresTheLabel() {
        let a = RecordedKey(keyCode: kVK_ANSI_K, modifierFlags: [.command], characters: "k")!
        let b = RecordedKey(keyCode: kVK_ANSI_K, modifierFlags: [.command], characters: "K")!
        let c = RecordedKey(keyCode: kVK_ANSI_K, modifierFlags: [.command, .shift], characters: "k")!
        #expect(a.isSameCombination(as: b))
        #expect(!a.isSameCombination(as: c))
    }
}

/// The rules of the Add / Edit Shortcut sheet.
struct ShortcutDraftTests {
    @Test func newDraftCantSaveUntilAKeyIsRecorded() {
        var draft = ShortcutDraft()
        #expect(!draft.isComplete)
        #expect(!draft.canSave(existing: []))
        draft.setKey(ctrlOptUp, for: .volumeUp)
        #expect(draft.canSave(existing: []))
    }

    @Test func switchingActionKeepsTheRecordedKey() {
        var draft = ShortcutDraft()
        draft.setKey(ctrlOptUp, for: .volumeUp)
        draft.kind = .single(.volumeDown)
        #expect(draft.key(for: .volumeDown) == ctrlOptUp)
        #expect(draft.bindings().map(\.action) == [.volumeDown])
    }

    @Test func keyAlreadyUsedByAnotherShortcutIsReported() {
        let existing = ShortcutBinding(key: ctrlOptUp, action: .volumeUp, target: .app(bundleID: "com.spotify.client"))
        var draft = ShortcutDraft()
        draft.setKey(ctrlOptUp, for: .volumeUp)
        #expect(draft.problems(existing: [existing]) == [.alreadyUsed(ctrlOptUp, by: existing)])
        #expect(!draft.canSave(existing: [existing]))
    }

    @Test func editingDoesNotClashWithItself() {
        let binding = ShortcutBinding(key: ctrlOptUp, action: .volumeUp, target: .frontmost)
        let draft = ShortcutDraft(editing: binding)
        #expect(draft.problems(existing: [binding]).isEmpty)
        #expect(draft.canSave(existing: [binding]))
    }

    @Test func editingKeepsTheSameIDAndLoadsTheShortcut() {
        let binding = ShortcutBinding(key: ctrlOptUp, action: .toggleMute, target: .app(bundleID: "us.zoom.xos"))
        var draft = ShortcutDraft(editing: binding)
        #expect(draft.isEditing)
        #expect(draft.kind == .single(.toggleMute))
        #expect(draft.target == .app(bundleID: "us.zoom.xos"))

        draft.setKey(ctrlOptM, for: .toggleMute)
        let saved = draft.bindings()
        #expect(saved.count == 1)
        #expect(saved[0].id == binding.id)
        #expect(saved[0].key == ctrlOptM)
    }

    @Test func fullSetMakesThreeShortcutsForTheSameApp() {
        var draft = ShortcutDraft()
        draft.kind = .fullSet
        draft.target = .app(bundleID: "com.spotify.client")
        draft.setKey(ctrlOptUp, for: .volumeUp)
        draft.setKey(ctrlOptDown, for: .volumeDown)
        #expect(!draft.isComplete)  // mute still missing
        draft.setKey(ctrlOptM, for: .toggleMute)

        let saved = draft.bindings()
        #expect(saved.map(\.action) == [.volumeUp, .volumeDown, .toggleMute])
        #expect(saved.allSatisfy { $0.target == .app(bundleID: "com.spotify.client") })
        #expect(Set(saved.map(\.id)).count == 3)
        #expect(draft.canSave(existing: []))
    }

    @Test func fullSetCantUseTheSameKeyTwice() {
        var draft = ShortcutDraft()
        draft.kind = .fullSet
        draft.setKey(ctrlOptUp, for: .volumeUp)
        draft.setKey(ctrlOptUp, for: .volumeDown)
        draft.setKey(ctrlOptM, for: .toggleMute)
        #expect(draft.problems(existing: []) == [.sameKeyTwice(ctrlOptUp)])
        #expect(!draft.canSave(existing: []))
    }
}

/// "Other app…" reads the app's id and name from the chosen .app.
struct AppBundleInfoTests {
    @Test func readsIdentifierAndName() throws {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("FaderTests-\(UUID().uuidString)")
            .appendingPathComponent("Some Player.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.player", "CFBundleName": "Player"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        let info = AppBundleInfo.read(at: app)
        #expect(info?.bundleID == "com.example.player")
        #expect(info?.name == "Player")
    }

    @Test func folderThatIsNotAnAppGivesNothing() {
        #expect(AppBundleInfo.read(at: FileManager.default.temporaryDirectory) == nil)
    }
}

/// Stand-in for HotKeyCenter that remembers pause / resume calls.
@MainActor
private final class FakeHotKeys: HotKeyPausing {
    var calls: [Bool] = []
    var isPaused: Bool { calls.last ?? false }
    func setSuspended(_ suspended: Bool) { calls.append(suspended) }
}

/// The recorder must always switch shortcuts back on when it stops, however it stops.
@MainActor
struct KeyRecorderControllerTests {
    @Test func recordingPausesShortcuts() {
        let hotKeys = FakeHotKeys()
        let recorder = KeyRecorderController(hotKeys: hotKeys)
        recorder.begin()
        #expect(recorder.isRecording)
        #expect(hotKeys.isPaused)
    }

    @Test func validKeyIsRecordedAndShortcutsResume() {
        let hotKeys = FakeHotKeys()
        let recorder = KeyRecorderController(hotKeys: hotKeys)
        var recorded: RecordedKey?
        recorder.onRecord = { recorded = $0 }

        recorder.begin()
        let outcome = recorder.handleKeyDown(keyCode: kVK_UpArrow, modifierFlags: [.control, .option], characters: nil)

        #expect(outcome == .recorded(ctrlOptUp))
        #expect(recorded == ctrlOptUp)
        #expect(!recorder.isRecording)
        #expect(hotKeys.calls == [true, false])
    }

    @Test func plainLetterIsExplainedAndKeepsListening() {
        let hotKeys = FakeHotKeys()
        let recorder = KeyRecorderController(hotKeys: hotKeys)
        recorder.begin()
        let outcome = recorder.handleKeyDown(keyCode: kVK_ANSI_S, modifierFlags: [], characters: "s")

        #expect(outcome == .rejected(.needsModifier))
        #expect(recorder.rejection == .needsModifier)
        #expect(recorder.isRecording)
        #expect(hotKeys.isPaused)
    }

    @Test func escapeCancelsAndShortcutsResume() {
        let hotKeys = FakeHotKeys()
        let recorder = KeyRecorderController(hotKeys: hotKeys)
        var recorded: RecordedKey?
        recorder.onRecord = { recorded = $0 }

        recorder.begin()
        #expect(recorder.handleKeyDown(keyCode: kVK_Escape, modifierFlags: [], characters: nil) == .cancelled)
        #expect(recorded == nil)
        #expect(!recorder.isRecording)
        #expect(hotKeys.calls == [true, false])
    }

    @Test func cancellingTwiceResumesOnce() {
        let hotKeys = FakeHotKeys()
        let recorder = KeyRecorderController(hotKeys: hotKeys)
        recorder.begin()
        recorder.begin()  // a second click while already recording
        recorder.cancel()
        recorder.cancel()  // e.g. Esc, then the sheet closing
        #expect(hotKeys.calls == [true, false])
    }

    @Test func keysAreIgnoredWhenNotRecording() {
        let hotKeys = FakeHotKeys()
        let recorder = KeyRecorderController(hotKeys: hotKeys)
        #expect(recorder.handleKeyDown(keyCode: kVK_UpArrow, modifierFlags: [.control], characters: nil) == nil)
        #expect(hotKeys.calls.isEmpty)
    }

    @Test func heldModifiersAreShownWhileRecording() {
        let recorder = KeyRecorderController(hotKeys: FakeHotKeys())
        recorder.begin()
        recorder.handleFlagsChanged([.control, .option])
        #expect(recorder.heldModifiers == "⌃⌥")
        recorder.handleFlagsChanged([])
        #expect(recorder.heldModifiers == "")
    }

    @Test func clickOutsideCancelsButClickInsideDoesNot() {
        let hotKeys = FakeHotKeys()
        let recorder = KeyRecorderController(hotKeys: hotKeys)
        recorder.frameInWindow = CGRect(x: 100, y: 50, width: 150, height: 24)
        recorder.begin()

        recorder.handleClick(atTopLeftPoint: CGPoint(x: 120, y: 60))
        #expect(recorder.isRecording)

        recorder.handleClick(atTopLeftPoint: CGPoint(x: 20, y: 300))
        #expect(!recorder.isRecording)
        #expect(hotKeys.calls == [true, false])
    }
}
