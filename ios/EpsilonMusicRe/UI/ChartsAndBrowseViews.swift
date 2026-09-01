import SwiftUI

// MARK: - Charts screen (ChartsScreen.kt parity)

struct ChartsView: View {
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    @State private var shelves: [Shelf] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Charts", showBack: true) { EmptyView() }
                if isLoading {
                    HStack { Spacer(); ProgressView().padding(.vertical, 60); Spacer() }
                } else if let error = errorText {
                    ErrorBanner(message: error, onRetry: { load() })
                } else {
                    ForEach(shelves) { shelf in
                        SectionHeader(title: shelf.title)
                        if shelf.isSongList {
                            VStack(spacing: 2) {
                                ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                                    if case .song(let song) = item {
                                        SongRow(song: song, showIndex: index + 1,
                                                showLike: false,
                                                isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                                            player.play(tapped, queue: shelf.items.compactMap { songItem -> Song? in
                                                if case .song(let s) = songItem { return s }
                                                return nil
                                            }, sourceName: shelf.title)
                                        }
                                    }
                                }
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(shelf.items) { item in
                                        NavigableMediaCard(item: item)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task { load() }
    }

    private func load() {
        isLoading = true
        errorText = nil
        Task { @MainActor in
            do {
                shelves = try await InnerTube.shared.charts()
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }
}

extension Shelf {
    /// True when most items are songs (chart song lists render as rows).
    var isSongList: Bool {
        let songCount = items.filter { item in
            if case .song = item { return true }
            return false
        }.count
        return songCount > items.count / 2
    }
}

// MARK: - New releases (NewReleaseScreen.kt parity)

struct NewReleasesView: View {
    @Environment(\.epsPalette) private var pal

    @State private var albums: [MediaGridItem] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "New releases", showBack: true) { EmptyView() }
                if isLoading {
                    HStack { Spacer(); ProgressView().padding(.vertical, 60); Spacer() }
                } else if let error = errorText {
                    ErrorBanner(message: error, onRetry: { load() })
                } else if albums.isEmpty {
                    EmptyPlaceholder(icon: "square.stack", text: "No new releases found.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                        ForEach(albums) { item in
                            NavigableMediaCard(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task { load() }
    }

    private func load() {
        isLoading = true
        Task { @MainActor in
            do {
                albums = try await InnerTube.shared.newReleaseAlbums()
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Mood / genre detail browse (YouTubeBrowseScreen.kt parity)

struct BrowseView: View {
    let title: String
    let browseId: String
    var params: String? = nil

    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    @State private var shelves: [Shelf] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: title, showBack: true) { EmptyView() }
                if isLoading {
                    HStack { Spacer(); ProgressView().padding(.vertical, 60); Spacer() }
                } else if let error = errorText {
                    ErrorBanner(message: error, onRetry: { load() })
                } else if shelves.isEmpty {
                    EmptyPlaceholder(icon: "music.quarternote.3", text: "Nothing to browse here yet.")
                } else {
                    ForEach(shelves) { shelf in
                        ItemShelf(shelf: shelf) { song, songs in
                            player.play(song, queue: songs, sourceName: title)
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task { load() }
    }

    private func load() {
        isLoading = true
        errorText = nil
        Task { @MainActor in
            do {
                shelves = try await InnerTube.shared.browse(browseId: browseId, params: params)
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }
}
