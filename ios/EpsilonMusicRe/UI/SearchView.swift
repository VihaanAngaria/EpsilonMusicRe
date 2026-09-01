import SwiftUI

/// Search tab — mirrors the Android OnlineSearchScreen: search bar,
/// suggestions, filter chips (Songs / Videos / Artists / Albums /
/// Community playlists / Featured playlists), numbered song results,
/// artist rows, album/playlist grids, "load more" continuation.
struct SearchView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.epsPalette) private var pal

    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var filter: SearchFilter = .songs
    @State private var suggestions: [String] = []
    @State private var results: [GridItem] = []
    @State private var continuation: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if !submittedQuery.isEmpty {
                    ChipsRow(options: SearchFilter.allCases.map { ($0, $0.title) },
                              isSelected: { $0 == filter },
                              onSelect: { newFilter in
                                  filter = newFilter
                                  runSearch(submittedQuery)
                              })
                        .padding(.vertical, 2)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if submittedQuery.isEmpty {
                            idleContent
                        } else {
                            resultContent
                        }
                        Color.clear.frame(height: 100)
                    }
                }
            }
            .background(pal.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .task {
                filter = settings.defaultSearchFilter
            }
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(pal.textSecondary)
            TextField("Search songs, artists, albums…", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(pal.textPrimary)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    submitSearch(query)
                }
                .onChange(of: query) { newValue in
                    if submittedQuery.isEmpty || newValue.isEmpty {
                        loadSuggestions(newValue)
                    }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    submittedQuery = ""
                    results = []
                    suggestions = []
                    continuation = nil
                    errorText = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(pal.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Idle (no submitted query)

    @ViewBuilder
    private var idleContent: some View {
        if !suggestions.isEmpty {
            SectionHeader(title: "Suggestions")
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    query = suggestion
                    submitSearch(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(pal.textSecondary)
                        Text(suggestion)
                            .font(.system(size: 15))
                            .foregroundStyle(pal.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else if !recentSearches.isEmpty {
            SectionHeader(title: "Recent searches")
            ForEach(recentSearches, id: \.self) { recent in
                Button {
                    query = recent
                    submitSearch(recent)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14))
                            .foregroundStyle(pal.textSecondary)
                        Text(recent)
                            .font(.system(size: 15))
                            .foregroundStyle(pal.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            recentSearches.removeAll { $0 == recent }
                            UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(pal.textSecondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button {
                recentSearches = []
                UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
            } label: {
                Text("Clear recent searches")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pal.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        } else {
            EmptyPlaceholder(icon: "magnifyingglass",
                             text: "Search YouTube Music — songs, videos, artists, albums and playlists.")
        }
    }

    // MARK: Results

    @ViewBuilder
    private var resultContent: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView().padding(.vertical, 40)
                Spacer()
            }
        } else if let error = errorText {
            ErrorBanner(message: error, onRetry: { runSearch(submittedQuery) })
        } else if results.isEmpty {
            EmptyPlaceholder(icon: "music.note", text: "No results found for “\(submittedQuery)”.")
        } else {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                resultRow(item, index: index)
            }
            if continuation != nil {
                if isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().padding(.vertical, 12)
                        Spacer()
                    }
                } else {
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
    }

    @ViewBuilder
    private func resultRow(_ item: GridItem, index: Int) -> some View {
        let songs = results.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        switch item {
        case .song(let song):
            SongRow(song: song, showIndex: filter == .songs || filter == .videos ? index + 1 : nil) { tapped, _ in
                player.play(tapped, queue: songs.isEmpty ? [tapped] : songs, sourceName: "Search: \(submittedQuery)")
            }
        case .artist(let artist):
            NavigationLink(value: Route.artist(artist)) {
                ArtistRow(artist: artist)
            }
            .buttonStyle(.plain)
        case .album(let album):
            NavigationLink(value: Route.album(album)) {
                albumPlaylistRow(title: album.title, subtitle: [album.artistsText, album.year].compactMap { $0 }.joined(separator: " • "), thumbnail: album.thumbnail)
            }
            .buttonStyle(.plain)
        case .playlist(let playlist):
            NavigationLink(value: Route.onlinePlaylist(playlist)) {
                albumPlaylistRow(title: playlist.title, subtitle: [playlist.owner, playlist.countText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • "), thumbnail: playlist.thumbnail)
            }
            .buttonStyle(.plain)
        }
    }

    private func albumPlaylistRow(title: String, subtitle: String, thumbnail: String?) -> some View {
        HStack(spacing: 12) {
            SongThumb(url: thumbnail, size: 56, corner: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(pal.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(pal.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pal.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: Data

    private func submitSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchFocused = false
        submittedQuery = trimmed
        if !recentSearches.contains(trimmed) {
            recentSearches.insert(trimmed, at: 0)
            if recentSearches.count > 10 {
                recentSearches.removeLast()
            }
            UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
        }
        runSearch(trimmed)
    }

    private func runSearch(_ text: String) {
        isLoading = true
        errorText = nil
        results = []
        continuation = nil
        Task { @MainActor in
            do {
                let result = try await InnerTube.shared.search(query: text, filter: filter)
                results = result.items
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
                let more = try await InnerTube.shared.searchContinuation(token)
                // Deduplicate by id.
                let existingIds = Set(results.map { $0.id })
                let newItems = more.items.filter { !existingIds.contains($0.id) }
                results.append(contentsOf: newItems)
                continuation = more.continuation
            } catch {
                continuation = nil
            }
            isLoadingMore = false
        }
    }

    private func loadSuggestions(_ partial: String) {
        let trimmed = partial.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }
        Task { @MainActor in
            let newSuggestions = (try? await InnerTube.shared.suggestions(query: trimmed)) ?? []
            // Only apply if the query hasn't advanced past this request.
            if query.hasPrefix(trimmed) {
                suggestions = newSuggestions
            }
        }
    }
}
