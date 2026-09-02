# Lock Clock

A background macOS utility that draws a solid, non–Liquid Glass clock on the Lock Screen after Apple’s large Lock Screen clock has been turned off in System Settings.

It is a personal AppKit agent. It uses a small set of private SkyLight APIs to place a display-only window on the Lock Screen Space. It is not App Store compatible.

## Download and install (no Xcode)

You do **not** need Xcode. Download the latest `LockClock-1.0.0-N.zip` from [Releases](https://github.com/christos-pas/mac-os-tahoe-classic-clock/releases) (or the zip someone built with `make dist`).

This build is **ad-hoc signed and not notarized**. There is no Apple Developer ID. macOS Gatekeeper will warn you. That is expected, not a virus scan result.

1. In **System Settings → Wallpaper**, turn off Apple’s large Lock Screen clock.
2. Double-click the zip to unpack **LockClock.app**.
3. Drag it to **Applications**.
4. Open it the first time with **Control-click → Open** (or right-click → **Open**), then click **Open** in the dialog.
5. If macOS says the app is **damaged** and should be moved to the Trash, that is the quarantine flag on an unsigned download. In Terminal:

   ```bash
   xattr -d com.apple.quarantine /Applications/LockClock.app
   ```

   Then Control-click → **Open** again.
6. A clock icon appears in the menu bar. There is no Dock icon.
7. Lock with **Control-Command-Q**. Unlock to hide the clock.

Quit from the menu bar icon. To uninstall, quit, then drag **Lock Clock** from Applications to the Trash. If it was set to open at login, also remove it in **System Settings → General → Login Items**.

Do not run a copy from Downloads long-term. Use `/Applications`.

## Requirements

- macOS Tahoe **26.6.2** (build 25G83) or a close Tahoe release
- Apple Silicon (verified on `arm64`)
- Xcode **26.6** (17F113) or the matching Swift toolchain
- Ability to turn off Apple’s large Lock Screen clock in **System Settings → Wallpaper / Lock Screen**

No Accessibility permission, Screen Recording permission, root, or SIP change is required.

## Xcode version

Developed and built with:

```text
Xcode 26.6 (17F113)
macOS 26.6.2 (25G83)
```

## macOS version

The SkyLight symbols and Space APIs used here were resolved and exercised on this exact system:

```text
ProductVersion: 26.6.2
BuildVersion:   25G83
Architecture:   arm64
```

## How to build

From the project root:

```bash
make build
```

or:

```bash
xcodebuild -scheme LockClock -configuration Release -derivedDataPath build
```

The app is written to:

```text
build.noindex/Build/Products/Release/LockClock.app
```

Or open `LockClock.xcodeproj` in Xcode and run the **LockClock** scheme.

The shared Debug scheme passes `--debug`, which opens the diagnostics window and skips automatic Launch at Login registration.

```bash
make diagnostics
```

opens that debug window and force-shows the clock on the desktop for styling. It does not install the app and does not register Launch at Login.

```bash
make settings
```

opens the Settings window.

## How to run

1. In **System Settings → Wallpaper**, disable Apple’s large Lock Screen clock.
2. Launch `LockClock.app`.
3. There is no Dock icon. A clock icon appears in the menu bar.
4. Open **Settings…** from that menu to change the clock, or uncheck **Show Lock Screen Clock** to disable it without quitting.
5. Lock with **Control-Command-Q**. The clock should appear in the upper center of each display.
6. Unlock. The clock should disappear immediately.

Development launch with diagnostics:

```bash
./build.noindex/Build/Products/Release/LockClock.app/Contents/MacOS/LockClock --debug
```

Force the clock onto the current desktop (positioning only; this is not the Lock Screen):

```bash
./build.noindex/Build/Products/Release/LockClock.app/Contents/MacOS/LockClock --debug --force-clock
```

Logs go to the unified log and `NSLog`. In Release builds they are off unless `--debug` is passed or `defaults write app.lockclock.LockClock debugLogging -bool true`.

```bash
log stream --predicate 'subsystem == "app.lockclock.LockClock"' --level info
```

## How to enable Launch at Login

On the first non-debug launch the app registers itself with `SMAppService.mainApp`.

You can also:

1. Run with `--debug` and click **Enable Launch at Login**.
2. Or from a shell:

```bash
osascript -e 'tell application "System Events" to get name of login item "LockClock"'
```

macOS 13+ also exposes the item under **System Settings → General → Login Items**.

Copy the app to `/Applications` before relying on login launch. A random build-folder path can be cleaned up by macOS later.

## How to disable Launch at Login

- Debug window: **Disable Launch at Login**
- System Settings → General → Login Items → remove **Lock Clock**
- Or `make uninstall`, which calls `SMAppService.mainApp.unregister()` for this app only

Do not use `sfltool resetbtm`. That resets every login item on the Mac.

## How to package a zip

```bash
make dist
```

Bumps the build number in `Version.xcconfig`, builds Release, and writes an unsigned zip to `dist/LockClock-1.0.0-N.zip`. The marketing version (`1.0.0`) is edited by hand in that file. Attach the zip to a GitHub Release.

## How to install from source

```bash
make install
```

copies the Release app to `/Applications/LockClock.app`. It refuses to overwrite a different app that happens to use that name. Override the destination with `PREFIX`:

```bash
make install PREFIX="$HOME/Applications"
```

## How to uninstall

```bash
make uninstall
```

That command only:

1. Quits this app’s process
2. Unregisters this app’s Launch at Login item
3. Deletes `/Applications/LockClock.app` after checking its bundle id is `app.lockclock.LockClock`
4. Deletes defaults for `app.lockclock.LockClock`

It does not use `sudo`, does not reset other login items, and will abort if the app at the destination is not Lock Clock.

Quitting destroys the private SkyLight Space this process created. Nothing is written into Apple’s Lock Screen implementation.

## Private API caveat

Lock Clock does **not** assume a normal `NSWindow` can sit above the Tahoe Lock Screen. Research on this 26.6.2 machine shows that AppKit / CoreGraphics window levels stay inside the current user Space. The Lock Screen is a separate Space whose absolute level is 300.

The app therefore uses these SkyLight symbols, loaded with `dlopen` / `dlsym` (never linked as a public SDK):

| Symbol | Role | Verified on 26.6.2 |
| --- | --- | --- |
| `SLSMainConnectionID` | WindowServer connection | Returns a non-zero cid |
| `SLSSpaceCreate` | Create an overlay Space | Returns a non-zero sid |
| `SLSSpaceSetAbsoluteLevel` | Place that Space at 400 | Level reads back as 400 |
| `SLSSpaceGetAbsoluteLevel` | Diagnostics | Returns 400 after set |
| `SLSShowSpaces` | Show the overlay Space when locked | Status 0 |
| `SLSHideSpaces` | Hide it when unlocked | Status 0 |
| `SLSSpaceAddWindowsAndRemoveFromSpaces` | Move the clock window onto that Space | Status 0 |
| `SLSSpaceDestroy` | Tear the Space down on quit | Status 0 |
| `SLSGetActiveSpace` | Diagnostics | Returns the current user Space |

400 is `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`, the same level [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) uses so UI can appear on the Lock Screen while staying below VoiceOver (600). The clock window is small, ignores mouse events, and cannot become key, so it should not cover or steal the password field.

`SLSSetWindowLevel` / `SLSGetWindowLevel` exist in the 26.6.2 SkyLight binary but were **not** used. Their argument lists were not live-tested, and window level alone is the wrong mechanism.

If SkyLight initialization fails, the app logs `[LockClock] SkyLight initialization failed` and falls back to `NSWindow.Level.screenSaver`. That fallback is **not** expected to appear on the Tahoe Lock Screen.

## Permissions

| Permission | Required? |
| --- | --- |
| Accessibility | No |
| Screen Recording | No |
| Full Disk Access | No |
| Root | No |
| Disable SIP | No |
| App Sandbox | Must stay off (private WindowServer calls) |

The clock never captures the screen, never installs an event tap, and never talks to `loginwindow` beyond listening for public distributed notifications.

## Research findings (macOS 26.6.2)

### 1. Can a normal AppKit window appear above the Tahoe Lock Screen?

**Not by window level alone.** The Lock Screen lives in its own WindowServer Space (`kCGSSpaceAbsoluteLevelScreenLock` = 300). `NSWindow.level` only orders windows inside the current Space.

### 2. Does `.screenSaver` work on Tahoe’s Lock Screen?

**Do not assume yes.** On this system:

```text
kCGScreenSaverWindowLevelKey → 1000
kCGMaximumWindowLevelKey     → 2147483631
kCGOverlayWindowLevelKey     → 102
```

Those values are real, but they do not move a window into the Lock Screen Space. A live lock-screen screenshot of an AppKit-only window was not taken from this session (locking the machine would interrupt it). The architecture therefore uses SkyLight Spaces, not `.screenSaver`.

### 3. Which SkyLight APIs are required?

The working path is Space-based, not `SLSSetWindowLevel`:

1. `SLSMainConnectionID()`
2. `SLSSpaceCreate(cid, 1, 0)`
3. `SLSSpaceSetAbsoluteLevel(cid, sid, 400)`
4. `SLSShowSpaces(cid, [sid])` when locked
5. `SLSSpaceAddWindowsAndRemoveFromSpaces(cid, sid, [windowNumber], 7)`
6. `SLSHideSpaces` on unlock, `SLSSpaceDestroy` on quit

This is a local subset of SkyLightWindow. The full package is unnecessary.

### 4. How can lock/unlock be detected reliably?

Combination used:

- **Events:** `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`
- **Truth on wake / display change:** `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`
- **Console ownership:** `kCGSSessionOnConsoleKey`

`NSWorkspace.sessionDidResignActiveNotification` is **not** treated as lock. It is Fast User Switch / losing the console.

### 5. Command-Control-Q

Expected: `com.apple.screenIsLocked`, then `CGSSessionScreenIsLocked == true`. `sessionDidResignActive` is not expected.

### 6. Automatic lock

Expected: the same `com.apple.screenIsLocked` notification once the configured idle timer and “require password” policy lock the session.

### 7. Sleep / wake

Expected:

- `NSWorkspace.willSleepNotification`, often preceded by `com.apple.screenIsLocked` if a password is required
- `NSWorkspace.didWakeNotification`
- Re-query `CGSessionCopyCurrentDictionary` on wake, because an unlock during sleep can be missed

Display sleep (`screensDidSleep`) is not treated as lock by itself.

### 8. How SkyLightWindow positions system UI

It creates one overlay Space, sets its absolute level to 400, shows that Space, and moves the `NSWindow` onto it with `SLSSpaceAddWindowsAndRemoveFromSpaces`. It also sets `canBecomeVisibleWithoutLogin = true` and a very high `NSWindow.level`. Lock Clock copies that Space mechanism, but keeps `canBecomeKey` / `canBecomeMain` false and ignores mouse events.

### 9. Does the mechanism work on macOS 26.6.2?

**The SkyLight calls succeed on this machine.** Live results from 26.6.2 / 25G83 / Apple Silicon:

```text
SLSMainConnectionID                         → 646699
SLSSpaceCreate                              → space id 25/26
SLSSpaceSetAbsoluteLevel(..., 400)          → 0, level now 400
SLSShowSpaces / SLSHideSpaces / Destroy     → 0
SLSSpaceAddWindowsAndRemoveFromSpaces       → 0 (windowNumber 312)
CGSessionCopyCurrentDictionary              → present, unlocked
NSScreen                                    → Built-in Retina + DELL P2419H
```

A live `--debug --force-clock` launch on this 26.6.2 machine then created and promoted one clock window per display:

```text
[LockClock] SkyLight ready cid=925859 space=27 level=400
[LockClock] Creating window for display: Built-in Retina Display
[LockClock] SkyLight promotion successful
[LockClock] Creating window for display: DELL P2419H
[LockClock] SkyLight promotion successful
```

Those windows live on the level-400 overlay Space, so `CGWindowListCopyWindowInfo` does not list them. A Control-Command-Q confirmation is still required to judge Lock Screen placement. This session did not lock the machine.

### 10–14. Permissions and platform

- Accessibility: **no**
- Screen Recording: **no**
- Disable SIP: **no**
- Root: **no**
- Apple Silicon: **yes** (this is the verified platform)

## Test checklist

### Test 1 — Normal launch

Launch while unlocked. Expected: no visible clock.

### Test 2 — Manual lock

Control-Command-Q. Expected: Apple clock hidden, Lock Clock visible, unlock UI still usable.

### Test 3 — Unlock

Unlock. Expected: clock gone, desktop normal.

### Test 4 — Repeated lock/unlock

At least 10 cycles. Expected: one window per display, no leaks, no crashes.

### Test 5 — Sleep/wake

Lock, sleep, wake. Expected: clock still there while locked; gone after unlock.

### Test 6 — Automatic lock

Wait for the idle lock. Expected: clock appears.

### Test 7 — External monitor

This development machine already has a built-in Retina display and a DELL P2419H. Lock and check both.

### Test 8 — Display disconnect

Unplug a display while unlocked. Expected: no leftover windows.

### Test 9 — Restart

After login the app should already be running if Launch at Login is enabled. Lock → clock appears.

### Test 10 — Quit

Quit while unlocked. Expected: overlay Space destroyed, no system file changes. Login item remains only if you left it enabled.

## Known Tahoe 26.6.2 limitations

- Private SkyLight Space APIs can change in a future macOS update.
- The clock cannot be App Store distributed.
- Visual lock-screen placement still needs a live lock to fine-tune `verticalFraction` (default 0.19 from the top).
- Fast User Switch hides the clock; it is not shown on another user’s session.
- If SkyLight fails to load, the AppKit fallback will not appear on the Lock Screen.
- The app must keep running. It does not inject anything into `loginwindow`, so quitting removes the clock.
- Do not make the clock window fullscreen. A small text window is required so the password field stays reachable.

## Appearance

Defaults are a system-font clock, regular weight, 125 pt, `#ffffff` at 70% opacity, centered, 19% down from the top of each screen. Change them from the menu bar clock icon → **Settings…**, or with `defaults`:

```bash
defaults write app.lockclock.LockClock clock.fontFamily -string system
defaults write app.lockclock.LockClock clock.fontWeight -string regular
defaults write app.lockclock.LockClock clock.fontSize -float 125
defaults write app.lockclock.LockClock clock.opacity -float 0.70
defaults write app.lockclock.LockClock clock.horizontalFraction -float 0.50
defaults write app.lockclock.LockClock clock.verticalFraction -float 0.19
defaults write app.lockclock.LockClock clock.showSeconds -bool false
```

Supported families: `system`, `helveticaNeue`, `sfPro`, `sfCompact`.  
Supported weights: `thin`, `light`, `regular`, `medium`, `semibold`, `bold`.

There is no glass, blur, or translucency material. The text is a normal SwiftUI `Text` inside a clear, click-through `NSWindow`.

## License

This project is released under the [MIT License](LICENSE).

Copyright © 2026 [Christos S. Paschalidis](https://github.com/christos-pas)  
[christos.paschalidis.dev@gmail.com](mailto:christos.paschalidis.dev@gmail.com)
