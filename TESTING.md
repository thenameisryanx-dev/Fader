# Testing Fader

Every change gets two kinds of checks before it's saved as done.

## 1. Automated checks (a few seconds)

```bash
./check.sh
```

This runs all automated tests and builds the app. If it says ❌, the change isn't done.

GitHub runs the same `./check.sh` on its own Mac after every push and on every pull request.
After pushing, open the repo's **Actions** tab (or the ✓/✗ next to the latest commit): a red ✗ means
it failed there even if it passed on your Mac, and the run's log says why.

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
- [ ] Look closely at the menu's corners over a light window: no faint square outline or shadow
      sticking out past the rounded corners. Check again after an app's row appears or goes away
- [ ] The sliders are filled in your accent colour (blue by default, not grey) while the menu is open
- [ ] Start and stop audio in an app with the menu open: its row appears and goes away, and the
      menu grows and shrinks with it (its top edge stays put, no empty space)
- [ ] The menu closes when you: click the icon again, press Escape, click another app or the
      desktop, click another menu bar icon. Afterwards you can type in the app you were using
- [ ] Settings… opens the Settings window and closes the menu
- [ ] Drag sliders and click the speaker icons in the menu to mute and unmute: they work as before

### When a change touches the look (`Theme.swift`, glass, buttons)

- [ ] Open the menu over a colourful window or wallpaper: the background is Liquid Glass (clear,
      bending the colours behind it at the edges), with rounder corners than before
- [ ] Sliders have the new pill-shaped glass knob; "Settings…" and "Quit Fader" are glass capsules.
      Each row shows the app icon, name and % on top, then a speaker icon and the slider
- [ ] The speaker icon shows more waves as you raise the volume. Clicking it mutes (red, crossed out,
      "Muted") and clicking again unmutes. There is only one speaker icon per row
- [ ] The slider fill is easy to see in both light and dark mode (System Settings → Appearance)
- [ ] Switch the accent colour to Graphite (System Settings → Appearance): the sliders turn grey. Switch it back
- [ ] Use a volume shortcut: the on-screen overlay is glass too, with a bar in your accent colour
- [ ] Press the shortcut over something colourful (a photo or a bright web page): the overlay is the
      same Liquid Glass as the menu (the colours behind it blur and bend at its rounded edges), not a
      flat grey box. Its shadow is rounded with no faint square outline around the corners
- [ ] Tap a volume shortcut a few times: the overlay's bar lands on each new value the moment you
      press, at the same time as the % number. Hold the key: the bar keeps up with the number and
      stops the moment you let go, without sliding on afterwards or flickering
- [ ] System Settings → Accessibility → Display → turn on "Reduce transparency": the menu and
      overlay turn solid and stay readable. Turn it back off afterwards
- [ ] Same with "Increase contrast": text and sliders stay readable

### When a change touches volume memory or devices

- [ ] Set an app to 30% on one output (e.g. JBL), switch to another output (e.g. AirPods) and set 70%
- [ ] Switch back and forth: each output gets its own volume back
- [ ] Quit Fader and reopen it: the volumes are still remembered
- [ ] Settings → "Saved volumes per output device" lists them; the ✕ button forgets one

### When a change touches the overall volume row

