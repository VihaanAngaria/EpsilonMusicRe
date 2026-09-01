import SwiftUI

// MARK: - Route

enum Route: Hashable {
    case settings
    case explore
    case moods
    case liked
    case history
    case topTracks
    case localSongs
    case offline
    case localPlaylist(String)
    case onlinePlaylist(PlaylistItem)
    case album(AlbumItem)
    case artist(ArtistItem)
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
                .environment(\.epsPalette, palette)
                .preferredColorScheme(isDark ? .dark : .light)
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
