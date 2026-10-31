import Testing
@testable import Fader

/// System audio processes stay out of the mixer, so Fader never taps (and mutes) them.
struct HiddenProcessesTests {
    /// Core Audio reports the system sounds process (alerts, beeps) without "com.apple.",
    /// so it used to slip through and get tapped.
    @Test func systemSoundsAreHidden() {
        #expect(MixerModel.isHidden("systemsoundserverd"))
        #expect(MixerModel.isHidden("com.apple.systemsoundserverd"))
    }

    @Test func coreAudioItselfIsHidden() {
        #expect(MixerModel.isHidden("com.apple.coreaudiod"))
        #expect(MixerModel.isHidden("com.apple.audio.AudioComponentRegistrar"))
    }

    @Test func realAppsAreShown() {
        #expect(!MixerModel.isHidden("com.google.Chrome"))
        #expect(!MixerModel.isHidden("com.spotify.client"))
    }
}
