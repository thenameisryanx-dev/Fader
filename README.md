# Fader

A menu bar per-app volume mixer for macOS 15+.

- A volume slider and mute button for every app that plays audio
- Volumes are remembered per app **per output device** (Spotify at 30% on speakers, 70% on AirPods)
- Global keyboard shortcuts bound to a specific app or to the frontmost app, active from launch

## Build and run

```bash
./build.sh
open build/Fader.app
```

The first time you open it, click **Allow Access** in the menu and grant System Audio Recording.
The app is signed ad hoc, so macOS may ask again after each rebuild.

Settings live in `~/Library/Application Support/Fader/settings.json`.

## Sharing it

```bash
./package.sh
```

This builds `build/Fader.dmg` with the app, an Applications shortcut and "How to open Fader.txt".
The app isn't signed with an Apple Developer ID, so on other Macs macOS blocks it the first time;
the text file explains how to allow it via **System Settings → Privacy & Security → Open Anyway**.
It runs on Apple Silicon Macs with macOS 15 or newer.

## Checking changes

Run `./check.sh` (all automated tests and the app build) after every change, then the manual checks
in [TESTING.md](TESTING.md). [CLAUDE.md](CLAUDE.md) describes the full workflow.

## How it works

Apps at 100% and not muted aren't touched. When you lower or mute an app, Fader creates a Core Audio
process tap that mutes the app's own output and captures it, then plays it back through a private
aggregate device on the current output device with the gain applied (`AppTap.swift`).
Switching output devices rebuilds the taps with that device's saved volumes (`MixerModel.swift`).

Logs: `/usr/bin/log stream --predicate 'subsystem == "com.ryan.Fader"' --level debug`
