# Epsilon Music — iOS

A native SwiftUI app that mirrors the Android app — same design language, same
music-note logo, near-black surfaces, the signature red accent (#ED5564) — and
**every Android feature**: YouTube Music streaming, account sync, downloads,
synced lyrics from 8 providers with romanization and AI translation, a 10-band
equalizer, crossfade, Listen Together, music recognition, Discord presence,
scrobbling, Spotify import and more.

## What's included

- **Home** — app title bar with logo + account avatar + recognition + settings,
  Quick picks from your history, YouTube Music home shelves, Explore / Charts /
  Moods & genres / New releases shortcuts, offline fallback to on-device songs
  and bundled demo tracks, welcome dialog
- **Search** — YouTube Music search with live suggestions, recent searches
  (persisted) and filter chips (Songs / Videos / Artists / Albums / Community
  playlists / Featured playlists), numbered song results, load-more pagination
- **Library** — the Android chip row (Playlists / Songs / Albums / Artists /
  Local) with the library mix grid (Liked songs, My top tracks, Downloaded,
  Stats, Offline, On this device), synced YouTube Music library sections
  (saved playlists / albums / artists) when signed in, local playlists with
  create/rename/reorder/remove, and the Android-style Create playlist +
  Import playlist FABs
- **Player** — full-screen player with swipeable pages (Up next • Artwork •
  Related), like button, download button with state, comments, seek slider
  (plain or wavy), double-tap seek gestures, shuffle / previous / play / next /
  repeat, volume slider, codec/quality chip, sleep timer (5–120 min or end of
  track, with fade-out), add-to-playlist, start radio, queue sheet with
  reorder + shuffle/repeat/radio pills + similar content, share, media
  details (with Return YouTube Dislike estimates), background styles
  (default / gradient / blurred artwork / glow), canvas animated artwork
  (Apple Music motion / Epsilon community manifest) and the rotating
  clover-vinyl artwork mode
- **Playback** — AVPlayer streaming engine with the Android app's stream
  client fallback order (ANDROID_VR 1.65.10 → ANDROID_VR 1.43.32 → IOS),
  queue with shuffle/repeat, autoplay radio when the queue ends, error
  re-resolve + skip, persistent queue restore, lock screen / Control Center
  controls (play, pause, next, previous, seek) and background audio
  (`UIBackgroundModes: audio`), equal-power **crossfade** (1–15 s), audio
  normalization from stream loudness data, and 15-second silence hopping
- **Equalizer** — the Android Axion EQ: 10-band biquad peaking EQ (31 Hz–16 kHz,
  Q 1.41, ±12 dB), Simple (Bass/Mids/Treble circular control with the triangle
  band mapping) and Advanced (10 vertical sliders + preamp) modes, all 17
  presets (Epsilon Signature ×11, Dolby Atmos ×3, Dirac Audio ×3) plus custom
  presets — applied to AVPlayer audio in real time through the public
  `MTAudioProcessingTap` API
- **Account** — Google sign-in in an in-app WebView (accounts.google.com →
  music.youtube.com cookie capture) with SAPISIDHASH authorization on every
  InnerTube request, `onBehalfOfUser` data-sync, account profile (name /
  email / handle / avatar), advanced 6-line token login, YouTube watch-history
  registration, liked songs, saved playlists, liked albums and artist
  subscriptions sync
- **Lyrics** — the full provider chain in configurable order: YouLyPlus,
  Paxsenix, Unison, BetterLyrics (TTML with word timings), SimpMusic, LRCLIB,
  KuGou, YouTube transcripts and YouTube Music lyrics — with local
  **romanization** (Korean Hangul, Japanese kana with digraphs and sokuun,
  Cyrillic, Devanagari, Gurmukhi), tap-to-seek synced auto-scroll, and **AI
  translation** (OpenRouter / Mistral / any OpenAI-compatible endpoint / DeepL,
  literal / romanized / transcribed modes, auto-translate)
- **Downloads** — tap the download button to store the stream offline
  (Documents/Downloads), play offline automatically, "Downloaded" library
  section with sorting, storage stats and clear-all, auto-download on like
- **Music recognition** — the Android app's Shazam-style engine: 10 s mic
  recording, 16 kHz resampling, the full DejaVu FFT fingerprint generator
  (2048-point FFT, band peaks, binary signature with CRC32) and the
  amp.shazam.com discovery API — with cover art, genre, ISRC, Apple Music /
  Spotify links, play-on-YouTube-Music matching and persistent recognition
  history
- **Listen Together** — the full WebSocket protocol: create/join rooms with
  host approval, host transfer, kick, in-sync playback controls, buffer-ready
  handshake, clock-synced positions, chat, track suggestions with
  approve/reject, participant-control toggle, ping keep-alive and the public
  server list (app/server.json)
- **Discord Rich Presence** — user-token Gateway WebSocket v9 (IDENTIFY,
  heartbeats, READY) with the Android app's Listening activity payload,
  elapsed/remaining timestamps, external-asset registration, show-when-paused
  and its own Discord login flow (localStorage token capture)
- **Spotify import** — sp_dc WebView sign-in, TOTP-signed web-player token,
  api-partner GraphQL persisted queries (libraryV3, fetchPlaylist,
  fetchLibraryTracks), liked-songs and playlist import with the Android app's
  weighted title/artist/duration matching to YouTube Music, plus paste-a-link
  import
- **Scrobbling** — ListenBrainz (user token, playing-now + single listens)
  and Last.fm (mobile-session auth, scrobble threshold percent, now-playing
  and love/unlove)
- **Stats & history** — period chips (1 week → all time), most-played songs /
  artists / albums with listen time, shuffle FAB, activity history sheet
  (total time, plays, unique songs/artists), local history with date buckets
  and YouTube Music remote history when signed in
- **AI extras** — create-playlist-from-prompt, modify-playlist-with-AI
  instructions and recommendations from listening history
- **Backup & restore** — export/import everything (settings, liked songs,
  history, playlists, downloads, recognition history) as one JSON file, plus
  CSV / M3U playlist import with YouTube Music matching
- **Theming** — system/light/dark, pure black mode, dynamic accent extracted
  from the current artwork, and the Android accent color palette

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
`NSAppleMusicUsageDescription`); recognition requires the microphone prompt
(`NSMicrophoneUsageDescription`).

