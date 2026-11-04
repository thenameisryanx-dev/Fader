# Testing Fader

Every change gets two kinds of checks before it's saved as done.

## 1. Automated checks (a few seconds)

```bash
./check.sh
```

This runs all automated tests and builds the app. If it says ❌, the change isn't done.

## 2. Manual checks (about 5 minutes)

These cover what a computer can't check: whether you actually *hear* the difference.
Open the freshly built app first:

```bash
open build/Fader.app
```

If macOS asks for System Audio Recording again, allow it. The app is signed ad hoc, so each
rebuild can look like a new app to macOS.

### Every version (quick check)

- [ ] Fader's icon appears in the menu bar and the menu opens
- [ ] Play music (Spotify, Music or a YouTube video). The app appears in the list with a green dot
- [ ] Drag its slider down: the sound gets quieter right away, with no crackling
- [ ] Drag it back to 100%: normal volume, no gap or click
- [ ] Mute and unmute it: the sound stops and comes back
- [ ] Other apps playing at the same time are not affected

### When a change touches the menu window (`MenuPanel.swift`)

- [ ] Open the menu: no empty strip at the top, rounded corners, and it hangs just below the icon
- [ ] The sliders are blue (not grey) while the menu is open
- [ ] Start and stop audio in an app with the menu open: its row appears and goes away, and the
      menu grows and shrinks with it (its top edge stays put, no empty space)
- [ ] The menu closes when you: click the icon again, press Escape, click another app or the
      desktop, click another menu bar icon. Afterwards you can type in the app you were using
- [ ] Settings… opens the Settings window and closes the menu
- [ ] Drag sliders and press the mute buttons in the menu: they work as before

### When a change touches volume memory or devices

- [ ] Set an app to 30% on one output (e.g. JBL), switch to another output (e.g. AirPods) and set 70%
- [ ] Switch back and forth: each output gets its own volume back
- [ ] Quit Fader and reopen it: the volumes are still remembered
- [ ] Settings → "Saved volumes per output device" lists them; the ✕ button forgets one

### When a change touches the overall volume row

- [ ] The "Overall volume" row at the top shows the same level as the volume in Control Center
- [ ] Drag its slider: everything gets louder or quieter, and Control Center's slider moves with it
- [ ] Press the volume keys on the keyboard with the menu open: the row's slider follows
- [ ] Its mute button mutes everything (the volume keys' mute does the same and the row shows –)
- [ ] With an app turned down in Fader, lowering the overall volume makes that app quieter too
- [ ] Switch outputs (e.g. speakers to AirPods): the row shows the new output's volume
- [ ] On the JBL Go 4 (USB), drag the overall slider quickly back and forth for about 10 seconds:
      the menu never freezes, the slider stays under your finger, and when you let go the sound
      settles at the level the slider shows

### When a change touches shortcuts

- [ ] Quit Fader, reopen it, and **without opening the menu** press a shortcut: it works
- [ ] A shortcut for a specific app controls that app even when another app is in front
- [ ] A "Frontmost app" shortcut controls the app you're using
- [ ] Holding volume up or down keeps changing the volume; the on-screen overlay shows the level
- [ ] Recording a combination another app already uses shows the ⚠️ warning

### When a change touches the audio engine (`AppTap.swift`, `MixerModel.swift`)

Run everything above, plus:

- [ ] Bluetooth: lower an app's volume while on AirPods or another Bluetooth device, then start a call or open a mic app (the audio format changes). Sound continues afterwards
- [ ] Unplug or disconnect the current output while audio plays: it moves to the next output at the right volume
- [ ] Quit Fader while an app is turned down: the app goes back to normal volume
- [ ] Play an alert sound (`osascript -e beep`): it plays at normal volume, and the list
      shows no "systemsoundserverd" row
- [ ] Leave music playing for 10 minutes with the volume lowered: no dropouts. Activity Monitor shows Fader using little CPU

### When a change touches the launcher (`Open Fader.command`)

- [ ] With Fader not running, double-click `Open Fader.command` in Finder: a Terminal window shows
      the build, then Fader's icon appears in the menu bar
- [ ] With an app turned down in Fader, double-click it again: the old Fader quits and the new one
      opens with only one icon in the menu bar, and the app comes back at the volume you set
- [ ] Break the build on purpose (e.g. type `xyz` at the top of `FaderApp.swift`) and double-click it:
      the Terminal window shows the error and the running Fader keeps working. Undo the edit afterwards

### When a change touches packaging (`package.sh`)

- [ ] Run `./package.sh`, then double-click `build/Fader.dmg`: a window shows Fader, an Applications shortcut and "How to open Fader.txt"
- [ ] Drag Fader onto Applications, eject the disk image, and open Fader from Applications: it runs (run the quick check above)
- [ ] Before sending a new version to someone, test on another Mac or user account if you can: the "Open Anyway" steps in the text file work

## When something breaks

1. Write down what you did and what happened.
2. Stream the logs while reproducing it, and paste them into Claude:
   ```bash
   /usr/bin/log stream --predicate 'subsystem == "com.ryan.Fader"' --level debug
   ```
3. When the bug is fixed, a test that reproduces it gets added so it can't quietly come back.
