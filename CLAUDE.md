# Fader

Menu bar per-app volume mixer for macOS 15+, written from scratch in Swift (SwiftPM, no Xcode project).
See README.md for how it works.

## About Ryan

Ryan is new to app development. Explain what you're doing and why in plain language, define jargon
the first time it comes up, and say what he needs to do by hand (e.g. which manual checks to run).

## Workflow (every change)

1. One feature or fix at a time, on its own git branch (`git switch -c feature-name`).
2. Every new feature or bug fix comes with automated tests in `Tests/FaderTests/`.
   For a bug, write the test that reproduces it first, watch it fail, then fix it.
3. Run `./check.sh` after every change. A change is not done while it fails or has build warnings.
   Never delete or weaken a test to make it pass. If a test is wrong, explain why before changing it.
4. Update `TESTING.md` when a feature needs a manual check (anything you have to hear or click),
   and tell Ryan exactly which manual checks this change needs.
5. Commit only after `./check.sh` passes and Ryan confirms the manual checks. Then merge the branch into `main`
   and `git push` it: GitHub (public repo thenameisryanx-dev/Fader) is the only backup.

## Code rules

- Settings file compatibility: any new field in `FaderSettings` / `AppPrefs` must be decoded with
  `decodeIfPresent` and a default. `loadsSettingsFileFromVersion0_1` guards this; never edit that fixture.
- `GainRenderer.render` runs on the real-time audio thread: no allocation, locks, logging, or Swift arrays there.
- A process tap mutes the app it taps. Any failure after creating a tap must destroy it (see `AppTap.init`).
- Apps at 100% and unmuted must stay untapped.
- Keep pure logic out of AppKit and Core Audio types where possible so it can be unit-tested
  (e.g. `MixerModel.pickFrontmostTarget`).

## Commands

- `./check.sh`: all automated checks (tests and app build)
- `swift test`: tests only
- `./build.sh` then `open build/Fader.app`: build and run
- `./package.sh`: build `build/Fader.dmg` to send to other people
- Logs: `/usr/bin/log stream --predicate 'subsystem == "com.ryan.Fader"' --level debug`