## Notes & scope

- Stream URLs come from the same InnerTube `player` endpoint the Android app
  uses; the ANDROID_VR clients return whole-file progressive AAC streams that
  AVPlayer plays directly. Rare tracks may resolve only a short preview via
  the IOS client — the Android client has the same tail-end behavior.
- DRM-protected Apple Music catalog songs cannot be played by third-party
  apps; the on-device loader skips them (tracks synced from a computer work
  fine).
- **Ringtones**: iOS does not allow third-party apps to set system ringtones —
  that Android feature has no equivalent (Apple's GarageBand workflow is the
  only path).
- **Home-screen widgets**: iOS apps surface now-playing controls through the
  lock screen and Control Center (implemented) rather than app widgets;
  a WidgetKit extension is a possible future addition.
- Equalizer, normalization and silence skipping run through
  `MTAudioProcessingTap` (a public MediaToolbox API) attached to the player's
  audio mix.
- CI: `.github/workflows/ios-build.yml` builds the app for the iOS Simulator
  on a macOS runner (unsigned) on every change to `ios/`.

## Project layout

```
ios/
  project.yml                     XcodeGen project spec
  EpsilonMusicRe/
    App/                          App entry, root tabs + routes
    Core/
      InnerTube.swift             Swift port of the innertube module
      InnerTubeExtended.swift     Comments, charts, library sync, playlist
                                  CRUD, transcript, likes, media info
      Account.swift               YouTube sign-in + SAPISIDHASH auth
      PlayerManager.swift         AVPlayer queue + crossfade + persistence
      Equalizer.swift             Biquad DSP + MTAudioProcessingTap engine
      DownloadManager.swift       Offline downloads + caches
      LyricsProviders.swift       All 8 lyrics providers + priority chain
      Romanization.swift          Local Korean/Japanese/Cyrillic/… engine
      AIClient.swift              OpenAI-compatible translation + AI playlists
      Recognition.swift           Mic recorder + DejaVu fingerprint + Shazam
      ListenTogether.swift        Listen Together WebSocket client
      Scrobbler.swift             ListenBrainz + Last.fm
      DiscordPresence.swift       Discord Gateway RPC
      SpotifyImport.swift         sp_dc + TOTP + GraphQL + YT matching
      Updater.swift               GitHub releases + backup + canvas providers
      LibraryStore.swift          Liked/history/playlists/stats/downloads
      AppSettings.swift           Preferences + theming
      Models.swift / JSONHelper.swift
    UI/                           All screens and components
    Resources/
      Assets.xcassets             App icon (logo on black), accent color, logo
      demo-*.wav                  Bundled demo tracks
```
