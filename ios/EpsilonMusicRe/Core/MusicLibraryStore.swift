import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Loads the device music library (MusicKit/MPMediaQuery) and falls back to the
/// bundled demo tracks when the library is empty or access is denied.
@MainActor
final class MusicLibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isLoading = false
    @Published private(set) var libraryAccessDenied = false

    private let demoSongs: [Song]

    init() {
        demoSongs = Self.loadDemoSongs()
        songs = demoSongs
        refresh()
    }

    var isUsingDemoTracks: Bool {
        songs.first?.isDemo ?? false
    }

    func refresh() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            loadDeviceLibrary()
        case .notDetermined:
            isLoading = true
            MPMediaLibrary.requestAuthorization { [weak self] _ in
                Task { @MainActor in
                    self?.isLoading = false
                    self?.refresh()
                }
            }
        default:
            libraryAccessDenied = true
            songs = demoSongs
        }
    }

    private func loadDeviceLibrary() {
        isLoading = true
        defer { isLoading = false }

        let query = MPMediaQuery.songs()
        var result: [Song] = []
        for item in (query.items ?? []) {
            // DRM-protected catalog items have no local asset URL — skip them.
            guard let url = item.assetURL else { continue }
            let artwork = item.artwork?.image(at: CGSize(width: 512, height: 512))
            result.append(
                Song(
                    id: "media-\(item.persistentID)",
                    title: item.title ?? "Unknown Title",
                    artist: item.artist ?? "Unknown Artist",
                    album: item.albumTitle,
                    duration: item.playbackDuration,
                    url: url,
                    artwork: artwork,
                    isDemo: false
                )
            )
        }
        result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        songs = result.isEmpty ? demoSongs : result
        libraryAccessDenied = false
    }

    private static let demoMetadata: [String: (title: String, artist: String)] = [
        "demo-aurora": ("Aurora Drive", "Epsilon Demo"),
        "demo-midnight": ("Midnight Tape", "Epsilon Demo"),
        "demo-sundown": ("Sundown Loop", "Epsilon Demo")
    ]

    private static func loadDemoSongs() -> [Song] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: nil) ?? []
        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let base = url.deletingPathExtension().lastPathComponent
                let meta = demoMetadata[base]
                let duration = (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
                return Song(
                    id: "demo-\(base)",
                    title: meta?.title ?? base,
                    artist: meta?.artist ?? "Epsilon Demo",
                    album: nil,
                    duration: duration,
                    url: url,
                    artwork: nil,
                    isDemo: true
                )
            }
    }

    var artists: [ArtistGroup] {
        let groups = Dictionary(grouping: songs, by: { $0.artist })
        return groups
            .map { ArtistGroup(name: $0.key, songs: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
