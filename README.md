<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Cranny app icon">
</p>

<h1 align="center">Cranny</h1>

<p align="center">
  Your MacBook's notch, made useful.<br>
  Media controls, a files tray with AirDrop, your calendar, a camera mirror, Shortcuts and live activities.
</p>

<p align="center">
  <a href="https://github.com/Anjel-Patel/Cranny/releases/latest"><img src="https://img.shields.io/github/v/release/Anjel-Patel/Cranny?label=version&color=6c5ce7" alt="Latest version"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/price-free-2ea44f" alt="Free">
</p>

<p align="center">
  <a href="#install"><b>Install</b></a> ·
  <a href="https://github.com/Anjel-Patel/Cranny/releases/latest">Download</a> ·
  <a href="Sources/README.md">For developers</a>
</p>

![The open notch with media player, Shortcuts and Mirror widgets](docs/nook.png)

If you used NotchNook, Cranny will feel familiar: a "nook" of widgets, a files tray
with AirDrop, and live activities around the notch. It even picks up your NotchNook
settings on first launch. Cranny is an independent project and isn't affiliated with
lo.cafe or NotchNook.

## Features

### The notch

- Hover to wake the notch, then click it (or swipe down on the trackpad) to open it, or
  have it open on hover.
- Haptic feedback, an optional translucent background, notch width fine-tuning, and a
  demo mode for screen recordings.
- Works on Macs without a notch too: a small handle at the top of the screen does the
  same job. External displays can have one as well.

### Nook widgets

Arrange widgets on a grid, then reorder and resize them.

- **Media player**: works with anything that shows up in Control Center's Now Playing,
  such as Spotify, Apple Music, YouTube in your browser, IINA and VLC. You get artwork,
  a scrubbable progress bar and playback controls. Click the artwork to jump to the
  app that's playing.
- **Calendar**: the day's events, with one-click Join buttons for Zoom, Meet, Teams and
  more. Swipe left or right to change days.
- **Mirror**: a quick look at your front camera before a call. The camera only runs
  while the mirror is on.
- **Shortcuts**: run your macOS Shortcuts from the notch.

### Files tray

![The files tray holding three files next to an AirDrop drop zone](docs/tray.png)

- Drag files onto the notch and drop them in the tray to keep them handy while you
  switch apps or spaces. Drag them back out to move them where you need them.
- Drop files on **AirDrop** to share them.
- Images, links and text dropped on the tray are saved as files.

### Live activities

| While music plays | Quick Peek on hover |
| --- | --- |
| ![Album art and an audio visualizer beside the notch](docs/live-activity.png) | ![The song title and artist shown under the notch](docs/quick-peek.png) |

- Album art plus an audio visualizer tinted with the album's colours, a countdown to
  your next meeting, or the number of files in the tray.
- Hover for a Quick Peek. Click to play/pause or join a meeting.
- Fullscreen video stays distraction-free: live activities step aside while you watch.
  You can also hide them in every fullscreen app, or always show them.
- Two-finger swipes over the notch: down or up to open or close it, left or right to
  change tracks.

## Install

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/Anjel-Patel/Cranny/main/install.sh | bash
```

It installs the latest version into your Applications folder and opens it
([see what it does](install.sh)).

<details>
<summary>Prefer to download it yourself?</summary>

1. Download **Cranny.zip** from the [latest release](https://github.com/Anjel-Patel/Cranny/releases/latest),
   unzip it and move **Cranny** to your Applications folder.
2. Open Cranny. If macOS says it can't be opened, go to **System Settings → Privacy &
   Security** and click **Open Anyway**.

</details>

Cranny runs on macOS 14 Sonoma or later, on Apple silicon and Intel Macs.

## Getting started

- Hover over the notch, then click it (or swipe down on the trackpad) to open the nook.
- Drag a file onto the notch to keep it in the tray.
- For settings, click the gear in the open notch or right-click the notch.

## Updates

Cranny lets you know when a new version is out: a small notice appears beside the notch,
and **Settings → About** installs it with one click. After an update, macOS may ask again
for Calendar or Camera access.

## Privacy

- Calendar and camera access are optional, and only used by the Calendar and Mirror
  widgets.
- Everything stays on your Mac. The only thing Cranny looks up online is whether a new
  version is available, which you can turn off in Settings → About.

## Uninstall

Turn off **Launch at login** in Settings, quit Cranny (right-click the notch → Quit
Cranny) and move it from Applications to the Trash. To remove its data as well, delete
`~/Library/Application Support/Cranny`.

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/Anjel-Patel/Cranny/issues).
Want to contribute? Start with the [developer guide](Sources/README.md).

## Credits

Made with the help of Claude.

## License

[MIT](LICENSE)