- [ ] The "Overall volume" row at the top shows the same level as the volume in Control Center
- [ ] Drag its slider: everything gets louder or quieter, and Control Center's slider moves with it
- [ ] Press the volume keys on the keyboard with the menu open: the row's slider follows
- [ ] Its speaker icon mutes everything (the volume keys' mute does the same and the row shows –)
- [ ] With an app turned down in Fader, lowering the overall volume makes that app quieter too
- [ ] Switch outputs (e.g. speakers to AirPods): the row shows the new output's volume
- [ ] On the JBL Go 4 (USB), drag the overall slider quickly back and forth for about 10 seconds:
      the menu never freezes, the slider stays under your finger, and when you let go the sound
      settles at the level the slider shows
- [ ] On the JBL Go 4, open the menu and press the volume keys quickly about 10 times (or drag the
      volume slider in Control Center): you can keep dragging an app's slider the whole time with
      no spinning beachball, and a few seconds after you stop, the overall row shows the JBL's level

### When a change touches shortcuts

- [ ] Quit Fader, reopen it, and **without opening the menu** press a shortcut: it works
- [ ] A shortcut for a specific app controls that app even when another app is in front
- [ ] A "Frontmost app" shortcut controls the app you're using
- [ ] Holding volume up or down keeps changing the volume; the on-screen overlay shows the level
- [ ] Press a volume shortcut on a normal desktop: the overlay hangs just below Fader's menu bar
      icon (centred under it, like macOS's own volume popup under the Sound icon)
- [ ] Put an app in full screen (green button, or Safari → View → Enter Full Screen) and press the
      shortcut: the overlay appears at the top middle of the screen, close to the top edge.
      Leave full screen and press it again: it's back under the menu bar icon
- [ ] Hold a shortcut down: the overlay stays in one place while the volume changes
- [ ] Press a shortcut once, wait until the overlay starts fading (just over a second), then press
      it again: the overlay comes straight back, fully visible, and stays about a second before fading.
      Try it a few times with slightly different timing; it never vanishes right after a press
- [ ] Recording a combination another app already uses shows the ⚠️ warning
- [ ] Settings → **Add Shortcut…** opens a sheet. Click the box: it turns blue and says "Press keys…".
      Hold ⌃⌥: it shows "⌃⌥…". Press ↑: the box shows ⌃⌥↑ and **Add** turns on
- [ ] In the box, press a plain letter: an orange message explains you need ⌃, ⌥ or ⌘, and it keeps listening
- [ ] While the box is listening, press Esc: it stops listening and the sheet stays open.
      Click it again, then click somewhere else in the sheet: it stops listening too
- [ ] Right after adding a shortcut (no restart), it works, and your **older** shortcuts still work too
- [ ] Try to add a key that another Fader shortcut already uses: an orange message names that shortcut and **Add** stays off
- [ ] Double-click a shortcut (or click the pencil): the sheet opens filled in. Change the app and save:
      the row updates in the same place, and the shortcut now controls the new app
- [ ] Action → "Up, down and mute (3 shortcuts)": three boxes appear; recording all three adds three rows
- [ ] App → "Other app…": pick an app from Applications that isn't running; it appears in the row
- [ ] Quit and reopen Fader: all shortcuts are still there and work

### When a change touches the audio engine (`AppTap.swift`, `MixerModel.swift`)

Run everything above, plus:

- [ ] Bluetooth: lower an app's volume while on AirPods or another Bluetooth device, then start a call or open a mic app (the audio format changes). Sound continues afterwards
- [ ] Unplug or disconnect the current output while audio plays: it moves to the next output at the right volume
- [ ] Quit Fader while an app is turned down: the app goes back to normal volume
- [ ] Play an alert sound (`osascript -e beep`): it plays at normal volume, and the list
      shows no "systemsoundserverd" row
- [ ] Leave music playing for 10 minutes with the volume lowered: no dropouts. Activity Monitor shows Fader using little CPU
- [ ] With the JBL Go 4 and AirPods both connected and music playing, leave Fader running for a few
      minutes, then press a volume shortcut about 20 times, a second or two apart: the on-screen
      overlay answers every press right away, never seconds late. Clicking in the menu feels instant too
- [ ] With the menu open, start and stop music: the app's row appears and goes away within about 2 s
- [ ] Right after a rebuild, before allowing access: the menu shows "Allow Access". Click it and allow:
      the banner goes away and turning an app down works. (If you allow it in System Settings instead,
      the banner goes away within about 5 s.)
- [ ] Run `/usr/bin/log stream --predicate 'process == "Fader"' | grep TCC` for 20 seconds: at most one
      line every 5 seconds before access is allowed, and none at all once it is

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
