import AppKit
import Carbon.HIToolbox
import Testing
@testable import Fader

/// Recording shortcuts and deciding which app a shortcut controls.
struct RecordedKeyTests {
    @Test func showsModifiersInStandardMacOrder() {
        let key = RecordedKey(
            keyCode: kVK_ANSI_S,
            modifierFlags: [.command, .shift, .option, .control],
            characters: "s"
        )
        #expect(key?.display == "⌃⌥⇧⌘S")
    }

    @Test func arrowKeysGetSymbols() {
        let key = RecordedKey(keyCode: kVK_UpArrow, modifierFlags: [.option, .shift], characters: nil)
        #expect(key?.display == "⌥⇧↑")
    }

    @Test func storesCarbonModifiersForRegistration() {
        let key = RecordedKey(keyCode: kVK_UpArrow, modifierFlags: [.option, .shift], characters: nil)
        #expect(key?.carbonModifiers == UInt32(optionKey | shiftKey))
        #expect(key?.keyCode == UInt32(kVK_UpArrow))
    }

    /// A global shortcut on a plain letter would stop you typing that letter anywhere.
    @Test func rejectsPlainLetters() {
        #expect(RecordedKey(keyCode: kVK_ANSI_S, modifierFlags: [], characters: "s") == nil)
        #expect(RecordedKey(keyCode: kVK_ANSI_S, modifierFlags: [.shift], characters: "S") == nil)
    }

    @Test func allowsFunctionKeysOnTheirOwn() {
        let key = RecordedKey(keyCode: kVK_F5, modifierFlags: [], characters: nil)
        #expect(key?.display == "F5")
    }

    @Test func ignoresCapsLock() {
        let key = RecordedKey(keyCode: kVK_ANSI_M, modifierFlags: [.command, .capsLock], characters: "m")
        #expect(key?.display == "⌘M")
        #expect(key?.carbonModifiers == UInt32(cmdKey))
    }
}

struct FrontmostTargetTests {
    @Test func frontmostAppWinsWhenItMakesSound() {
        let target = MixerModel.pickFrontmostTarget(
            frontmost: "com.apple.Safari",
            lastControlled: "com.spotify.client",
            hasPlayed: ["com.apple.Safari", "com.spotify.client"],
            playingInOrder: ["com.spotify.client"]
        )
        #expect(target == "com.apple.Safari")
    }

    @Test func silentFrontmostFallsBackToLastControlledApp() {
        let target = MixerModel.pickFrontmostTarget(
            frontmost: "com.apple.finder",
            lastControlled: "com.spotify.client",
            hasPlayed: ["com.spotify.client", "us.zoom.xos"],
            playingInOrder: ["com.spotify.client", "us.zoom.xos"]
        )
        #expect(target == "com.spotify.client")
    }

    @Test func lastControlledAppThatStoppedIsSkipped() {
        let target = MixerModel.pickFrontmostTarget(
            frontmost: "com.apple.finder",
            lastControlled: "com.spotify.client",
            hasPlayed: ["com.spotify.client", "us.zoom.xos"],
            playingInOrder: ["us.zoom.xos"]
        )
        #expect(target == "us.zoom.xos")
    }

    @Test func nothingPlayingTargetsFrontmostAnyway() {
        let target = MixerModel.pickFrontmostTarget(
            frontmost: "com.apple.finder",
            lastControlled: nil,
            hasPlayed: [],
            playingInOrder: []
        )
        #expect(target == "com.apple.finder")
    }

    @Test func noInformationMeansNoTarget() {
        let target = MixerModel.pickFrontmostTarget(
            frontmost: nil, lastControlled: nil, hasPlayed: [], playingInOrder: []
        )
        #expect(target == nil)
    }
}
