import SwiftUI

// MARK: - Shared route destination (all Route cases, used by every tab's
// NavigationStack so the app navigates identically from anywhere).

struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .settings: SettingsView()
        case .explore: ExploreView()
        case .moods: MoodsView()
        case .charts: ChartsView()
        case .newReleases: NewReleasesView()
        case .liked: LikedSongsView()
        case .history: HistoryView()
        case .topTracks: TopTracksView()
        case .stats: StatsView()
        case .localSongs: LocalSongsView()
        case .offline: OfflineView()
        case .downloaded: DownloadedSongsView()
        case .recognition: RecognitionView()
        case .spotifyImport: SpotifyImportView()
        case .localPlaylist(let id): LocalPlaylistView(playlistId: id)
        case .onlinePlaylist(let item): OnlinePlaylistView(item: item)
        case .album(let item): AlbumView(item: item)
        case .artist(let item): ArtistView(item: item)
        case .browse(let title, let browseId, let params):
            BrowseView(title: title, browseId: browseId, params: params)
        }
    }
}

// MARK: - Downloaded songs view (CachePlaylistScreen parity)

struct DownloadedSongsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    @State private var songs: [Song] = []
    @State private var sortKey = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Downloaded", showBack: true) { EmptyView() }
                if songs.isEmpty {
                    EmptyPlaceholder(icon: "arrow.down.circle", text: "Songs you download appear here for offline playback.")
                } else {
                    Picker("Sort", selection: $sortKey) {
                        Text("Recent").tag(0)
                        Text("Name").tag(1)
                        Text("Artist").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    ForEach(sortedSongs) { song in
                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                            player.play(tapped, queue: sortedSongs, sourceName: "Downloaded")
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .onAppear { reload() }
    }

    private var sortedSongs: [Song] {
        switch sortKey {
        case 1: return songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case 2: return songs.sorted { $0.artistsText.localizedCaseInsensitiveCompare($1.artistsText) == .orderedAscending }
        default: return songs
        }
    }

    private func reload() {
        songs = downloads.downloadedSongs()
    }
}
