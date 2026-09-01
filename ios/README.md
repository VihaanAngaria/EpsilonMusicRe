# Epsilon Music — iOS

A native SwiftUI app that mirrors the Android app's design and core
experience: the music-note logo, near-black surfaces, the signature red accent
(#ED5564) — and the same features: YouTube Music streaming, search, home feed,
playlists, queue, radio, synced lyrics and dynamic theming.

## What's included

- **Home** — app title bar with logo + settings, Quick picks from your
  history, YouTube Music home shelves, Explore and Moods & genres shortcuts;
  offline fallback to on-device songs and bundled demo tracks
- **Search** — YouTube Music search with live suggestions, recent searches and
  filter chips (Songs / Videos / Artists / Albums / Community playlists /
  Featured playlists), numbered song results, load-more pagination
- **Library** — the Android chip row (Playlists / Songs / Albums / Artists /
  Local) with the library mix grid (Liked songs, My top tracks, Offline,
  On this device), local playlists with create/rename/reorder/remove, and the
  Android-style Create playlist + Import playlist FABs
- **Player** — full-screen player with swipeable pages (Up next • Artwork •
  Related), like button, seek slider, shuffle / previous / play / next /
  repeat, synced lyrics (LRCLIB) with auto-scroll and tap-to-seek, sleep
  timer, add-to-playlist, start radio, share, open in YouTube Music
- **Playback** — AVPlayer streaming engine with the Android app's stream
  client fallback order (ANDROID_VR 1.65.10 → ANDROID_VR 1.43.32 → IOS),
  queue with shuffle/repeat, autoplay radio when the queue ends, error
  re-resolve + skip, lock screen / Control Center controls (play, pause,
  next, previous, seek) and background audio (`UIBackgroundModes: audio`)
- **Data layer** — a Swift port of the `innertube` module: search, search
  suggestions, `player` stream resolution, `next`/radio, `music/get_queue`,
  browse (home, playlist, album, artist, explore, moods & genres) with
  dynamic JSON navigation
- **Music sources** — YouTube Music streaming plus the device music library
  via MediaPlayer/MPMediaQuery (non-DRM tracks) and three bundled demo tracks
  so the app is playable out of the box (e.g. on the simulator)
- **Theming** — system/light/dark, pure black mode, MaterialKolor-style
  dynamic accent extracted from the current artwork, and the Android accent
  color palette (Settings → Appearance)

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

- Stream URLs come from the same InnerTube `player` endpoint the Android app
  uses; the ANDROID_VR clients return whole-file progressive AAC streams that
  AVPlayer plays directly. Rare tracks may resolve only a short preview via
  the IOS client — the Android client has the same tail-end behavior.
- DRM-protected Apple Music catalog songs cannot be played by third-party
  apps; the on-device loader skips them (tracks synced from a computer work
  fine).
- Account sign-in, downloads, equalizer, music recognition (Shazam Kit),
  Discord/Spotify/Last.fm integrations and Listen-Together hosting remain
  Android-only for now; the iOS code is structured (Core = client/store/
  player, UI = screens) so they can be added incrementally.
- CI: `.github/workflows/ios-build.yml` builds the app for the iOS Simulator
  on a macOS runner (unsigned) on every change to `ios/`.

## Project layout

```
ios/
  project.yml                     XcodeGen project spec
  EpsilonMusicRe/
    App/                          App entry, root tabs + mini player + routes
    Core/
      InnerTube.swift             Swift port of the innertube module
      PlayerManager.swift         AVPlayer streaming queue + remote commands
      LibraryStore.swift          Liked/history/playlists/stats persistence
      Lyrics.swift                LRCLIB synced lyrics + LRC parser
      AppSettings.swift           Preferences, theme palette, accent extraction
      Models.swift / JSONHelper.swift
    UI/                           Home, Search, Library, player, settings screens
    Resources/
      Assets.xcassets             App icon (logo on black), accent color, logo
      demo-*.wav                  Bundled demo tracks
```
