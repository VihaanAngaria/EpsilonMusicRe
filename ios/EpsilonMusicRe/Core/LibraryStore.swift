import Foundation
import Combine
import MediaPlayer

/// The music library: liked songs, playback history, local playlists,
/// on-device songs and bundled demo tracks. JSON persistence mirrors the
/// Android app's Room database for the subset iOS persists locally.
@MainActor
final class LibraryStore: ObservableObject {

    static let shared = LibraryStore()

    // MARK: Published state

    @Published private(set) var likedSongs: [Song] = []
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var playlists: [LocalPlaylist] = []
    @Published private(set) var localSongs: [Song] = []
    @Published var onDevicePermissionDenied: Bool = false
    @Published var hasLocalPermission: Bool = false

    /// Albums/artists the user opened (shown under Library > Albums/Artists).
    @Published private(set) var visitedAlbums: [AlbumItem] = []
    @Published private(set) var visitedArtists: [ArtistItem] = []

    // MARK: Persistence

    private var documentsUrl: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private var storageFile: URL { documentsUrl.appendingPathComponent("epsilon-library.json") }

    private struct Persisted: Codable {
        var liked: [Song] = []
        var history: [HistoryEntry] = []
        var playlists: [LocalPlaylist] = []
        var visitedAlbums: [AlbumItem] = []
        var visitedArtists: [ArtistItem] = []
    }

