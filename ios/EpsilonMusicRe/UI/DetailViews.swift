import SwiftUI

// MARK: - Shared media header (Android playlist/album headers)

struct MediaHeader: View {
    let title: String
    let subtitle: String?
    let thumbnail: String?
    var isCircle: Bool = false

    @Environment(\.epsPalette) private var pal

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SongThumb(url: thumbnail, size: 140, corner: isCircle ? 70 : 12, circle: isCircle)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(pal.textPrimary)
                    .lineLimit(2)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

// MARK: - Online playlist / album page

struct OnlinePlaylistView: View {
    let item: PlaylistItem

    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    @State private var page: MediaPage?
    @State private var songs: [Song] = []
    @State private var continuation: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var showSaveAlert = false
    @State private var savedName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: item.title, showBack: true) {
                    saveMenu
                }
                MediaHeader(title: page?.title ?? item.title,
                            subtitle: page?.subtitle,
                            thumbnail: page?.thumbnail ?? item.thumbnail)
                if !songs.isEmpty {
                    PlayShuffleButtons {
                        player.play(songs[0], queue: songs, sourceName: page?.title ?? item.title)
                    } onShuffle: {
                        var shuffled = songs
                        shuffled.shuffle()
                        player.play(shuffled[0], queue: shuffled, sourceName: page?.title ?? item.title)
                        player.shuffle = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                songList
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task { load() }
        .alert("Save playlist to library", isPresented: $showSaveAlert) {
            TextField("Playlist name", text: $savedName)
            Button("Save") {
                let name = savedName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !songs.isEmpty {
                    _ = library.importPlaylist(name: name, songs: songs)
                }
                savedName = ""
            }
            Button("Cancel", role: .cancel) { savedName = "" }
        } message: {
            Text("Saves \(songs.count) songs as a local playlist you can edit offline.")
        }
    }

    private var saveMenu: some View {
        Menu {
            Button {
                savedName = (page?.title ?? item.title).replacingOccurrences(of: "/", with: "-")
                showSaveAlert = true
            } label: {
                Label("Save to library", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(pal.textSecondary)
        }
    }

    @ViewBuilder
    private var songList: some View {
        if isLoading {
            HStack { Spacer(); ProgressView().padding(.vertical, 40); Spacer() }
        } else if let error = errorText {
            ErrorBanner(message: error, onRetry: { load() })
        } else if songs.isEmpty {
            EmptyPlaceholder(icon: "music.note.list", text: "This playlist is empty or unavailable.")
        } else {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, showIndex: index + 1, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                    player.play(tapped, queue: songs, sourceName: page?.title ?? item.title)
                }
            }
            if continuation != nil {
                Button {
                    loadMore()
                } label: {
                    Text("Load more")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(pal.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() {
        isLoading = true
        errorText = nil
        Task { @MainActor in
            do {
                let result = try await InnerTube.shared.playlistOrAlbum(browseId: item.browseId, isPlaylist: true)
                page = result
                songs = result.songs
                continuation = result.continuation
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func loadMore() {
        guard let token = continuation, !isLoadingMore else { return }
        isLoadingMore = true
        Task { @MainActor in
            do {
                let more = try await InnerTube.shared.playlistContinuation(token, isPlaylist: true)
                let existing = Set(songs.map { $0.id })
                songs.append(contentsOf: more.songs.filter { !existing.contains($0.id) })
                continuation = more.continuation
            } catch {
                continuation = nil
            }
            isLoadingMore = false
        }
    }
}

// MARK: - Album page

struct AlbumView: View {
    let item: AlbumItem

    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    @State private var page: MediaPage?
    @State private var songs: [Song] = []
    @State private var continuation: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: item.title, showBack: true) {
                    EmptyView()
                }
                MediaHeader(title: page?.title ?? item.title,
                            subtitle: page?.subtitle,
                            thumbnail: page?.thumbnail ?? item.thumbnail)
                if !songs.isEmpty {
                    PlayShuffleButtons {
                        player.play(songs[0], queue: songs, sourceName: page?.title ?? item.title)
                    } onShuffle: {
                        var shuffled = songs
                        shuffled.shuffle()
                        player.play(shuffled[0], queue: shuffled, sourceName: page?.title ?? item.title)
                        player.shuffle = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                if isLoading {
                    HStack { Spacer(); ProgressView().padding(.vertical, 40); Spacer() }
                } else if let error = errorText {
                    ErrorBanner(message: error, onRetry: { load() })
                } else if songs.isEmpty {
                    EmptyPlaceholder(icon: "opticaldisc", text: "This album is empty or unavailable.")
                } else {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SongRow(song: song, showIndex: index + 1, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                            player.play(tapped, queue: songs, sourceName: page?.title ?? item.title)
                        }
                    }
                    if continuation != nil {
                        Button {
                            loadMore()
                        } label: {
                            Text("Load more")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(pal.accent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task {
            load()
            library.recordVisitedAlbum(item)
        }
    }

    private func load() {
        isLoading = true
        errorText = nil
        Task { @MainActor in
            do {
                let result = try await InnerTube.shared.playlistOrAlbum(browseId: item.browseId, isPlaylist: false)
                page = result
                songs = result.songs
                continuation = result.continuation
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func loadMore() {
        guard let token = continuation, !isLoadingMore else { return }
        Task { @MainActor in
            do {
                let more = try await InnerTube.shared.playlistContinuation(token, isPlaylist: false)
                let existing = Set(songs.map { $0.id })
                songs.append(contentsOf: more.songs.filter { !existing.contains($0.id) })
                continuation = more.continuation
            } catch {
                continuation = nil
            }
        }
    }
}

// MARK: - Artist page

struct ArtistView: View {
    let item: ArtistItem

    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    @State private var artistPage: ArtistPage?
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: item.name, showBack: true) {
                    EmptyView()
                }
                MediaHeader(title: artistPage?.artist.name ?? item.name,
                            subtitle: "Artist",
                            thumbnail: artistPage?.artist.thumbnail ?? item.thumbnail,
                            isCircle: true)
                if !songs.isEmpty {
                    PlayShuffleButtons {
                        player.play(songs[0], queue: songs, sourceName: artistPage?.artist.name ?? item.name)
                    } onShuffle: {
                        var shuffled = songs
                        shuffled.shuffle()
                        player.play(shuffled[0], queue: shuffled, sourceName: artistPage?.artist.name ?? item.name)
                        player.shuffle = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                if isLoading {
                    HStack { Spacer(); ProgressView().padding(.vertical, 40); Spacer() }
                } else if let error = errorText {
                    ErrorBanner(message: error, onRetry: { load() })
                } else {
                    SectionHeader(title: "Songs")
                    ForEach(Array(songs.enumerated()), id: \.element.id) { _, song in
                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                            player.play(tapped, queue: songs, sourceName: artistPage?.artist.name ?? item.name)
                        }
                    }
                    ForEach(shelves) { shelf in
                        ItemShelf(shelf: shelf, circleItems: false) { song, shelfSongs in
                            player.play(song, queue: shelfSongs.isEmpty ? [song] : shelfSongs, sourceName: shelf.title)
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task {
            load()
            library.recordVisitedArtist(item)
        }
    }

    private var songs: [Song] {
        artistPage?.songs ?? []
    }

    private var shelves: [Shelf] {
        artistPage?.shelves ?? []
    }

    private func load() {
        isLoading = true
        errorText = nil
        Task { @MainActor in
            do {
                artistPage = try await InnerTube.shared.artist(browseId: item.browseId)
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Local playlist

struct LocalPlaylistView: View {
    let playlistId: String

    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal
    @Environment(\.dismiss) private var dismiss

    @State private var renameText = ""
    @State private var showRename = false
    @State private var showDeleteConfirm = false

    private var playlist: LocalPlaylist? {
        library.playlist(playlistId)
    }

    var body: some View {
        Group {
            if let playlist = playlist {
                content(playlist)
            } else {
                EmptyPlaceholder(icon: "music.note.list", text: "Playlist not found.")
            }
        }
        .background(pal.background.ignoresSafeArea())
    }

    private func content(_ playlist: LocalPlaylist) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: playlist.name, showBack: true) {
                    Menu {
                        Button {
                            renameText = playlist.name
                            showRename = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete playlist", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(pal.textSecondary)
                    }
                }
                MediaHeader(title: playlist.name,
                            subtitle: "\(playlist.songCount) songs",
                            thumbnail: playlist.thumbnailUrl)
                if !playlist.songs.isEmpty {
                    PlayShuffleButtons {
                        player.play(playlist.songs[0], queue: playlist.songs, sourceName: playlist.name)
                    } onShuffle: {
                        var shuffled = playlist.songs
                        shuffled.shuffle()
                        player.play(shuffled[0], queue: shuffled, sourceName: playlist.name)
                        player.shuffle = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    ForEach(Array(playlist.songs.enumerated()), id: \.element.id) { index, song in
                        SongRow(song: song, showIndex: index + 1, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                            player.play(tapped, queue: playlist.songs, sourceName: playlist.name)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                if let idx = playlist.songs.firstIndex(where: { $0.id == song.id }) {
                                    library.removeFromPlaylist(playlistId, at: IndexSet(integer: idx))
                                }
                            } label: {
                                Label("Remove from playlist", systemImage: "trash")
                            }
                        }
                    }
                } else {
                    EmptyPlaceholder(icon: "music.note.plus", text: "This playlist is empty. Add songs from search or the player menu.")
                }
                Color.clear.frame(height: 96)
            }
        }
        .alert("Rename playlist", isPresented: $showRename) {
            TextField("Playlist name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    library.renamePlaylist(playlistId, to: name)
                }
            }
            Button("Cancel", role: .cancel) { renameText = "" }
        }
        .alert("Delete playlist?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                library.deletePlaylist(playlistId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Liked songs

struct LikedSongsView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Liked songs", showBack: true) { EmptyView() }
                MediaHeader(title: "Liked songs", subtitle: "\(library.likedSongs.count) songs", thumbnail: library.likedSongs.first?.thumbnailUrl)
                if library.likedSongs.isEmpty {
                    EmptyPlaceholder(icon: "heart", text: "Songs you like will show up here.")
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
                    .padding(.vertical, 10)
                    ForEach(library.likedSongs) { song in
                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                            player.play(tapped, queue: library.likedSongs, sourceName: "Liked songs")
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "History", showBack: true) {
                    if !library.history.isEmpty {
                        Button {
                            library.clearHistory()
                        } label: {
                            Text("Clear")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(pal.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if library.history.isEmpty {
                    EmptyPlaceholder(icon: "clock.arrow.circlepath", text: "Songs you play will show up here.")
                } else {
                    ForEach(library.history) { entry in
                        let date = Date(timeIntervalSince1970: entry.playedAt)
                        SongRow(song: entry.song,
                                isCurrent: player.currentSong?.id == entry.song.id,
                                subtitleOverride: relativeDate(date)) { tapped, _ in
                            let songs = library.history.map { $0.song }
                            player.play(tapped, queue: songs, sourceName: "History")
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Top tracks

struct TopTracksView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    private var top: [Song] { library.topSongs(limit: 100) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "My top tracks", showBack: true) { EmptyView() }
                MediaHeader(title: "My top tracks", subtitle: "\(top.count) tracks", thumbnail: top.first?.thumbnailUrl)
                if top.isEmpty {
                    EmptyPlaceholder(icon: "chart.line.uptrend.xyaxis", text: "Your most-played tracks will show up here.")
                } else {
                    PlayShuffleButtons {
                        player.play(top[0], queue: top, sourceName: "My top tracks")
                    } onShuffle: {
                        var shuffled = top
                        shuffled.shuffle()
                        player.play(shuffled[0], queue: shuffled, sourceName: "My top tracks")
                        player.shuffle = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, song in
                        SongRow(song: song, showIndex: index + 1,
                                isCurrent: player.currentSong?.id == song.id,
                                subtitleOverride: "\(song.subtitle) • \(library.playCount(for: song)) plays") { tapped, _ in
                            player.play(tapped, queue: top, sourceName: "My top tracks")
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

// MARK: - Local songs

struct LocalSongsView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "On this device", showBack: true) { EmptyView() }
                if library.onDevicePermissionDenied {
                    ErrorBanner(message: "Music library access was denied. Enable it in iOS Settings > Privacy & Security > Music.")
                } else if library.localSongs.isEmpty {
                    EmptyPlaceholder(icon: "folder", text: "No songs found on this device.")
                } else {
                    PlayShuffleButtons {
                        player.play(library.localSongs[0], queue: library.localSongs, sourceName: "On this device")
                    } onShuffle: {
                        var shuffled = library.localSongs
                        shuffled.shuffle()
                        player.play(shuffled[0], queue: shuffled, sourceName: "On this device")
                        player.shuffle = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    ForEach(library.localSongs) { song in
                        SongRow(song: song, showLike: false, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                            player.play(tapped, queue: library.localSongs, sourceName: "On this device")
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

// MARK: - Offline (demo)

struct OfflineView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    private var demoSongs: [Song] {
        library.localSongs.filter { $0.isDemo }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Offline", showBack: true) { EmptyView() }
                MediaHeader(title: "Offline tracks", subtitle: "\(demoSongs.count) bundled demo songs", thumbnail: nil)
                if demoSongs.isEmpty {
                    EmptyPlaceholder(icon: "arrow.down.circle", text: "Bundled demo tracks appear here and always play, even offline.")
                } else {
                    PlayShuffleButtons {
                        player.play(demoSongs[0], queue: demoSongs, sourceName: "Offline")
                    } onShuffle: {
                        var shuffled = demoSongs
                        shuffled.shuffle()
                        player.play(shuffled[0], queue: shuffled, sourceName: "Offline")
                        player.shuffle = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    ForEach(demoSongs) { song in
                        SongRow(song: song, showLike: false, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                            player.play(tapped, queue: demoSongs, sourceName: "Offline")
                        }
                    }
                    SectionHeader(title: "About offline playback",
                                  trailingText: nil)
                    Text("These demo tracks ship with the app. On the Android edition, downloaded YouTube Music songs also appear here; on iOS, stream caching is limited by the platform's media policies.")
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

// MARK: - Explore

struct ExploreView: View {
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    @State private var shelves: [Shelf] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Explore", showBack: true) { EmptyView() }
                if isLoading {
                    HStack { Spacer(); ProgressView().padding(.vertical, 40); Spacer() }
                } else if let error = errorText {
                    ErrorBanner(message: error, onRetry: { load() })
                } else if shelves.isEmpty {
                    EmptyPlaceholder(icon: "square.grid.2x2", text: "Nothing to explore right now.")
                } else {
                    ForEach(shelves) { shelf in
                        ItemShelf(shelf: shelf, circleItems: false) { song, songs in
                            player.play(song, queue: songs.isEmpty ? [song] : songs, sourceName: shelf.title)
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task { if shelves.isEmpty { load() } }
    }

    private func load() {
        isLoading = true
        errorText = nil
        Task { @MainActor in
            do {
                shelves = try await InnerTube.shared.explore()
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Moods & genres

struct MoodsView: View {
    @Environment(\.epsPalette) private var pal

    @State private var items: [MediaGridItem] = []
    @State private var isLoading = true
    @State private var errorText: String?

    private let tileColors: [Color] = [
        Color(red: 0.85, green: 0.28, blue: 0.33),
        Color(red: 0.93, green: 0.60, blue: 0.19),
        Color(red: 0.35, green: 0.62, blue: 0.85),
        Color(red: 0.42, green: 0.72, blue: 0.45),
        Color(red: 0.62, green: 0.44, blue: 0.82),
        Color(red: 0.90, green: 0.49, blue: 0.55),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Moods & genres", showBack: true) { EmptyView() }
                if isLoading {
                    HStack { Spacer(); ProgressView().padding(.vertical, 40); Spacer() }
                } else if let error = errorText {
                    ErrorBanner(message: error, onRetry: { load() })
                } else if items.isEmpty {
                    EmptyPlaceholder(icon: "face.smiling", text: "No moods available right now.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: moodRoute(item)) {
                                ZStack(alignment: .bottomLeading) {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(tileColors[index % tileColors.count].opacity(0.85))
                                    Text(item.title)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .padding(12)
                                }
                                .frame(height: 84)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task { if items.isEmpty { load() } }
    }

    private func moodRoute(_ item: MediaGridItem) -> Route {
        switch item {
        case .playlist(let p): return .onlinePlaylist(p)
        case .album(let a): return .album(a)
        case .artist(let a): return .artist(a)
        case .song: return .explore
        }
    }

    private func load() {
        isLoading = true
        errorText = nil
        Task { @MainActor in
            do {
                items = try await InnerTube.shared.moodsAndGenres()
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }
}
