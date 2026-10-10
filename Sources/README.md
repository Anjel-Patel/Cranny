# Cranny developer guide

Everything you need to build, change and release Cranny. The [main README](../README.md)
is for people using the app.

## Requirements

- macOS 14 or later.
- The Xcode Command Line Tools (`xcode-select --install`). Full Xcode works too but isn't
  needed.

The package targets macOS 14 and uses the Swift 5 language mode.

## Building

```sh
./build.sh               # build for this Mac: build/Cranny.app, Cranny.zip and Cranny.zip.sha256
./build.sh --universal   # Apple silicon + Intel, which is what releases use
./build.sh --install     # also install to /Applications and relaunch
```

`build.sh` compiles the app with SwiftPM, compiles the Now Playing helper with clang, draws
the icon (`Tools/make-icon.swift`), assembles and ad-hoc signs the bundle, then zips it.
macOS ties Calendar and Camera permission to the exact build, so expect to grant them again
after rebuilding.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/Cranny/App` | Entry point, app delegate, menus, `cranny://` and notification commands |
| `Sources/Cranny/Notch` | Notch window, layout model, pointer and gesture handling, notch views |
| `Sources/Cranny/Widgets` | Media, Calendar, Mirror and Shortcuts widgets |
| `Sources/Cranny/Tray` | Files tray storage, drag in and out, AirDrop |
| `Sources/Cranny/Clipboard` | Clipboard history, its tab, dragging items out |
| `Sources/Cranny/Services` | Now Playing, Calendar (EventKit), camera, Shortcuts, login item, updates |
| `Sources/Cranny/Settings` | Settings model, NotchNook import, Settings and Welcome windows |
| `Sources/Cranny/Support` | Logging, notch geometry, fullscreen detection, image helpers |
| `Helper/` | Now Playing helper library (`MediaHelper.m`) and its perl loader |
| `Resources/Info.plist` | Bundle metadata, version, permission prompts |
| `Tools/` | Icon generator and `notchctl` (sends commands to a running copy) |
| `install.sh` | The one-line installer from the main README, served straight from `main` |
| `.github/workflows/build.yml` | CI: universal build on macOS 14 and 15 for every push and PR |

## How it works

### The notch window

Each notched screen (or the main screen on Macs without a notch) gets a borderless,
non-activating panel above the menu bar. The panel ignores the mouse except inside the
notch's current outline, so menu bar items beside the notch stay clickable. Pointer
movement comes from global and local event monitors, plus a short polling timer while the
notch is hovered or open. All the drawing is SwiftUI.

When the notch appears it starts at the physical notch's exact size at full opacity and
grows from there. When it goes away it shrinks back first (`NotchModel.settle()`), so it
never shows as a translucent ghost.

### Now Playing

Since macOS 15.4, only Apple-signed processes can read the system's Now Playing
information. Cranny therefore loads a small helper library (`Helper/MediaHelper.m`) into
the system's own `/usr/bin/perl`. The helper streams playback state back as JSON lines,
accepts play/pause/skip/seek commands on stdin, and exits when Cranny quits. Thanks to
[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) for popularising
this approach.

With **Only show music** on, `NowPlaying.isShown` hides anything that isn't music, and the
live activity, Quick Peek, media widget and media swipes all follow it. `MediaSourceKind`
sorts the playing app: music apps are a list of bundle IDs plus anything whose Info.plist
declares the Music category. Browsers are the apps that open web links, and what they play
counts as music when it has an album, which songs have and videos don't.

### Fullscreen

`FullscreenDetector` asks the window server (SkyLight) whether a display's current Space is
a fullscreen Space. It also treats a window that covers the whole display while its app is
frontmost as fake fullscreen. Only windows of regular (Dock) apps count, so transparent
overlays from background utilities don't trigger it.

### Updates

`UpdateChecker` asks GitHub's releases API for the latest release 20 seconds after every
launch, then once a day while Cranny runs. A failed check is retried within the hour. To install,
it downloads `Cranny.zip` and `Cranny.zip.sha256` from that release, checks the hash,
unpacks the app with `ditto`, and hands over to a small script. The script waits for
Cranny to quit, swaps the bundle (restoring the old one if anything fails) and reopens it.

To try it, give a build an older version number and ask it to check:

```sh
plutil -replace CFBundleShortVersionString -string 1.0.0 build/Cranny.app/Contents/Info.plist
codesign --force --sign - --identifier io.github.rdbms234.Cranny build/Cranny.app
open build/Cranny.app && sleep 2 && build/notchctl update
```

Quit any other copy of Cranny first, since two copies fight over the notch. Opening Settings
in a test copy also moves **Launch at login** to that copy, so switch it off and on again in
your installed copy afterwards.

### Clipboard

`ClipboardStore` reads the clipboard's change count twice a second, which is cheap and never
triggers a privacy prompt, and only reads the clipboard itself after it changed. Each copy
keeps every format the app offered, so copying it back keeps its formatting. Copies marked
private or temporary ([nspasteboard.org](http://nspasteboard.org) types, used by password
managers) are skipped. Nothing is written to disk.

macOS has a "Paste from Other Apps" privacy setting (`NSPasteboard.accessBehavior`) that
macOS 27 doesn't enforce yet. If it does one day, Cranny reads on the first copy, which shows
macOS's one-time prompt and lists Cranny in Privacy & Security, then shows a card asking the
user to set it to Allow. To see that card:

```sh
defaults write io.github.rdbms234.Cranny debugClipboardAccess ask   # or deny
defaults delete io.github.rdbms234.Cranny debugClipboardAccess
```

### Camera

A capture session can't be changed from two threads at once, so `CameraEngine` does all
setup, starting and stopping on one serial queue, and the Mirror shares a single preview
layer that's attached once. Clicks only record whether the camera should run, and the queue
catches up with the latest wish. Rebuilding this per click is what used to crash Cranny.

### `@State` and the Command Line Tools

In the macOS 27 SDK, SwiftUI's `@State` is a compiler macro whose plugin only ships with
full Xcode. The project therefore uses `@ViewState`, an alias for the underlying property
wrapper (`Support/Log.swift`), so it builds with just the Command Line Tools.

## Testing on other Macs

Cranny can pretend the main screen has a different notch, or none at all, so you can check
layouts for other MacBooks. Relaunch after changing it:

```sh
defaults write io.github.rdbms234.Cranny debugNotchSize 200x38   # width x height in points
defaults write io.github.rdbms234.Cranny debugNotchSize none     # a Mac without a notch
defaults delete io.github.rdbms234.Cranny debugNotchSize         # back to normal
```

## Automation and debugging

URL commands (also handy from Shortcuts or Raycast):

```sh
open -g "cranny://open"              # open the nook; it stays open until you hover it
open -g "cranny://open?tab=tray"
open -g "cranny://toggle"
open -g "cranny://close"
open -g "cranny://update"            # check for updates now
open "cranny://settings?pane=nook"   # general, nook, live, calendar, shortcuts, about
```

`Tools/notchctl.swift` sends the same commands without going through LaunchServices,
plus a few extras for testing:

```sh
swiftc -O Tools/notchctl.swift -o build/notchctl
build/notchctl hover 5        # pretend the pointer rests on the notch for 5 seconds
build/notchctl media toggle   # or: next, previous
```

Logs:

```sh
log stream --style compact --predicate 'subsystem == "io.github.rdbms234.Cranny"'
```

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Open a pull request and merge it once CI passes.
3. Build from `main`: `./build.sh --universal`.
4. Publish both assets. The installer and the in-app updater look for exactly these names
   on the latest release. The notes appear in Settings → About, so keep them short.

   ```sh
   gh release create vX.Y.Z build/Cranny.zip build/Cranny.zip.sha256 \
     --title "Cranny X.Y.Z" --notes-file notes.md
   ```

## Distribution and signing

Releases are signed ad hoc and aren't notarized. A copy downloaded in a browser is
therefore quarantined, and macOS asks the user to approve it once (System Settings →
Privacy & Security → Open Anyway, or `xattr -dr com.apple.quarantine`). The installer
script and the in-app updater avoid that step, because files fetched with `curl` or
`URLSession` aren't quarantined.

Notarizing would remove the prompt for every download method and keep permissions across
updates. It needs:

- an Apple Developer ID ($99/year);
- the hardened runtime, with camera and calendar entitlements;
- `notarytool` and `stapler`, which ship with the Command Line Tools.

Since Homebrew 5, the official cask repository only accepts apps that pass Gatekeeper, so
a Homebrew cask would have to live in a personal tap until then.

## Contributing

Issues and pull requests are welcome. Keep changes focused, match the surrounding style,
and make sure CI passes.