    private init() {
        load()
        loadLocalSongs()
        loadDemoSongs()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageFile) else { return }
        if let persisted = try? JSONDecoder().decode(Persisted.self, from: data) {
            likedSongs = persisted.liked
            history = persisted.history
            playlists = persisted.playlists
            visitedAlbums = persisted.visitedAlbums
            visitedArtists = persisted.visitedArtists
        }
    }

    private func save() {
        let persisted = Persisted(liked: likedSongs, history: history, playlists: playlists,
                                  visitedAlbums: visitedAlbums, visitedArtists: visitedArtists)
        if let data = try? JSONEncoder().encode(persisted) {
            try? data.write(to: storageFile, options: [.atomic])
        }
    }

    // MARK: Demo + on-device songs

    private func loadDemoSongs() {
        if localSongs.contains(where: { $0.isDemo }) { return }
        let demo = [
            Song(videoId: "demo-aurora", title: "Aurora Arpeggio",
                 artists: ["Epsilon Demo"], album: "Demo Essentials",
                 duration: 92, thumbnail: nil, isLocal: true, localKey: "demo-aurora", isDemo: true),
            Song(videoId: "demo-midnight", title: "Midnight Pads",
                 artists: ["Epsilon Demo"], album: "Demo Essentials",
                 duration: 85, thumbnail: nil, isLocal: true, localKey: "demo-midnight", isDemo: true),
            Song(videoId: "demo-sundown", title: "Sundown Plucks",
                 artists: ["Epsilon Demo"], album: "Demo Essentials",
                 duration: 78, thumbnail: nil, isLocal: true, localKey: "demo-sundown", isDemo: true),
        ]
        localSongs.append(contentsOf: demo)
    }

    /// Bundled demo file URL (or nil).
    static func demoFileUrl(for song: Song) -> URL? {
        guard song.isDemo, let key = song.localKey else { return nil }
        return Bundle.main.url(forResource: key, withExtension: "wav")
    }

    /// Loads the device music library (requires user permission on first access).
    func loadLocalSongs() {
        let status = MPMediaLibrary.authorizationStatus()
        switch status {
        case .authorized:
            hasLocalPermission = true
            onDevicePermissionDenied = false
            requestOnDeviceSongs()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { [weak self] newStatus in
                Task { @MainActor in
                    if newStatus == .authorized {
                        self?.hasLocalPermission = true
                        self?.requestOnDeviceSongs()
                    } else {
                        self?.onDevicePermissionDenied = true
                    }
                }
            }
        default:
            onDevicePermissionDenied = true
        }
    }

    private func requestOnDeviceSongs() {
        let query = MPMediaQuery.songs()
        let items = query.items ?? []
        var mapped: [Song] = []
        for item in items {
            // Skip items without a playable local asset (e.g. Apple Music catalog
            // streams — the Android app's equivalent DRM-skip).
            guard item.assetURL != nil else { continue }
            let key = item.persistentID.description
            let duration = Int(item.playbackDuration)
            let song = Song(
                videoId: "local-\(key)",
                title: item.title ?? "Unknown title",
                artists: [item.artist ?? "Unknown artist"],
                album: item.albumTitle,
                duration: duration > 0 ? duration : nil,
                thumbnail: nil,
                isLocal: true,
                localKey: key,
                isDemo: false)
            mapped.append(song)
        }
        // Replace previous non-demo local entries.
        localSongs = mapped + localSongs.filter { $0.isDemo }
    }

    /// File URL for a local (MPMediaItem) song — resolved lazily via MediaPlayer.
    func localFileUrl(for song: Song) -> URL? {
        if song.isDemo { return Self.demoFileUrl(for: song) }
        guard song.isLocal, let key = song.localKey, let pid = UInt64(key) else { return nil }
        let query = MPMediaQuery()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: pid), forProperty: MPMediaItemPropertyPersistentID))
        return query.items?.first?.assetURL
    }

    // MARK: Likes

    func isLiked(_ song: Song) -> Bool {
        likedSongs.contains(where: { $0.id == song.id })
    }

    func toggleLike(_ song: Song) {
        if let index = likedSongs.firstIndex(where: { $0.id == song.id }) {
            likedSongs.remove(at: index)
        } else {
            likedSongs.insert(song, at: 0)
        }
        save()
    }

    // MARK: History

    func recordPlay(_ song: Song) {
        let entry = HistoryEntry(song: song, playedAt: Date().timeIntervalSince1970)
        history.removeAll { $0.id == entry.id && $0.song.id == song.id }
        history.insert(entry, at: 0)
        if history.count > 500 { history.removeLast(history.count - 500) }
        save()
    }

    func clearHistory() {
        history = []
        save()
    }

    /// Play counts across history — the stats source.
    func topSongs(limit: Int = 50) -> [Song] {
        var counts: [String: (song: Song, count: Int)] = [:]
        for entry in history {
            if let existing = counts[entry.song.id] {
                counts[entry.song.id] = (existing.song, existing.count + 1)
            } else {
                counts[entry.song.id] = (entry.song, 1)
            }
        }
        return counts.values.sorted { $0.count > $1.count }.prefix(limit).map { $0.song }
    }

    func playCount(for song: Song) -> Int {
        history.filter { $0.song.id == song.id }.count
    }

    // MARK: Playlists

    func createPlaylist(named name: String, songs: [Song] = []) -> String {
        let id = "pl-\(UUID().uuidString.prefix(8).lowercased())"
        let playlist = LocalPlaylist(id: id, name: name, createdAt: Date().timeIntervalSince1970, songs: songs)
        playlists.insert(playlist, at: 0)
        save()
        return id
    }

    func renamePlaylist(_ id: String, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = name
        save()
    }

    func deletePlaylist(_ id: String) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func playlist(_ id: String) -> LocalPlaylist? {
        playlists.first { $0.id == id }
    }

    func addToPlaylist(_ id: String, song: Song) -> Bool {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return false }
        if playlists[index].songs.contains(where: { $0.id == song.id }) { return false }
        playlists[index].songs.append(song)
        save()
        return true
    }

    func removeFromPlaylist(_ id: String, at offsets: IndexSet) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].songs.remove(atOffsets: offsets)
        save()
    }

    func moveSongInPlaylist(_ id: String, from source: IndexSet, to destination: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].songs.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Imports an online playlist into the local library ("Save playlist" flow).
    func importPlaylist(name: String, songs: [Song]) -> String {
        createPlaylist(named: name, songs: songs)
    }

    // MARK: Visited pages (Albums/Artists library tabs)

    func recordVisitedAlbum(_ album: AlbumItem) {
        visitedAlbums.removeAll { $0.id == album.id }
        visitedAlbums.insert(album, at: 0)
        if visitedAlbums.count > 100 { visitedAlbums.removeLast() }
        save()
    }

    func recordVisitedArtist(_ artist: ArtistItem) {
        visitedArtists.removeAll { $0.id == artist.id }
        visitedArtists.insert(artist, at: 0)
        if visitedArtists.count > 100 { visitedArtists.removeLast() }
        save()
    }

    // MARK: Queue helpers (Android "recent activity" style shortcuts)

    /// Songs that are played most recently — "Quick picks" seed.
    var recentUniqueSongs: [Song] {
        var seen: Set<String> = []
        var out: [Song] = []
        for entry in history {
            if seen.insert(entry.song.id).inserted {
                out.append(entry.song)
            }
        }
        return out
    }
}
