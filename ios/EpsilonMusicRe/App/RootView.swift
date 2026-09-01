import SwiftUI

// MARK: - Route

enum Route: Hashable {
    case settings
    case explore
    case moods
    case charts
    case newReleases
    case liked
    case history
    case topTracks
    case stats
    case localSongs
    case offline
    case downloaded
    case recognition
    case spotifyImport
    case localPlaylist(String)
    case onlinePlaylist(PlaylistItem)
    case album(AlbumItem)
    case artist(ArtistItem)
    case browse(title: String, browseId: String, params: String?)
}

// MARK: - Palette environment

private struct EpsPaletteKey: EnvironmentKey {
    static let defaultValue = EpsPalette.resolve(isDark: true, pureBlack: true, accent: .epsAccent)
}

extension EnvironmentValues {
    var epsPalette: EpsPalette {
        get { self[EpsPaletteKey.self] }
        set { self[EpsPaletteKey.self] = newValue }
    }
}

// MARK: - Root

/// Root: the Android app's main scaffold — bottom tabs
/// [Home, Search, Listen Together, Library] in that exact order (Screens.kt
/// MainScreens), mini player above the tab bar, full-screen player cover.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var recognition: RecognitionManager
    @EnvironmentObject private var lt: ListenTogetherClient
    @EnvironmentObject private var discord: DiscordPresence
    @EnvironmentObject private var scrobbler: Scrobbler
    @EnvironmentObject private var spotify: SpotifyImporter
    @EnvironmentObject private var updater: Updater
    @EnvironmentObject private var eq: EqualizerEngine
    @EnvironmentObject private var ai: AIClient
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab = 0
    @State private var showPlayer = false

    private var isDark: Bool {
        switch settings.themeMode {
        case .system: return colorScheme == .dark
        case .light: return false
        case .dark: return true
        }
    }

    private var accent: Color {
        if settings.dynamicTheme, let dominant = player.artworkDominantColor {
            return Color(dominant)
        }
        return settings.accentColor
    }

    var body: some View {
        let palette = EpsPalette.resolve(isDark: isDark, pureBlack: settings.pureBlack, accent: accent)

        TabView(selection: $selectedTab) {
            HomeView()
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            SearchView()
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(1)
            ListenTogetherView()
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
                .tabItem { Label("Together", systemImage: "person.2.fill") }
                .tag(2)
            LibraryView()
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(3)
        }
        .preferredColorScheme(isDark ? .dark : .light)
        .tint(palette.accent)
        .environment(\.epsPalette, palette)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(account)
                .environmentObject(downloads)
                .environmentObject(eq)
                .environmentObject(ai)
                .environment(\.epsPalette, palette)
                .preferredColorScheme(isDark ? .dark : .light)
        }
        .onAppear {
            // The persisted queue is restored paused (Android onCreate parity).
        }
    }

    @ViewBuilder
    private var miniPlayer: some View {
        if player.currentSong != nil {
            MiniPlayerBar {
                showPlayer = true
            }
        }
    }
}
