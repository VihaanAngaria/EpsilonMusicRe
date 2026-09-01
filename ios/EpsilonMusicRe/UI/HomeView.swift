import SwiftUI

/// Home tab — mirrors the Android HomeScreen: app title bar with logo +
/// settings gear, quick picks from listening history, YouTube Music home
/// shelves (listen again / new releases / moods), with offline fallback to
/// on-device and bundled demo songs.
struct HomeView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var recognition: RecognitionManager
    @Environment(\.epsPalette) private var pal

    @State private var shelves: [Shelf] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showWelcome = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: []) {
                    NavigationTitleBar(title: "Epsilon Music", showLogo: true) {
                        HStack(spacing: 14) {
                            NavigationLink(value: Route.recognition) {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(pal.textSecondary)
                            }
                            .buttonStyle(.plain)
                            NavigationLink(value: Route.settings) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(pal.textSecondary)
                            }
                            .buttonStyle(.plain)
                            NavigationLink(value: Route.settings) {
                                accountAvatar
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    exploreShortcuts

                    if !quickPicks.isEmpty {
                        quickPicksSection
                    }

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 40)
                            Spacer()
                        }
                    } else if let error = loadError {
                        ErrorBanner(message: "YouTube Music feed unavailable — \(error)", onRetry: reload)
                    } else {
                        ForEach(shelves) { shelf in
                            ItemShelf(shelf: shelf, circleItems: isArtistShelf(shelf)) { song, songs in
                                player.play(song, queue: songs, sourceName: shelf.title)
                            }
                        }
                    }

                    offlineSections

                    Color.clear.frame(height: 120)
                }
            }
            .background(pal.background.ignoresSafeArea())
            .navigationDestination(for: Route.self) { route in
                RouteDestination(route: route)
            }
            .task { reloadIfNeeded() }
            .alert("Welcome to Epsilon Music", isPresented: $showWelcome) {
                Button("Start listening") {}
            } message: {
                Text("Sign in from Settings → Account to sync your library, or start exploring right away.")
            }
            .onAppear {
                if !UserDefaults.standard.bool(forKey: "welcomeShown") {
                    UserDefaults.standard.set(true, forKey: "welcomeShown")
                    showWelcome = true
                }
            }
        }
    }

    @ViewBuilder
    private var accountAvatar: some View {
        if account.isLoggedIn, let photo = account.accountPhoto {
            AsyncImage(url: URL(string: photo)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
            .foregroundStyle(pal.textSecondary)
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(pal.textSecondary)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var exploreShortcuts: some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.explore) {
                shortcutTile(icon: "square.grid.2x2.fill", title: "Explore")
            }
            .buttonStyle(.plain)
            NavigationLink(value: Route.charts) {
                shortcutTile(icon: "chart.bar.fill", title: "Charts")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        HStack(spacing: 12) {
            NavigationLink(value: Route.moods) {
                shortcutTile(icon: "face.smiling.inverse", title: "Moods & genres")
            }
            .buttonStyle(.plain)
            NavigationLink(value: Route.newReleases) {
                shortcutTile(icon: "sparkles", title: "New releases")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func shortcutTile(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(pal.accent)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pal.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.surface))
    }

    private var quickPicks: [Song] {
        Array(library.recentUniqueSongs.prefix(12))
    }

    private var quickPicksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Quick picks", trailingText: "From your history")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(quickPicks.enumerated()), id: \.element.id) { _, song in
                        VStack(alignment: .leading, spacing: 8) {
                            SongThumb(url: song.thumbnailUrl, size: 128, corner: 12)
                            Text(song.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(pal.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(song.artistsText)
                                .font(.system(size: 11))
                                .foregroundStyle(pal.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 128)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.play(song, queue: quickPicks, sourceName: "Quick picks")
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// Fallback sections that always work — device songs + demo tracks.
    @ViewBuilder
    private var offlineSections: some View {
        if !shelves.isEmpty || isLoading { EmptyView() } else {
            let deviceSongs = library.localSongs.filter { !$0.isDemo }
            if !deviceSongs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Songs on this device", trailingText: "\(deviceSongs.count)")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(deviceSongs.prefix(12)) { song in
                                VStack(alignment: .leading, spacing: 8) {
                                    SongThumb(url: song.thumbnailUrl, size: 128, corner: 12)
                                    Text(song.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(pal.textPrimary)
                                        .lineLimit(2)
                                    Text(song.artistsText)
                                        .font(.system(size: 11))
                                        .foregroundStyle(pal.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 128)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    player.play(song, queue: deviceSongs, sourceName: "Songs on this device")
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            let demoSongs = library.localSongs.filter { $0.isDemo }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Demo tracks", trailingText: "Always available")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(demoSongs) { song in
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(pal.surfaceHighest)
                                    Image(systemName: "waveform")
                                        .font(.system(size: 30))
                                        .foregroundStyle(pal.accent)
                                }
                                .frame(width: 128, height: 128)
                                Text(song.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(pal.textPrimary)
                                    .lineLimit(2)
                                Text(song.artistsText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(pal.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 128)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.play(song, queue: demoSongs, sourceName: "Demo tracks")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: Data

    private func reloadIfNeeded() {
        if shelves.isEmpty && loadError == nil {
            reload()
        }
    }

    private func reload() {
        isLoading = true
        loadError = nil
        Task { @MainActor in
            do {
                let result = try await InnerTube.shared.home()
                shelves = result.filter { !$0.items.isEmpty }
            } catch {
                loadError = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func isArtistShelf(_ shelf: Shelf) -> Bool {
        shelf.items.first { if case .artist = $0 { return true } else { return false } } != nil
            && shelf.items.allSatisfy { if case .artist = $0 { return true } else { return false } }
    }

    // MARK: Routing

    private func routeDestination(_ route: Route) -> some View {
        RouteDestination(route: route)
    }
}
