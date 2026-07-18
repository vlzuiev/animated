# Animated — Free Animated Wallpapers for macOS (Desktop + Lock Screen)

[![Latest release](https://img.shields.io/github/v/release/vlzuiev/animated)](https://github.com/vlzuiev/animated/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue)](#requirements)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**Turn any video into a live animated wallpaper on your Mac — including the real lock screen.** Free, open source, native Swift, no account, no tracking.

## Download

**[⬇ Download the latest release](https://github.com/vlzuiev/animated/releases/latest)** — unzip, move `Animated.app` to Applications, open.

On first launch macOS blocks the app (it's a free open-source project, not notarized by Apple): go to **System Settings → Privacy & Security**, scroll down, click **"Open Anyway"** and confirm — needed exactly once. Then click the ✦ star in the menu bar, **Choose Video…**, and enjoy. Prefer compiling yourself? See [Build from source](#build-from-source).

Animated is a lightweight menu bar app for **macOS 26 (Tahoe)** that plays a muted, looping video **behind your desktop icons** and installs the same video as your **lock screen live wallpaper** — something macOS normally reserves for Apple's own aerial videos.

> Works with any MP4 or MOV you own. 4K supported, hardware-decoded, a few percent CPU.

## Features

- 🎬 **Any video as wallpaper** — MP4, MOV, H.264 or HEVC; no conversion tools needed
- 🔒 **Animated lock screen** — the genuine macOS lock screen plays your video (macOS 26+)
- ⚡ **Instant apply** — desktop switches immediately; lock screen follows in seconds (no re-encoding thanks to passthrough remux)
- 🖥 **Multi-display** — every connected screen gets the wallpaper
- 🔋 **Lightweight** — native Swift + AVFoundation, hardware video decode, ~5% CPU for 4K
- 📊 **Transparent** — live CPU / memory / disk stats right in the menu
- 🍎 **Reversible** — one click restores Apple's original wallpaper, byte-for-byte
- 🚀 **Start at login**, pause/resume, zero telemetry, no account

## How is this possible?

macOS doesn't offer an API for custom animated wallpapers. Animated combines two techniques:

1. **Desktop**: a borderless window one layer below the desktop icons plays your video with `AVPlayerLooper` — the classic live-wallpaper approach used by every wallpaper app.
2. **Lock screen**: on macOS 26 Apple stores its animated "aerial" wallpapers in your own home folder. Animated converts your video into aerial format (tiled to ~3 minutes, audio stripped, `.mov`) and swaps it into a downloaded aerial's slot — macOS then plays *your* video on the real lock screen, thinking it's its own. A backup of Apple's original is kept for clean restore.

Everything happens inside your user account — no admin rights, no system files outside `~`, no SIP changes.

## Requirements

- macOS 26 (Tahoe) or later
- One Apple aerial wallpaper downloaded once via System Settings → Wallpaper (the "slot" we borrow)
- To build: Xcode 16+, [Homebrew](https://brew.sh), XcodeGen (`brew install xcodegen`)

## Build from source

```sh
git clone https://github.com/vlzuiev/animated.git
cd animated
xcodegen generate
xcodebuild -project Animated.xcodeproj -scheme Animated -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Animated.app
```

A ✦ star icon appears in the menu bar. Click **Choose Video…**, pick a video — desktop animates instantly, lock screen a few seconds later ("Preparing lock screen…" shows progress). Enable **Start at Login** for the full experience.

## FAQ

### Can you set a video as wallpaper on macOS?
Yes — this app plays any MP4/MOV as a looping desktop wallpaper on macOS, for free.

### Can the Mac lock screen have an animated wallpaper?
Natively only Apple's built-in aerials animate on the lock screen. Animated makes the lock screen play *your* video on macOS 26 by swapping it into the aerial store in your home folder.

### Does it work on macOS Sonoma or Sequoia?
The desktop wallpaper works on any recent macOS. The lock screen technique targets macOS 26 (Tahoe), where the aerial store moved into the user's home folder.

### Is it safe? Can I undo it?
Everything stays inside your user folder, and Apple's original video is backed up before the first swap. **Use Apple Background** in the menu restores everything exactly.

### Why isn't this on the App Store?
The lock screen trick requires an unsandboxed app writing to the wallpaper store — impossible under App Store rules. That's why commercial apps with this feature are paid direct downloads.

### Does a macOS update break it?
An update may restore Apple's aerial video. Your desktop keeps working; just re-pick your video to reinstall the lock screen.

### GIF or WebM wallpapers?
Convert them to MP4 first (any converter works). The app accepts what macOS plays natively: MP4, MOV, M4V.

## Known limitations

- The pre-login screen after a cold boot (FileVault) stays static — that screen exists before your session.
- Right after switching videos, the first lock may show the previous frame for a second (system snapshot cache, self-heals).
- Lock screen slot files can be large (the video is tiled to ~3 minutes at source bitrate).

## Credits & prior art

- [Wallpaper-Sync](https://github.com/GonzaloRojas14/Wallpaper-Sync) — proved the aerial-swap technique on Tahoe; studying its scripts saved this project days of reverse engineering.
- [Aerial](https://github.com/AerialScreensaver/Aerial) — the pioneer of custom aerial content on macOS.
- Commercial apps in this space: Wallspace, Backdrop, Wallpaper Engine (Windows).

## License

MIT — see [LICENSE](LICENSE). Not affiliated with or endorsed by Apple. "Aerial" wallpaper videos are Apple's content; this app only manages files in your own user folder.
