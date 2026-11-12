import AppKit
import Testing
@testable import Fader

/// Fader's look: Apple's Liquid Glass with standard controls, laid out like macOS's own Control Center.
struct ThemeTests {
    // MARK: Speaker icon (also the mute button)

    @Test func speakerShowsMoreWavesAsVolumeRises() {
        #expect(Theme.speakerSymbol(volume: 0, isMuted: false) == "speaker.fill")
        #expect(Theme.speakerSymbol(volume: 0.2, isMuted: false) == "speaker.wave.1.fill")
        #expect(Theme.speakerSymbol(volume: 0.5, isMuted: false) == "speaker.wave.2.fill")
        #expect(Theme.speakerSymbol(volume: 0.9, isMuted: false) == "speaker.wave.3.fill")
        #expect(Theme.speakerSymbol(volume: 1, isMuted: false) == "speaker.wave.3.fill")
    }

    @Test func speakerIsCrossedOutWhenMutedAtAnyVolume() {
        for volume: Float in [0, 0.5, 1] {
            #expect(Theme.speakerSymbol(volume: volume, isMuted: true) == "speaker.slash.fill")
        }
    }

    @Test func speakerSymbolsExistOnThisMac() {
        // A typo in a symbol name would show an empty space instead of an icon.
        for volume: Float in [0, 0.2, 0.5, 1] {
            for muted in [false, true] {
                let name = Theme.speakerSymbol(volume: volume, isMuted: muted)
                #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
            }
        }
    }

    // MARK: Rounded corners

    @Test func innerCornersFollowTheOuterCornersCurve() {
        // Apple's "concentric" rule: a shape inset by 14 pt inside an 18 pt corner gets a 4 pt corner,
        // so both curves share the same centre.
        #expect(Theme.concentricRadius(outer: 18, inset: 14) == 4)
        #expect(Theme.concentricRadius(outer: 26, inset: 10) == 16)
    }

    @Test func innerCornersNeverBecomeSharp() {
        #expect(Theme.concentricRadius(outer: 12, inset: 14) == Theme.minimumCornerRadius)
    }
}
