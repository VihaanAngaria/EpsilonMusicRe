import SwiftUI

enum LibraryChip: String, CaseIterable, Identifiable, Hashable {
    case library, playlists, songs, albums, artists, local
    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .playlists: return "Playlists"
        case .songs: return "Songs"
        case .albums: return "Albums"
        case .artists: return "Artists"
        case .local: return "Local"
        }
    }
}

/// Library tab — mirrors the Android LibraryScreen: chip row
/// [Playlists, Songs, Albums, Artists, Local], the library mix grid
/// (liked / top / offline / local tiles), playlists view with the
/// create + import FABs, and album/artist pages from listening activity.
struct LibraryView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    @State private var chip: LibraryChip = .library
    @State private var showCreateDialog = false
    @State private var newPlaylistName = ""
    @State private var showImportDialog = false
    @State private var importUrl = ""
    @State private var importError: String?
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    NavigationTitleBar(title: "Library") {
                        Menu {
                            Picker("View", selection: $chip) {
                                ForEach(LibraryChip.allCases) { c in
                                    Text(c.title).tag(c)
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(pal.textSecondary)
                        }
                    }

                    // Chip row (Android: Playlists/Songs/Albums/Artists/Local).
                    ChipsRow(options: [
                        (LibraryChip.playlists, "Playlists"),
                        (LibraryChip.songs, "Songs"),
                        (LibraryChip.albums, "Albums"),
                        (LibraryChip.artists, "Artists"),
                        (LibraryChip.local, "Local"),
                    ], isSelected: { chip != .library && $0 == chip },
                       onSelect: { newValue in
                           // Tapping the active chip again returns to the library overview.
                           chip = (chip == newValue) ? .library : newValue
                       })

                    content

                    Color.clear.frame(height: 120)
                }
            }
            .background(pal.background.ignoresSafeArea())
            .navigationDestination(for: Route.self) { route in
                destinationView(route)
            }
            .alert("Create playlist", isPresented: $showCreateDialog) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Create") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        _ = library.createPlaylist(named: name)
                    }
                    newPlaylistName = ""
                }
                Button("Cancel", role: .cancel) { newPlaylistName = "" }
            }
            .alert("Import playlist from YouTube Music", isPresented: $showImportDialog) {
                TextField("Playlist link or ID", text: $importUrl)
                Button("Import") { importPlaylist() }
                Button("Cancel", role: .cancel) { importError = nil }
            } message: {
                Text("Paste a public YouTube Music playlist link below")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if chip == .playlists {
                fabs
            }
        }
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        switch chip {
        case .library:
            libraryMix
        case .playlists:
            playlistsGrid
        case .songs:
            songsSection
        case .albums:
            albumsSection
        case .artists:
            artistsSection
        case .local:
            localSection
        }
    }

    // MARK: Library mix (Android LibraryMixScreen grid menu)

    private var libraryMix: some View {
        VStack(alignment: .leading, spacing: 4) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            gridTile(icon: "heart.fill", accentIcon: true, title: "Liked songs", countText: "\(library.likedSongs.count) songs", route: .liked)
            gridTile(icon: "chart.line.uptrend.xyaxis", title: "My top tracks", countText: "\(library.topSongs(limit: 100).count) songs", route: .topTracks)
            gridTile(icon: "arrow.down.circle.fill", title: "Offline / demo", countText: "\(library.localSongs.filter { $0.isDemo }.count) songs", route: .offline)
            gridTile(icon: "folder.fill", title: "On this device", countText: "\(library.localSongs.filter { !$0.isDemo }.count) songs", route: .localSongs)
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Playlists", trailingText: "\(library.playlists.count)")
                if library.playlists.isEmpty {
                    EmptyPlaceholder(icon: "music.note.list", text: "Create your first playlist with the + button, or import one from YouTube Music.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 16) {
                        ForEach(library.playlists.prefix(6)) { playlist in
                            NavigationLink(value: Route.localPlaylist(playlist.id)) {
                                MediaCard(title: playlist.name,
                                          subtitle: "\(playlist.songCount) songs",
                                          thumbnail: playlist.thumbnailUrl)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func gridTile(icon: String, accentIcon: Bool = false, title: String, countText: String, route: Route) -> some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accentIcon ? pal.accent : pal.textPrimary)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(pal.textPrimary)
                    .lineLimit(1)
                Text(countText)
                    .font(.system(size: 12))
                    .foregroundStyle(pal.textSecondary)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
        }
        .buttonStyle(.plain)
    }

    // MARK: Playlists

    private var playlistsGrid: some View {
        Group {
            if library.playlists.isEmpty {
                EmptyPlaceholder(icon: "music.note.list", text: "No playlists yet. Create one with the + button.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 16) {
                    ForEach(library.playlists) { playlist in
                        NavigationLink(value: Route.localPlaylist(playlist.id)) {
                            MediaCard(title: playlist.name, subtitle: "\(playlist.songCount) songs", thumbnail: playlist.thumbnailUrl)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// Android-style extended FABs: create playlist + import playlist.
    private var fabs: some View {
        VStack(spacing: 12) {
            Button {
                showImportDialog = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                    Text("Import playlist")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pal.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(pal.surfaceHigh))
            }
            .buttonStyle(.plain)

            Button {
                showCreateDialog = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Create playlist")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pal.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(pal.surfaceHigh))
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 96)
    }

    // MARK: Songs (liked)

    private var songsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if library.likedSongs.isEmpty {
                EmptyPlaceholder(icon: "heart", text: "Songs you like will show up here. Tap the heart next to any song.")
            } else {
                PlayShuffleButtons {
                    player.play(library.likedSongs[0], queue: library.likedSongs, sourceName: "Liked songs")
                } onShuffle: {
                    var shuffled = library.likedSongs
                    shuffled.shuffle()
                    player.play(shuffled[0], queue: shuffled, sourceName: "Liked songs")
                    player.shuffle = true
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ForEach(library.likedSongs) { song in
                    SongRow(song: song, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                        player.play(tapped, queue: library.likedSongs, sourceName: "Liked songs")
                    }
                }
            }
        }
    }

    // MARK: Albums / Artists

    private var albumsSection: some View {
        Group {
            if library.visitedAlbums.isEmpty {
                EmptyPlaceholder(icon: "opticaldisc", text: "Albums you open from search and home will appear here.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 16) {
                    ForEach(library.visitedAlbums) { album in
                        NavigationLink(value: Route.album(album)) {
                            MediaCard(title: album.title, subtitle: [album.artistsText, album.year].compactMap { $0 }.joined(separator: " • "), thumbnail: album.thumbnail)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var artistsSection: some View {
        Group {
            if library.visitedArtists.isEmpty {
                EmptyPlaceholder(icon: "person.crop.circle", text: "Artists you open from search and home will appear here.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 16) {
                    ForEach(library.visitedArtists) { artist in
                        NavigationLink(value: Route.artist(artist)) {
                            MediaCard(title: artist.name, subtitle: "Artist", thumbnail: artist.thumbnail, isCircle: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Local

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if library.onDevicePermissionDenied {
                ErrorBanner(message: "Music library access was denied. Enable it in iOS Settings > Privacy & Security > Music.")
            } else if library.localSongs.isEmpty {
                EmptyPlaceholder(icon: "folder", text: "No songs found on this device.")
            } else {
                SectionHeader(title: "On this device", trailingText: "\(library.localSongs.count) songs")
                ForEach(library.localSongs) { song in
                    SongRow(song: song, showLike: false, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                        player.play(tapped, queue: library.localSongs, sourceName: "On this device")
                    }
                }
            }
        }
    }

    // MARK: Import

    private func importPlaylist() {
        let text = importUrl.trimmingCharacters(in: .whitespaces)
        importUrl = ""
        guard !text.isEmpty else { return }
        // Accept full URLs or raw ids.
        var listId = text
        if let range = text.range(of: "list=") {
            listId = String(text[range.upperBound...])
            if let ampIndex = listId.firstIndex(of: "&") {
                listId = String(listId[..<ampIndex])
            }
        }
        listId = listId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !listId.isEmpty else { return }
        // Normalize to a browseable id.
        let browseId = listId.hasPrefix("VL") ? listId : "VL" + listId
        let item = PlaylistItem(browseId: browseId, title: "Imported playlist", owner: nil, countText: nil, thumbnail: nil, isLocal: false)
        navPath.append(Route.onlinePlaylist(item))
    }

    // MARK: Routing

    @ViewBuilder
    private func destinationView(_ route: Route) -> some View {
        switch route {
        case .settings: SettingsView()
        case .explore: ExploreView()
        case .moods: MoodsView()
        case .liked: LikedSongsView()
        case .history: HistoryView()
        case .topTracks: TopTracksView()
        case .localSongs: LocalSongsView()
        case .offline: OfflineView()
        case .localPlaylist(let id): LocalPlaylistView(playlistId: id)
        case .onlinePlaylist(let item): OnlinePlaylistView(item: item)
        case .album(let item): AlbumView(item: item)
        case .artist(let item): ArtistView(item: item)
        }
    }
}
