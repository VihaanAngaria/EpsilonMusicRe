# Epsilon Music — iOS

A native SwiftUI app that brings Epsilon Music to iOS with the same branding as
the Android app: the music-note logo, near-black surfaces, and the signature
red accent (#ED5564).

## What's included

- **Home** — greeting header with logo, Shuffle All / Play All tiles, your song list
- **Library** — Songs and Artists sections with search
- **Player** — full-screen player with artwork, scrub bar, queue ("Up Next"),
  and a mini player bar above the tab bar
- **Playback** — AVAudioPlayer-based queue player with lock screen /
  Control Center controls (play, pause, next, previous, seek) and background
  audio (`UIBackgroundModes: audio`)
- **Music sources** — the device music library via MediaPlayer/MPMediaQuery
  (non-DRM tracks with a local asset URL), with three bundled demo tracks as
  fallback so the app is playable out of the box (e.g. on the simulator)

## Requirements

- macOS with Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
  (only needed once — the `.xcodeproj` is generated, not committed)

## Build & run

```bash
cd ios
xcodegen generate
open EpsilonMusicRe.xcodeproj
```

Then choose a simulator and press Cmd+R.

**To run on a physical device:** open the generated project in Xcode, select the
EpsilonMusicRe target → Signing & Capabilities, and set your own team. The
bundle identifier is `app.epsilonmusic.epsreios` — change it if it conflicts
with your team. Music library access requires the "Media & Apple Music"
permission prompt at first run (already declared via
`NSAppleMusicUsageDescription`).

## Notes & scope

- DRM-protected Apple Music catalog songs cannot be played by third-party apps;
  the library loader skips them (tracks synced from a computer work fine).
- The Android app's streaming features (YouTube Music, downloads, lyrics,
  cast, Listen Together) are not part of this iOS client yet — the project is
  structured (Core = store/player, UI = screens) so they can be added
  incrementally.
- CI: `.github/workflows/ios-build.yml` builds the app for the iOS Simulator
  on a macOS runner (unsigned) on every change to `ios/`.

## Project layout

```
ios/
  project.yml                     XcodeGen project spec
  EpsilonMusicRe/
    App/                          App entry + root tab/mini-player structure
    Core/                         Theme, Song model, library store, player manager
    UI/                           Home, Library, Player, shared components
    Resources/
      Assets.xcassets             App icon (logo on black), accent color, logo
      demo-*.wav                  Bundled demo tracks
```
